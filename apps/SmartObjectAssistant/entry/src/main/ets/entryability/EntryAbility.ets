import { UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { syncService } from '../services/SyncService';

export default class EntryAbility extends UIAbility {
  onWindowStageCreate(stage: window.WindowStage): void { stage.loadContent('pages/Index'); }
  onDestroy(): void { syncService.stop(); }
}
