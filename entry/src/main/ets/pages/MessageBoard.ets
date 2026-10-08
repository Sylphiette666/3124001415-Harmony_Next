import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { ACCENT, INK, MUTED, PAGE_BG } from '../model/CourseData';
import { MessageStore } from '../model/MessageStore';
import { BOARD_PROXY_METHODS, BOARD_PROXY_PERMISSION, BoardTransport, isBoardUrl, MessageBoardBridge } from '../services/MessageBoardBridge';

@Entry
@Component
struct MessageBoard {
  @State title: string = '网页留言板';
  @State loading: boolean = true;
  @State progress: number = 0;
  @State error: string = '';
  @State generation: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge: MessageBoardBridge = new MessageBoardBridge();
  private timer: number = -1;
  private alive: boolean = true;

  aboutToAppear(): void {
    const transport: BoardTransport = {
      evaluate: (script: string): Promise<string> => this.controller.runJavaScript(script),
      toast: (message: string): void => this.getUIContext().getPromptAction().showToast({ message: message }),
      failed: (message: string): void => this.fail(message)
    };
    this.bridge.configure(new MessageStore(this.getUIContext().getHostContext() as common.UIAbilityContext), transport);
    this.armTimer();
  }
  aboutToDisappear(): void {
    this.alive = false; this.clearTimer(); this.bridge.dispose();
    try { this.controller.deleteJavaScriptRegister('NativeBoard'); } catch { /* Web may already be destroyed. */ }
  }
  private clearTimer(): void { if (this.timer !== -1) { clearTimeout(this.timer); this.timer = -1; } }
  private armTimer(): void {
    this.clearTimer();
    this.timer = setTimeout(() => this.fail('留言板连接超时，请重新加载'), 15000);
  }
  private fail(message: string): void {
    if (!this.alive) { return; }
    this.clearTimer(); this.bridge.beginPage(); this.loading = false; this.error = message;
  }
  private retry(): void {
    this.clearTimer(); this.bridge.beginPage();
    try { this.controller.deleteJavaScriptRegister('NativeBoard'); } catch { /* A failed Web may have no controller. */ }
    this.controller = new webview.WebviewController();
    this.title = '网页留言板'; this.error = ''; this.loading = true; this.progress = 0;
    this.generation++; this.armTimer();
  }
  private async pageReady(generation: number): Promise<void> {
    if (!this.alive || generation !== this.generation || this.error) { return; }
    try {
      await this.bridge.connect();
      if (this.alive && generation === this.generation && !this.error) {
        this.clearTimer(); this.loading = false; this.progress = 100;
      }
    } catch { if (generation === this.generation) { this.fail('网页通信建立失败，请重新加载'); } }
  }
  private refresh(): void {
    if (this.loading || this.error) { this.retry(); return; }
    // Refresh replaces the web document, so let the user protect an unsent draft.
    try {
      this.getUIContext().getPromptAction().showDialog({ title: '重新加载留言板？',
        message: '已保存的留言会保留，尚未提交的内容会清空。',
        buttons: [{ text: '取消', color: MUTED }, { text: '重新加载', color: ACCENT }]
      }).then((result) => { if (result.index === 1 && this.alive) { this.retry(); } }).catch(() => {});
    } catch { /* A closing page needs no dialog. */ }
  }
  build() {
    Column() {
      Row({ space: 10 }) {
        Button('‹', { type: ButtonType.Normal }).id('BoardBackButton').width(38).height(42)
          .fontSize(30).fontColor(INK).backgroundColor(Color.White).borderRadius(12)
          .accessibilityText('返回首页').onClick(() => this.getUIContext().getRouter().back())
        Column({ space: 4 }) {
          Text(this.title).id('BoardNativeTitle').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.error ? '加载失败' : this.loading ? '正在加载本地网页…' : '本机保存 · 离线可用')
            .id('BoardNativeStatus').fontSize(11).fontColor(MUTED)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button('通知', { type: ButtonType.Normal }).id('BoardNotifyButton').height(38)
          .padding({ left: 10, right: 10 }).fontSize(13).fontColor(ACCENT).backgroundColor('#E2F2F1').borderRadius(10)
          .enabled(!this.loading && !this.error).onClick(() => { this.bridge.notify(); })
        Button('刷新', { type: ButtonType.Normal }).id('BoardRefreshButton').height(38)
          .padding({ left: 10, right: 10 }).fontSize(13).fontColor(INK).backgroundColor(Color.White).borderRadius(10)
          .onClick(() => this.refresh())
      }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
      if (this.loading) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .id('BoardLoadProgress').width('100%').color(ACCENT).style({ strokeWidth: 3 })
      }
      Stack() {
        ForEach([this.generation], (generation: number) => {
          Web({ src: $rawfile('message-board.html'), controller: this.controller })
            .id('MessageBoardWeb').width('100%').height('100%')
            .javaScriptAccess(true).domStorageAccess(false).databaseAccess(false)
            .javaScriptProxy({ object: this.bridge, name: 'NativeBoard', methodList: BOARD_PROXY_METHODS,
              controller: this.controller, permission: BOARD_PROXY_PERMISSION })
            .onPageBegin((event) => {
              if (generation !== this.generation || !this.alive) { return; }
              if (event && !isBoardUrl(event.url)) { this.fail('该留言板仅支持内置页面'); return; }
              this.bridge.beginPage(); this.loading = true; this.error = ''; this.progress = 0; this.armTimer();
            })
            .onPageEnd(() => { this.pageReady(generation); })
            .onProgressChange((event) => {
              if (event && generation === this.generation && this.loading) { this.progress = event.newProgress; }
            })
            .onTitleReceive((event) => {
              if (event && generation === this.generation && event.title.startsWith('网页留言板')) {
                this.title = event.title.slice(0, 32);
              }
            })
            .onErrorReceive((event) => {
              if (event && generation === this.generation && event.request.isMainFrame()) {
                this.fail('本地留言页面加载失败，请重新加载');
              }
            })
            .onHttpErrorReceive((event) => {
              if (event && generation === this.generation && event.request.isMainFrame()) {
                this.fail('留言页面加载失败，请重新加载');
              }
            })
            .onRenderExited(() => { if (generation === this.generation) { this.fail('网页进程已退出，请重新加载'); } })
            .onOverrideUrlLoading((request) => !isBoardUrl(request.getRequestUrl()))
        }, (generation: number) => generation.toString())
        if (this.loading || this.error) {
          Column({ space: 16 }) {
            if (this.loading) { LoadingProgress().width(38).height(38).color(ACCENT) }
            Text(this.error ? '留言板暂时无法打开' : '正在打开留言板')
              .fontSize(20).fontWeight(FontWeight.Medium).fontColor(INK)
            Text(this.error || '正在读取页面与历史留言，请稍候…').id('BoardLoadMessage')
              .fontSize(14).fontColor(MUTED).textAlign(TextAlign.Center)
            if (this.error) {
              Button('重新加载').id('BoardRetryButton').fontColor(Color.White).backgroundColor(ACCENT)
                .height(44).onClick(() => this.retry())
            }
          }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(26).backgroundColor(PAGE_BG)
        }
      }.layoutWeight(1).width('100%')
    }.id('MessageBoardPage').width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
