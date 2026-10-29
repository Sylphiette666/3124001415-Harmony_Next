import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { campusSync } from '../services/CampusSync';
export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void { stage.loadContent('pages/Index'); }
  onDestroy(): void { campusSync.stop(); }
}
