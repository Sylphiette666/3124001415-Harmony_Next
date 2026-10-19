import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { atlasStore } from '../model/AtlasStore';
import { Structure } from '../model/Structure';
import { AtlasProxy, AtlasEvent, AtlasConcept, localResponse, parseConcepts } from '../services/AtlasBridge';

const INK: string = '#183F3D';
const ACCENT: string = '#177B70';
const MUTED: string = '#647675';

@Entry
@Component
struct Index {
  @State tab: number = 0;
  @State ready: boolean = false;
  @State notice: string = '';
  @State initError: string = '';
  @State structures: Structure[] = [];
  @State sheet: string = '';
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
  private pendingSelection: string = '';
  private atlasInput: TextInputController = new TextInputController();
  private loadTimer: number = -1;

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  aboutToAppear(): void {
    webview.WebviewController.setWebDebuggingAccess(false);
    this.proxy.callback = (event: AtlasEvent) => { this.webEvent(event); };
    this.initialize();
  }
  aboutToDisappear(): void { this.clearLoadTimer(); }
  onBackPress(): boolean { if (this.sheet) { this.sheet = ''; return true; } return false; }
  private async initialize(): Promise<void> {
    this.initError = '';
    try {
      await atlasStore.init(this.context()); this.structures = await atlasStore.structures();
      this.ready = true; this.startLoadTimer();
    } catch { this.initError = '学习记录初始化失败，请重试。'; }
  }
  private clearLoadTimer(): void {
    if (this.loadTimer >= 0) { clearTimeout(this.loadTimer); this.loadTimer = -1; }
  }
  private startLoadTimer(): void {
    this.clearLoadTimer();
    this.loadTimer = setTimeout(() => {
      if (this.progress < 100 && !this.webError) { this.webError = '本地模型加载时间较长'; }
      this.loadTimer = -1;
    }, 60000);
  }
  private webEvent(event: AtlasEvent): void {
    if (event.type === 'ready') { this.webReady = true; if (this.pendingSelection) { this.locate(this.pendingSelection); this.pendingSelection = ''; } }
    if (event.type === 'progress') { this.progress = event.progress || 0; if (this.progress >= 100) { this.clearLoadTimer(); this.webError = ''; } }
    if (event.type === 'error') { this.webError = event.message || '模型加载失败'; this.clearLoadTimer(); }
    if (event.type === 'selection' && event.id && event.name) {
      const existing = this.structures.find((s: Structure) => s.id === event.id);
      this.selected = { id: event.id, name: event.name, system: event.system || '', conceptId: event.conceptId || event.id,
        description: event.description || '', time: Date.now(), note: existing ? existing.note : '', favorite: existing ? existing.favorite : false };
      this.note = this.selected.note; this.recordVisit();
    }
  }
  private async recordVisit(): Promise<void> {
    try { await atlasStore.visit(this.selected); this.structures = await atlasStore.structures(); } catch { this.notice = '浏览记录保存失败，请重新选择结构重试。'; }
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
    this.tab = 0; this.sheet = ''; this.matches = []; this.search = ''; this.notice = '';
    if (!this.webReady) { this.pendingSelection = id; return; }
    try { await this.controller.runJavaScript(`window.HarmonyAtlas.select(${JSON.stringify(id)})`); } catch { this.notice = '定位失败，请重新加载模型后重试。'; }
  }
  private async saveStructure(favorite: boolean): Promise<void> {
    try { await atlasStore.updateStructure(this.selected.id, favorite, this.note); this.structures = await atlasStore.structures();
      const item = this.structures.find((s: Structure) => s.id === this.selected.id); if (item) { this.selected = item; } this.notice = '收藏与笔记已保存。';
    } catch { this.notice = '保存失败，请重试。'; }
  }
  private reloadWeb(): void { this.webReady = false; this.progress = 0; this.webError = ''; this.startLoadTimer(); this.controller.refresh(); }

  @Builder private heading(title: string, subtitle: string) {
    Column({ space: 5 }) { Text(title).fontSize(27).fontWeight(FontWeight.Bold).fontColor(INK); Text(subtitle).fontSize(12).fontColor(MUTED) }.alignItems(HorizontalAlign.Start).width('100%').padding({ left: 20, right: 20, top: 15, bottom: 12 })
  }
  @Builder private action(label: string, run: () => void) { Button(label).fontSize(13).fontColor(ACCENT).backgroundColor('#E6F1ED').height(34).onClick(run) }
  @Builder private atlas() {
    Column() {
      Row({ space: 8 }) { TextInput({ text: this.search, controller: this.atlasInput, placeholder: '心脏 / heart / 模型编号' }).id('atlasSearch').layoutWeight(1).height(40).onChange((v: string) => { this.search = v; }).onSubmit(() => { this.findStructure(); }); this.action('搜索', () => { this.findStructure(); }) }.padding(10)
      if (this.matches.length) { Scroll() { Column() { ForEach(this.matches, (c: AtlasConcept) => { Text(c.name + '  ›').fontSize(14).fontColor(INK).padding(12).width('100%').onClick(() => { this.locate(c.id); }) }, (c: AtlasConcept) => c.id) } }.height(130).backgroundColor(Color.White) }
      Web({ src: 'https://atlas.local/index.html', controller: this.controller }).id('atlasWeb').layoutWeight(1).width('100%')
        .javaScriptAccess(true).domStorageAccess(true).fileAccess(false).mixedMode(MixedMode.None)
        .onControllerAttached(() => { this.controller.registerJavaScriptProxy(this.proxy, 'NativeAtlas', ['onEvent']); })
        .onInterceptRequest((event) => { return localResponse(this.context(), event.request.getRequestUrl()); })
        .onOverrideUrlLoading((request: WebResourceRequest) => { return !request.getRequestUrl().startsWith('https://atlas.local/'); })
      if (this.webError) { Row() { Text(this.webError + '，请重试').fontColor('#A24635').fontSize(13).layoutWeight(1); this.action('重试', () => { this.reloadWeb(); }) }.padding(10) }
      if (this.selected.id) {
        Row({ space: 8 }) { Column({ space: 3 }) { Text(this.selected.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK).maxLines(1); Text(this.selected.system).fontSize(11).fontColor(MUTED) }.alignItems(HorizontalAlign.Start).layoutWeight(1); Button(this.selected.favorite ? '已收藏' : '收藏').fontSize(13).fontColor(ACCENT).backgroundColor('#E6F1ED').height(34).onClick(() => { this.saveStructure(!this.selected.favorite); }); this.action('详情', () => { this.note = this.selected.note; this.notice = ''; this.sheet = 'structure'; }) }.padding(12).backgroundColor(Color.White).width('100%')
      } else { Text(this.progress < 100 ? `本地模型加载中 ${this.progress}%` : '拖动旋转 · 双指缩放 · 点击结构查看详情').fontSize(11).fontColor(MUTED).padding(8) }
    }.width('100%').height('100%')
  }
  @Builder private study() {
    Column() {
      this.heading('我的学习', '收藏结构、回顾浏览、留下一条笔记')
      Row({ space: 10 }) { Button(this.favoritesOnly ? '● 收藏' : '收藏').fontSize(13).fontColor(ACCENT).backgroundColor('#E6F1ED').height(34).onClick(() => { this.favoritesOnly = true; }); Button(this.favoritesOnly ? '浏览历史' : '● 浏览历史').fontSize(13).fontColor(ACCENT).backgroundColor('#E6F1ED').height(34).onClick(() => { this.favoritesOnly = false; }); Blank(); this.action('关于', () => { this.sheet = 'about'; }) }.padding({ left: 16, right: 16, bottom: 12 }).width('100%')
      Scroll() { Column({ space: 10 }) {
        if (!this.structures.filter((s: Structure) => !this.favoritesOnly || s.favorite).length) { Text('去浏览页选择一个结构，开始记录学习。').fontColor(MUTED).padding(20) }
        ForEach(this.structures.filter((s: Structure) => !this.favoritesOnly || s.favorite), (item: Structure) => {
          Column({ space: 8 }) { Text(item.name).fontSize(17).fontColor(INK); Text(item.note || item.system).fontSize(13).fontColor(MUTED).maxLines(2); Row({ space: 10 }) { this.action('定位模型', () => { this.locate(item.id); }); this.action('详情 / 笔记', () => { this.selected = item; this.note = item.note; this.sheet = 'structure'; }) } }.alignItems(HorizontalAlign.Start).padding(16).width('100%').backgroundColor(Color.White).borderRadius(14)
        }, (item: Structure) => `${item.id}-${item.time}-${item.favorite}-${item.note}`)
      }.padding(16).width('100%') }.layoutWeight(1).width('100%')
    }.width('100%').height('100%')
  }
  @Builder private sheetContent() {
    Column() {
      Row() { this.action('‹ 返回', () => { this.sheet = ''; this.notice = ''; }); Blank(); Text(this.sheet === 'structure' ? '结构详情' : '关于知体').fontColor(INK).fontSize(18).fontWeight(FontWeight.Medium) }.padding(16).width('100%')
      Scroll() { Column({ space: 16 }) {
        if (this.sheet === 'structure') {
          Text(this.selected.name).fontSize(25).fontWeight(FontWeight.Bold).fontColor(INK)
          Text(this.selected.id + ' · ' + this.selected.system).fontSize(12).fontColor(MUTED)
          Text(this.selected.description).fontSize(15).lineHeight(25).fontColor(INK)
          Text('BodyParts3D · 通用教学说明').fontSize(12).fontColor(MUTED)
          Row({ space: 8 }) { Button(this.selected.favorite ? '取消收藏' : '加入收藏').fontSize(13).fontColor(ACCENT).backgroundColor('#E6F1ED').height(34).onClick(() => { this.saveStructure(!this.selected.favorite); }); this.action('定位并独立显示', () => { this.locate(this.selected.id).then(() => { this.controller.runJavaScript('window.HarmonyAtlas.isolate(true)').catch(() => {}); }); }) }
          TextArea({ text: this.note, placeholder: '为这个结构写一条学习笔记…' }).id('structureNote').height(180).maxLength(10000).onChange((v: string) => { this.note = v; })
          Button('保存笔记').backgroundColor(ACCENT).onClick(() => { this.saveStructure(this.selected.favorite); })
        } else {
          Text('知体 / Anatomy Course').fontSize(25).fontWeight(FontWeight.Bold).fontColor(INK)
          Text('实验二 · 离线人体解剖浏览与学习记录').fontSize(16).fontColor(ACCENT)
          Text('开发与移植：CODEX\n\nWeb 基础：Human Atlas（ashemag/human-atlas），MIT 许可。\n模型：BodyParts3D，© The Database Center for Life Science，CC Attribution 4.0 International。\n\nhttps://github.com/ashemag/human-atlas\nhttps://lifesciencedb.jp/bp3d/\nhttps://creativecommons.org/licenses/by/4.0/\n\n本应用包含成人男性参考模型，用于课程学习；结构说明保持上游通用教学范围。收藏、历史与笔记仅保存在本机。').fontSize(14).lineHeight(25).fontColor(MUTED).copyOption(CopyOptions.LocalDevice)
        }
        if (this.notice) { Text(this.notice).fontSize(13).fontColor('#A24635').width('100%') }
      }.alignItems(HorizontalAlign.Start).padding(20).width('100%') }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor('#F4F6F3')
  }
  build() {
    Stack() {
      Column() {
        if (!this.ready) {
          Column({ space: 16 }) { Text(this.initError || '正在读取学习记录…').fontColor(INK); if (this.initError) { this.action('重试初始化', () => { this.initialize(); }) } else { LoadingProgress().width(36).height(36) } }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Tabs({ index: this.tab, barPosition: BarPosition.End }) {
            TabContent() { this.atlas() }.tabBar('浏览')
            TabContent() { this.study() }.tabBar('学习')
          }.layoutWeight(1).barHeight(52).animationDuration(0).scrollable(false).onChange((index: number) => { this.tab = index; this.notice = ''; })
        }
        if (this.notice && !this.sheet) { Text(this.notice).fontSize(12).fontColor('#A24635').padding(8).width('100%').backgroundColor('#FFF3E9').onClick(() => { this.notice = ''; }) }
      }.width('100%').height('100%').backgroundColor('#F4F6F3')
      if (this.sheet) { this.sheetContent() }
    }.width('100%').height('100%')
  }
}
