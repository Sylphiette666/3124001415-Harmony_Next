import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';

// 测试加载可能早于 Ability 进入前台，等待真实的 UIAbility 上下文。
export async function getTestContext(): Promise<common.UIAbilityContext> {
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  for (let attempt = 0; attempt < 30; attempt++) {
    try {
      return (await delegator.getCurrentTopAbility()).context;
    } catch {
      if (attempt === 0) {
        await delegator.startAbility({
          bundleName: abilityDelegatorRegistry.getArguments().bundleName,
          abilityName: 'EntryAbility'
        });
      }
      await new Promise<void>((resolve) => { setTimeout(resolve, 200); });
    }
  }
  throw new Error('测试应用未能进入前台，无法取得本地存储上下文');
}