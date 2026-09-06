import { ACCENT, COURSE_TASKS, CourseTask, INK, MUTED, PAGE_BG } from '../model/CourseData';
@Entry
@Component
struct Tasks {
  private openTask(taskId: string): void {
    this.getUIContext().getRouter().pushUrl({
      url: 'pages/TaskDetail', params: { taskId: taskId }
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '任务打开失败，请重试' });
    });
  }
  build() {
    Column() {
      Row({ space: 14 }) {
        Button('‹ 返回', { type: ButtonType.Normal }).id('TasksBackButton').height(44)
          .fontSize(15).fontColor(ACCENT).backgroundColor(Color.Transparent)
          .onClick(() => this.getUIContext().getRouter().back())
        Text('任务列表').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
        Blank()
      }.width('100%').padding({ left: 10, right: 22, top: 8, bottom: 8 })
      Scroll() {
        Column({ space: 22 }) {
          Column({ space: 10 }) {
            Text('每一次实践，都有迹可循。').fontSize(25).fontWeight(FontWeight.Bold).fontColor(INK)
            Text('共 ' + COURSE_TASKS.length + ' 项课程任务，点击下方按钮查看详情。')
              .fontSize(14).fontColor(MUTED).lineHeight(22)
          }.width('100%').alignItems(HorizontalAlign.Start)
          ForEach(COURSE_TASKS, (task: CourseTask) => {
            Column({ space: 16 }) {
              Row() {
                Text('TASK ' + task.id).fontSize(12).fontWeight(FontWeight.Bold).fontColor(ACCENT)
                  .letterSpacing(1).padding({ left: 12, right: 12, top: 7, bottom: 7 })
                  .backgroundColor('#E6F4F3').borderRadius(10)
                Blank()
                Text(task.date).fontSize(12).fontColor(MUTED)
              }.width('100%')
              Text(task.title).fontSize(22).fontWeight(FontWeight.Bold).fontColor(INK).width('100%')
              Text(task.summary).fontSize(15).fontColor(MUTED).lineHeight(24).width('100%')
              Button('查看任务详情  →', { type: ButtonType.Normal }).id('TaskButton_' + task.id)
                .width('100%').height(50).fontSize(16).fontColor(Color.White).backgroundColor(ACCENT).borderRadius(14)
                .onClick(() => this.openTask(task.id))
            }.alignItems(HorizontalAlign.Start).width('100%').padding(22).backgroundColor(Color.White).borderRadius(22)
          }, (task: CourseTask) => task.id)
          Row({ space: 12 }) {
            Text('＋').fontSize(24).fontColor(MUTED)
            Text('新的课程任务将在这里继续更新。').fontSize(14).fontColor(MUTED).layoutWeight(1)
          }.width('100%').padding(20).border({ width: 1, color: '#D8E3E8', style: BorderStyle.Dashed }).borderRadius(18)
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 22, right: 22, top: 22, bottom: 30 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
