import { common } from '@kit.AbilityKit';
import { ACCENT, INK, MUTED, PAGE_BG } from '../model/CourseData';
import { BusinessCard } from '../model/BusinessCard';
import { CardStore } from '../model/CardStore';

interface CardDetailParams { cardId: string; }

@Entry
@Component
struct CardDetail {
  @State card: BusinessCard | undefined = undefined;
  @State error: string = '';
  @State busy: boolean = false;
  private cardId: string = '';

  aboutToAppear(): void {
    const params = this.getUIContext().getRouter().getParams() as CardDetailParams | undefined;
    this.cardId = params?.cardId || '';
  }

  onPageShow(): void {
    try {
      this.card = this.store().load().find((item: BusinessCard) => item.id === this.cardId);
      this.error = this.card ? '' : '这张名片不存在或已被删除，请返回名片夹。';
    } catch {
      this.error = '名片读取失败，请返回后重试。';
      this.card = undefined;
    }
  }

  onBackPress(): boolean { return this.busy; }

  private store(): CardStore {
    return new CardStore(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  private async favorite(): Promise<void> {
    if (this.busy || !this.card) { return; }
    this.busy = true;
    try {
      this.card = await this.store().toggleFavorite(this.cardId);
      this.error = '';
    } catch {
      this.error = '收藏结果未确认，请返回列表重新读取后再操作。';
    } finally {
      this.busy = false;
    }
  }

  private edit(): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/CardEditor', params: { cardId: this.cardId } })
      .catch(() => { this.error = '编辑页面打开失败，请重试。'; });
  }

  private confirmDelete(): void {
    if (this.busy || !this.card) { return; }
    this.getUIContext().showAlertDialog({
      title: '删除这张名片？',
      message: '将从本机删除“' + this.card.name + '”的名片，删除后无法恢复。',
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: { value: '删除名片', fontColor: '#B33B35', action: () => { this.remove(); } }
    });
  }

  private async remove(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      await this.store().remove(this.cardId);
      this.getUIContext().getRouter().back();
    } catch {
      this.error = '删除未完成，请返回列表检查后重试。';
    } finally { this.busy = false; }
  }

  @Builder
  detailRow(label: string, value: string) {
    Column({ space: 7 }) {
      Text(label).fontSize(12).fontColor(MUTED)
      Text(value || '未填写').fontSize(16).fontColor(value ? INK : MUTED)
        .copyOption(CopyOptions.LocalDevice).width('100%').lineHeight(25)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row() {
        Button('‹ 返回', { type: ButtonType.Normal }).id('CardDetailBackButton').height(44)
          .fontSize(15).fontColor(ACCENT).backgroundColor(Color.Transparent).enabled(!this.busy)
          .onClick(() => this.getUIContext().getRouter().back())
        Text('名片详情').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
        Blank()
        if (this.card) {
          Button('编辑', { type: ButtonType.Normal }).id('EditCardButton').height(40)
            .fontSize(14).fontColor(ACCENT).backgroundColor('#E2F2F1').borderRadius(12)
            .enabled(!this.busy).onClick(() => this.edit())
        }
      }.width('100%').padding({ left: 10, right: 22, top: 8, bottom: 8 })
      Scroll() {
        Column({ space: 20 }) {
          if (this.error) {
            Text(this.error).id('CardDetailError').fontSize(14).fontColor('#B33B35').width('100%').lineHeight(23)
          }
          if (this.card) {
            Column({ space: 22 }) {
              Row() {
                Text('BUSINESS CARD').fontSize(11).fontColor('#B4ECEB').letterSpacing(2)
                Blank()
                Text(this.card.group).fontSize(12).fontColor('#D2E4EC')
              }.width('100%')
              Row({ space: 16 }) {
                Text(this.card.name.slice(0, 1)).fontSize(30).fontWeight(FontWeight.Bold).fontColor('#183A4B')
                  .width(62).height(62).textAlign(TextAlign.Center).backgroundColor('#B4ECEB').borderRadius(20)
                Column({ space: 7 }) {
                  Text(this.card.name).id('CardDetailName').fontSize(28).fontWeight(FontWeight.Bold).fontColor(Color.White)
                  Text(this.card.title || '联系人').fontSize(14).fontColor('#D2E4EC')
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }.width('100%')
              Divider().color('#3E5A67')
              Text(this.card.organization || '个人名片').id('CardDetailOrganization').fontSize(16).fontColor('#D2E4EC').width('100%')
            }.width('100%').padding(24).alignItems(HorizontalAlign.Start).backgroundColor('#183A4B').borderRadius(24)

            Button(this.card.favorite ? '★ 已收藏 · 点击取消' : '☆ 收藏这张名片', { type: ButtonType.Normal })
              .id('ToggleCardFavoriteButton').width('100%').height(46).fontSize(15).fontColor(ACCENT)
              .backgroundColor('#E2F2F1').borderRadius(14).enabled(!this.busy).onClick(() => { this.favorite(); })

            Column({ space: 20 }) {
              Text('联系方式').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
              this.detailRow('电话', this.card.phone)
              this.detailRow('邮箱', this.card.email)
              this.detailRow('地址', this.card.address)
            }.width('100%').padding(22).alignItems(HorizontalAlign.Start).backgroundColor(Color.White).borderRadius(22)
            if (this.card.note) {
              Column({ space: 12 }) {
                Text('备注').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
                Text(this.card.note).id('CardDetailNote').fontSize(15).fontColor(MUTED).lineHeight(24)
              }.width('100%').padding(22).alignItems(HorizontalAlign.Start).backgroundColor(Color.White).borderRadius(22)
            }
            Text('长按联系方式可复制 · 名片保存在当前设备').fontSize(12).fontColor(MUTED).width('100%')
            Button('删除名片', { type: ButtonType.Normal }).id('DeleteCardButton').width('100%').height(46)
              .fontSize(15).fontColor('#B33B35').backgroundColor('#F9ECEA').borderRadius(14)
              .enabled(!this.busy).onClick(() => this.confirmDelete())
          }
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 22, right: 22, top: 18, bottom: 30 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
