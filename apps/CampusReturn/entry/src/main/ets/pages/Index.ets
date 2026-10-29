import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AppSettings } from '../model/Types';
import { UserProfile, CampusItem, PublishPayload, OutboxEntry, Candidate, CandidatePage, PairCase, CasesPage,
  ClaimRow, AppealRow, AppealsPage, NotificationsPage, NotificationRow, AdminPage, Policy, ActionResult,
  TimelineEvent, NameCount, PairInput, AnswerInput, AppealInput, ReviewInput, DecisionInput, ViolationInput, CATEGORIES, DEFAULT_POLICY } from '../model/CampusTypes';
import { cacheStore } from '../model/CacheStore';
import { formatTime, parseTime } from '../model/ExtractRules';
import { campusSync } from '../services/CampusSync';
import { apiClient, validateEndpoint } from '../services/ApiClient';
import { analyzePhoto, extractText, recognizeEvidence, uploadImage } from '../services/CampusAI';
import { importPhoto, ensureFolders, writeFile } from '../services/MediaFiles';
import { VoiceService, VoiceStatus } from '../services/VoiceService';

@Entry
@Component
struct Index {
  @State tab: string = '广场';
  @State sheet: string = '';
  @State busy: boolean = false;
  @State message: string = '先连接课程演示服务，也可离线查看已有缓存';
  @State error: string = '';
  @State items: CampusItem[] = [];
  @State outbox: OutboxEntry[] = [];
  @State profile: UserProfile | undefined = undefined;
  @State endpoint: string = 'http://127.0.0.1:8766';
  @State account: string = '';
  @State secret: string = '';
  @State kindFilter: string = '全部';
  @State kind: string = 'lost';
  @State category: string = '校园卡';
  @State color: string = '';
  @State place: string = '';
  @State timeText: string = formatTime(Date.now() - 3600000);
  @State description: string = '';
  @State ocrText: string = '';
  @State photo: string = '';
  @State question: string = '';
  @State expected: string = '';
  @State aiNote: string = '识别结果仅作建议，请确认每个字段后发布';
  @State voiceStatus: VoiceStatus = new VoiceStatus();
  @State candidates: Candidate[] = [];
  @State lostId: string = '';
  @State cases: PairCase[] = [];
  @State current: PairCase | undefined = undefined;
  @State answer: string = '';
  @State evidenceText: string = '';
  @State evidencePath: string = '';
  @State evidenceLevel: number = 1;
  @State reviewScore: string = '85';
  @State appeals: AppealRow[] = [];
  @State notifications: NotificationRow[] = [];
  @State admin: AdminPage | undefined = undefined;
  @State policy: Policy = DEFAULT_POLICY;
  @State penaltyUser: string = '';
  @State penaltyKind: string = 'false_post';
  private voice: VoiceService | undefined = undefined;
  private mainScroller: Scroller = new Scroller();
  private modalScroller: Scroller = new Scroller();

  aboutToAppear(): void { this.init(); }
  onPageShow(): void {
    const capture = AppStorage.get<string>('campusCapture');
    if (capture) { this.photo = capture; AppStorage.delete('campusCapture'); this.tab = '发布'; }
    campusSync.start((text: string, failed: boolean) => { this.syncNotice(text, failed); });
  }
  onPageHide(): void { campusSync.stop(); if (this.voice) { this.voice.stop(); } }
  aboutToDisappear(): void { campusSync.stop(); if (this.voice) { this.voice.dispose(); } }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private async syncNotice(text: string, failed: boolean): Promise<void> {
    try {
      await this.refreshCache(); if (failed) { this.error = text; return; }
      this.message = text; this.error = ''; this.profile = await apiClient.request<UserProfile>('/v1/me');
      if (this.profile.role !== 'admin' && this.tab === '管理') { this.tab = '广场'; }
      if (this.tab === '我的') { await this.loadMine(); }
    } catch (e) { this.error = (e as Error).message; }
  }
  private async init(): Promise<void> {
    await this.work(async () => {
      await cacheStore.init(this.context()); const settings = await cacheStore.settings();
      this.endpoint = settings.endpoint; this.account = settings.deviceId; this.secret = settings.deviceKey;
      this.configure(settings); await this.refreshCache();
      if (apiClient.configured) { await this.connect(false); }
    });
  }
  private configure(settings: AppSettings): void {
    apiClient.configure(settings); cacheStore.scope = settings.endpoint + '|' + settings.deviceId;
  }
  private async work(job: () => Promise<void>): Promise<void> {
    if (this.busy) { return; } this.busy = true; this.error = '';
    try { await job(); } catch (e) { this.error = (e as Error).message || '操作未完成，请重试'; }
    finally { this.busy = false; }
  }
  private async refreshCache(): Promise<void> { this.items = await cacheStore.items(); this.outbox = await cacheStore.pending(true); }
  private async connect(save: boolean = true): Promise<void> {
    if (campusSync.busy) { throw new Error('同步进行中，请稍后切换账号'); }
    const settings: AppSettings = { endpoint: validateEndpoint(this.endpoint), deviceId: this.account.trim(), deviceKey: this.secret,
      autoSync: true, modelPath: '', modelVersion: '1.0.0' };
    this.profile = undefined; this.cases = []; this.appeals = []; this.notifications = []; this.admin = undefined; this.current = undefined; this.tab = '广场';
    this.mainScroller.scrollTo({ xOffset: 0, yOffset: 0 }); this.configure(settings); await this.refreshCache();
    if (save) { await cacheStore.saveSettings(settings); }
    this.profile = await apiClient.request<UserProfile>('/v1/me');
    this.message = await campusSync.run(); this.sheet = ''; await this.refreshCache();
  }
  private async sync(): Promise<void> {
    this.message = await campusSync.run(); await this.refreshCache();
    this.profile = await apiClient.request<UserProfile>('/v1/me');
    if (this.tab === '认领') { await this.loadCases(); }
    if (this.tab === '我的') { await this.loadMine(); }
    if (this.tab === '管理') { await this.loadAdmin(); }
  }
  private async pick(evidence: boolean = false): Promise<void> {
    const result = await new photoAccessHelper.PhotoViewPicker().select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1 });
    if (!result.photoUris.length) { this.message = '已取消选图，可重新选择'; return; }
    const path = await importPhoto(this.context(), result.photoUris[0]);
    if (evidence) { this.evidencePath = path; } else { this.photo = path; }
  }
  private async demoPhoto(): Promise<void> {
    const ctx = this.context(); ensureFolders(ctx); const bytes = await ctx.resourceManager.getRawFileContent('demo-card.jpg');
    this.photo = ctx.filesDir + '/images/demo-card.jpg'; writeFile(this.photo, bytes.slice().buffer as ArrayBuffer);
    this.message = '已选择合成教学卡片，请点击识别；无真实身份信息';
  }
  private async analyze(): Promise<void> {
    if (!this.photo) { throw new Error('请先拍照或从相册选择图片'); }
    this.aiNote = '正在处理图片，调用端侧分类与OCR…';
    const result = await analyzePhoto(this.context(), this.photo);
    if (result.category) { this.category = result.category; } this.ocrText = result.ocrText; this.aiNote = result.note;
  }
  private async extract(): Promise<void> {
    if (!this.description.trim()) { throw new Error('请先输入或口述物品描述'); }
    this.aiNote = '正在进行分词与实体抽取…'; const result = await extractText(this.description);
    if (result.category) { this.category = result.category; } if (result.color) { this.color = result.color; }
    if (result.place) { this.place = result.place; } if (result.timeText) { this.timeText = result.timeText; }
    this.aiNote = result.note + (result.words.length ? ' · ' + result.words.slice(0, 12).join(' / ') : '');
  }
  private async microphone(): Promise<void> {
    if (!this.voice) { this.voice = new VoiceService((s: VoiceStatus) => { this.voiceStatus = s; }, (s: string) => { this.description = s; this.work(async () => { await this.extract(); }); }); }
    if (this.voiceStatus.listening) { await this.voice.stop(); } else { await this.voice.start(this.context()); }
  }
  private async publish(): Promise<void> {
    if (!apiClient.configured) { throw new Error('首次发布请先连接服务，之后断网也可保存待传'); }
    if (!this.place.trim() || this.description.trim().length < 2 || !this.photo) { throw new Error('请补全图片、地点和描述'); }
    if (this.description.length > 2000 || this.ocrText.length > 4000 || this.place.length > 100 || this.color.length > 30 || this.question.length > 200 || this.expected.length > 200) { throw new Error('字段过长：描述限2000字、OCR限4000字、地点100字、颜色30字、问题和答案200字，请缩短后发布'); }
    if (this.kind === 'found' && (!this.question.trim() || !this.expected.trim())) { throw new Error('拾获登记必须设置私密核验问题与答案'); }
    const stamp = parseTime(this.timeText); if (stamp > Date.now()) { throw new Error('丢失或拾获时间不能晚于现在'); }
    const payload: PublishPayload = { itemId: util.generateRandomUUID(), kind: this.kind, category: this.category, color: this.color,
      place: this.place.trim(), occurredAt: stamp, description: this.description.trim(), ocrText: this.ocrText,
      imageBase64: await uploadImage(this.photo), question: this.kind === 'found' ? this.question : '', answer: this.kind === 'found' ? this.expected : '' };
    await cacheStore.enqueue(payload, this.profile ? this.profile.name : this.account); await this.refreshCache();
    this.tab = '我的'; this.mainScroller.scrollTo({ xOffset: 0, yOffset: 0 }); this.message = '已保存到本地待传队列，正在同步…'; this.expected = ''; this.description = ''; this.photo = ''; this.ocrText = '';
    await this.sync();
  }
  private async loadCases(): Promise<void> { this.cases = (await apiClient.request<CasesPage>('/v1/matches')).matches; }
  private async loadMine(): Promise<void> {
    this.notifications = (await apiClient.request<NotificationsPage>('/v1/notifications')).notifications;
    this.appeals = (await apiClient.request<AppealsPage>('/v1/appeals')).appeals;
  }
  private async loadAdmin(): Promise<void> {
    this.admin = await apiClient.request<AdminPage>('/v1/admin'); this.policy = this.admin.policy; await this.loadMine();
  }
  private async chooseTab(tab: string): Promise<void> {
    this.tab = tab; this.sheet = ''; this.mainScroller.scrollTo({ xOffset: 0, yOffset: 0 }); if (tab !== '发布' && this.voice) { await this.voice.stop(); }
    if (tab === '认领') { await this.loadCases(); } if (tab === '我的') { await this.loadMine(); } if (tab === '管理') { await this.loadAdmin(); }
  }
  private async find(item: CampusItem): Promise<void> {
    this.lostId = item.itemId; const result = await apiClient.request<CandidatePage>('/v1/candidates/' + item.itemId);
    this.candidates = result.candidates; this.policy = result.policy; this.sheet = '候选'; this.modalScroller.scrollTo({ xOffset: 0, yOffset: 0 });
  }
  private async claim(foundId: string): Promise<void> {
    const body: PairInput = { lostId: this.lostId, foundId: foundId };
    const result = await apiClient.request<ActionResult>('/v1/claims', http.RequestMethod.POST, JSON.stringify(body));
    this.message = result.message || '认领申请已提交，依序核验'; this.tab = '认领'; this.sheet = ''; await this.loadCases(); await this.sync();
  }
  private async openCase(id: string): Promise<void> {
    this.current = await apiClient.request<PairCase>('/v1/matches/' + id); this.sheet = '流程'; this.modalScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    this.answer = ''; this.evidenceText = ''; this.evidencePath = ''; this.evidenceLevel = 1;
    const own = this.items.filter((i: CampusItem) => i.kind === 'lost' && i.ownerId === this.viewerId() && !['已完成', '已关闭'].includes(i.state));
    this.lostId = own.length ? own[0].itemId : '';
  }
  private viewerId(): string { return cacheStore.scope.split('|').pop() || ''; }
  private authorized(): boolean { return !!this.current && !!this.profile && (this.current.foundOwner === this.profile.id || this.profile.role === 'admin'); }
  private async submitAnswer(id: string): Promise<void> {
    const body: AnswerInput = { answer: this.answer, level: this.evidenceLevel, evidenceText: this.evidenceText,
      evidenceImage: this.evidencePath ? await uploadImage(this.evidencePath) : '' };
    const result = await apiClient.request<ActionResult>('/v1/claims/' + id + '/answer', http.RequestMethod.POST, JSON.stringify(body));
    this.message = result.message || '核验材料已提交'; if (this.current) { await this.openCase(this.current.matchId); } await this.refreshAll();
  }
  private async review(id: string, passed: boolean): Promise<void> {
    const score = Number(this.reviewScore); if (!Number.isFinite(score) || score < 0 || score > 100) { throw new Error('凭证评分须在0至100之间'); }
    const body: ReviewInput = { passed: passed, score: passed ? score : 0 };
    await apiClient.request<ActionResult>('/v1/claims/' + id + '/review', http.RequestMethod.POST, JSON.stringify(body));
    if (this.current) { await this.openCase(this.current.matchId); } await this.refreshAll();
  }
  private async complete(): Promise<void> {
    if (!this.current) { return; } await apiClient.request<ActionResult>('/v1/matches/' + this.current.matchId + '/complete', http.RequestMethod.POST, '{}');
    this.message = '已按凭证分与信用分择优完成领取'; await this.openCase(this.current.matchId); await this.refreshAll();
  }
  private async appeal(): Promise<void> {
    if (!this.current || !this.lostId) { throw new Error('请先发布自己的失物登记，并选择关联登记'); }
    const body: AppealInput = { lostId: this.lostId, level: this.evidenceLevel, evidenceText: this.evidenceText, evidenceImage: this.evidencePath ? await uploadImage(this.evidencePath) : '' };
    await apiClient.request<ActionResult>('/v1/matches/' + this.current.matchId + '/appeals', http.RequestMethod.POST, JSON.stringify(body));
    this.message = '申诉已受理，流程锁定等待发布者或平台裁定'; await this.openCase(this.current.matchId); await this.refreshAll();
  }
  private async decide(id: string, valid: boolean): Promise<void> {
    const body: DecisionInput = { valid: valid };
    await apiClient.request<ActionResult>('/v1/appeals/' + id + '/decision', http.RequestMethod.POST, JSON.stringify(body));
    this.message = valid ? '申诉成立，原流程已重开并优先通知申诉人' : '申诉不成立，已记录裁定与信用变化';
    await this.loadMine(); if (this.tab === '管理') { await this.loadAdmin(); } await this.refreshAll();
  }
  private async refreshAll(): Promise<void> { await campusSync.run(); await this.refreshCache(); this.profile = await apiClient.request<UserProfile>('/v1/me'); await this.loadCases(); }
  private async evidenceOCR(): Promise<void> {
    if (!this.evidencePath) { throw new Error('请先选择证据图片'); } this.evidenceText = await recognizeEvidence(this.evidencePath); this.message = '证据OCR已回填，请确认内容';
  }
  private preset(kind: number): void {
    if (kind === 0) { this.policy.weights = { place: .30, time: .20, ocr: .25, text: .20, color: .05 }; }
    if (kind === 1) { this.policy.weights = { place: .60, time: .15, ocr: .10, text: .10, color: .05 }; }
    if (kind === 2) { this.policy.weights = { place: .10, time: .10, ocr: .45, text: .30, color: .05 }; }
  }
  private async savePolicy(): Promise<void> { await apiClient.request<ActionResult>('/v1/admin/policy', http.RequestMethod.POST, JSON.stringify(this.policy)); this.message = '权重与阈值已保存，新候选实时重算；已有匹配保留审计分数'; await this.loadAdmin(); }
  private async penalty(): Promise<void> {
    const body: ViolationInput = { userId: this.penaltyUser, kind: this.penaltyKind, reasonId: util.generateRandomUUID() };
    await apiClient.request<ActionResult>('/v1/admin/violations', http.RequestMethod.POST, JSON.stringify(body)); await this.loadAdmin();
  }

  @Builder title(text: string, sub: string) { Column({ space: 5 }) { Text(text).fontSize(27).fontWeight(FontWeight.Bold).fontColor('#142A46'); Text(sub).fontSize(13).fontColor('#687D94'); }.alignItems(HorizontalAlign.Start).width('100%').margin({ bottom: 12 }) }
  @Builder action(label: string, id: string, click: () => void) { Button(label).id(id).fontSize(14).backgroundColor('#2467DD').height(42).onClick(click) }
  @Builder inputLabel(label: string) { Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#31465F').width('100%').margin({ top: 9, bottom: 4 }) }
  @Builder badge(text: string) { Text(text).fontSize(12).fontColor('#2467DD').backgroundColor('#EAF1FF').padding({ left: 9, right: 9, top: 5, bottom: 5 }).borderRadius(8) }
  @Builder itemCard(item: CampusItem) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        if (item.imageBase64) { Image('data:image/jpeg;base64,' + item.imageBase64).width(76).height(76).objectFit(ImageFit.Cover).borderRadius(12) }
        else { Text(item.imagePrivate ? '证件图片\n仅本人可见' : '物品登记').fontSize(12).fontColor('#71839A').textAlign(TextAlign.Center).width(76).height(76).backgroundColor('#F0F4F9').borderRadius(12) }
        Column({ space: 5 }) { Text((item.kind === 'lost' ? '寻找 · ' : '拾获 · ') + item.category).fontSize(18).fontWeight(FontWeight.Bold).fontColor('#142A46'); Text(item.place + ' · ' + item.color).fontSize(13).fontColor('#687D94'); Text(formatTime(item.occurredAt)).fontSize(12).fontColor('#7D8EA2'); }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        this.badge(item.state)
      }.width('100%')
      Text(item.description).fontSize(14).fontColor('#40546E').width('100%').maxLines(3)
      if (item.ocrHint) { Text('文字线索：' + item.ocrHint).fontSize(12).fontColor('#71839A').width('100%') }
      Row({ space: 10 }) {
        Text(item.ownerName).fontSize(12).fontColor('#7D8EA2').layoutWeight(1)
        if (item.kind === 'lost' && item.ownerId === this.viewerId() && item.state !== '待上传') { this.action('查看匹配', 'find-' + item.itemId, () => { this.work(async () => { await this.find(item); }); }) }
        if (item.completedMatchId) { this.action('领取记录 / 申诉', 'appeal-' + item.itemId, () => { this.work(async () => { await this.openCase(item.completedMatchId); }); }) }
      }.width('100%')
    }.padding(15).backgroundColor(Color.White).borderRadius(18).width('100%').margin({ bottom: 12 })
  }
  @Builder home() {
    this.title('让每件失物，回到原处', '校园失物招领 · 智能线索 · 有据认领')
    Row({ space: 8 }) { ForEach(['全部', '拾获', '失物'], (value: string) => { Button(value).type(ButtonType.Normal).borderRadius(12).backgroundColor(this.kindFilter === value ? '#2467DD' : Color.White).fontColor(this.kindFilter === value ? Color.White : '#687D94').onClick(() => { this.kindFilter = value; }) }) }.width('100%').margin({ bottom: 15 })
    Text(`${this.items.length}条本地登记 · 缓存可离线浏览`).fontSize(12).fontColor('#71839A').width('100%').margin({ bottom: 10 })
    ForEach(this.items.filter((i: CampusItem) => this.kindFilter === '全部' || i.kind === (this.kindFilter === '拾获' ? 'found' : 'lost')), (item: CampusItem) => { this.itemCard(item) }, (item: CampusItem) => item.itemId + '-' + item.version)
    if (!this.items.length) { Text('还没有缓存的登记\n连接服务刷新，或发布第一条线索').textAlign(TextAlign.Center).fontColor('#71839A').padding(35) }
  }
  @Builder publishForm() {
    this.title('发布一条线索', '拍照或口述，确认结构化字段后提交')
    Row({ space: 10 }) { Button('我丢失了').backgroundColor(this.kind === 'lost' ? '#2467DD' : '#A6B4C6').onClick(() => { this.kind = 'lost'; }); Button('我拾获了').backgroundColor(this.kind === 'found' ? '#2467DD' : '#A6B4C6').onClick(() => { this.kind = 'found'; }) }.width('100%')
    if (this.photo) { Image(fileUri.getUriFromPath(this.photo)).height(180).width('100%').objectFit(ImageFit.Contain).margin({ top: 12 }).borderRadius(16) }
    Row({ space: 7 }) {
      this.action('拍照', 'camera', () => { router.pushUrl({ url: 'pages/Camera' }); })
      this.action('相册', 'gallery', () => { this.work(async () => { await this.pick(); }); })
      this.action('教学图片', 'demo-photo', () => { this.work(async () => { await this.demoPhoto(); }); })
      this.action('识别', 'analyze', () => { this.work(async () => { await this.analyze(); }); })
    }.margin({ top: 12 }).width('100%')
    Text(this.aiNote).id('ai-note').fontSize(12).fontColor('#687D94').margin({ top: 10 }).width('100%')
    this.inputLabel('自然语言描述')
    TextArea({ text: this.description, placeholder: '昨天14点在图书馆北门丢失蓝色校园卡…' }).id('description').height(100).onChange((v: string) => { this.description = v; })
    Row({ space: 10 }) { this.action(this.voiceStatus.listening ? '结束录音' : '语音输入', 'microphone', () => { this.microphone(); }); this.action('提取字段', 'extract', () => { this.work(async () => { await this.extract(); }); }) }.width('100%').margin({ top: 8 })
    Text(this.voiceStatus.message).id('voice-status').fontSize(12).fontColor('#687D94').width('100%').margin({ top: 6 })
    this.inputLabel('类别（可修改）')
    Select(CATEGORIES.map((v: string): SelectOption => { return { value: v }; })).value(this.category).selected(CATEGORIES.indexOf(this.category)).onSelect((i: number) => { this.category = CATEGORIES[i]; }).width('100%').id('category')
    this.inputLabel('颜色'); TextInput({ text: this.color, placeholder: '例如：蓝色' }).id('color').onChange((v: string) => { this.color = v; })
    this.inputLabel('地点'); TextInput({ text: this.place, placeholder: '例如：图书馆北门' }).id('place').onChange((v: string) => { this.place = v; })
    this.inputLabel('丢失 / 拾获时间（北京时间）'); TextInput({ text: this.timeText, placeholder: 'YYYY-MM-DD HH:mm' }).id('time').onChange((v: string) => { this.timeText = v; })
    this.inputLabel('OCR文字线索（确认后可修改）'); TextArea({ text: this.ocrText, placeholder: '卡号、书名或标签文字' }).id('ocr').height(85).onChange((v: string) => { this.ocrText = v; })
    if (this.kind === 'found') {
      this.inputLabel('私密核验问题'); TextInput({ text: this.question, placeholder: '例如：卡片编号是什么？' }).id('question').onChange((v: string) => { this.question = v; })
      this.inputLabel('标准答案（仅保存服务端哈希）'); TextInput({ text: this.expected, placeholder: '不可公开给认领者' }).type(InputType.Password).id('expected').onChange((v: string) => { this.expected = v; })
    }
    Text('证件图与完整OCR只对本人和平台可见；他人仅见文字线索提示。').fontSize(12).fontColor('#687D94').margin({ top: 12 })
    this.action('确认字段并发布', 'publish', () => { this.work(async () => { await this.publish(); }); })
  }
  @Builder casesView() {
    this.title('认领进度', '按序核验 · 竞领择优 · 全程留痕')
    if (!this.cases.length) { Text('暂无认领流程，可从自己的失物登记查看候选并申请').fontColor('#71839A').padding(20) }
    ForEach(this.cases, (pair: PairCase) => {
      Column({ space: 10 }) { Row() { Text(pair.category + ' · ' + pair.place).fontSize(17).fontWeight(FontWeight.Bold).layoutWeight(1); this.badge(pair.state) }.width('100%'); Text(`匹配分 ${Math.round(pair.score * 100)}% · ${pair.claims.length}人参与`).fontSize(13).fontColor('#687D94'); this.action('查看流程', 'case-' + pair.matchId, () => { this.work(async () => { await this.openCase(pair.matchId); }); }) }.padding(16).width('100%').backgroundColor(Color.White).borderRadius(16).margin({ bottom: 12 })
    }, (pair: PairCase) => pair.matchId + pair.state)
  }
  @Builder evidenceForm() {
    this.inputLabel('凭证等级')
    Select([{ value: 'L1 问答记录' }, { value: 'L2 物品文字/照片凭证' }, { value: 'L3 证件照片OCR凭证' }]).selected(this.evidenceLevel - 1).value('L' + this.evidenceLevel).onSelect((i: number) => { this.evidenceLevel = i + 1; }).width('100%')
    TextArea({ text: this.evidenceText, placeholder: '填写可与物品线索核对的编号或文字；L3还须提交图片' }).id('evidence-text').height(85).onChange((v: string) => { this.evidenceText = v; })
    if (this.evidencePath) { Image(fileUri.getUriFromPath(this.evidencePath)).width('100%').height(140).objectFit(ImageFit.Contain) }
    Row({ space: 10 }) { this.action('选择证据图片', 'evidence-photo', () => { this.work(async () => { await this.pick(true); }); }); this.action('证据OCR', 'evidence-ocr', () => { this.work(async () => { await this.evidenceOCR(); }); }) }.width('100%')
  }
  @Builder claimCard(claim: ClaimRow) {
    Column({ space: 8 }) {
      Text(claim.name + ' · ' + claim.state).fontSize(16).fontWeight(FontWeight.Bold).width('100%')
      Text(`凭证 ${claim.score}分 · L${claim.level} · 信用 ${claim.credit}`).fontSize(12).fontColor('#687D94').width('100%')
      if (claim.answer) { Text('作答：' + claim.answer + '\n凭证：' + claim.evidenceText).fontSize(13).width('100%') }
      if (claim.evidenceImage) { Image('data:image/jpeg;base64,' + claim.evidenceImage).height(140).width('100%').objectFit(ImageFit.Contain) }
      if (claim.userId === this.viewerId() && claim.state === '核验中' && !claim.answer) {
        TextInput({ text: this.answer, placeholder: '回答发布者的核验问题' }).id('claim-answer').onChange((v: string) => { this.answer = v; })
        this.evidenceForm()
        this.action('提交核验', 'submit-answer', () => { this.work(async () => { await this.submitAnswer(claim.claimId); }); })
      }
      if (this.authorized() && claim.state === '核验中' && claim.answer) {
        TextInput({ text: this.reviewScore, placeholder: '通过评分60～100' }).id('review-score').type(InputType.Number).onChange((v: string) => { this.reviewScore = v; })
        Row({ space: 10 }) { this.action('审核通过', 'review-pass', () => { this.work(async () => { await this.review(claim.claimId, true); }); }); this.action('驳回凭证', 'review-fail', () => { this.work(async () => { await this.review(claim.claimId, false); }); }) }
      }
    }.padding(13).backgroundColor('#F0F4F9').borderRadius(14).width('100%').margin({ bottom: 9 })
  }
  @Builder caseDetail() {
    if (this.current) {
      Text(this.current.category + ' · ' + this.current.state).id('case-state').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
      Text(this.current.place + ' · 匹配分 ' + Math.round(this.current.score * 100) + '%').fontColor('#687D94').width('100%')
      Text('核验问题：' + this.current.question).fontSize(16).fontWeight(FontWeight.Medium).width('100%').margin({ top: 10, bottom: 10 })
      ForEach(this.current.claims, (c: ClaimRow) => { this.claimCard(c) }, (c: ClaimRow) => c.claimId + c.state + c.answer)
      if (this.authorized() && !['已完成', '已关闭', '申诉中'].includes(this.current.state)) { this.action('确认领取（全部核验后择优）', 'complete', () => { this.work(async () => { await this.complete(); }); }) }
      if (this.current.state === '已完成' && !this.authorized()) {
        Text('发现冒领？提交高于原凭证等级的证据').fontSize(15).fontWeight(FontWeight.Bold).margin({ top: 15 })
        this.inputLabel('关联自己的失物登记')
        Select(this.items.filter((i: CampusItem) => i.kind === 'lost' && i.ownerId === this.viewerId() && !['已完成', '已关闭'].includes(i.state)).map((i: CampusItem): SelectOption => { return { value: i.category + ' · ' + i.place }; })).onSelect((idx: number) => { const own = this.items.filter((i: CampusItem) => i.kind === 'lost' && i.ownerId === this.viewerId() && !['已完成', '已关闭'].includes(i.state)); this.lostId = own[idx].itemId; }).width('100%')
        this.evidenceForm(); this.action('提交申诉', 'appeal-submit', () => { this.work(async () => { await this.appeal(); }); })
      }
      this.inputLabel('流程时间线')
      ForEach(this.current.events, (e: TimelineEvent) => { Column({ space: 4 }) { Text(e.state + ' · ' + formatTime(e.created)).fontSize(13).fontWeight(FontWeight.Medium).width('100%'); Text(e.message).fontSize(13).fontColor('#687D94').width('100%') }.padding(12).backgroundColor('#F0F4F9').borderRadius(12).margin({ bottom: 6 }).width('100%') })
    }
  }
  @Builder appealsView() {
    ForEach(this.appeals, (a: AppealRow) => {
      Column({ space: 8 }) {
        Text('申诉 · ' + a.state + ' · L' + a.level).fontSize(16).fontWeight(FontWeight.Bold).width('100%')
        Text('申请人 ' + a.userId + '\n' + a.evidenceText + (a.decision ? '\n裁定：' + a.decision : '')).fontSize(13).width('100%')
        if (a.evidenceImage) { Image('data:image/jpeg;base64,' + a.evidenceImage).height(140).width('100%').objectFit(ImageFit.Contain) }
        Text('裁定期限 ' + formatTime(a.deadline)).fontSize(12).fontColor('#687D94')
        if (a.state === '待裁定' && (a.userId !== this.viewerId() || (this.profile && this.profile.role === 'admin'))) {
          Text('核对证据后裁定，结果影响领取状态和信用分。').fontSize(12).fontColor('#687D94')
          Row({ space: 10 }) { this.action('申诉成立', 'appeal-valid', () => { this.work(async () => { await this.decide(a.appealId, true); }); }); this.action('申诉不成立', 'appeal-invalid', () => { this.work(async () => { await this.decide(a.appealId, false); }); }) }
        }
      }.padding(15).width('100%').backgroundColor(Color.White).borderRadius(16).margin({ bottom: 10 })
    }, (a: AppealRow) => a.appealId + a.state)
  }
  @Builder mine() {
    if (this.profile) {
      Text(this.profile.name).fontSize(26).fontWeight(FontWeight.Bold).width('100%'); Text(`${this.profile.role === 'admin' ? '平台管理员' : '普通用户'} · 信用 ${this.profile.credit} · ${this.profile.banned ? '认领已限制' : '账号正常'}`).fontSize(14).fontColor('#687D94').width('100%').margin({ bottom: 12 });
      Text('发布信用门槛 ' + this.profile.creditFloor + '分；反复冒领将禁止认领。').fontSize(12).fontColor('#687D94').width('100%')
    }
    this.inputLabel('本地待传队列（' + this.outbox.length + '）')
    if (!this.outbox.length) { Text('所有发布已收到服务端确认').fontSize(13).fontColor('#687D94').width('100%') }
    ForEach(this.outbox, (o: OutboxEntry) => { Text(`${o.payload.category} · 已尝试${o.attempts}次\n${o.error || '等待上传'}\n${o.retryAt ? '下次 ' + formatTime(o.retryAt) : '可立即同步'}`).fontSize(13).fontColor('#95631A').padding(12).backgroundColor('#FFF1DA').borderRadius(12).width('100%') })
    this.action('立即重试同步', 'retry-sync', () => { this.work(async () => { await this.sync(); }); })
    this.inputLabel('通知')
    ForEach(this.notifications, (n: NotificationRow) => { Text(n.message + '\n' + formatTime(n.created)).fontSize(13).fontColor('#40546E').padding(12).backgroundColor(Color.White).borderRadius(12).width('100%').margin({ bottom: 7 }) })
    this.inputLabel('申诉与裁定'); this.appealsView()
    this.inputLabel('我的登记'); ForEach(this.items.filter((i: CampusItem) => i.ownerId === this.viewerId()), (item: CampusItem) => { this.itemCard(item) }, (item: CampusItem) => item.itemId + item.version)
  }
  @Builder adminView() {
    this.title('平台管理', '服务端校验管理员身份 · SQL汇总统计')
    if (this.admin) {
      Text(`用户 ${this.admin.stats.users}    登记 ${this.admin.stats.items}\n匹配 ${this.admin.stats.matches}    完成 ${this.admin.stats.completed}\n待裁定 ${this.admin.stats.pendingAppeals}`).id('admin-stats').fontSize(20).fontWeight(FontWeight.Bold).lineHeight(34).padding(18).width('100%').backgroundColor('#EAF1FF').borderRadius(16)
      ForEach(this.admin.categories, (c: NameCount) => { Text(c.name + '：' + c.count).fontSize(13).width('100%') })
      this.inputLabel('匹配权重与自动阈值')
      Row({ space: 8 }) { Button('均衡').onClick(() => { this.preset(0); }); Button('地点优先').onClick(() => { this.preset(1); }); Button('文字优先').onClick(() => { this.preset(2); }) }
      Text(`地点${this.policy.weights.place} · 时间${this.policy.weights.time} · OCR${this.policy.weights.ocr}\n描述${this.policy.weights.text} · 颜色${this.policy.weights.color}\n自动匹配阈值 ${this.policy.threshold.toFixed(2)}`).id('weights').fontSize(13).lineHeight(24).width('100%')
      Slider({ value: this.policy.threshold, min: .1, max: 1, step: .01 }).onChange((v: number) => { this.policy.threshold = v; }).width('100%')
      this.action('保存策略', 'save-policy', () => { this.work(async () => { await this.savePolicy(); }); })
      this.inputLabel('低信用 / 冒领 / 限制名单')
      ForEach(this.admin.users, (u: UserProfile) => { Text(`${u.id} · ${u.name} · ${u.credit}分 · 冒领${u.false_claims}次 · ${u.banned ? '禁止认领' : '未封禁'}`).fontSize(13).padding(10).width('100%').backgroundColor(Color.White).borderRadius(10) })
      this.inputLabel('登记核实后的违规处罚')
      TextInput({ text: this.penaltyUser, placeholder: '用户ID' }).id('penalty-user').onChange((v: string) => { this.penaltyUser = v; })
      Select([{ value: '虚假发布' }, { value: '爽约' }]).selected(0).value(this.penaltyKind === 'false_post' ? '虚假发布' : '爽约').onSelect((v: number) => { this.penaltyKind = v === 0 ? 'false_post' : 'no_show'; })
      this.action('登记处罚', 'penalty', () => { this.work(async () => { await this.penalty(); }); })
      this.inputLabel('全部申诉'); this.appealsView()
    }
  }
  @Builder modalContent() {
    Column({ space: 10 }) {
      Row() { Text(this.sheet === '连接' ? '连接课程服务' : this.sheet === '候选' ? '匹配候选' : '认领流程').fontSize(21).fontWeight(FontWeight.Bold).layoutWeight(1); Button('关闭').id('close-sheet').backgroundColor('#EAF1FF').fontColor('#2467DD').onClick(() => { this.sheet = ''; }) }.width('100%')
      Scroll(this.modalScroller) { Column({ space: 10 }) {
        if (this.sheet === '连接') {
          Text('账号和随机口令由本机服务配置生成，口令仅保存在应用私有目录。模拟器通过HDC转发连接。').fontSize(13).fontColor('#687D94')
          this.inputLabel('服务地址'); TextInput({ text: this.endpoint }).id('endpoint').onChange((v: string) => { this.endpoint = v; })
          this.inputLabel('账号'); TextInput({ text: this.account, placeholder: '例如：alice / bob / charlie / admin' }).id('account').onChange((v: string) => { this.account = v; })
          this.inputLabel('口令'); TextInput({ text: this.secret, placeholder: '使用本机生成的随机口令' }).id('secret').type(InputType.Password).onChange((v: string) => { this.secret = v; })
          this.action('保存并连接', 'connect', () => { this.work(async () => { await this.connect(); }); })
        }
        if (this.sheet === '候选') {
          Text('类别与时间先约束，再加权评分。低于自动阈值的候选仍可人工认领。').fontSize(13).fontColor('#687D94')
          if (!this.candidates.length) { Text('未检索到符合类别与时间约束的拾获登记，可稍后刷新重试').fontColor('#687D94').padding(20) }
          ForEach(this.candidates, (c: Candidate) => { Column({ space: 9 }) {
            Text(c.item.category + ' · ' + c.item.place).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
            Text(`${Math.round(c.score * 100)}% · ${c.automatic ? '达到自动阈值' : '可人工申请'}\n地点 ${c.factors.place.toFixed(2)} · 时间 ${c.factors.time.toFixed(2)}\nOCR ${c.factors.ocr.toFixed(2)} · 描述 ${c.factors.text.toFixed(2)} · 颜色 ${c.factors.color.toFixed(2)}`).fontSize(13).lineHeight(23).width('100%')
            Text(c.item.description).fontSize(13).fontColor('#687D94').width('100%'); this.action('申请认领', 'claim-' + c.item.itemId, () => { this.work(async () => { await this.claim(c.item.itemId); }); })
          }.padding(15).backgroundColor('#F0F4F9').borderRadius(14).width('100%') }, (c: Candidate) => c.item.itemId)
        }
        if (this.sheet === '流程') { this.caseDetail() }
      }.width('100%').padding({ bottom: 20 }) }.layoutWeight(1).width('100%')
    }.padding(18).width('96%').height('84%').backgroundColor(Color.White).borderRadius(24).shadow({ radius: 25, color: '#44000000', offsetY: 3 })
  }
  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        Row({ space: 10 }) { Image($r('app.media.app_icon')).width(40).height(40); Text('归物').fontSize(25).fontWeight(FontWeight.Bold).fontColor('#142A46').layoutWeight(1); Button('连接').id('settings').backgroundColor('#EAF1FF').fontColor('#2467DD').onClick(() => { this.sheet = '连接'; }); Button('刷新').id('sync').backgroundColor('#2467DD').onClick(() => { this.work(async () => { await this.sync(); }); }) }.padding({ left: 20, right: 20, top: 12, bottom: 12 }).width('100%')
        Text(this.error || this.message).id('status').fontSize(12).fontColor(this.error ? '#A74721' : '#517095').padding({ left: 20, right: 20, top: 7, bottom: 7 }).backgroundColor(this.error ? '#FFF1DA' : '#EAF1FF').width('100%').maxLines(3)
        if (this.busy) { Row({ space: 10 }) { LoadingProgress().width(20).height(20); Text('处理中，请稍候…').fontSize(12).fontColor('#2467DD') }.width('100%').padding(7) }
        Scroll(this.mainScroller) { Column({ space: 10 }) { if (this.tab === '广场') { this.home() } if (this.tab === '发布') { this.publishForm() } if (this.tab === '认领') { this.casesView() } if (this.tab === '我的') { this.mine() } if (this.tab === '管理') { this.adminView() } }.padding(20).width('100%').alignItems(HorizontalAlign.Start) }.layoutWeight(1).width('100%').align(Alignment.TopStart).id('content-scroll')
        Row() { ForEach(this.profile && this.profile.role === 'admin' ? ['广场', '发布', '认领', '我的', '管理'] : ['广场', '发布', '认领', '我的'], (value: string) => { Text(value).fontSize(16).fontWeight(this.tab === value ? FontWeight.Bold : FontWeight.Normal).fontColor(this.tab === value ? '#2467DD' : '#7D8EA2').layoutWeight(1).textAlign(TextAlign.Center).height(52).id('tab-' + value).onClick(() => { this.work(async () => { await this.chooseTab(value); }); }) }) }.padding({ bottom: 18, top: 6 }).width('100%').backgroundColor(Color.White)
      }.width('100%').height('100%').backgroundColor('#F5F7FB').padding({ top: 28 })
      if (this.sheet) { Column().width('100%').height('100%').backgroundColor('#77142A46'); this.modalContent() }
    }.width('100%').height('100%')
  }
}
