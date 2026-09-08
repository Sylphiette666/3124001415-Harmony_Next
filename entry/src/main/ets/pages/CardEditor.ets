import { common } from '@kit.AbilityKit';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import { ACCENT, INK, MUTED, PAGE_BG } from '../model/CourseData';
import { BusinessCard, CARD_GROUPS, copyCard, validateCard } from '../model/BusinessCard';
import { CardStore } from '../model/CardStore';

interface CardEditorParams { cardId?: string; }

@Entry
@Component
struct CardEditor {
  @State nameText: string = '';
  @State organizationText: string = '';
  @State titleText: string = '';
  @State phoneText: string = '';
  @State emailText: string = '';
  @State addressText: string = '';
  @State noteText: string = '';
  @State group: string = '其他';
  @State saving: boolean = false;
  @State error: string = '';
  @State loaded: boolean = false;
  @State editing: boolean = false;
  private original: BusinessCard = new BusinessCard();
  private initialSnapshot: string = '';
  private allowBack: boolean = false;
  private previousKeyboardMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;

  aboutToAppear(): void {
    this.previousKeyboardMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    const params = this.getUIContext().getRouter().getParams() as CardEditorParams | undefined;
    this.editing = !!params?.cardId;
    try {
      const cards = this.store().load();
      if (params?.cardId) {
        const existing = cards.find((item: BusinessCard) => item.id === params.cardId);
        if (!existing) { this.error = '该名片已不存在，请返回名片夹。'; return; }
        this.original = copyCard(existing);
      }
      this.nameText = this.original.name;
      this.organizationText = this.original.organization;
      this.titleText = this.original.title;
      this.phoneText = this.original.phone;
      this.emailText = this.original.email;
      this.addressText = this.original.address;
      this.noteText = this.original.note;
      this.group = this.original.group;
      this.initialSnapshot = JSON.stringify(this.draft());
      this.loaded = true;
    } catch {
      this.error = '名片数据读取失败，暂时无法编辑。请返回后重试。';
    }
  }

  aboutToDisappear(): void {
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode);
  }

  private store(): CardStore {
    return new CardStore(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  private draft(): BusinessCard {
    const result = copyCard(this.original);
    result.name = this.nameText;
    result.organization = this.organizationText;
    result.title = this.titleText;
    result.phone = this.phoneText;
    result.email = this.emailText;
    result.address = this.addressText;
    result.note = this.noteText;
    result.group = this.group;
    return result;
  }

  private changed(): boolean {
    return this.loaded && JSON.stringify(this.draft()) !== this.initialSnapshot;
  }

  private close(): void {
    if (this.saving) { return; }
    if (!this.changed()) {
      this.allowBack = true;
      this.getUIContext().getRouter().back();
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '放弃本次修改？',
      message: '未保存的内容将不会保留。',
      primaryButton: { value: '继续编辑', action: () => {} },
      secondaryButton: {
        value: '放弃修改',
        action: () => { this.allowBack = true; this.getUIContext().getRouter().back(); }
      }
    });
  }

  onBackPress(): boolean {
    if (this.allowBack) { return false; }
    if (this.saving) { return true; }
    if (this.changed()) { this.close(); return true; }
    return false;
  }

  private async save(): Promise<void> {
    if (this.saving || !this.loaded) { return; }
    const card = this.draft();
    this.error = validateCard(card);
    if (this.error) { return; }
    this.saving = true;
    try {
      await this.store().save(card);
      this.allowBack = true;
      this.getUIContext().getRouter().back();
    } catch {
      this.error = '保存失败，请重新读取名片后重试。';
    } finally { this.saving = false; }
  }

  @Builder
  field(label: string, id: string, value: string, placeholder: string, change: (text: string) => void,
    max: number = 100, inputType: InputType = InputType.Normal) {
    Column({ space: 9 }) {
      Text(label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(INK)
      TextInput({ text: value, placeholder }).id(id).height(48).fontSize(16).maxLength(max)
        .type(inputType).backgroundColor(PAGE_BG).borderRadius(12).onChange(change)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Button('‹ 返回', { type: ButtonType.Normal }).id('CardEditorBackButton').height(44)
          .fontSize(15).fontColor(ACCENT).backgroundColor(Color.Transparent)
          .enabled(!this.saving).onClick(() => this.close())
        Text(this.editing ? '编辑名片' : '新增名片').id('CardEditorTitle').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
        Blank()
      }.width('100%').padding({ left: 10, right: 22, top: 8, bottom: 8 })
      Scroll() {
        Column({ space: 20 }) {
          Text('姓名为必填；电话和邮箱至少填写一项。').fontSize(14).fontColor(MUTED).width('100%').lineHeight(23)
          if (this.loaded) {
            Column({ space: 20 }) {
              this.field('姓名 *', 'CardNameInput', this.nameText, '请输入姓名',
                (value: string) => { this.nameText = value; }, 40)
              this.field('电话', 'CardPhoneInput', this.phoneText, '手机或固定电话',
                (value: string) => { this.phoneText = value; }, 30, InputType.PhoneNumber)
              this.field('邮箱', 'CardEmailInput', this.emailText, 'name@example.com',
                (value: string) => { this.emailText = value; }, 120, InputType.Email)
            }.width('100%').padding(22).backgroundColor(Color.White).borderRadius(22)
            Column({ space: 20 }) {
              this.field('单位 / 学校', 'CardOrganizationInput', this.organizationText, '请输入单位或学校',
                (value: string) => { this.organizationText = value; }, 60)
              this.field('职位 / 身份', 'CardTitleInput', this.titleText, '例如：同学、老师、工程师',
                (value: string) => { this.titleText = value; }, 40)
              Column({ space: 10 }) {
                Text('名片分组').fontSize(14).fontWeight(FontWeight.Medium).fontColor(INK)
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(CARD_GROUPS, (item: string, index: number) => {
                    Button(item, { type: ButtonType.Normal }).id('EditorGroup_' + index).height(38)
                      .fontSize(14).fontColor(this.group === item ? Color.White : MUTED)
                      .backgroundColor(this.group === item ? ACCENT : PAGE_BG).borderRadius(10)
                      .padding({ left: 16, right: 16 }).margin({ right: 8, bottom: 8 })
                      .onClick(() => { this.group = item; })
                  }, (item: string) => item)
                }.width('100%')
              }.width('100%').alignItems(HorizontalAlign.Start)
              this.field('地址', 'CardAddressInput', this.addressText, '办公地址或联系地址（选填）',
                (value: string) => { this.addressText = value; }, 160)
              Column({ space: 9 }) {
                Text('备注').fontSize(14).fontWeight(FontWeight.Medium).fontColor(INK)
                TextArea({ text: this.noteText, placeholder: '记录相识场景或其他信息（选填）' }).id('CardNoteInput')
                  .height(110).fontSize(15).maxLength(500).backgroundColor(PAGE_BG).borderRadius(12)
                  .onChange((value: string) => { this.noteText = value; })
              }.width('100%').alignItems(HorizontalAlign.Start)
            }.width('100%').padding(22).backgroundColor(Color.White).borderRadius(22)
          }
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 22, right: 22, top: 16, bottom: 24 })
      }.id('CardEditorScroll').enabled(!this.saving).width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
      Column({ space: 10 }) {
        if (this.error) {
          Text(this.error).id('CardEditorError').fontSize(14).fontColor('#B33B35').width('100%')
        }
        Button(this.saving ? '正在保存…' : '保存名片', { type: ButtonType.Normal }).id('SaveCardButton')
          .width('100%').height(50).fontSize(16).fontColor(Color.White).backgroundColor(ACCENT).borderRadius(14)
          .enabled(this.loaded && !this.saving).onClick(() => { this.save(); })
      }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 22, right: 22, top: 12, bottom: 16 })
        .backgroundColor(Color.White)
    }.width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
