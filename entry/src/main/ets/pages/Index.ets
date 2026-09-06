import { common } from '@kit.AbilityKit';
import { ACCENT, COURSE_TASKS, INK, MUTED, PAGE_BG, StudentProfile } from '../model/CourseData';
import { ProfileStore } from '../model/ProfileStore';

@Entry
@Component
struct Index {
  @State profile: StudentProfile = new StudentProfile();
  @State loadError: string = '';
  onPageShow(): void {
    try {
      this.loadError = '';
      this.profile = ProfileStore.load(this.getUIContext().getHostContext() as common.UIAbilityContext);
    } catch {
      this.loadError = '个人信息读取失败，请稍后重试';
    }
  }
  private openPage(url: string): void {
    this.getUIContext().getRouter().pushUrl({ url }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '页面打开失败，请重试' });
    });
  }
  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Text(label).fontSize(14).fontColor(MUTED).width(58)
      Text(value).fontSize(15).fontColor(INK).layoutWeight(1)
    }.width('100%').padding({ top: 8, bottom: 8 })
  }
  build() {
    Column() {
      Scroll() {
        Column({ space: 24 }) {
          Row() {
            Text('H / N').fontSize(18).fontWeight(FontWeight.Bold).fontColor(ACCENT)
            Blank()
            Text('2026 · 秋季学期').fontSize(13).fontColor(MUTED)
          }.width('100%')
          Column({ space: 14 }) {
            Text('HARMONYOS NEXT').fontSize(12).fontColor('#B4ECEB').letterSpacing(2)
            Text('课程学习项目').id('ProjectTitle').fontSize(32).fontWeight(FontWeight.Bold).fontColor(Color.White)
            Text('在这里整理每一次课程任务，\n记录学习与实践。')
              .fontSize(15).fontColor('#D2E4EC').lineHeight(24)
            Row({ space: 8 }) {
              Text('ArkTS').fontSize(12).fontColor(Color.White).padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor('#365464').borderRadius(20)
              Text('ArkUI').fontSize(12).fontColor(Color.White).padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor('#365464').borderRadius(20)
            }.margin({ top: 6 })
          }.alignItems(HorizontalAlign.Start).width('100%').padding(26)
            .backgroundColor('#183A4B').borderRadius(24)
          Column({ space: 14 }) {
            Row() {
              Text('个人信息').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
              Blank()
              Button('编辑', { type: ButtonType.Normal }).id('EditProfileButton')
                .fontSize(14).fontColor(ACCENT).backgroundColor('#E6F4F3').borderRadius(12)
                .height(40).padding({ left: 16, right: 16 }).onClick(() => this.openPage('pages/Profile'))
            }.width('100%')
            Column() {
              Row({ space: 14 }) {
                Text(this.profile.name ? this.profile.name.slice(0, 1) : '同')
                  .fontSize(24).fontWeight(FontWeight.Bold).fontColor(ACCENT).width(52).height(52)
                  .textAlign(TextAlign.Center).backgroundColor('#E2F2F1').borderRadius(18)
                Column({ space: 5 }) {
                  Text(this.profile.name || '请填写姓名').id('StudentName').fontSize(21)
                    .fontWeight(FontWeight.Bold).fontColor(INK)
                  Text('课程学习档案').fontSize(13).fontColor(MUTED)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }.width('100%').margin({ bottom: 18 })
              Divider().color('#EDF1F4').margin({ bottom: 10 })
              if (this.loadError) {
                Text(this.loadError).fontSize(13).fontColor('#AF3434').width('100%')
              }
              this.infoRow('学号', this.profile.studentId)
              this.infoRow('班级', this.profile.className || '请填写班级或专业')
            }.width('100%').padding(22).backgroundColor(Color.White).borderRadius(22)
          }.width('100%')
          Column({ space: 14 }) {
            Row() {
              Text('我的任务').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
              Blank()
              Text(COURSE_TASKS.length.toString() + ' 项任务').fontSize(13).fontColor(MUTED)
            }.width('100%')
            Button({ type: ButtonType.Normal }) {
              Row({ space: 14 }) {
                Text('01').fontSize(23).fontWeight(FontWeight.Bold).fontColor(ACCENT)
                Column({ space: 6 }) {
                  Text('打开任务列表').fontSize(17).fontWeight(FontWeight.Bold).fontColor(INK)
                  Text('查看课程作业与任务详情').fontSize(13).fontColor(MUTED)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text('›').fontSize(30).fontColor(ACCENT)
              }.width('100%').padding(22)
            }.id('OpenTasksButton').width('100%').backgroundColor(Color.White).borderRadius(22)
              .onClick(() => this.openPage('pages/Tasks'))
          }.width('100%')
          Text('HARMONY NEXT  /  学习 · 实践 · 积累').fontSize(11).fontColor(MUTED).letterSpacing(1)
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 22, right: 22, top: 24, bottom: 30 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
