import { FrameCallback } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const SPLASH_DURATION_MS = 1000;

// Start the visible delay after the decoded image has reached a rendered frame.
class SplashFrameCallback extends FrameCallback {
  private onRendered: () => void;

  constructor(onRendered: () => void) {
    super();
    this.onRendered = onRendered;
  }

  onIdle(): void {
    this.onRendered();
  }
}

@Entry
@Component
struct Splash {
  @State navigationError: boolean = false;
  private visible: boolean = false;
  private imageReady: boolean = false;
  private framePending: boolean = false;
  private navigating: boolean = false;
  private timerId: number = -1;

  onPageShow(): void {
    this.visible = true;
    this.scheduleAfterFrame();
  }

  onPageHide(): void {
    this.visible = false;
    this.clearTimer();
  }

  aboutToDisappear(): void {
    this.visible = false;
    this.clearTimer();
  }

  private clearTimer(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private imagePrepared(): void {
    this.imageReady = true;
    this.scheduleAfterFrame();
  }

  private scheduleAfterFrame(): void {
    if (!this.visible || !this.imageReady || this.framePending || this.navigating || this.timerId !== -1) {
      return;
    }
    this.framePending = true;
    this.getUIContext().postFrameCallback(new SplashFrameCallback(() => {
      this.framePending = false;
      if (!this.visible || this.navigating || this.timerId !== -1) {
        return;
      }
      hilog.info(0x0000, 'Splash', 'Launch image rendered; starting 1000 ms display.');
      this.timerId = setTimeout(() => {
        this.timerId = -1;
        this.enterApplication();
      }, SPLASH_DURATION_MS);
    }));
  }

  private enterApplication(): void {
    if (!this.visible || this.navigating) {
      return;
    }
    this.navigating = true;
    this.navigationError = false;
    hilog.info(0x0000, 'Splash', 'Entering the course application.');
    this.getUIContext().getRouter().replaceUrl({ url: 'pages/Index' }).catch(() => {
      this.navigating = false;
      this.navigationError = true;
    });
  }

  build() {
    Column({ space: 24 }) {
      Image($r('app.media.launch_logo'))
        .id('SplashLogo')
        .width('100%')
        .aspectRatio(764 / 620)
        .constraintSize({ maxWidth: 420, maxHeight: '80%' })
        .objectFit(ImageFit.Contain)
        .accessibilityText('广东工业大学')
        .onComplete((event) => {
          if (event && event.loadingStatus === 1) {
            this.imagePrepared();
          }
        })
        .onError(() => {
          hilog.error(0x0000, 'Splash', 'Launch image could not be decoded.');
          this.imagePrepared();
        })
      if (this.navigationError) {
        Button('进入软件').id('SplashRetryButton')
          .onClick(() => this.enterApplication())
      }
    }
    .id('SplashPage')
    .width('100%')
    .height('100%')
    .padding({ left: 32, right: 32 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(Color.White)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
