import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { camera } from '@kit.CameraKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { writeFile, ensureFolders } from '../services/MediaFiles';

@Entry
@Component
struct CaptureCamera {
  @State ready: boolean = false;
  @State busy: boolean = false;
  @State error: string = '';
  @State front: boolean = false;
  private surface: XComponentController = new XComponentController();
  private input: camera.CameraInput | undefined = undefined;
  private preview: camera.PreviewOutput | undefined = undefined;
  private output: camera.PhotoOutput | undefined = undefined;
  private session: camera.PhotoSession | undefined = undefined;
  private generation: number = 0;
  private visible: boolean = false;
  private opening: boolean = false;

  onPageShow(): void { this.visible = true; }
  onPageHide(): void { this.visible = false; this.generation++; this.release(); }
  aboutToDisappear(): void { this.visible = false; this.generation++; this.release(); }
  private context(): common.UIAbilityContext { return this.getUIContext().getHostContext() as common.UIAbilityContext; }
  private async release(): Promise<void> {
    this.ready = false;
    const session = this.session; const preview = this.preview; const output = this.output; const input = this.input;
    this.session = undefined; this.preview = undefined; this.output = undefined; this.input = undefined;
    try { if (session) { await session.stop(); } } catch {}
    try { if (session) { await session.release(); } } catch {}
    try { if (preview) { await preview.release(); } } catch {}
    try { if (output) { await output.release(); } } catch {}
    try { if (input) { await input.close(); } } catch {}
  }
  private async open(): Promise<void> {
    if (this.opening || this.busy) { return; }
    this.opening = true; this.error = ''; const token = ++this.generation;
    try {
      await this.release();
      const permission = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(this.context(), ['ohos.permission.CAMERA']);
      if (permission.authResults[0] !== 0) { throw new Error('需要相机权限才能拍照。可授权后重试，或返回使用相册选图。'); }
      if (!this.visible || token !== this.generation) { return; }
      const manager = camera.getCameraManager(this.context()); const devices = manager.getSupportedCameras();
      const position = this.front ? camera.CameraPosition.CAMERA_POSITION_FRONT : camera.CameraPosition.CAMERA_POSITION_BACK;
      const device = devices.find((candidate: camera.CameraDevice) => candidate.cameraPosition === position);
      if (!device) { throw new Error(this.front ? '当前设备没有前置相机，可切换后置相机或返回选图。' : '相机暂不可用。可重试，或返回使用相册和示例照片。'); }
      const capability = manager.getSupportedOutputCapability(device, camera.SceneMode.NORMAL_PHOTO);
      const previews = capability.previewProfiles.slice().sort((a: camera.Profile, b: camera.Profile) =>
        Math.abs(a.size.width * a.size.height - 1280 * 720) - Math.abs(b.size.width * b.size.height - 1280 * 720));
      const photos = capability.photoProfiles.filter((p: camera.Profile) => p.format === camera.CameraFormat.CAMERA_FORMAT_JPEG)
        .sort((a: camera.Profile, b: camera.Profile) => Math.abs(a.size.width * a.size.height - 1920 * 1080) - Math.abs(b.size.width * b.size.height - 1920 * 1080));
      if (!previews.length) { throw new Error('设备未提供预览格式，请返回相册选图。'); }
      this.input = manager.createCameraInput(device); await this.input.open();
      if (!this.visible || token !== this.generation) { await this.release(); return; }
      this.preview = manager.createPreviewOutput(previews[0], this.surface.getXComponentSurfaceId());
      if (photos.length) { this.output = manager.createPhotoOutput(photos[0]); }
      else if (capability.photoProfiles.length) { this.output = manager.createPhotoOutput(capability.photoProfiles[0]); }
      else { this.output = manager.createPhotoOutput(); }
      this.output.on('photoAvailable', (error: BusinessError, photo: camera.Photo) => {
        if (error) { this.error = '照片获取失败，请重试。'; this.busy = false; return; }
        this.received(photo, token);
      });
      this.session = manager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
      this.session.beginConfig(); this.session.addInput(this.input); this.session.addOutput(this.preview); this.session.addOutput(this.output);
      await this.session.commitConfig(); await this.session.start();
      if (!this.visible || token !== this.generation) { await this.release(); return; }
      this.ready = true;
    } catch (error) {
      const message = (error as Error).message || '';
      console.error('SmartObjects camera: ' + message);
      this.error = /[\u4e00-\u9fff]/.test(message) ? message : '相机暂时不可用，请重试，或返回使用相册选图。'; await this.release();
    }
    finally { this.opening = false; }
  }
  private async received(photo: camera.Photo, token: number): Promise<void> {
    try {
      if (!this.visible || token !== this.generation) { return; }
      const component = await photo.main.getComponent(image.ComponentType.JPEG);
      if (!this.visible || token !== this.generation) { return; }
      ensureFolders(this.context());
      const path = this.context().filesDir + '/images/camera-' + Date.now() + '.jpg';
      writeFile(path, component.byteBuffer);
      AppStorage.setOrCreate('smartObjectCapture', path); this.getUIContext().getRouter().back();
    } catch { this.error = '保存照片失败，请重新拍摄。'; }
    finally { this.busy = false; await photo.release(); }
  }
  private async capture(): Promise<void> {
    if (!this.ready || this.busy || !this.output) { return; }
    this.busy = true; this.error = '';
    try { await this.output.capture({ quality: camera.QualityLevel.QUALITY_LEVEL_HIGH, rotation: this.output.getPhotoRotation(0) }); }
    catch { this.error = '拍摄失败，请重试。'; this.busy = false; }
  }
  build() {
    Column({ space: 16 }) {
      Row() {
        Button('‹ 返回').id('CameraBack').backgroundColor('#254C48').onClick(() => { this.getUIContext().getRouter().back(); })
        Blank(); Text(this.front ? '前置相机' : '后置相机').fontSize(18).fontColor(Color.White)
        Blank(); Button('切换').id('SwitchCamera').enabled(!this.opening && !this.busy).backgroundColor('#254C48').onClick(() => { this.front = !this.front; this.open(); })
      }.width('100%').padding(16)
      XComponent({ id: 'capture-preview', type: XComponentType.SURFACE, controller: this.surface })
        .id('CameraPreview').width('100%').layoutWeight(1).onLoad(() => { this.open(); })
      if (this.error) {
        Text(this.error).fontSize(14).fontColor('#FFCEB0').padding({ left: 20, right: 20 })
        Button('重新打开相机').id('RetryCamera').onClick(() => { this.open(); })
      }
      Text(this.error ? '可重试或返回相册选图。' : this.ready ? '将物品置于画面内，拍照后在本机识别。' : '正在准备相机预览…').fontColor('#C7DDD4').fontSize(13)
      Button(this.busy ? '正在拍摄…' : '拍照并使用').id('CapturePhoto').enabled(this.ready && !this.busy)
        .backgroundColor('#D3F4B5').fontColor('#103C39').fontSize(19).height(56).width('70%').onClick(() => { this.capture(); })
    }.width('100%').height('100%').backgroundColor('#103C39').padding({ bottom: 24 })
  }
}
