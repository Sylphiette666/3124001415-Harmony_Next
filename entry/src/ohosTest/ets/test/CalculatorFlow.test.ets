import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON, On } from '@kit.TestKit';

/**
 * 纯 UI 回归：所有计算均通过页面按键完成，不依赖系统 TTS 服务。
 * 测试结束时尽量返回首页，避免影响后续名片/资料测试。
 */
class CalculatorUi {
  driver: Driver = Driver.create();
  bundleName: string;

  constructor(bundleName: string) { this.bundleName = bundleName; }

  selector(id: string): On { return ON.id(id).inWindow(this.bundleName); }

  async find(id: string): Promise<Component | null> {
    try { return await this.driver.findComponent(this.selector(id)); } catch { return null; }
  }

  async wait(id: string, timeout: number = 6000): Promise<Component> {
    const component = await this.driver.waitForComponent(this.selector(id), timeout);
    if (!component) { throw new Error('等待计算器控件超时：' + id); }
    return component;
  }

  async click(id: string): Promise<void> {
    await (await this.wait(id)).click();
    await this.driver.delayMs(180);
  }

  async text(id: string): Promise<string> {
    return await (await this.wait(id)).getText();
  }

  async expectText(id: string, expected: string): Promise<void> {
    for (let attempt = 0; attempt < 20; attempt++) {
      try {
        const component = await this.find(id);
        if (component && await component.getText() === expected) { return; }
      } catch { /* 页面状态更新后重试。 */ }
      await this.driver.delayMs(120);
    }
    expect(await this.text(id)).assertEqual(expected);
  }

  async reveal(id: string, scrollId: string): Promise<Component> {
    const direct = await this.find(id);
    if (direct) { return direct; }
    const scroll = await this.wait(scrollId);
    const found = await scroll.scrollSearch(this.selector(id));
    if (!found) { throw new Error('滚动后仍找不到计算器控件：' + id); }
    return found;
  }

  async key(id: string): Promise<void> {
    await (await this.reveal(id, 'CalculatorScroll')).click();
    await this.driver.delayMs(120);
  }

  async press(...ids: string[]): Promise<void> {
    for (const id of ids) { await this.key(id); }
  }

  async returnHome(): Promise<void> {
    const back = await this.find('CalculatorBackButton');
    if (back) {
      await back.click();
      await this.driver.delayMs(500);
    }
    await this.wait('OpenCalculatorButton', 5000);
  }
}

export default function calculatorFlowTest() {
  describe('TalkingCalculatorUi', () => {
    it('performsStandardAndVoiceCalculatorFlows', 0, async () => {
      const args = abilityDelegatorRegistry.getArguments();
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: args.bundleName, abilityName: 'EntryAbility' });
      const ui = new CalculatorUi(args.bundleName);
      let entered = false;
      try {
        // 首页入口可能在滚动区下方；先等待首页，再用滚动搜索稳定找到入口。
        await ui.wait('HomeScroll');
        await ui.reveal('OpenCalculatorButton', 'HomeScroll');
        await ui.click('OpenCalculatorButton');
        entered = true;
        await ui.wait('CalculatorPage');
        await ui.wait('CalcDisplay');
        // SpeechStatus 只验证控件存在；不要求 TTS ready，避免把系统音频服务问题
        // 混入计算逻辑回归。给页面一小段时间完成语音初始化即可。
        await ui.wait('SpeechStatus');
        await ui.driver.delayMs(500);

        await ui.expectText('CalcDisplay', '0');

        await ui.press('CalcKey_1', 'CalcKey_2', 'CalcKey_add', 'CalcKey_3', 'CalcKey_equals');
        await ui.expectText('CalcDisplay', '15');
        await ui.key('CalcKey_equals');
        await ui.expectText('CalcDisplay', '18');

        await ui.key('CalcKey_clearAll');
        await ui.expectText('CalcDisplay', '0');

        await ui.press('CalcKey_2', 'CalcKey_0', 'CalcKey_0', 'CalcKey_add',
          'CalcKey_1', 'CalcKey_0', 'CalcKey_percent', 'CalcKey_equals');
        await ui.expectText('CalcDisplay', '220');

        await ui.key('CalcKey_clearAll');
        await ui.press('CalcKey_7', 'CalcKey_divide', 'CalcKey_0', 'CalcKey_equals');
        // 错误状态显示独立提示，继续输入数字可以恢复。
        const error = await ui.find('CalcError');
        expect(error !== null).assertTrue();
        expect((await ui.text('CalcError')).length > 0).assertTrue();
        await ui.key('CalcKey_9');
        await ui.expectText('CalcDisplay', '9');
        await ui.press('CalcKey_equals', 'CalcKey_sign');
        await ui.expectText('CalcDisplay', '-9');

        // 此处检查语音开关状态；真实播放由系统日志与音频另行验证。
        const voiceState = await ui.text('VoiceToggleButton');
        if (voiceState === '语音开') {
          await ui.click('VoiceToggleButton');
          await ui.expectText('VoiceToggleButton', '语音关');
          await ui.click('VoiceToggleButton');
          await ui.expectText('VoiceToggleButton', '语音开');
        } else {
          await ui.click('VoiceToggleButton');
          await ui.expectText('VoiceToggleButton', '语音开');
          await ui.click('VoiceToggleButton');
          await ui.expectText('VoiceToggleButton', '语音关');
          await ui.click('VoiceToggleButton');
          await ui.expectText('VoiceToggleButton', '语音开');
        }
        await ui.click('ReplayResultButton');
      } finally {
        if (entered) {
          try { await ui.returnHome(); } catch { /* 保留原始断言错误。 */ }
        }
      }
    });
  });
}
