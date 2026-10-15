import { ChatCard } from './ChatCard';
import { common, Want } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { connection } from '@kit.NetworkKit';
import { courseStore } from '../model/CourseStore';
import { CourseDocument, Segment, Evidence, ChatMessage, Structure, AppSettings, retrieve, localAnswer, nextCodePoint } from '../model/Knowledge';
import { CloudClient } from '../services/CloudClient';
import { AtlasProxy, AtlasEvent, AtlasConcept, localResponse, parseConcepts } from '../services/AtlasBridge';

interface IntentMessage { question: string; nonce: number; }
const INK: string = '#183F3D';
const ACCENT: string = '#177B70';
const MUTED: string = '#647675';

@Entry
@Component
struct Index {
  @StorageLink('askIntent') @Watch('consumeIntent') intent: string = '';
  @State tab: number = 1;
  @State ready: boolean = false;
  @State busy: boolean = false;
  @State notice: string = '';
  @State initError: string = '';
  @State question: string = '';
  @State messages: ChatMessage[] = [];
  @State documents: CourseDocument[] = [];
  @State structures: Structure[] = [];
  @State sheet: string = '';
  @State editId: string = '';
  @State editTitle: string = '';
  @State editSource: string = '';
  @State editBody: string = '';
  @State sourceDoc: CourseDocument = { id: '', title: '', source: '', body: '', revision: 0, updated: 0 };
  @State sourceSegment: Segment = { id: '', documentId: '', title: '', source: '', text: '', start: 0, end: 0, revision: 0, vector: [], model: '' };
  @State sourceStale: boolean = false;
  @State cloudMode: boolean = false;
  @State endpoint: string = '';
  @State search: string = '';
  @State matches: AtlasConcept[] = [];
  @State webReady: boolean = false;
  @State progress: number = 0;
  @State webError: string = '';
  @State selected: Structure = { id: '', name: '', system: '', conceptId: '', description: '', time: 0, note: '', favorite: false };
  @State note: string = '';
  @State favoritesOnly: boolean = true;
  private controller: webview.WebviewController = new webview.WebviewController();
  private proxy: AtlasProxy = new AtlasProxy();
  private client: CloudClient = new CloudClient();
  private generation: number = 0;
  private timer: number = -1;
  private pendingSelection: string = '';
  private seenIntent: string = '';
  private atlasInput: TextInputController = new TextInputController();
  private questionInput: TextInputController = new TextInputController();
  private chatScroll: Scroller = new Scroller();

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  aboutToAppear(): void {
    webview.WebviewController.setWebDebuggingAccess(false);
    this.proxy.callback = (event: AtlasEvent) => { this.webEvent(event); };
    this.initialize();
  }
  aboutToDisappear(): void { this.stop(); this.client.cancel(); }
  onBackPress(): boolean { if (this.sheet) { this.sheet = ''; return true; } return false; }
  private async initialize(): Promise<void> {
    this.initError = '';
    try {
      await courseStore.init(this.context()); this.documents = await courseStore.documents();
      this.structures = await courseStore.structures(); const settings = await courseStore.settings();
      this.cloudMode = settings.cloud; this.endpoint = settings.endpoint; this.ready = true; this.consumeIntent();
    } catch { this.initError = '资料库初始化失败，请重试。'; }
  }
  private consumeIntent(): void {
    if (!this.ready || !this.intent || this.intent === this.seenIntent) { return; }
    this.seenIntent = this.intent;
    try { const request = JSON.parse(this.intent) as IntentMessage;
      if (request.question) { this.sheet = ''; this.tab = 1; this.question = request.question; this.ask(); }
    } catch { this.notice = '无法读取意图参数，请在下方输入问题。'; }
  }
  private stop(): void {
    this.generation++; this.client.cancel();
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
    if (this.messages.length > 0) {
      const item = this.messages[this.messages.length - 1];
      if (item.state === '检索中' || item.state === '回答中' || item.state === '资料向量化中') { item.state = '已停止'; this.messages = this.messages.slice(); }
    }
    this.busy = false;
  }
  private refreshMessage(): void { this.messages = this.messages.slice(); }
  private async ask(retry: string = ''): Promise<void> {
    const input = (retry || this.question).trim();
    if (!input || !this.ready) { return; }
    this.questionInput.stopEditing();
    this.stop(); this.question = ''; this.notice = ''; this.busy = true;
    const token = this.generation;
    const message = new ChatMessage(input.slice(0, 600), this.cloudMode, courseStore.version);
    this.messages = [...this.messages, message];
    try {
      let segments = await courseStore.segments();
      let vector: number[] = []; let model = '';
      if (this.cloudMode) {
        if (!connection.hasDefaultNetSync()) { throw new Error('当前无网络。请连接网络后重试，或在设置中切换为本地摘录模式。'); }
        if (!this.endpoint) { throw new Error('尚未配置云端服务，请在设置中填写 HTTPS 地址，或使用本地模式。'); }
        message.state = '资料向量化中'; this.refreshMessage();
        const query = await this.client.embeddings(this.endpoint, [input]);
        if (token !== this.generation) { return; }
        vector = query.vectors[0]; model = this.endpoint + '|' + query.model;
        const pending = segments.filter((s: Segment) => s.model !== model || s.vector.length !== vector.length);
        for (let offset = 0; offset < pending.length; offset += 16) {
          const batch = pending.slice(offset, offset + 16);
          const result = await this.client.embeddings(this.endpoint, batch.map((s: Segment) => s.text));
          if (token !== this.generation) { return; }
          if (result.model !== query.model) { throw new Error('向量模型发生变化，请重新提问'); }
          await courseStore.vectors(batch, result.vectors, model);
        }
        segments = await courseStore.segments();
      }
      if (token !== this.generation) { return; }
      message.evidence = retrieve(input, segments, vector, model);
      if (!message.evidence.length) { message.state = '未检索到相关内容'; message.answer = localAnswer(input, []); this.busy = false; this.refreshMessage(); return; }
      message.state = '回答中'; this.refreshMessage();
      if (this.cloudMode) {
        await this.client.answer(this.endpoint, input, message.evidence, (delta: string) => {
          if (token === this.generation) { message.answer += delta; this.refreshMessage(); }
        });
        if (token === this.generation) { message.state = '已完成'; this.busy = false; this.refreshMessage(); }
      } else {
        const full = localAnswer(input, message.evidence); let offset = 0;
        this.timer = setInterval(() => {
          if (token !== this.generation) { return; }
          offset = nextCodePoint(full, offset); message.answer = full.slice(0, offset);
          if (offset >= full.length) { clearInterval(this.timer); this.timer = -1; message.state = '已完成'; this.busy = false; }
          this.refreshMessage();
        }, 12);
      }
    } catch (error) {
      if (token !== this.generation) { return; }
      message.state = '请求失败'; message.error = (error as Error).message || '请求未完成，请检查网络或服务地址后重试。'; this.busy = false; this.refreshMessage();
    }
  }
  private edit(doc?: CourseDocument): void {
    this.editId = doc ? doc.id : ''; this.editTitle = doc ? doc.title : '';
    this.editSource = doc ? doc.source : ''; this.editBody = doc ? doc.body : ''; this.notice = ''; this.sheet = 'editor';
  }
  private async saveDocument(): Promise<void> {
    if (this.busy) { this.stop(); }
    this.busy = true; this.notice = '正在切分并保存资料…';
    try {
      const doc: CourseDocument = { id: this.editId || `user-${Date.now()}`, title: this.editTitle, source: this.editSource || '用户本地资料', body: this.editBody, revision: 0, updated: 0 };
      await courseStore.save(doc); this.documents = await courseStore.documents(); this.messages = []; this.sheet = '';
      this.notice = '资料已保存，检索索引已同步更新。';
    } catch (error) { this.notice = (error as Error).message || '保存失败，请重试'; } finally { this.busy = false; }
  }
  private deleteDocument(doc: CourseDocument): void {
    AlertDialog.show({ title: '删除这篇资料？', message: `《${doc.title}》及检索片段将从本地移除。`,
      primaryButton: { value: '保留', action: () => {} }, secondaryButton: { value: '删除', action: () => { this.removeDocument(doc.id); } } });
  }
  private async removeDocument(id: string): Promise<void> {
    this.stop(); this.busy = true;
    try { await courseStore.remove(id); this.documents = await courseStore.documents(); this.messages = []; this.notice = '资料与对应片段已删除。'; }
    catch { this.notice = '删除失败，请重试。'; } finally { this.busy = false; }
  }
  private async openSource(evidence: Evidence): Promise<void> {
    this.sourceSegment = evidence.segment;
    try { const docs = await courseStore.documents(); const doc = docs.find((d: CourseDocument) => d.id === evidence.segment.documentId);
      this.sourceStale = !doc || doc.revision !== evidence.segment.revision;
      this.sourceDoc = doc || { id: '', title: evidence.segment.title, source: evidence.segment.source, body: '', revision: 0, updated: 0 }; this.sheet = 'source';
    } catch { this.notice = '读取来源失败，请再次点击重试。'; }
  }
  private async saveSettings(): Promise<void> {
    if (this.cloudMode && !/^https:\/\/[^\s]+$/.test(this.endpoint.trim())) { this.notice = '云端模式需要 HTTPS 服务地址。'; return; }
    this.stop();
    try { const settings: AppSettings = { endpoint: this.endpoint.trim(), cloud: this.cloudMode }; await courseStore.saveSettings(settings); this.sheet = ''; this.notice = '设置已保存。'; }
    catch { this.notice = '设置保存失败，请重试。'; }
  }
  private async debugIntent(): Promise<void> {
    const want: Want = { bundleName: 'cn.gdut.anatomycourse', abilityName: 'EntryAbility', uri: 'anatomycourse://ask', parameters: { question: '如何通过 ArkAF 意图自动提问？' } };
    try { await this.context().startAbility(want); } catch { this.notice = '意图启动失败，请重试。'; }
  }
  private webEvent(event: AtlasEvent): void {
    if (event.type === 'ready') { this.webReady = true; if (this.pendingSelection) { this.locate(this.pendingSelection); this.pendingSelection = ''; } }
    if (event.type === 'progress') { this.progress = event.progress || 0; }
    if (event.type === 'error') { this.webError = event.message || '模型加载失败'; }
    if (event.type === 'selection' && event.id && event.name) {
      const existing = this.structures.find((s: Structure) => s.id === event.id);
      this.selected = { id: event.id, name: event.name, system: event.system || '', conceptId: event.conceptId || event.id,
        description: event.description || '', time: Date.now(), note: existing ? existing.note : '', favorite: existing ? existing.favorite : false };
      this.note = this.selected.note; this.recordVisit();
    }
  }
  private async recordVisit(): Promise<void> {
    try { await courseStore.visit(this.selected); this.structures = await courseStore.structures(); } catch { this.notice = '浏览记录保存失败，请重新选择结构重试。'; }
  }
  private async findStructure(): Promise<void> {
    this.atlasInput.stopEditing();
    if (!this.webReady) { this.notice = '模型目录加载中，请稍后重试搜索。'; return; }
    try { const json = await this.controller.runJavaScript(`JSON.stringify(window.HarmonyAtlas.search(${JSON.stringify(this.search.trim())}))`);
      this.matches = parseConcepts(json);
      if (!this.matches.length) { this.notice = '未找到结构，请尝试“心脏”、heart 或模型编号。'; } else { this.notice = ''; }
    } catch { this.notice = '搜索失败，请重试加载浏览器。'; }
  }
  private async locate(id: string): Promise<void> {
    this.tab = 0; this.sheet = ''; this.matches = [];
    if (!this.webReady) { this.pendingSelection = id; return; }
    try { await this.controller.runJavaScript(`window.HarmonyAtlas.select(${JSON.stringify(id)})`); } catch { this.notice = '定位失败，请重新加载模型后重试。'; }
  }
  private async saveStructure(favorite: boolean): Promise<void> {
    try { await courseStore.updateStructure(this.selected.id, favorite, this.note); this.structures = await courseStore.structures();
      const item = this.structures.find((s: Structure) => s.id === this.selected.id); if (item) { this.selected = item; } this.notice = '收藏与笔记已保存。';
    } catch { this.notice = '保存失败，请重试。'; }
  }
  private reloadWeb(): void { this.webReady = false; this.progress = 0; this.webError = ''; this.controller.refresh(); }

  @Builder private heading(title: string, subtitle: string) {
    Column({ space: 5 }) { Text(title).fontSize(27).fontWeight(FontWeight.Bold).fontColor(INK); Text(subtitle).fontSize(12).fontColor(MUTED) }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20, top: 15, bottom: 12 })
  }
  @Builder private action(label: string, run: () => void) { Button(label).fontSize(13).fontColor(ACCENT).backgroundColor('#E6F1ED').height(34).onClick(run) }
  @Builder private chat() {
    Column() {
      Row() { Column({ space: 4 }) { Text('课程知识问答').fontSize(26).fontWeight(FontWeight.Bold).fontColor(INK); Text(`${this.documents.length} 篇本地资料 · 回答可追溯`).fontSize(12).fontColor(MUTED) }.alignItems(HorizontalAlign.Start).layoutWeight(1); this.action('设置', () => { this.notice = ''; this.sheet = 'settings'; }) }.padding(20).width('100%')
      Scroll(this.chatScroll) {
        Column({ space: 16 }) {
          if (!this.messages.length) {
            Column({ space: 16 }) {
              Text('把疑问，交给你的课程资料。').fontSize(22).fontColor(INK).fontWeight(FontWeight.Medium)
              Text('输入自然语言问题，查看依据原文的回答与引用。当前模式：' + (this.cloudMode ? '云端生成' : '本地资料摘录')).fontSize(14).fontColor(MUTED).lineHeight(23)
              ForEach(['如何让 ArkWeb 离线加载模型？', '修改资料后如何更新检索内容？', 'ArkAF 意图怎样携带问题？'], (sample: string) => {
                Button(sample).fontSize(14).fontColor(ACCENT).backgroundColor('#FFFFFF').width('100%').height(46).onClick(() => { this.ask(sample); })
              })
            }.alignItems(HorizontalAlign.Start).padding(20).backgroundColor('#E4EEEA').borderRadius(18).margin({ top: 8 })
          }
          ForEach(this.messages, (message: ChatMessage) => {
            ChatCard({ message: message, onSource: (e: Evidence) => { this.openSource(e); }, onRetry: (q: string) => { this.ask(q); } })
          }, (message: ChatMessage) => message.id)
        }.padding({ left: 16, right: 16, bottom: 16 }).width('100%')
      }.layoutWeight(1).width('100%').scrollBar(BarState.Auto).align(Alignment.TopStart)
      Row({ space: 8 }) {
        TextInput({ text: this.question, controller: this.questionInput, placeholder: '向课程资料提问…' }).id('questionInput').layoutWeight(1).height(46).maxLength(600).backgroundColor(Color.White).onChange((value: string) => { this.question = value; }).onSubmit(() => { this.ask(); })
        Button(this.busy ? '停止' : '发送').id('sendQuestion').backgroundColor(ACCENT).height(44).onClick(() => { if (this.busy) { this.stop(); } else { this.ask(); } })
      }.padding(12).width('100%')
    }.width('100%').height('100%')
  }
  @Builder private library() {
    Column() {
      Column({ space: 5 }) { Text('课程资料库').fontSize(27).fontWeight(FontWeight.Bold).fontColor(INK); Text(`${this.documents.length} 篇 · 修改后即时重建索引`).fontSize(12).fontColor(MUTED) }.alignItems(HorizontalAlign.Start).width('100%').padding(20)
      Row() { this.action('＋ 新增资料', () => { this.edit(); }); Blank(); Text('本地 RDB').fontSize(12).fontColor(MUTED) }.padding({ left: 20, right: 20, bottom: 10 }).width('100%')
      Scroll() { Column({ space: 10 }) {
        if (!this.documents.length) { Text('还没有资料。添加至少一篇资料后即可提问。').fontColor(MUTED).padding(20) }
        ForEach(this.documents, (doc: CourseDocument) => {
          Column({ space: 8 }) {
            Text(doc.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(INK)
            Text(`${doc.body.length} 字 · 版本 ${doc.revision}`).fontSize(12).fontColor(MUTED)
            Text(doc.body).fontSize(13).fontColor(MUTED).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            Row({ space: 10 }) { this.action('阅读 / 编辑', () => { this.edit(doc); }); this.action('删除', () => { this.deleteDocument(doc); }) }
          }.alignItems(HorizontalAlign.Start).padding(16).backgroundColor(Color.White).borderRadius(14).width('100%')
        }, (doc: CourseDocument) => `${doc.id}-${doc.revision}`)
      }.padding({ left: 16, right: 16, bottom: 16 }).width('100%') }.layoutWeight(1).width('100%')
    }.width('100%').height('100%')
  }
  @Builder private atlas() {
    Column() {
      Row({ space: 8 }) { TextInput({ text: this.search, controller: this.atlasInput, placeholder: '心脏 / heart / 模型编号' }).id('atlasSearch').layoutWeight(1).height(40).onChange((v: string) => { this.search = v; }).onSubmit(() => { this.findStructure(); }); this.action('搜索', () => { this.findStructure(); }) }.padding(10)
      if (this.matches.length) { Scroll() { Column() { ForEach(this.matches, (c: AtlasConcept) => { Text(c.name + '  ›').fontSize(14).fontColor(INK).padding(12).width('100%').onClick(() => { this.locate(c.id); }) }, (c: AtlasConcept) => c.id) } }.height(130).backgroundColor(Color.White) }
      Web({ src: 'https://atlas.local/index.html', controller: this.controller }).id('atlasWeb').layoutWeight(1).width('100%')
        .javaScriptAccess(true).domStorageAccess(true).fileAccess(false).mixedMode(MixedMode.None)
        .onControllerAttached(() => { this.controller.registerJavaScriptProxy(this.proxy, 'NativeAtlas', ['onEvent']); })
        .onInterceptRequest((event) => { return localResponse(this.context(), event.request.getRequestUrl()); })
        .onOverrideUrlLoading((request: WebResourceRequest) => { return !request.getRequestUrl().startsWith('https://atlas.local/'); })
      if (this.webError) { Row() { Text('模型加载失败').fontColor('#A24635').fontSize(13).layoutWeight(1); this.action('重试', () => { this.reloadWeb(); }) }.padding(10) }
      if (this.selected.id) {
        Row({ space: 8 }) { Column({ space: 3 }) { Text(this.selected.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK).maxLines(1); Text(this.selected.system).fontSize(11).fontColor(MUTED) }.alignItems(HorizontalAlign.Start).layoutWeight(1); Button(this.selected.favorite ? '已收藏' : '收藏').fontSize(13).fontColor(ACCENT).backgroundColor('#E6F1ED').height(34).onClick(() => { this.saveStructure(!this.selected.favorite); }); this.action('详情', () => { this.note = this.selected.note; this.notice = ''; this.sheet = 'structure'; }) }.padding(12).backgroundColor(Color.White).width('100%')
      } else { Text(this.progress < 100 ? `本地模型加载中 ${this.progress}%` : '拖动旋转 · 双指缩放 · 点击结构查看详情').fontSize(11).fontColor(MUTED).padding(8) }
    }.width('100%').height('100%')
  }
  @Builder private study() {
    Column() {
      this.heading('我的学习', '收藏结构、回顾浏览、留下一条笔记')
      Row({ space: 10 }) { this.action(this.favoritesOnly ? '● 收藏' : '收藏', () => { this.favoritesOnly = true; }); this.action(this.favoritesOnly ? '浏览历史' : '● 浏览历史', () => { this.favoritesOnly = false; }); Blank(); this.action('关于', () => { this.sheet = 'about'; }) }.padding({ left: 16, right: 16, bottom: 12 }).width('100%')
      Scroll() { Column({ space: 10 }) {
        if (!this.structures.filter((s: Structure) => !this.favoritesOnly || s.favorite).length) { Text('去解剖页选择一个结构，开始记录学习。').fontColor(MUTED).padding(20) }
        ForEach(this.structures.filter((s: Structure) => !this.favoritesOnly || s.favorite), (item: Structure) => {
          Column({ space: 8 }) { Text(item.name).fontSize(17).fontColor(INK); Text(item.note || item.system).fontSize(13).fontColor(MUTED).maxLines(2); Row({ space: 10 }) { this.action('定位模型', () => { this.locate(item.id); }); this.action('详情 / 笔记', () => { this.selected = item; this.note = item.note; this.sheet = 'structure'; }) } }.alignItems(HorizontalAlign.Start).padding(16).width('100%').backgroundColor(Color.White).borderRadius(14)
        }, (item: Structure) => `${item.id}-${item.time}-${item.favorite}-${item.note}`)
      }.padding(16).width('100%') }.layoutWeight(1).width('100%')
    }.width('100%').height('100%')
  }
  @Builder private sheetContent() {
    Column() {
      Row() { this.action('‹ 返回', () => { if (!this.busy || this.sheet !== 'editor') { this.sheet = ''; this.notice = ''; } }); Blank(); Text(this.sheet === 'editor' ? '编辑课程资料' : this.sheet === 'source' ? '来源与原文' : this.sheet === 'settings' ? '问答设置' : this.sheet === 'structure' ? '结构详情' : '关于知体').fontColor(INK).fontSize(18).fontWeight(FontWeight.Medium) }.padding(16).width('100%')
      Scroll() { Column({ space: 16 }) {
        if (this.sheet === 'editor') {
          TextInput({ text: this.editTitle, placeholder: '资料名称（必填）' }).id('docTitle').maxLength(100).onChange((v: string) => { this.editTitle = v; })
          TextInput({ text: this.editSource, placeholder: '资料出处 / URL' }).id('docSource').maxLength(500).onChange((v: string) => { this.editSource = v; })
          TextArea({ text: this.editBody, placeholder: '粘贴或输入正文，20—60000 字' }).id('docBody').height(350).maxLength(60000).onChange((v: string) => { this.editBody = v; })
          Button(this.busy ? '正在处理…' : '保存并更新知识库').backgroundColor(ACCENT).enabled(!this.busy).width('100%').onClick(() => { this.saveDocument(); })
        } else if (this.sheet === 'source') {
          Text(this.sourceDoc.title).fontSize(23).fontWeight(FontWeight.Bold).fontColor(INK)
          Text(this.sourceDoc.source).fontSize(12).fontColor(MUTED).copyOption(CopyOptions.LocalDevice)
          if (this.sourceStale) { Text('资料已修改或删除。以下是回答时的引用快照，请重新提问获取最新依据。').fontColor('#A24635').fontSize(14); Text(this.sourceSegment.text).fontSize(16).lineHeight(26) }
          else { Text(`版本 ${this.sourceDoc.revision} · 高亮为引用片段`).fontSize(12).fontColor(ACCENT); Text() { Span(this.sourceDoc.body.slice(0, this.sourceSegment.start)); Span(this.sourceDoc.body.slice(this.sourceSegment.start, this.sourceSegment.end)).fontColor(ACCENT).fontWeight(FontWeight.Bold); Span(this.sourceDoc.body.slice(this.sourceSegment.end)) }.fontSize(16).lineHeight(27).fontColor(INK).copyOption(CopyOptions.LocalDevice) }
        } else if (this.sheet === 'settings') {
          Text('本地摘录随时可用，默认不发送资料。').fontSize(17).fontColor(INK)
          Row() { Text('启用云端生成与语义检索').fontSize(15).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.cloudMode }).selectedColor(ACCENT).onChange((v: boolean) => { this.cloudMode = v; }) }.width('100%')
          Text('开启后会将问题和课程片段发送到下方服务，资料首次处理会生成向量。模型密钥仅保存在服务器，不能填入 App。').fontSize(13).fontColor(MUTED).lineHeight(22)
          TextInput({ text: this.endpoint, placeholder: 'https://你的服务域名' }).id('cloudEndpoint').onChange((v: string) => { this.endpoint = v; })
          Button('保存设置').backgroundColor(ACCENT).onClick(() => { this.saveSettings(); })
          Divider()
          Text('ArkAF / Want 入口验证').fontSize(18).fontColor(INK)
          Text('向 EntryAbility 发送带 question 参数的 Want，返回后将自动提问。').fontSize(13).fontColor(MUTED)
          this.action('通过 Want 唤起问答', () => { this.debugIntent(); })
        } else if (this.sheet === 'structure') {
          Text(this.selected.name).fontSize(25).fontWeight(FontWeight.Bold).fontColor(INK)
          Text(this.selected.id + ' · ' + this.selected.system).fontSize(12).fontColor(MUTED)
          Text(this.selected.description).fontSize(15).lineHeight(25).fontColor(INK)
          Text('BodyParts3D · 通用教学说明').fontSize(12).fontColor(MUTED)
          Row({ space: 8 }) { Button(this.selected.favorite ? '取消收藏' : '加入收藏').fontSize(13).fontColor(ACCENT).backgroundColor('#E6F1ED').height(34).onClick(() => { this.saveStructure(!this.selected.favorite); }); this.action('定位并独立显示', () => { this.locate(this.selected.id).then(() => { this.controller.runJavaScript('window.HarmonyAtlas.isolate(true)').catch(() => {}); }); }) }
          TextArea({ text: this.note, placeholder: '为这个结构写一条学习笔记…' }).id('structureNote').height(180).maxLength(10000).onChange((v: string) => { this.note = v; })
          Button('保存笔记').backgroundColor(ACCENT).onClick(() => { this.saveStructure(this.selected.favorite); })
        } else {
          Text('知体 / Anatomy Course').fontSize(25).fontWeight(FontWeight.Bold).fontColor(INK)
          Text('原生学习工具 × 离线 3D 解剖浏览 × 课程知识问答').fontSize(16).fontColor(ACCENT)
          Text('开发与移植：CODEX\n\nWeb 基础：Human Atlas（ashemag/human-atlas），MIT 许可。\n模型：BodyParts3D，© The Database Center for Life Science，CC Attribution 4.0 International。\n\nhttps://github.com/ashemag/human-atlas\nhttps://lifesciencedb.jp/bp3d/\nhttps://creativecommons.org/licenses/by/4.0/\n\n本应用包含成人男性参考模型，用于课程学习；结构说明保持上游通用教学范围。知识库默认包含 12 篇鸿蒙课程讲义，可自行增删修改。').fontSize(14).lineHeight(25).fontColor(MUTED).copyOption(CopyOptions.LocalDevice)
        }
        if (this.notice) { Text(this.notice).fontSize(13).fontColor('#A24635').width('100%') }
      }.alignItems(HorizontalAlign.Start).padding(20).width('100%') }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F6F3')
  }
  build() {
    Stack() {
      Column() {
        if (!this.ready) {
          Column({ space: 16 }) { Text(this.initError || '正在初始化课程资料…').fontColor(INK); if (this.initError) { this.action('重试初始化', () => { this.initialize(); }) } else { LoadingProgress().width(36).height(36) } }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Tabs({ index: this.tab, barPosition: BarPosition.End }) {
            TabContent() { this.atlas() }.tabBar('解剖')
            TabContent() { this.chat() }.tabBar('问答')
            TabContent() { this.library() }.tabBar('资料')
            TabContent() { this.study() }.tabBar('学习')
          }.layoutWeight(1).barHeight(52).animationDuration(0).scrollable(false).onChange((index: number) => { this.tab = index; this.notice = ''; })
        }
        if (this.notice && !this.sheet) { Text(this.notice).fontSize(12).fontColor('#A24635').padding(8).width('100%').backgroundColor('#FFF3E9').onClick(() => { this.notice = ''; }) }
      }.width('100%').height('100%').backgroundColor('#F4F6F3')
      if (this.sheet) { this.sheetContent() }
    }.width('100%').height('100%')
  }
}
