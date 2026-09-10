import { common } from '@kit.AbilityKit';
import { ACCENT, INK, MUTED, PAGE_BG, StudentProfile } from '../model/CourseData';
import { ProfileStore } from '../model/ProfileStore';
@Entry
@Component
struct Profile {
  @State studentName: string = '';
  @State studentId: string = '3124001415';
  @State className: string = '';
  @State saving: boolean = false;
  @State error: string = '';
  aboutToAppear(): void {
    try {
      const profile = ProfileStore.load(this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.studentName = profile.name;
      this.studentId = profile.studentId;
      this.className = profile.className;
    } catch {
      this.error = '个人信息读取失败，请返回后重试。';
    }
  }
  private async save(): Promise<void> {
    if (!this.studentName.trim() || !this.studentId.trim() || !this.className.trim()) {
      this.error = '请完整填写姓名、学号和班级或专业。';
      return;
    }
    if (!/^[0-9]{6,20}$/.test(this.studentId.trim())) {
      this.error = '学号应为 6 至 20 位数字。';
      return;
    }
    this.saving = true;
    this.error = '';
    const profile = new StudentProfile();
    profile.name = this.studentName.trim();
    profile.studentId = this.studentId.trim();
    profile.className = this.className.trim();
    try {
      await ProfileStore.save(this.getUIContext().getHostContext() as common.UIAbilityContext, profile);
      this.getUIContext().getRouter().back();
    } catch {
      this.error = '保存失败，请稍后重试。';
    } finally {
      this.saving = false;
    }
  }
  build() {
    Column() {
      Row({ space: 14 }) {
        Button('‹ 返回', { type: ButtonType.Normal }).id('ProfileBackButton').height(44)
          .fontSize(15).fontColor(ACCENT).backgroundColor(Color.Transparent).enabled(!this.saving)
          .onClick(() => this.getUIContext().getRouter().back())
        Text('编辑个人信息').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
        Blank()
      }.width('100%').padding({ left: 10, right: 22, top: 8, bottom: 8 })
      Scroll() {
        Column({ space: 22 }) {
          Text('完善你的课程学习档案').fontSize(25).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
          Text('保存后会显示在首页，信息仅保存在当前设备。').fontSize(14).fontColor(MUTED).lineHeight(22).width('100%')
          Column({ space: 12 }) {
            Text('姓名').fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK).width('100%')
            TextInput({ placeholder: '请输入姓名', text: this.studentName }).id('NameInput')
              .height(52).fontSize(16).maxLength(30).backgroundColor(PAGE_BG).borderRadius(12)
              .onChange((value: string) => { this.studentName = value; })
            Text('学号').fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK).width('100%').margin({ top: 10 })
            TextInput({ placeholder: '请输入学号', text: this.studentId }).id('StudentIdInput')
              .height(52).fontSize(16).maxLength(20).type(InputType.Number).backgroundColor(PAGE_BG).borderRadius(12)
              .onChange((value: string) => { this.studentId = value; })
            Text('班级 / 专业').fontSize(15).fontWeight(FontWeight.Medium).fontColor(INK).width('100%').margin({ top: 10 })
            TextInput({ placeholder: '请输入班级或专业', text: this.className }).id('ClassInput')
              .height(52).fontSize(16).maxLength(60).backgroundColor(PAGE_BG).borderRadius(12)
              .onChange((value: string) => { this.className = value; })
          }.width('100%').padding(22).backgroundColor(Color.White).borderRadius(22)
          if (this.error) {
            Text(this.error).id('ProfileError').fontSize(14).fontColor('#AF3434').width('100%')
          }
          Button(this.saving ? '正在保存…' : '保存个人信息', { type: ButtonType.Normal }).id('SaveProfileButton')
            .width('100%').height(52).fontSize(16).fontColor(Color.White).backgroundColor(ACCENT).borderRadius(14)
            .enabled(!this.saving).onClick(() => { this.save(); })
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 22, right: 22, top: 22, bottom: 30 })
      }.id('ProfileScroll').width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
