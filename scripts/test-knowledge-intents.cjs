const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {findTypeScript,readOptions}=require('./test-knowledge-support.cjs');
const ts=findTypeScript(readOptions());
const store=new Map();
global.AppStorage={setOrCreate:(k,v)=>store.set(k,v),get:k=>store.get(k)};
const load=(rel,deps)=>{const exports={};const file=path.resolve(__dirname,'..',rel);const code=ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true}}).outputText;vm.runInThisContext(`(function(require,exports){${code}\n})`,{filename:file})(deps,exports);return exports;};
global.Observed=target=>target;
const K=load('entry/src/main/ets/model/Knowledge.ets',()=>({}));
class UIAbility {context={getApplicationContext:()=>({setColorMode:()=>{}})};}
const ability=load('entry/src/main/ets/entryability/EntryAbility.ets',id=>id==='@kit.AbilityKit'?{UIAbility,ConfigurationConstant:{ColorMode:{}},InsightIntentLink:()=>target=>target}:id==='@kit.PerformanceAnalysisKit'?{hilog:{info:()=>{},error:()=>{}}}:id==='@kit.ArkUI'?{router:{RouterMode:{Single:1}}}:K).default;
function setup(){store.clear();let name='Index';const loads=[],pushes=[];let finish;
 const route={getState:()=>({name:'pages/'+name,path:'pages/',index:1}),getStateByUrl:url=>url==='pages/'+name?[{name:'pages/'+name,index:1}]:[],pushUrl:(o,mode)=>{pushes.push({url:o.url,mode});return new Promise(r=>{finish=()=>{name='KnowledgeAssistant';r();};});}};
 const stage={loadContent:(url,callback)=>{loads.push(url);name=url.split('/').at(-1);callback({code:0});},getMainWindowSync:()=>({getUIContext:()=>({getRouter:()=>route,getPromptAction:()=>({showToast:()=>{}})})})};
 return {instance:new ability(),stage,route,loads,pushes,setPage:v=>name=v,finish:()=>finish?.()};
}
(async()=>{
 let t=setup();t.instance.onCreate({},{});t.instance.onWindowStageCreate(t.stage);assert.deepEqual(t.loads,['pages/Splash']);assert.equal(t.pushes.length,0);
 t=setup();t.instance.onCreate({parameters:{question:'冷启动问题'}},{});t.instance.onWindowStageCreate(t.stage);assert.deepEqual(t.loads,['pages/KnowledgeAssistant']);assert.equal(t.pushes.length,0);assert.equal(JSON.parse(store.get('courseAskIntent')).question,'冷启动问题');
 t=setup();t.instance.onCreate({},{});t.instance.onWindowStageCreate(t.stage);t.setPage('Weather');t.instance.onNewWant({uri:'courselearning://ask?question='+encodeURIComponent('热启动问题')},{});assert.deepEqual(t.pushes,[{url:'pages/KnowledgeAssistant',mode:1}]);
 t.instance.onNewWant({parameters:{question:'更新的问题'}},{});assert.equal(t.pushes.length,1);assert.equal(JSON.parse(store.get('courseAskIntent')).question,'更新的问题');t.finish();await Promise.resolve();
 t.instance.onNewWant({parameters:{question:'已经在问答页'}},{});assert.equal(t.pushes.length,1);assert.equal(JSON.parse(store.get('courseAskIntent')).question,'已经在问答页');
 t=setup();t.instance.onCreate({},{});t.instance.onNewWant({parameters:{question:'窗口前收到'}},{});assert.equal(t.pushes.length,0);t.instance.onWindowStageCreate(t.stage);assert.deepEqual(t.loads,['pages/KnowledgeAssistant']);
 t=setup();t.instance.onCreate({},{});t.instance.onWindowStageCreate(t.stage);t.instance.onNewWant({parameters:{question:'启动页显示中'}},{});assert.equal(t.pushes.length,0);assert.equal(JSON.parse(store.get('courseAskIntent')).question,'启动页显示中');
 t=setup();t.instance.onCreate({},{});t.instance.onWindowStageCreate(t.stage);t.route.getState=()=>({name:'pages/Weather',path:'pages/',index:2});t.route.getStateByUrl=url=>url==='pages/KnowledgeAssistant'?[{name:'pages/KnowledgeAssistant',index:1}]:[];t.instance.onNewWant({parameters:{question:'从旧任务恢复问答'}},{});assert.equal(t.pushes.length,1);assert.equal(t.pushes[0].mode,1);
 t=setup();t.instance.onCreate({uri:'courselearning://ask-evil?question=x'},{});t.instance.onWindowStageCreate(t.stage);assert.deepEqual(t.loads,['pages/Splash']);
 console.log('PASS: actual EntryAbility cold/warm intents; single route during concurrent requests; latest question retained; real path-based state names; splash handoff; invalid URI ignored.');
})().catch(e=>{console.error(e);process.exitCode=1;});
