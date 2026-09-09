import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON, On } from '@kit.TestKit';
import { BusinessCard } from '../../../main/ets/model/BusinessCard';
import { CardStore } from '../../../main/ets/model/CardStore';

// API 20+ 的 paste 模式通过 UiTest 注入文本。测试不会点击输入法协议或系统授权按钮；
// 若设备首次输入提示阻挡操作，测试会明确失败，finally 仅删除本次创建的 QA 名片。
class CardUi {
  driver: Driver = Driver.create();
  bundleName: string;

  constructor(bundleName: string) { this.bundleName = bundleName; }

  selector(id: string): On { return ON.id(id).inWindow(this.bundleName); }

  async wait(id: string): Promise<Component> {
    const component = await this.driver.waitForComponent(this.selector(id), 5000);
    if (!component) { throw new Error('等待应用控件超时：' + id); }
    return component;
  }

  async click(id: string): Promise<void> {
    await (await this.wait(id)).click();
    await this.driver.delayMs(500);
  }

  async text(id: string): Promise<string> {
    for (let attempt = 0; attempt < 10; attempt++) {
      try { return await (await this.wait(id)).getText(); } catch {
        await this.driver.delayMs(200);
      }
    }
    throw new Error('页面更新后仍无法读取控件：' + id);
  }

  async expectText(id: string, expected: string): Promise<void> {
    for (let attempt = 0; attempt < 20; attempt++) {
      try {
        const component = await this.driver.findComponent(this.selector(id));
        if (component && await component.getText() === expected) { return; }
      } catch { /* 页面刷新后重新查找控件。 */ }
      await this.driver.delayMs(200);
    }
    expect(await this.text(id)).assertEqual(expected);
  }

  async input(id: string, value: string): Promise<void> {
    await (await this.wait(id)).inputText(value, { paste: true, addition: false });
    for (let attempt = 0; attempt < 10; attempt++) {
      const component = await this.driver.findComponent(this.selector(id));
      if (component && await component.getText() === value) {
        // 等待输入法切换布局稳定，避免紧接着点击到移动中的保存按钮。
        await this.driver.delayMs(600);
        return;
      }
      await this.driver.delayMs(200);
    }
    throw new Error('UiTest 文本注入未生效：' + id + '。请检查设备输入法首次提示；测试不会自动授权。');
  }

  async scrollTo(id: string, scrollId: string = ''): Promise<void> {
    const target = await this.driver.findComponent(this.selector(id));
    if (target) { return; }
    const scroll = scrollId.length > 0 ? await this.wait(scrollId) :
      await this.driver.findComponent(ON.type('Scroll').inWindow(this.bundleName));
    if (!scroll) { throw new Error('找不到包含目标控件的滚动区：' + id); }
    const found = await scroll.scrollSearch(this.selector(id));
    if (!found) { throw new Error('滚动后仍未找到应用控件：' + id); }
  }

  async expectMissing(id: string): Promise<void> {
    for (let attempt = 0; attempt < 10; attempt++) {
      if (!await this.driver.findComponent(this.selector(id))) { return; }
      await this.driver.delayMs(200);
    }
    throw new Error('控件仍存在，预期应被筛选或删除：' + id);
  }

  async clickDialogText(text: string): Promise<void> {
    const selector = text === '删除名片' ?
      ON.text(text).isAfter(ON.text('删除这张名片？')).inWindow(this.bundleName) :
      ON.text(text).inWindow(this.bundleName);
    const component = await this.driver.waitForComponent(selector, 5000);
    if (!component) { throw new Error('找不到应用确认弹窗按钮：' + text); }
    await component.click();
    await this.driver.delayMs(500);
  }
}

export default function cardFlowTest() {
  describe('BusinessCardUiFlow', () => {
    it('createsEditsFiltersAndDeletesOnlyItsOwnCard', 0, async () => {
      const args = abilityDelegatorRegistry.getArguments();
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({ bundleName: args.bundleName, abilityName: 'EntryAbility' });
      const ui = new CardUi(args.bundleName);
      await ui.driver.delayMs(800);
      const ability = await delegator.getCurrentTopAbility();
      const store = new CardStore(ability.context);
      const originalIds = store.load().map((card: BusinessCard) => card.id);
      const marker = 'QA_CardUI_' + Date.now().toString() + '_' + Math.floor(Math.random() * 10000).toString();
      const editedName = marker + '_edit';
      let createdId = '';
      try {
        // 从首页走真实导航，空表单应停留在编辑页并显示可理解的提示。
        // 冷启动先经过约一秒的校徽启动页。
        await ui.wait('OpenCardsButton');
        await ui.scrollTo('OpenCardsButton');
        await ui.click('OpenCardsButton');
        await ui.click('NewCardButton');
        await ui.wait('CardNameInput');
        await ui.click('SaveCardButton');
        expect(await ui.text('CardEditorError')).assertEqual('请填写姓名');
        await ui.input('CardNameInput', marker);
        await ui.input('CardPhoneInput', '13800000000');
        await ui.click('SaveCardButton');
        await ui.wait('NewCardButton');

        const created = store.load().find((card: BusinessCard) => card.name === marker &&
          originalIds.indexOf(card.id) < 0);
        if (!created) { throw new Error('UI 保存后未找到本次 QA 名片'); }
        createdId = created.id;
        expect(created.phone).assertEqual('13800000000');
        expect(created.favorite).assertFalse();

        // 精确搜索使列表断言不受设备中已有联系人影响。
        await ui.input('CardSearch', marker);
        await ui.scrollTo('CardItem_' + createdId, 'CardsList');
        await ui.click('CardItem_' + createdId);
        expect(await ui.text('CardDetailName')).assertEqual(marker);
        await ui.click('EditCardButton');
        expect(await ui.text('CardNameInput')).assertEqual(marker);
        await ui.input('CardNameInput', editedName);
        await ui.input('CardPhoneInput', '13900000000');
        await ui.click('SaveCardButton');
        await ui.expectText('CardDetailName', editedName);
        const edited = store.load().find((card: BusinessCard) => card.id === createdId);
        if (!edited) { throw new Error('编辑保存后 QA 名片丢失'); }
        expect(edited.phone).assertEqual('13900000000');
        expect(edited.name).assertEqual(editedName);

        // 默认“其他”分组；不匹配分组必须隐藏当前 QA 名片。
        await ui.click('CardDetailBackButton');
        await ui.click('CardGroup_1');
        await ui.expectMissing('CardItem_' + createdId);
        await ui.click('CardGroup_0');
        await ui.wait('CardItem_' + createdId);

        // 未收藏时筛选应隐藏，收藏之后应重新出现。
        await ui.click('FavoriteFilterButton');
        await ui.expectMissing('CardItem_' + createdId);
        await ui.click('FavoriteFilterButton');
        await ui.click('CardItem_' + createdId);
        await ui.click('ToggleCardFavoriteButton');
        await ui.expectText('ToggleCardFavoriteButton', '★ 已收藏 · 点击取消');
        await ui.click('CardDetailBackButton');
        await ui.click('FavoriteFilterButton');
        await ui.wait('CardItem_' + createdId);
        await ui.input('CardSearch', marker + '_absent');
        await ui.expectMissing('CardItem_' + createdId);
        await ui.input('CardSearch', editedName);
        await ui.click('CardItem_' + createdId);

        // 先取消删除，应保留；再次确认后，页面和存储均不应再包含它。
        await ui.scrollTo('DeleteCardButton');
        await ui.click('DeleteCardButton');
        await ui.clickDialogText('取消');
        expect(store.load().some((card: BusinessCard) => card.id === createdId)).assertTrue();
        await ui.click('DeleteCardButton');
        await ui.clickDialogText('删除名片');
        await ui.wait('NewCardButton');
        await ui.expectMissing('CardItem_' + createdId);
        expect(store.load().some((card: BusinessCard) => card.id === createdId)).assertFalse();
        await ui.click('CardsBackButton');
        await ui.wait('OpenCardsButton');
      } catch (error) {
        try { await ui.driver.screenCap(ability.context.filesDir + '/cards-ui-failure.png'); } catch {}
        throw error as Error;
      } finally {
        // 包括“保存已落盘但导航断言失败”的情况；只匹配本次随机名称和新 ID。
        const leftovers = store.load().filter((card: BusinessCard) => originalIds.indexOf(card.id) < 0 &&
          (card.id === createdId || card.name === marker || card.name === editedName));
        for (const card of leftovers) { await store.remove(card.id); }
      }
    });
  });
}
