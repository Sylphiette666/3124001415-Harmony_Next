import { AbilityConstant, ConfigurationConstant, UIAbility, Want, InsightIntentLink } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, router } from '@kit.ArkUI';
import { extractQuestion } from '../model/Knowledge';

const DOMAIN = 0x0000;

@InsightIntentLink({
  intentName: 'AskCourse', domain: 'education', intentVersion: '1.0.0',
  displayName: '课程知识问答', displayDescription: '查询本地课程资料，查看带原文依据的回答',
  uri: 'courselearning://ask', keywords: ['课程问答', '知识问答', '查资料'],
  parameters: { type: 'object', properties: { question: { type: 'string', description: '用户希望查询的课程问题' } }, required: ['question'] },
  paramMappings: [{ paramName: 'question', paramMappingName: 'question' }]
})
export default class EntryAbility extends UIAbility {
  private stage: window.WindowStage | undefined = undefined;
  private contentReady: boolean = false;
  private navigating: boolean = false;
  private requestSequence: number = 0;

  private receive(want: Want): void {
    const value = want.parameters ? want.parameters['question'] : undefined;
    const question = extractQuestion(want.uri || '', typeof value === 'string' ? value : '');
    if (!question) { return; }
    AppStorage.setOrCreate('courseAskIntent', JSON.stringify({ question: question, nonce: `${Date.now()}-${++this.requestSequence}` }));
    this.showKnowledge();
  }

  private showKnowledge(): void {
    if (!this.stage || !this.contentReady || this.navigating || !AppStorage.get<string>('courseAskIntent')) { return; }
    const ui = this.stage.getMainWindowSync().getUIContext();
    const pageRouter = ui.getRouter();
    const current = pageRouter.getState();
    // Router state names can include the page path. Match URL and active index instead.
    const onKnowledge = pageRouter.getStateByUrl('pages/KnowledgeAssistant').some((state: router.RouterState) => state.index === current.index);
    const onSplash = pageRouter.getStateByUrl('pages/Splash').some((state: router.RouterState) => state.index === current.index);
    // Splash owns its timed navigation; its storage watcher redirects pending intents.
    if (onKnowledge || onSplash) { return; }
    this.navigating = true;
    ui.getRouter().pushUrl({ url: 'pages/KnowledgeAssistant' }, router.RouterMode.Single).then(() => {
      this.navigating = false;
    }).catch(() => {
      this.navigating = false;
      ui.getPromptAction().showToast({ message: '知识问答页面打开失败，请从首页重试。' });
    });
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void { this.receive(want); }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.receive(want);
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    this.stage = windowStage;
    this.contentReady = false;
    const firstPage = AppStorage.get<string>('courseAskIntent') ? 'pages/KnowledgeAssistant' : 'pages/Splash';
    windowStage.loadContent(firstPage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      this.contentReady = true;
      // The initial page itself consumes the pending question. Do not push a second instance.
      if (firstPage !== 'pages/KnowledgeAssistant') { this.showKnowledge(); }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    this.stage = undefined; this.contentReady = false; this.navigating = false;
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}