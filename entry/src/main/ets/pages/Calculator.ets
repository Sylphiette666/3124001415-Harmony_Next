import { ACCENT, INK, MUTED, PAGE_BG } from '../model/CourseData';
import { CalculatorEngine, CalculatorState, spokenNumber } from '../model/CalculatorEngine';
import { CalculatorSpeech, SpeechStatus } from '../services/CalculatorSpeech';

@Entry
@Component
struct Calculator {
  @State viewState: CalculatorState = new CalculatorState();
  @State speechState: SpeechStatus = new SpeechStatus();
  @State voiceEnabled: boolean = true;
  @State lastResult: string = '';
  private engine: CalculatorEngine = new CalculatorEngine();
  private speech: CalculatorSpeech | undefined = undefined;
  private pageVisible: boolean = false;

  onPageShow(): void {
    this.pageVisible = true;
    this.speech = new CalculatorSpeech((status: SpeechStatus) => {
      if (this.pageVisible) this.speechState = status;
    });
    this.speech.setEnabled(this.voiceEnabled);
    if (this.voiceEnabled) void this.speech.initialize();
  }

  onPageHide(): void {
    this.releaseSpeech();
  }

  aboutToDisappear(): void {
    this.releaseSpeech();
  }

  private releaseSpeech(): void {
    this.pageVisible = false;
    this.speech?.dispose();
    this.speech = undefined;
  }

  private handleKey(key: string): void {
    const next: CalculatorState = this.engine.press(key);
    this.viewState = next;
    if (key === 'AC') {
      this.lastResult = '';
      this.speech?.stop();
    }
    this.lastResult = next.calculated ? next.display : '';
    if (next.error !== '') {
      this.speak(this.keySpeech(key) + '，' + next.error);
    } else if (next.calculated) {
      this.speak(this.keySpeech(key) + (key === '=' ? '，' : '，结果是') + spokenNumber(next.display));
    } else {
      this.speak(this.keySpeech(key));
    }
  }

  private keySpeech(key: string): string {
    if (/^[0-9]$/.test(key) || key === '.') return key === '.' ? '小数点' : key;
    if (key === '+') return '加';
    if (key === '-') return '减';
    if (key === '×') return '乘';
    if (key === '÷') return '除';
    if (key === '=') return '等于';
    if (key === '±') return '正负号';
    if (key === '%') return '百分号';
    if (key === '1/x') return '倒数';
    if (key === 'x²') return '平方';
    if (key === '√') return '平方根';
    if (key === '⌫') return '退格';
    return key === 'AC' ? '全部清除' : '清除当前输入';
  }

  private speak(text: string): void {
    this.speech?.speak(text);
  }

  private retrySpeech(): void {
    if (this.voiceEnabled) void this.speech?.initialize();
  }

  private toggleVoice(): void {
    this.voiceEnabled = !this.voiceEnabled;
    this.speech?.setEnabled(this.voiceEnabled);
  }

  private replay(): void {
    if (this.lastResult !== '') {
      this.speech?.stop();
      this.speak('结果是' + spokenNumber(this.lastResult));
    }
  }

  @Builder
  keyButton(label: string, id: string, background: ResourceColor, foreground: ResourceColor = INK) {
    Button(label, { type: ButtonType.Normal }).id(id)
      .height(48).fontSize(19).fontWeight(FontWeight.Medium).fontColor(foreground)
      .backgroundColor(background).borderRadius(14).layoutWeight(1)
      .accessibilityText(this.keySpeech(label)).onClick(() => this.handleKey(label));
  }

  build() {
    Column() {
      Row({ space: 14 }) {
        Button('‹ 返回', { type: ButtonType.Normal }).id('CalculatorBackButton').height(44)
          .fontSize(15).fontColor(ACCENT).backgroundColor(Color.Transparent)
          .onClick(() => this.getUIContext().getRouter().back())
        Text('有声计算器').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
        Blank()
      }.width('100%').padding({ left: 10, right: 18, top: 4, bottom: 4 })
      Scroll() {
        Column({ space: 10 }) {
          Row() {
            Column({ space: 4 }) {
              Text('标准计算器').fontSize(22).fontWeight(FontWeight.Bold).fontColor(INK)
              Text('按键和结果支持中文语音播报').fontSize(13).fontColor(MUTED)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Button(this.voiceEnabled ? '语音开' : '语音关', { type: ButtonType.Normal }).id('VoiceToggleButton')
              .fontSize(13).fontColor(this.voiceEnabled ? ACCENT : MUTED)
              .backgroundColor(this.voiceEnabled ? '#E2F2F1' : '#E9EEF1').borderRadius(12)
              .height(40).padding({ left: 14, right: 14 }).onClick(() => this.toggleVoice())
          }.width('100%')
          Column({ space: 8 }) {
            Text(this.viewState.expression || '准备开始计算').id('CalcExpression').fontSize(14)
              .fontColor('#90A5AF').width('100%').textAlign(TextAlign.End)
            Text(this.viewState.display).id('CalcDisplay').fontSize(44).fontWeight(FontWeight.Bold)
              .fontColor(INK).width('100%').height(56).textAlign(TextAlign.End).maxLines(1)
              .minFontSize(18).maxFontSize(44).heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
            if (this.viewState.error) {
              Text(this.viewState.error).id('CalcError').fontSize(14).fontColor('#AF3434')
                .width('100%').textAlign(TextAlign.End)
            }
          }.id('CalculatorDisplayCard').width('100%').padding(16).backgroundColor(Color.White).borderRadius(20)
          Row({ space: 10 }) {
            Text(this.speechState.message).id('SpeechStatus').fontSize(12).fontColor(MUTED)
              .layoutWeight(1).onClick(() => this.retrySpeech())
            Button('重播结果', { type: ButtonType.Normal }).id('ReplayResultButton')
              .fontSize(12).fontColor(ACCENT).backgroundColor('#E2F2F1').borderRadius(10)
              .height(34).padding({ left: 12, right: 12 }).enabled(this.voiceEnabled && this.lastResult !== '')
              .onClick(() => this.replay())
          }.width('100%')
          Column({ space: 8 }) {
            Row({ space: 10 }) {
              this.keyButton('%', 'CalcKey_percent', '#DCE8EC', ACCENT)
              this.keyButton('CE', 'CalcKey_clearEntry', '#DCE8EC', ACCENT)
              this.keyButton('AC', 'CalcKey_clearAll', '#DCE8EC', ACCENT)
              this.keyButton('⌫', 'CalcKey_backspace', '#DCE8EC', ACCENT)
            }.width('100%')
            Row({ space: 10 }) {
              this.keyButton('1/x', 'CalcKey_reciprocal', '#E9F0F2', ACCENT)
              this.keyButton('x²', 'CalcKey_square', '#E9F0F2', ACCENT)
              this.keyButton('√', 'CalcKey_sqrt', '#E9F0F2', ACCENT)
              this.keyButton('÷', 'CalcKey_divide', '#D9F0EF', ACCENT)
            }.width('100%')
            Row({ space: 10 }) {
              this.keyButton('7', 'CalcKey_7', Color.White)
              this.keyButton('8', 'CalcKey_8', Color.White)
              this.keyButton('9', 'CalcKey_9', Color.White)
              this.keyButton('×', 'CalcKey_multiply', '#D9F0EF', ACCENT)
            }.width('100%')
            Row({ space: 10 }) {
              this.keyButton('4', 'CalcKey_4', Color.White)
              this.keyButton('5', 'CalcKey_5', Color.White)
              this.keyButton('6', 'CalcKey_6', Color.White)
              this.keyButton('-', 'CalcKey_subtract', '#D9F0EF', ACCENT)
            }.width('100%')
            Row({ space: 10 }) {
              this.keyButton('1', 'CalcKey_1', Color.White)
              this.keyButton('2', 'CalcKey_2', Color.White)
              this.keyButton('3', 'CalcKey_3', Color.White)
              this.keyButton('+', 'CalcKey_add', '#D9F0EF', ACCENT)
            }.width('100%')
            Row({ space: 10 }) {
              this.keyButton('±', 'CalcKey_sign', '#E9F0F2', ACCENT)
              this.keyButton('0', 'CalcKey_0', Color.White)
              this.keyButton('.', 'CalcKey_decimal', Color.White)
              this.keyButton('=', 'CalcKey_equals', ACCENT, Color.White)
            }.width('100%')
          }.id('CalculatorKeypad').width('100%').constraintSize({ maxWidth: 560 })
        }.width('100%').constraintSize({ maxWidth: 680 }).padding({ left: 18, right: 18, top: 10, bottom: 18 })
      }.id('CalculatorScroll').layoutWeight(1).width('100%').scrollBar(BarState.Off).align(Alignment.Top)
    }.id('CalculatorPage').width('100%').height('100%').backgroundColor(PAGE_BG)
  }
}
