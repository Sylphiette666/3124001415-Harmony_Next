import { ChatMessage, Evidence } from '../model/Knowledge';
const INK: string = '#183F3D';
const ACCENT: string = '#177B70';
const MUTED: string = '#647675';
@Component
export struct ChatCard {
 @ObjectLink message: ChatMessage;
 onSource: (e: Evidence) => void = () => {};
 onRetry: (q: string) => void = () => {};
 build() {
Column({ space: 12 }) {
              Text(this.message.question).fontSize(17).fontWeight(FontWeight.Medium).fontColor(INK).width('100%').padding(14).backgroundColor('#DCEDE7').borderRadius(14)
              Row() { Text(this.message.mode).fontSize(11).fontColor(MUTED).layoutWeight(1); Text(this.message.state).fontSize(11).fontColor(ACCENT) }.width('100%')
              if (this.message.answer) { Text(this.message.answer).fontSize(15).lineHeight(25).fontColor(INK).width('100%').copyOption(CopyOptions.LocalDevice) }
              if (this.message.error) { Text(this.message.error).fontSize(14).fontColor('#A24635').width('100%') }
              ForEach(this.message.evidence, (e: Evidence, index: number) => {
                Column({ space: 5 }) { Text(`[${index + 1}] ${e.segment.title}  ›`).fontSize(13).fontWeight(FontWeight.Medium).fontColor(ACCENT); Text(e.segment.text).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(12).fontColor(MUTED) }.alignItems(HorizontalAlign.Start).width('100%').padding(11).backgroundColor('#F2F6F3').borderRadius(10).onClick(() => { this.onSource(e); })
              }, (e: Evidence) => e.segment.id)
              if (this.message.state === '请求失败' || this.message.state === '已停止' || this.message.state === '未检索到相关内容') { Button('重试此问题').fontSize(13).fontColor(ACCENT).backgroundColor('#E6F1ED').height(34).onClick(() => { this.onRetry(this.message.question); }) }
            }.alignItems(HorizontalAlign.Start).padding(16).backgroundColor(Color.White).borderRadius(18).width('100%')
 }
}
