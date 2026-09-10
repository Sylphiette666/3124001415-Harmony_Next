import { describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON, On } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { StudentProfile } from '../../../main/ets/model/CourseData';
import { getTestContext } from './TestContext';

class ProfileUi {
  driver: Driver = Driver.create();
  bundleName: string;

  constructor(bundleName: string) { this.bundleName = bundleName; }

  selector(id: string): On { return ON.id(id).inWindow(this.bundleName); }

  async wait(id: string): Promise<Component> {
    const component = await this.driver.waitForComponent(this.selector(id), 5000);
    if (!component) { throw new Error('等待个人资料控件超时：' + id); }
    return component;
  }

  async reveal(id: string, scrollId: string): Promise<Component> {
    const component = await this.driver.findComponent(this.selector(id));
    if (component) { return component; }
    const scroll = await this.wait(scrollId);
    const found = await scroll.scrollSearch(this.selector(id));
    if (!found) { throw new Error('滚动后仍找不到个人资料控件：' + id); }
    return found;
  }

  async click(id: string, scrollId: string = ''): Promise<void> {
    const component = scrollId ? await this.reveal(id, scrollId) : await this.wait(id);
    await component.click();
    await this.driver.delayMs(500);
  }

  async input(id: string, value: string): Promise<void> {
    await (await this.reveal(id, 'ProfileScroll')).inputText(value, { paste: true, addition: false });
    for (let attempt = 0; attempt < 15; attempt++) {
      try {
        const component = await this.driver.findComponent(this.selector(id));
        if (component && await component.getText() === value) {
          await this.driver.delayMs(600);
          return;
        }
      } catch { /* 文本输入导致布局刷新，重新查找控件。 */ }
      await this.driver.delayMs(200);
    }
    throw new Error('个人资料文本注入未生效：' + id + '；请确认设备系统输入法可用。');
  }

  async dismissKeyboard(context: common.UIAbilityContext): Promise<void> {
    const appWindow = await window.getLastWindow(context);
    const area = appWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD);
    if (area.bottomRect.height <= 0) { return; }
    // 只有应用报告键盘占用区域时才返回一次，避免误退出尚未保存的编辑页。
    await this.driver.pressBack();
    await this.wait('ProfileScroll');
    for (let attempt = 0; attempt < 15; attempt++) {
      if (appWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect.height <= 0) {
        await this.driver.delayMs(400);
        return;
      }
      await this.driver.delayMs(200);
    }
    throw new Error('系统键盘未收起，停止点击可能被遮挡的保存按钮。');
  }

  async expectText(id: string, expected: string, scrollId: string): Promise<void> {
    await this.reveal(id, scrollId);
    let actual = '';
    for (let attempt = 0; attempt < 15; attempt++) {
      try {
        const component = await this.driver.findComponent(this.selector(id));
        if (component) {
          actual = await component.getText();
          if (actual === expected) { return; }
        }
      } catch { /* 页面更新时的旧控件已失效，重新读取。 */ }
      await this.driver.delayMs(200);
    }
    expect(actual).assertEqual(expected);
  }

  async expectHome(profile: StudentProfile): Promise<void> {
    await this.wait('HomeScroll');
    // 直接检查保存返回后的现有首页，不重启或重新打开首页掩盖响应式刷新问题。
    await this.expectText('StudentClass', profile.className || '请填写班级或专业', 'HomeScroll');
    await this.expectText('StudentId', profile.studentId, 'HomeScroll');
    await this.expectText('StudentName', profile.name || '请填写姓名', 'HomeScroll');
  }

  async readEditor(): Promise<StudentProfile> {
    const ids: string[] = ['NameInput', 'StudentIdInput', 'ClassInput'];
    const placeholders: string[] = ['请输入姓名', '请输入学号', '请输入班级或专业'];
    const values: string[] = [];
    for (let index = 0; index < ids.length; index++) {
      const actual = await (await this.reveal(ids[index], 'ProfileScroll')).getText();
      values.push(actual === placeholders[index] ? '' : actual);
    }
    const profile = new StudentProfile();
    profile.name = values[0];
    profile.studentId = values[1];
    profile.className = values[2];
    return profile;
  }

  async openEditor(): Promise<void> {
    const back = await this.driver.findComponent(this.selector('ProfileBackButton'));
    if (!back) {
      await this.wait('HomeScroll');
      await this.click('EditProfileButton', 'HomeScroll');
    }
    await this.wait('ProfileScroll');
  }

  async fillAndSave(profile: StudentProfile, context: common.UIAbilityContext): Promise<void> {
    await this.input('NameInput', profile.name);
    await this.input('StudentIdInput', profile.studentId);
    await this.input('ClassInput', profile.className);
    await this.dismissKeyboard(context);
    await this.click('SaveProfileButton', 'ProfileScroll');
  }

  async expectEditor(profile: StudentProfile): Promise<void> {
    await this.expectText('NameInput', profile.name, 'ProfileScroll');
    await this.expectText('StudentIdInput', profile.studentId, 'ProfileScroll');
    await this.expectText('ClassInput', profile.className, 'ProfileScroll');
  }
}

export default function profileFlowTest() {
  describe('ProfileHomepageRefresh', () => {
    it('updatesClassOnHomeAfterTwoSavesAndRestoresOriginalProfile', 0, async () => {
      const args = abilityDelegatorRegistry.getArguments();
      await abilityDelegatorRegistry.getAbilityDelegator().startAbility({
        bundleName: args.bundleName, abilityName: 'EntryAbility'
      });
      const abilityContext = await getTestContext();
      let original = new StudentProfile();
      const ui = new ProfileUi(args.bundleName);
      const unique = Date.now().toString();
      const edited = new StudentProfile();
      edited.name = 'QA资料' + unique;
      edited.studentId = '999' + unique;
      edited.className = 'QA回归班级 A ' + unique;
      let flowError: Error | undefined = undefined;
      let uiModified = false;
      try {
        await ui.wait('HomeScroll');
        await ui.openEditor();
        original = await ui.readEditor();
        if (!original.name.trim() || !original.className.trim() ||
          !/^[0-9]{6,20}$/.test(original.studentId.trim())) {
          throw new Error('只读保护：运行资料 UI 回归前须已有完整姓名、有效学号和班级；本次未修改资料。');
        }
        uiModified = true;
        await ui.fillAndSave(edited, abilityContext);
        await ui.expectHome(edited);

        // 第二次只修改班级：姓名和学号应保持，已有首页行应再次刷新。
        await ui.openEditor();
        await ui.expectEditor(edited);
        edited.className = 'QA回归班级 B ' + unique;
        await ui.input('ClassInput', edited.className);
        await ui.dismissKeyboard(abilityContext);
        await ui.click('SaveProfileButton', 'ProfileScroll');
        await ui.expectHome(edited);
      } catch (error) {
        flowError = error as Error;
        try { await ui.driver.screenCap(abilityContext.filesDir + '/profile-ui-failure.png'); } catch {}
        throw error as Error;
      } finally {
        // 备份、修改和恢复均走真实表单，避免测试模块与应用模块的存储目录差异。
        try {
          if (uiModified) {
            await ui.openEditor();
            await ui.fillAndSave(original, abilityContext);
            await ui.expectHome(original);
            await ui.openEditor();
            await ui.expectEditor(original);
            await ui.click('ProfileBackButton');
            await ui.wait('HomeScroll');
          } else {
            const back = await ui.driver.findComponent(ui.selector('ProfileBackButton'));
            if (back) { await ui.click('ProfileBackButton'); }
          }
        } catch (cleanupError) {
          if (flowError) {
            throw new Error('原始流程错误：' + (flowError.stack || flowError.message) +
              '\n资料恢复错误：' + (cleanupError as Error).message);
          }
          throw cleanupError as Error;
        }
      }
    });
  });
}
