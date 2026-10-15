import { UIAbility, Want, InsightIntentLink } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { extractQuestion } from '../model/Knowledge';

@InsightIntentLink({
  intentName: 'AskCourse', domain: 'education', intentVersion: '1.0.0',
  displayName: '课程知识问答', displayDescription: '依据本地课程资料回答问题并展示可追溯的原文来源',
  uri: 'anatomycourse://ask', keywords: ['课程问答', '知识问答', '查资料'],
  parameters: { type: 'object', properties: { question: { type: 'string', description: '用户希望查询的课程问题' } }, required: ['question'] },
  paramMappings: [{ paramName: 'question', paramMappingName: 'question' }]
})
export default class EntryAbility extends UIAbility {
  private receive(want: Want): void {
    const value = want.parameters ? want.parameters['question'] : undefined;
    const question = extractQuestion(want.uri || '', typeof value === 'string' ? value : '');
    if (question) { AppStorage.setOrCreate('askIntent', JSON.stringify({ question: question, nonce: Date.now() })); }
  }
  onCreate(want: Want): void { this.receive(want); }
  onNewWant(want: Want): void { this.receive(want); }
  onWindowStageCreate(stage: window.WindowStage): void { stage.loadContent('pages/Index'); }
}
