import { ACCENT, COURSE_TASKS, CourseTask, INK, MUTED, PAGE_BG, TaskRouteParams } from '../model/CourseData';
@Entry
@Component
struct TaskDetail {
  @State task: CourseTask | undefined = undefined;
  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as TaskRouteParams | undefined;
    this.task = COURSE_TASKS.find((item: CourseTask) => item.id === params?.taskId);
  }
  build() {
    Column() {
      Row({ space: 14 }) {
        Button('‹ 返回', { type: ButtonType.Normal }).id('DetailBackButton').height(44)
          .fontSize(15).fontColor(ACCENT).backgroundColor(Color.Transparent)
          .onClick(() => this.getUIContext().getRouter().back())
        Text('任务详情').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
        Blank()
      }.width('100%').padding({ left: 10, right: 22, top: 8, bottom: 8 })
      Scroll() {
        Column({ space: 22 }) {
          if (this.task) {
            Column({ space: 14 }) {
              Text('TASK ' + this.task.id + '  /  ' + this.task.date).fontSize(12)
                .fontColor('#B4ECEB').letterSpacing(1)
              Text(this.task.title).id('TaskDetailTitle').fontSize(29).fontWeight(FontWeight.Bold).fontColor(Color.White)
              Text(this.task.summary).fontSize(15).fontColor('#D2E4EC').lineHeight(25)
            }.width('100%').padding(24).alignItems(HorizontalAlign.Start).backgroundColor('#183A4B').borderRadius(22)
            if (this.task.pageUrl) {
              Button('进入任务应用  →', { type: ButtonType.Normal }).id('OpenTaskAppButton')
                .width('100%').height(50).fontSize(16).fontColor(Color.White)
                .backgroundColor(ACCENT).borderRadius(14)
                .onClick(() => {
                  this.getUIContext().getRouter().pushUrl({ url: this.task!.pageUrl }).catch(() => {
                    this.getUIContext().getPromptAction().showToast({ message: '应用打开失败，请重试' });
                  });
                })
            }
            Column({ space: 20 }) {
              Text('任务要求').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
              ForEach(this.task.requirements, (requirement: string, index: number) => {
                Row({ space: 12 }) {
                  Text((index + 1).toString().padStart(2, '0')).fontSize(14).fontWeight(FontWeight.Bold)
                    .fontColor(ACCENT).width(30).margin({ top: 2 })
                  Text(requirement).fontSize(16).fontColor(INK).lineHeight(26).layoutWeight(1)
                }.width('100%').alignItems(VerticalAlign.Top)
              }, (requirement: string) => requirement)
            }.width('100%').padding(22).backgroundColor(Color.White).borderRadius(22)
            Column({ space: 12 }) {
              Text('操作指引').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
              Text('在首页查看并编辑个人信息，进入任务列表后，点击每个任务的按钮即可阅读详情。使用顶部返回按钮或系统返回手势回到上一页。')
                .fontSize(15).fontColor(MUTED).lineHeight(25)
            }.width('100%').alignItems(HorizontalAlign.Start).padding(22).backgroundColor(Color.White).borderRadius(22)
          } else {
            Column({ space: 14 }) {
              Text('未找到该任务').fontSize(24).fontWeight(FontWeight.Bold).fontColor(INK)
              Text('请返回任务列表，重新选择任务。').fontSize(15).fontColor(MUTED)
            }.width('100%').padding(30).backgroundColor(Color.White).borderRadius(22)
          }
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 22, right: 22, top: 22, bottom: 30 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
