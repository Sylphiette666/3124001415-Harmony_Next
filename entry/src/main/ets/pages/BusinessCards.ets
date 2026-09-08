import { common } from '@kit.AbilityKit';
import { ACCENT, INK, MUTED, PAGE_BG } from '../model/CourseData';
import { BusinessCard, CARD_GROUPS, filterCards } from '../model/BusinessCard';
import { CardStore } from '../model/CardStore';

@Entry
@Component
struct BusinessCards {
  @State cards: BusinessCard[] = [];
  @State visibleCards: BusinessCard[] = [];
  @State query: string = '';
  @State group: string = '全部';
  @State favoritesOnly: boolean = false;
  @State error: string = '';
  private groups: string[] = ['全部', ...CARD_GROUPS];

  onPageShow(): void { this.reload(); }

  private reload(): void {
    try {
      this.cards = new CardStore(this.getUIContext().getHostContext() as common.UIAbilityContext).load();
      this.error = '';
      this.applyFilters();
    } catch {
      this.error = '暂时无法读取名片，原有数据已保留。请重试。';
      this.visibleCards = [];
    }
  }

  private applyFilters(): void {
    this.visibleCards = filterCards(this.cards, this.query, this.group, this.favoritesOnly);
  }

  private open(url: string, cardId: string = ''): void {
    this.getUIContext().getRouter().pushUrl({ url, params: { cardId } }).catch(() => {
      this.error = '页面打开失败，请重试。';
    });
  }

  private clearFilters(): void {
    this.query = '';
    this.group = '全部';
    this.favoritesOnly = false;
    this.applyFilters();
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Button('‹ 返回', { type: ButtonType.Normal }).id('CardsBackButton').height(44)
          .fontSize(15).fontColor(ACCENT).backgroundColor(Color.Transparent)
          .onClick(() => this.getUIContext().getRouter().back())
        Text('电子名片').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
        Blank()
        Button('＋ 新增', { type: ButtonType.Normal }).id('NewCardButton').height(40)
          .fontSize(14).fontColor(Color.White).backgroundColor(ACCENT).borderRadius(12)
          .enabled(!this.error).onClick(() => this.open('pages/CardEditor'))
      }.width('100%').padding({ left: 10, right: 22, top: 8, bottom: 8 })

      Column({ space: 16 }) {
        Column({ space: 8 }) {
          Text('CARD BOOK').fontSize(11).fontColor(ACCENT).letterSpacing(2).fontWeight(FontWeight.Bold)
          Row() {
            Text('让联系井然有序').fontSize(26).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
            Text(this.cards.length.toString() + ' 张').id('CardCount').fontSize(14).fontColor(MUTED)
          }.width('100%')
          Text('本机保存 · 随时查找').fontSize(13).fontColor(MUTED)
        }.width('100%').alignItems(HorizontalAlign.Start)
        TextInput({ text: this.query, placeholder: '搜索姓名、单位、电话或邮箱' }).id('CardSearch')
          .height(48).fontSize(14).backgroundColor(Color.White).borderRadius(14)
          .onChange((value: string) => { this.query = value; this.applyFilters(); })
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.groups, (item: string, index: number) => {
              Button(item, { type: ButtonType.Normal }).id('CardGroup_' + index).height(38)
                .fontSize(14).fontColor(this.group === item ? Color.White : MUTED)
                .backgroundColor(this.group === item ? ACCENT : Color.White).borderRadius(12)
                .padding({ left: 16, right: 16 })
                .onClick(() => { this.group = item; this.applyFilters(); })
            }, (item: string) => item)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        Row() {
          Text(this.error ? '读取异常' : '显示 ' + this.visibleCards.length + ' 张名片')
            .id('VisibleCardCount').fontSize(13).fontColor(MUTED)
          Blank()
          Button(this.favoritesOnly ? '★ 仅看收藏' : '☆ 仅看收藏', { type: ButtonType.Normal })
            .id('FavoriteFilterButton').height(38).fontSize(13)
            .fontColor(this.favoritesOnly ? ACCENT : MUTED).backgroundColor(Color.Transparent)
            .onClick(() => { this.favoritesOnly = !this.favoritesOnly; this.applyFilters(); })
        }.width('100%')

        if (this.error) {
          Column({ space: 16 }) {
            Text(this.error).id('CardsError').fontSize(16).fontColor(INK).lineHeight(24)
            Button('重新读取').id('CardsRetryButton').backgroundColor(ACCENT).onClick(() => this.reload())
          }.width('100%').padding(24).backgroundColor(Color.White).borderRadius(20)
        } else if (this.visibleCards.length === 0) {
          Column({ space: 14 }) {
            Text(this.cards.length === 0 ? '□' : '⌕').fontSize(46).fontColor(ACCENT)
            Text(this.cards.length === 0 ? '还没有名片' : '没有找到名片').id('CardsEmptyTitle')
              .fontSize(22).fontWeight(FontWeight.Bold).fontColor(INK)
            Text(this.cards.length === 0 ? '添加第一位联系人，建立你的名片夹。' : '换个关键词，或清除分组与收藏筛选。')
              .fontSize(14).fontColor(MUTED).lineHeight(23).textAlign(TextAlign.Center)
            Button(this.cards.length === 0 ? '新增第一张名片' : '清除筛选', { type: ButtonType.Normal })
              .id('CardsEmptyAction').fontSize(15).fontColor(Color.White).height(46)
              .backgroundColor(ACCENT).borderRadius(12)
              .onClick(() => {
                if (this.cards.length === 0) { this.open('pages/CardEditor'); } else { this.clearFilters(); }
              })
          }.width('100%').padding({ left: 22, right: 22, top: 36, bottom: 36 })
            .backgroundColor(Color.White).borderRadius(22)
        } else {
          List({ space: 14 }) {
            ForEach(this.visibleCards, (card: BusinessCard) => {
              ListItem() {
                Button({ type: ButtonType.Normal }) {
                  Column({ space: 16 }) {
                    Row({ space: 12 }) {
                      Text(card.name.slice(0, 1)).fontSize(23).fontWeight(FontWeight.Bold)
                        .fontColor(ACCENT).width(48).height(48).textAlign(TextAlign.Center)
                        .backgroundColor('#E2F2F1').borderRadius(16)
                      Column({ space: 5 }) {
                        Text(card.name).fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(card.title || '未填写职位').fontSize(13).fontColor(MUTED)
                          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                      Text(card.favorite ? '★' : '›').fontSize(22).fontColor(card.favorite ? '#B47B20' : MUTED)
                    }.width('100%')
                    if (card.organization) {
                      Text(card.organization).fontSize(14).fontColor(INK).width('100%')
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                    Row({ space: 12 }) {
                      Text(card.phone || card.email).fontSize(14).fontColor(MUTED).layoutWeight(1)
                        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(card.group).fontSize(11).fontColor(ACCENT)
                        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                        .backgroundColor('#EDF7F5').borderRadius(8)
                    }.width('100%')
                  }.width('100%').padding(20).alignItems(HorizontalAlign.Start)
                }.id('CardItem_' + card.id).width('100%').backgroundColor(Color.White).borderRadius(20)
                  .onClick(() => this.open('pages/CardDetail', card.id))
              }
            }, (card: BusinessCard) => card.id)
          }.id('CardsList').width('100%').layoutWeight(1).scrollBar(BarState.Off)
        }
      }.width('100%').constraintSize({ maxWidth: 680 }).layoutWeight(1)
        .padding({ left: 22, right: 22, top: 18, bottom: 22 })
    }.width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
