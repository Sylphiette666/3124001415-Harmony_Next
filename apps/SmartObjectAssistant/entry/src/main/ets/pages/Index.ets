import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { fileUri } from '@kit.CoreFileKit';
import { ScanRecord, Detection, AppSettings, InferenceResult, Timings, ModelManifest, CloudPage, CloudStats, UploadRecord, EMPTY_TIMINGS, InferenceRequest, CategoryCount } from '../model/Types';
import { LABELS, summarize } from '../model/DetectionMath';
import { scanStore } from '../model/ScanStore';
import { inferenceService } from '../services/Inference';
import { importPhoto, makeThumbnail, ensureFolders, writeFile, exportPhoto } from '../services/MediaFiles';
import { prepareBundledModel, updateModel } from '../services/Models';
import { apiClient, validateEndpoint } from '../services/ApiClient';
import { syncService } from '../services/SyncService';

const INK: string = '#153E39';
const GREEN: string = '#236751';
const MUTED: string = '#6C7D75';
const BG: string = '#F5F6F2';

@Entry
@Component
struct Index {
  @State tab: number = 0;
  @State ready: boolean = false;
  @State busy: boolean = false;
  @State notice: string = '';
  @State error: string = '';
  @State imagePath: string = '';
  @State photoWidth: number = 1;
  @State photoHeight: number = 1;
  @State detections: Detection[] = [];
  @State hasResult: boolean = false;
  @State threshold: number = 0.35;
  @State resultThreshold: number = 0.35;
  @State resultModelVersion: string = '1.0.0';
  @State timings: Timings = EMPTY_TIMINGS;
  @State comparison: Timings[] = [];
  @State savedId: string = '';
  @State recognizedAt: number = 0;
  @State records: ScanRecord[] = [];
  @State sheet: string = '';
  @State settings: AppSettings = { endpoint: 'http://127.0.0.1:8765', deviceId: '', deviceKey: '', autoSync: true, modelPath: '', modelVersion: '1.0.0' };
  @State endpointDraft: string = '';
  @State deviceDraft: string = '';
  @State keyDraft: string = '';
  @State autoDraft: boolean = true;
  @State category: string = '';
  @State startDate: string = '';
  @State endDate: string = '';
  @State cloudRecords: UploadRecord[] = [];
  @State cloudTotal: number = 0;
  @State cloudPage: number = 1;
  @State cloudStats: CloudStats = { recordCount: 0, objectCount: 0, categories: [] };
  @State syncing: boolean = false;
  @State querying: boolean = false;
  @State modelBusy: boolean = false;
  @State checkingModel: boolean = false;
  @State modelNotice: string = '随包模型 · 可离线识别';
  @State modelInfo: string = '';
  @State manifest: ModelManifest | undefined = undefined;
  @State editItems: Detection[] = [];
  @State editing: ScanRecord | undefined = undefined;
  @State visibleRecord: ScanRecord | undefined = undefined;
  @State pulse: number = 0;
  private initializing: boolean = false;
  private syncError: string = '';
  private alive: boolean = false;
  private pulseTimer: number = -1;
  private canvasSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvas: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.canvasSettings);
  private canvasWidth: number = 0;
  private canvasHeight: number = 300;
  private canvasReady: boolean = false;

  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  aboutToAppear(): void { this.alive = true; this.initialize(); }
  onPageShow(): void {
    this.alive = true;
    const capture = AppStorage.get<string>('smartObjectCapture');
    if (capture) { AppStorage.set('smartObjectCapture', ''); this.setImage(capture); }
    if (this.ready) { syncService.start((message: string) => { this.syncChanged(message); }); this.refreshRecords(); }
  }
  onPageHide(): void { this.alive = false; syncService.stop(); }
  aboutToDisappear(): void { this.alive = false; syncService.stop(); if (this.pulseTimer >= 0) { clearInterval(this.pulseTimer); } }
  onBackPress(): boolean {
    if (this.sheet && !this.modelBusy && !this.busy) { this.sheet = ''; return true; }
    return false;
  }
  private async initialize(): Promise<void> {
    if (this.initializing) { return; }
    this.initializing = true; this.error = '';
    try {
      await scanStore.init(this.context()); ensureFolders(this.context());
      this.settings = await prepareBundledModel(this.context(), await scanStore.settings()); apiClient.configure(this.settings);
      this.modelInfo = await inferenceService.inspect(this.settings.modelPath); this.ready = true; await this.refreshRecords();
      syncService.start((message: string) => { this.syncChanged(message); });
      if (apiClient.configured) { this.checkModel(false); syncService.auto(); }
    } catch (error) { console.error('SmartObjects initialization: ' + (error as Error).message); this.error = '模型或本地记录加载失败，请点击重新加载。若仍失败，请检查安装包中的模型是否完整。'; }
    finally { this.initializing = false; }
  }
  private async setImage(path: string): Promise<void> {
    if (this.busy || this.modelBusy) { return; }
    this.error = ''; this.notice = ''; this.detections = []; this.hasResult = false; this.savedId = ''; this.comparison = [];
    const source = image.createImageSource(path);
    try {
      const info = await source.getImageInfo();
      if (info.size.width * info.size.height > 16000000) { throw new Error('请选择1600万像素以内的图片，以免占用过多内存。'); }
      this.imagePath = path; this.photoWidth = info.size.width; this.photoHeight = info.size.height; this.drawBoxes();
    } catch (error) { this.error = (error as Error).message || '无法读取图片，请重新选择。'; }
    finally { await source.release(); }
  }
  private async pickPhoto(): Promise<void> {
    if (this.busy || this.modelBusy) { return; }
    this.error = '';
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const selected = await picker.select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: 1 });
      if (selected.photoUris.length) { await this.setImage(await importPhoto(this.context(), selected.photoUris[0])); }
    } catch { this.error = '选图失败，请重新打开相册，或使用拍照与示例照片。'; }
  }
  private async sample(): Promise<void> {
    if (this.busy || this.modelBusy) { return; }
    try {
      const bytes = await this.context().resourceManager.getRawFileContent('sample-bus.jpg');
      const path = this.context().filesDir + '/images/sample-bus.jpg'; writeFile(path, bytes.slice().buffer as ArrayBuffer);
      await this.setImage(path); this.notice = '已载入随包示例照片，点击开始识别。';
    } catch { this.error = '示例图片读取失败，请重试或选择自己的照片。'; }
  }
  private async recognize(compare: boolean = false): Promise<void> {
    if (this.busy || this.modelBusy || !this.imagePath || !this.ready) { return; }
    this.busy = true; this.error = ''; this.notice = ''; this.savedId = ''; this.comparison = [];
    this.pulse = 0; this.pulseTimer = setInterval(() => { this.pulse++; }, 100);
    try {
      const request: InferenceRequest = { imagePath: this.imagePath, modelPath: this.settings.modelPath, threshold: this.threshold, mode: 'TaskPool' };
      const usedVersion = this.settings.modelVersion;
      const result = await inferenceService.run(request);
      this.applyResult(result); this.resultThreshold = this.threshold; this.resultModelVersion = usedVersion;
      if (compare) {
        const sync = await inferenceService.run({ imagePath: this.imagePath, modelPath: this.settings.modelPath, threshold: this.threshold, mode: '同步' });
        this.comparison = [result.timings, sync.timings]; this.notice = '对照完成。同步模式仅供比较，日常识别使用 TaskPool。';
      } else { this.notice = this.detections.length ? `识别到 ${this.detections.length} 个物品，可修正清单后保存。` : '没有检出物品。可降低置信度阈值，或换一张更清晰的照片后重试。'; }
    } catch (error) { this.error = (error as Error).message || '识别失败，请检查图片与模型后重试。'; }
    finally { this.busy = false; clearInterval(this.pulseTimer); this.pulseTimer = -1; }
  }
  private applyResult(result: InferenceResult): void {
    this.photoWidth = result.geometry.width; this.photoHeight = result.geometry.height; this.detections = result.detections;
    this.timings = result.timings; this.hasResult = true; this.recognizedAt = Date.now(); this.drawBoxes();
  }
  private drawBoxes(): void {
    if (!this.canvasReady || !this.canvasWidth) { return; }
    const ctx = this.canvas; const scale = Math.min(this.canvasWidth / this.photoWidth, this.canvasHeight / this.photoHeight);
    const left = (this.canvasWidth - this.photoWidth * scale) / 2; const top = (this.canvasHeight - this.photoHeight * scale) / 2;
    ctx.clearRect(0, 0, this.canvasWidth, this.canvasHeight); ctx.lineWidth = 2;
    ctx.font = `${this.getUIContext().vp2px(12)}px sans-serif`;
    this.detections.forEach((item: Detection) => {
      const x = left + item.x1 * scale; const y = top + item.y1 * scale;
      const label = item.name + ' ' + Math.round(item.score * 100) + '%'; const labelWidth = ctx.measureText(label).width + 10;
      ctx.strokeStyle = '#C8FF8E'; ctx.strokeRect(x, y, (item.x2 - item.x1) * scale, (item.y2 - item.y1) * scale);
      const labelY = Math.max(0, y - 20); const labelX = Math.max(0, Math.min(this.canvasWidth - labelWidth, x));
      ctx.fillStyle = '#153E39'; ctx.fillRect(labelX, labelY, labelWidth, 20); ctx.fillStyle = '#E5FFD2'; ctx.fillText(label, labelX + 5, labelY + 14);
    });
  }
  private async saveResult(): Promise<void> {
    if (this.busy || !this.hasResult || this.savedId) { return; }
    this.busy = true; this.error = '';
    try {
      const id = util.generateRandomUUID(); const now = Date.now();
      const thumb = await makeThumbnail(this.context(), this.imagePath, id);
      const record: ScanRecord = { recordId: id, capturedAt: this.recognizedAt || now, updatedAt: now, revision: 1, imagePath: this.imagePath,
        thumbnailPath: thumb, width: this.photoWidth, height: this.photoHeight, modelVersion: this.resultModelVersion,
        threshold: this.resultThreshold, items: this.detections.slice(), timings: this.timings,
        syncState: 'pending', attempts: 0, nextRetry: 0, lastError: '' };
      await scanStore.save(record); this.savedId = id; await this.refreshRecords(); this.notice = '已保存到本机记录。配置服务后可同步。'; syncService.auto();
    } catch { this.error = '本地保存失败，请重试。'; }
    finally { this.busy = false; }
  }
  private editResult(record?: ScanRecord): void {
    this.editing = record; const items = record ? record.items : this.detections;
    this.editItems = JSON.parse(JSON.stringify(items)) as Detection[]; this.error = ''; this.sheet = 'edit';
  }
  private editLabel(id: string, name: string): void {
    this.editItems = this.editItems.map((item: Detection): Detection => {
      if (item.id !== id) { return item; }
      return { id: item.id, classId: LABELS.indexOf(name.trim()), name: name, score: item.score, x1: item.x1, y1: item.y1, x2: item.x2, y2: item.y2 };
    });
  }
  private async saveEdits(): Promise<void> {
    if (this.busy) { return; }
    if (this.editItems.some((item: Detection) => !item.name.trim())) { this.error = '类别名称不能为空。'; return; }
    this.busy = true;
    try {
      const items = this.editItems.map((item: Detection): Detection => {
        return { id: item.id, classId: item.classId, name: item.name.trim().slice(0, 50), score: item.score, x1: item.x1, y1: item.y1, x2: item.x2, y2: item.y2 };
      });
      if (this.editing) {
        const record = JSON.parse(JSON.stringify(this.editing)) as ScanRecord; record.items = items; record.revision++; record.updatedAt = Date.now();
        record.syncState = 'pending'; record.lastError = ''; record.attempts = 0; record.nextRetry = 0;
        await scanStore.save(record); this.visibleRecord = record;
        if (this.savedId === record.recordId) { this.detections = items; this.drawBoxes(); }
        await this.refreshRecords(); this.sheet = ''; this.notice = '清单已修正，新版本将重新同步。'; syncService.auto();
      } else { this.detections = items; this.savedId = ''; this.drawBoxes(); this.sheet = ''; this.notice = '已修正清单，可保存到本机。'; }
    } catch { this.error = '修改保存失败，请重试。'; }
    finally { this.busy = false; }
  }
  private interval(): number[] {
    const parse = (value: string): number => {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) { throw new Error('日期格式为 YYYY-MM-DD，例如 2026-10-22。'); }
      const stamp = Date.parse(value + 'T00:00:00+08:00');
      if (!Number.isFinite(stamp) || new Date(stamp + 8 * 3600000).toISOString().slice(0, 10) !== value) { throw new Error('日期无效，请检查。'); }
      return stamp;
    };
    const start = this.startDate ? parse(this.startDate.trim()) : 0;
    const end = this.endDate ? parse(this.endDate.trim()) + 86400000 - 1 : 32503680000000;
    if (start > end) { throw new Error('开始日期不能晚于结束日期。'); } return [start, end];
  }
  private async refreshRecords(): Promise<void> {
    if (!this.ready) { return; }
    try { const range = this.interval(); this.records = await scanStore.records(this.category, range[0], range[1]); }
    catch (error) { this.error = (error as Error).message || '读取记录失败，请重试。'; }
  }
  private showRecord(record: ScanRecord): void { this.visibleRecord = record; this.error = ''; this.sheet = 'record'; }
  private removeRecord(record: ScanRecord): void {
    AlertDialog.show({ title: '删除本机记录？', message: '已同步的云端记录会保留。',
      primaryButton: { value: '取消', action: () => {} }, secondaryButton: { value: '删除', action: () => {
        scanStore.remove(record.recordId).then(() => { this.sheet = ''; this.refreshRecords(); }).catch(() => { this.error = '删除失败，请重试。'; });
      } } });
  }
  private openSettings(): void {
    this.endpointDraft = this.settings.endpoint; this.deviceDraft = this.settings.deviceId; this.keyDraft = this.settings.deviceKey;
    this.autoDraft = this.settings.autoSync; this.error = ''; this.sheet = 'settings';
  }
  private async saveSettings(): Promise<void> {
    if (this.modelBusy || this.busy || syncService.busy) { this.error = '请等待当前处理完成后保存连接设置。'; return; }
    try {
      const endpoint = validateEndpoint(this.endpointDraft);
      if (!/^[A-Za-z0-9_-]{3,100}$/.test(this.deviceDraft.trim())) { throw new Error('设备标识需为3—100位字母、数字、下划线或连字符。'); }
      if (this.keyDraft && this.keyDraft.length < 16) { throw new Error('请输入服务端分配的完整设备密钥。'); }
      const next: AppSettings = { endpoint: endpoint, deviceId: this.deviceDraft.trim(), deviceKey: this.keyDraft.trim(),
        autoSync: this.autoDraft, modelPath: this.settings.modelPath, modelVersion: this.settings.modelVersion };
      await scanStore.saveSettings(next); this.settings = next; apiClient.configure(next); this.sheet = ''; this.notice = '连接设置已保存。';
      if (apiClient.configured) { this.checkModel(false); syncService.auto(); }
    } catch (error) { this.error = (error as Error).message || '设置保存失败，请重试。'; }
  }
  private async sync(): Promise<void> {
    if (this.syncing) { return; }
    this.syncing = true; this.error = ''; this.notice = '正在同步本机待传记录…';
    try { this.notice = await syncService.sync(true); }
    catch (error) { this.notice = ''; this.error = (error as Error).message || '上传失败，可重试。'; this.syncError = this.error; }
    finally { this.syncing = false; await this.refreshRecords(); }
  }
  private syncChanged(message: string): void {
    this.refreshRecords();
    if (message && this.syncError && this.error === this.syncError) {
      this.error = ''; this.syncError = ''; this.notice = message;
    }
  }
  private async queryCloud(page: number = 1): Promise<void> {
    if (this.querying) { return; }
    this.querying = true; this.error = '';
    try {
      const range = this.interval(); const query = `start=${range[0]}&end=${range[1]}&category=${encodeURIComponent(this.category.trim())}`;
      const result = await apiClient.request<CloudPage>(`/v1/records?${query}&page=${page}&pageSize=10`);
      const stats = await apiClient.request<CloudStats>('/v1/statistics?' + query);
      this.cloudRecords = result.records; this.cloudTotal = result.total; this.cloudPage = result.page; this.cloudStats = stats;
      if (!result.total) { this.notice = '云端没有符合条件的记录。可调整筛选条件或先同步本机记录。'; }
      else { this.notice = ''; }
    } catch (error) { this.error = (error as Error).message || '查询失败，请重试。'; }
    finally { this.querying = false; }
  }
  private async checkModel(loud: boolean = true): Promise<void> {
    if (this.modelBusy || this.checkingModel) { return; }
    this.checkingModel = true; this.modelNotice = '正在检查模型版本…';
    try {
      this.manifest = await apiClient.request<ModelManifest>('/v1/models/latest');
      this.modelNotice = this.manifest.version === this.settings.modelVersion ? '当前已是最新版本' : `发现新模型 ${this.manifest.version}，可下载更新`;
    } catch (error) { this.modelNotice = '暂时无法检查更新，当前模型仍可离线识别。'; if (loud) { this.error = (error as Error).message; } }
    finally { this.checkingModel = false; }
  }
  private async downloadModel(): Promise<void> {
    if (this.modelBusy || this.checkingModel || this.busy || !this.manifest) { return; }
    this.modelBusy = true; this.error = ''; this.modelNotice = '正在下载并校验模型，完成前继续保留旧版本…';
    try {
      this.settings = await updateModel(this.context(), this.settings, this.manifest);
      this.modelInfo = await inferenceService.inspect(this.settings.modelPath); this.modelNotice = '模型已校验并切换至 ' + this.settings.modelVersion;
    } catch (error) { this.error = (error as Error).message || '更新失败，已保留旧模型，请重试。'; this.modelNotice = '更新未完成，当前版本 ' + this.settings.modelVersion; }
    finally { this.modelBusy = false; }
  }
  private date(stamp: number): string {
    const date = new Date(stamp); const two = (n: number): string => n.toString().padStart(2, '0');
    return `${date.getFullYear()}-${two(date.getMonth() + 1)}-${two(date.getDate())} ${two(date.getHours())}:${two(date.getMinutes())}`;
  }
  private async exportRecordPhoto(): Promise<void> {
    if (this.busy || !this.visibleRecord) { return; }
    this.busy = true; this.error = '';
    try { this.notice = await exportPhoto(this.context(), this.visibleRecord.imagePath) ? '照片已保存到相册。' : '已取消相册保存。'; }
    catch { this.error = '相册保存未完成，请重试。原始照片仍保留在本机记录中。'; }
    finally { this.busy = false; }
  }
  private countText(items: Detection[]): string { return summarize(items).map((item) => item.name + ' × ' + item.count).join(' · ') || '未检出物品'; }

  @Builder private smallButton(label: string, action: () => void) {
    Button(label).height(36).fontSize(13).backgroundColor('#E5EDE4').fontColor(GREEN).onClick(action)
  }
  @Builder private title(name: string, sub: string) {
    Column({ space: 6 }) { Text(name).fontSize(28).fontWeight(FontWeight.Bold).fontColor(INK); Text(sub).fontSize(12).fontColor(MUTED) }.alignItems(HorizontalAlign.Start).width('100%')
  }
  @Builder private timingView(t: Timings) {
    Column({ space: 7 }) {
      Text(`${t.mode} · 总计 ${t.totalMs.toFixed(0)} ms`).fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK)
      Text(`预处理 ${t.preprocessMs.toFixed(0)}  /  推理 ${t.inferenceMs.toFixed(0)}  /  后处理 ${t.postprocessMs.toFixed(0)} ms`).fontSize(12).fontColor(MUTED)
      Text(`解码 ${t.decodeMs.toFixed(0)} ms · 模型加载 ${t.loadMs.toFixed(0)} ms · 主线程最大延迟 ${t.uiDelayMs.toFixed(0)} ms`).fontSize(11).fontColor(MUTED)
    }.alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor('#EDF2E9').borderRadius(12)
  }
  @Builder private currentTimingView() {
    Column({ space: 7 }) {
      Text(`${this.timings.mode} · 总计 ${this.timings.totalMs.toFixed(0)} ms`).fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK)
      Text(`预处理 ${this.timings.preprocessMs.toFixed(0)}  /  推理 ${this.timings.inferenceMs.toFixed(0)}  /  后处理 ${this.timings.postprocessMs.toFixed(0)} ms`).fontSize(12).fontColor(MUTED)
      Text(`解码 ${this.timings.decodeMs.toFixed(0)} ms · 模型加载 ${this.timings.loadMs.toFixed(0)} ms · 主线程最大延迟 ${this.timings.uiDelayMs.toFixed(0)} ms`).fontSize(11).fontColor(MUTED)
    }.alignItems(HorizontalAlign.Start).width('100%').padding(14).backgroundColor('#EDF2E9').borderRadius(12)
  }
  @Builder private captureTab() {
    Scroll() {
      Column({ space: 18 }) {
        Column({ space: 6 }) { Text('识别身边的物品').fontSize(28).fontWeight(FontWeight.Bold).fontColor(INK); Text(`YOLOv13n · 80类物品 · 模型 ${this.settings.modelVersion}`).fontSize(12).fontColor(MUTED) }.alignItems(HorizontalAlign.Start).width('100%')
        Stack() {
          if (this.imagePath) {
            Image(fileUri.getUriFromPath(this.imagePath)).width('100%').height(300).objectFit(ImageFit.Contain).borderRadius(18)
          } else {
            Column({ space: 16 }) {
              Text('⌜  ◇  ⌟').fontSize(52).fontColor('#729279')
              Text('拍摄或选择一张照片').fontSize(20).fontWeight(FontWeight.Medium).fontColor(INK)
              Text('识别在本机完成，图片保存在本机。').fontSize(13).fontColor(MUTED)
            }.width('100%').height(300).justifyContent(FlexAlign.Center)
          }
          Canvas(this.canvas).width('100%').height(300).hitTestBehavior(HitTestMode.None)
            .onReady(() => { this.canvasReady = true; this.drawBoxes(); })
            .onAreaChange((_old: Area, current: Area) => { this.canvasWidth = Number(current.width); this.canvasHeight = Number(current.height); this.drawBoxes(); })
        }.width('100%').height(300).backgroundColor('#E6EBDD').borderRadius(18).clip(true)
        Row({ space: 12 }) {
          Button('相机拍照').id('OpenCamera').layoutWeight(1).height(48).backgroundColor(INK).fontColor(Color.White)
            .enabled(!this.busy && !this.modelBusy).onClick(() => { this.getUIContext().getRouter().pushUrl({ url: 'pages/Camera' }).catch(() => { this.error = '相机页面打开失败，请重试。'; }); })
          Button('相册选图').id('ChoosePhoto').layoutWeight(1).height(48).backgroundColor('#DCEAD4').fontColor(INK)
            .enabled(!this.busy && !this.modelBusy).onClick(() => { this.pickPhoto(); })
        }.width('100%')
        this.smallButton('使用示例照片', () => { this.sample(); })
        Column({ space: 8 }) {
          Row() { Text('置信度阈值').fontColor(INK).fontSize(15); Blank(); Text(Math.round(this.threshold * 100) + '%').fontColor(GREEN).fontWeight(FontWeight.Bold) }.width('100%')
          Slider({ value: this.threshold, min: 0.1, max: 0.9, step: 0.05 }).id('ConfidenceSlider').selectedColor(GREEN).width('100%')
            .enabled(!this.busy).onChange((value: number) => { this.threshold = value; })
          Text('阈值越高，保留的结果越谨慎。调整后点击识别重新计算。').fontSize(11).fontColor(MUTED)
        }.alignItems(HorizontalAlign.Start).width('100%')
        Button(this.busy ? `正在处理… ${this.pulse}` : '开始识别').id('RunDetection').width('100%').height(50).fontSize(17)
          .backgroundColor(GREEN).enabled(!!this.imagePath && !this.busy && !this.modelBusy).onClick(() => { this.recognize(); })
        if (this.hasResult) {
          Column({ space: 12 }) {
            Row() { Text('物品清单').fontSize(21).fontWeight(FontWeight.Bold).fontColor(INK); Blank(); this.smallButton('修正清单', () => { this.editResult(); }) }.width('100%')
            Text(this.countText(this.detections)).id('ObjectSummary').fontSize(17).fontColor(GREEN).lineHeight(26).width('100%')
            Text(`结果模型 ${this.resultModelVersion} · 阈值 ${Math.round(this.resultThreshold * 100)}%`).fontSize(11).fontColor(MUTED)
            this.currentTimingView()
            Button(this.savedId ? '已保存到本机' : '保存识别记录').id('SaveDetection').width('100%').height(44).backgroundColor(INK)
              .enabled(!this.busy && !this.savedId).onClick(() => { this.saveResult(); })
          }.width('100%').alignItems(HorizontalAlign.Start)
        }
        Divider().color('#DFE5DC')
        Column({ space: 12 }) {
          Text('推理响应对照').fontSize(17).fontColor(INK).fontWeight(FontWeight.Medium)
          Text('使用同一照片和阈值，顺序比较 TaskPool 与同步调用。同步测试期间界面可能短暂停顿。').fontSize(12).fontColor(MUTED).lineHeight(20)
          Button('运行同步 / 异步对照').id('CompareInference').height(40).fontSize(13).fontColor(GREEN).backgroundColor('#E5EDE4')
            .enabled(!!this.imagePath && !this.busy && !this.modelBusy).onClick(() => { this.recognize(true); })
          ForEach(this.comparison, (t: Timings) => { this.timingView(t) }, (t: Timings) => t.mode)
        }.alignItems(HorizontalAlign.Start).width('100%')
      }.padding(20).width('100%').constraintSize({ maxWidth: 720 })
    }.id('RecognitionScroll').layoutWeight(1).width('100%').scrollBar(BarState.Auto)
  }
  @Builder private filters(cloud: boolean) {
    Column({ space: 10 }) {
      TextInput({ text: this.category, placeholder: '按物品类别筛选，如 水杯 / 人' }).id('CategoryFilter').onChange((v: string) => { this.category = v; }).maxLength(50)
      Row({ space: 8 }) {
        TextInput({ text: this.startDate, placeholder: '开始 YYYY-MM-DD' }).id('StartDate').layoutWeight(1).fontSize(12).onChange((v: string) => { this.startDate = v; }).maxLength(10)
        TextInput({ text: this.endDate, placeholder: '结束 YYYY-MM-DD' }).id('EndDate').layoutWeight(1).fontSize(12).onChange((v: string) => { this.endDate = v; }).maxLength(10)
      }.width('100%')
      Row({ space: 10 }) {
        this.smallButton(cloud ? '查询云端 / 重试' : '筛选 / 刷新', () => { if (cloud) { this.queryCloud(); } else { this.refreshRecords(); } })
        this.smallButton('清空筛选', () => { this.category = ''; this.startDate = ''; this.endDate = ''; if (cloud) { this.queryCloud(); } else { this.refreshRecords(); } })
      }.width('100%')
    }.width('100%')
  }
  @Builder private historyTab() {
    Scroll() {
      Column({ space: 16 }) {
        Column({ space: 6 }) { Text('本机识别记录').fontSize(28).fontWeight(FontWeight.Bold).fontColor(INK); Text(`${this.records.length} 条匹配记录 · 展示最近200条`).fontSize(12).fontColor(MUTED) }.alignItems(HorizontalAlign.Start).width('100%')
        this.filters(false)
        Button(this.syncing ? '正在同步…' : '同步待传记录 / 重试').id('SyncRecords').width('100%').height(44).backgroundColor(GREEN).enabled(!this.syncing).onClick(() => { this.sync(); })
        if (!this.records.length) { Text('还没有符合条件的记录。识别照片后可在这里保存和查询。').fontSize(15).fontColor(MUTED).lineHeight(24).padding(20) }
        ForEach(this.records, (record: ScanRecord) => {
          Column({ space: 10 }) {
            Row({ space: 12 }) {
              Image(fileUri.getUriFromPath(record.thumbnailPath)).width(72).height(72).borderRadius(12).objectFit(ImageFit.Cover)
              Column({ space: 7 }) {
                Text(this.countText(record.items)).fontSize(16).fontColor(INK).fontWeight(FontWeight.Medium).maxLines(2)
                Text(this.date(record.capturedAt)).fontSize(11).fontColor(MUTED)
                Text(record.syncState === 'uploaded' ? '已同步 · 版本 ' + record.revision : '待同步 · 已重试 ' + record.attempts + ' 次').fontSize(11).fontColor(GREEN)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }.width('100%')
            if (record.lastError) { Text(record.lastError).fontSize(11).fontColor('#A34D32').maxLines(3) }
            Row({ space: 8 }) { this.smallButton('查看记录', () => { this.showRecord(record); }); this.smallButton('修正清单', () => { this.editResult(record); }); this.smallButton('删除本机', () => { this.removeRecord(record); }) }
          }.width('100%').padding(16).alignItems(HorizontalAlign.Start).backgroundColor(Color.White).borderRadius(16)
        }, (record: ScanRecord) => record.recordId + '-' + record.revision + '-' + record.syncState + '-' + record.attempts)
      }.width('100%').padding(20).constraintSize({ maxWidth: 720 })
    }.id('HistoryScroll').width('100%').layoutWeight(1)
  }
  @Builder private cloudTab() {
    Scroll() {
      Column({ space: 16 }) {
        this.title('云端记录与统计', '鉴权连接 · 批量同步 · 分类统计')
        if (!apiClient.configured) { Text('先在右上角设置中连接自己的服务。端侧识别和本机记录可独立使用。').fontColor(MUTED).fontSize(14).lineHeight(23) }
        this.filters(true)
        if (this.querying) { Row({ space: 12 }) { LoadingProgress().width(24).height(24); Text('正在读取云端记录…').fontColor(MUTED) } }
        Row({ space: 12 }) {
          Column({ space: 5 }) { Text(this.cloudStats.recordCount.toString()).fontSize(30).fontWeight(FontWeight.Bold).fontColor(INK); Text('条识别记录').fontSize(12).fontColor(MUTED) }.layoutWeight(1)
          Column({ space: 5 }) { Text(this.cloudStats.objectCount.toString()).fontSize(30).fontWeight(FontWeight.Bold).fontColor(INK); Text('个匹配物品').fontSize(12).fontColor(MUTED) }.layoutWeight(1)
        }.padding(20).width('100%').backgroundColor('#E4EEDB').borderRadius(16)
        ForEach(this.cloudStats.categories, (count: CategoryCount) => { Row() { Text(count.name).fontColor(INK); Blank(); Text(count.count.toString()).fontColor(GREEN) }.width('100%') }, (count: CategoryCount) => count.name)
        ForEach(this.cloudRecords, (record: UploadRecord) => {
          Column({ space: 8 }) {
            Text(this.countText(record.items)).fontColor(INK).fontSize(16).fontWeight(FontWeight.Medium)
            Text(this.date(record.capturedAt) + ' · 版本 ' + record.revision).fontSize(12).fontColor(MUTED)
            Text('记录 ' + record.recordId).fontSize(10).fontColor(MUTED).copyOption(CopyOptions.LocalDevice)
          }.alignItems(HorizontalAlign.Start).width('100%').padding(16).backgroundColor(Color.White).borderRadius(14)
        }, (record: UploadRecord) => record.recordId + '-' + record.revision)
        Row({ space: 8 }) {
          Button('上一页').enabled(this.cloudPage > 1 && !this.querying).backgroundColor('#E5EDE4').fontColor(GREEN).onClick(() => { this.queryCloud(this.cloudPage - 1); })
          Text(`${this.cloudPage} / ${Math.max(1, Math.ceil(this.cloudTotal / 10))}`).fontColor(MUTED).layoutWeight(1).textAlign(TextAlign.Center)
          Button('下一页').enabled(this.cloudPage * 10 < this.cloudTotal && !this.querying).backgroundColor('#E5EDE4').fontColor(GREEN).onClick(() => { this.queryCloud(this.cloudPage + 1); })
        }.width('100%')
      }.padding(20).width('100%').constraintSize({ maxWidth: 720 })
    }.id('CloudScroll').width('100%').layoutWeight(1)
  }
  @Builder private sheetView() {
    Column() {
      Row() {
        Button('‹ 返回').id('SheetBack').backgroundColor('#E5EDE4').fontColor(GREEN).enabled(!this.busy && !this.modelBusy).onClick(() => { this.sheet = ''; this.error = ''; })
        Blank(); Text(this.sheet === 'settings' ? '连接与模型设置' : this.sheet === 'edit' ? '修正物品清单' : '识别记录').fontSize(18).fontColor(INK)
      }.width('100%').padding(16)
      Scroll() {
        Column({ space: 16 }) {
          if (this.sheet === 'settings') {
            Text('服务连接').fontSize(22).fontColor(INK).fontWeight(FontWeight.Bold)
            Text('同步时仅上传缩略图、识别清单与记录信息，原始照片保留在本机。').fontSize(13).fontColor(MUTED).lineHeight(22)
            TextInput({ text: this.endpointDraft, placeholder: 'https://服务域名' }).id('ServiceEndpoint').onChange((v: string) => { this.endpointDraft = v; })
            Text('本地模拟器调试可用 http://127.0.0.1:8765，需按文档配置端口转发。').fontSize(11).fontColor(MUTED)
            TextInput({ text: this.deviceDraft, placeholder: '设备标识' }).id('DeviceId').maxLength(100).onChange((v: string) => { this.deviceDraft = v; })
            TextInput({ text: this.keyDraft, placeholder: '服务端分配的设备密钥' }).id('DeviceKey').type(InputType.Password).maxLength(200).onChange((v: string) => { this.keyDraft = v; })
            Row() { Text('网络恢复后自动重传').fontSize(14).fontColor(INK).layoutWeight(1); Toggle({ type: ToggleType.Switch, isOn: this.autoDraft }).id('AutoSync').selectedColor(GREEN).onChange((v: boolean) => { this.autoDraft = v; }) }.width('100%')
            Button('保存连接设置').id('SaveSettings').width('100%').backgroundColor(GREEN).onClick(() => { this.saveSettings(); })
            Divider()
            Text('端侧模型').fontSize(22).fontColor(INK).fontWeight(FontWeight.Bold)
            Text('YOLOv13n · 当前版本 ' + this.settings.modelVersion).fontSize(16).fontColor(INK)
            Text(this.modelNotice).id('ModelStatus').fontSize(13).fontColor(MUTED).lineHeight(22)
            Text(this.modelInfo).fontSize(10).fontColor(MUTED).copyOption(CopyOptions.LocalDevice)
            Row({ space: 8 }) {
              Button(this.checkingModel ? '检查中…' : '检查版本 / 重试').id('CheckModel').enabled(!this.modelBusy && !this.checkingModel).backgroundColor('#E5EDE4').fontColor(GREEN).fontSize(13).onClick(() => { this.checkModel(); })
              Button(this.modelBusy ? '处理中…' : '下载并切换').id('UpdateModel').enabled(!this.modelBusy && !this.checkingModel && !!this.manifest && this.manifest.version !== this.settings.modelVersion)
                .backgroundColor(GREEN).fontSize(13).onClick(() => { this.downloadModel(); })
            }.width('100%')
            Text('更新会验证文件长度、SHA256和模型输入输出，成功后才切换。下载失败继续使用旧版本。').fontSize(12).fontColor(MUTED).lineHeight(21)
          } else if (this.sheet === 'edit') {
            Text('修正类别名称，或删除误检项。').fontColor(MUTED).fontSize(14)
            if (!this.editItems.length) { Text('清单为空，可保留本次“未检出物品”记录。').fontColor(MUTED).fontSize(14) }
            ForEach(this.editItems, (item: Detection, index: number) => {
              Row({ space: 8 }) {
                TextInput({ text: item.name, placeholder: '类别名称' }).id('EditItem_' + index).layoutWeight(1).maxLength(50).onChange((v: string) => { this.editLabel(item.id, v); })
                Button('删除').id('RemoveItem_' + index).backgroundColor('#F4E8DF').fontColor('#A34D32').fontSize(12).onClick(() => { this.editItems = this.editItems.filter((candidate: Detection) => candidate.id !== item.id); })
              }.width('100%')
            }, (item: Detection) => item.id)
            Button('保存清单修改').id('SaveItemEdits').enabled(!this.busy).backgroundColor(GREEN).width('100%').onClick(() => { this.saveEdits(); })
          } else if (this.visibleRecord) {
            Image(fileUri.getUriFromPath(this.visibleRecord.imagePath)).width('100%').height(280).objectFit(ImageFit.Contain).backgroundColor('#E6EBDD').borderRadius(16)
            Text(this.countText(this.visibleRecord.items)).fontSize(22).fontColor(INK).fontWeight(FontWeight.Bold)
            Text(this.date(this.visibleRecord.capturedAt)).fontSize(13).fontColor(MUTED)
            Text(`模型 ${this.visibleRecord.modelVersion} · 阈值 ${Math.round(this.visibleRecord.threshold * 100)}% · 清单版本 ${this.visibleRecord.revision}`).fontSize(12).fontColor(MUTED)
            this.timingView(this.visibleRecord.timings)
            ForEach(this.visibleRecord.items, (item: Detection) => { Text(`${item.name} · ${(item.score * 100).toFixed(1)}% · [${item.x1.toFixed(0)},${item.y1.toFixed(0)},${item.x2.toFixed(0)},${item.y2.toFixed(0)}]`).fontSize(12).fontColor(MUTED) }, (item: Detection) => item.id)
            Button('修正此条清单').backgroundColor(GREEN).onClick(() => { if (this.visibleRecord) { this.editResult(this.visibleRecord); } })
            Button(this.busy ? '正在保存…' : '保存原图到相册').id('ExportRecordPhoto').backgroundColor('#E5EDE4').fontColor(GREEN).enabled(!this.busy).onClick(() => { this.exportRecordPhoto(); })
          }
          if (this.error) { Text(this.error).id('SheetError').fontSize(13).fontColor('#A34D32').lineHeight(22) }
        }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(BG)
  }
  build() {
    Stack() {
      Column() {
        Row() {
          Row({ space: 9 }) { Image($r('app.media.app_icon')).width(34).height(34); Text('识物').fontSize(22).fontWeight(FontWeight.Bold).fontColor(INK) }
          Blank(); Button('设置').id('OpenSettings').height(36).fontSize(13).backgroundColor('#E5EDE4').fontColor(GREEN).enabled(this.ready && !this.busy && !this.modelBusy).onClick(() => { this.openSettings(); })
        }.width('100%').padding({ left: 20, right: 20, top: 12, bottom: 8 })
        if (!this.ready) {
          Column({ space: 16 }) {
            if (!this.error) { LoadingProgress().width(36).height(36) }
            Text(this.error || '正在加载本地模型与记录…').fontColor(INK).fontSize(15).textAlign(TextAlign.Center).padding(20)
            if (this.error) { Button('重新加载').id('RetryInitialize').onClick(() => { this.initialize(); }) }
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Tabs({ index: this.tab, barPosition: BarPosition.End }) {
            TabContent() { this.captureTab() }.tabBar('识别')
            TabContent() { this.historyTab() }.tabBar('记录')
            TabContent() { this.cloudTab() }.tabBar('云端')
          }.layoutWeight(1).barHeight(52).animationDuration(0).scrollable(false).onChange((index: number) => { this.tab = index; this.notice = ''; this.error = ''; if (index === 1) { this.refreshRecords(); } })
        }
        if (this.ready && (this.notice || this.error)) {
          Row({ space: 8 }) {
            Text(this.error || this.notice).id('StatusMessage').fontSize(12).fontColor(this.error ? '#A34D32' : GREEN).layoutWeight(1).lineHeight(19)
            if (this.error && this.tab === 0 && this.imagePath) { Button('重试').id('RetryDetection').fontSize(12).height(32).backgroundColor('#E5EDE4').fontColor(GREEN).enabled(!this.busy).onClick(() => { this.recognize(); }) }
            Button('×').height(28).width(28).padding(0).fontSize(18).fontColor(MUTED).backgroundColor(Color.Transparent).onClick(() => { this.notice = ''; this.error = ''; })
          }.padding(10).width('100%').backgroundColor(this.error ? '#FFF0E6' : '#E8F0E2')
        }
      }.width('100%').height('100%').backgroundColor(BG)
      if (this.sheet) { this.sheetView() }
    }.width('100%').height('100%')
  }
}
