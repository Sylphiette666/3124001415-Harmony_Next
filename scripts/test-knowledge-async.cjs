// Tests actual page control methods with deferred I/O; ArkUI builders are excluded.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {findTypeScript,readOptions}=require('./test-knowledge-support.cjs');
const ts=findTypeScript(readOptions());
const root=path.resolve(__dirname,'..');
function compile(source,name,deps){const exports={};const code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true}}).outputText;vm.runInThisContext(`(function(require,exports){${code}\n})`,{filename:name})(deps,exports);return exports;}
global.Observed=target=>target;global.TextInputController=class{stopEditing(){}};global.Scroller=class{calls=0;scrollEdge(){this.calls++;}};global.Edge={Bottom:'bottom'};global.AppStorage={set:()=>{}};
const K=compile(fs.readFileSync(path.join(root,'entry/src/main/ets/model/Knowledge.ets'),'utf8'),'Knowledge',()=>({}));
let store={version:1},networkAvailable=true;
const source=fs.readFileSync(path.join(root,'entry/src/main/ets/pages/KnowledgeAssistant.ets'),'utf8').split('  @Builder')[0].replace(/@Entry\s*\n@Component\s*\n/,'').replace('struct KnowledgeAssistant {','export class KnowledgeAssistant {').replace(/@StorageLink\([^\n]+?\) @Watch\([^\n]+?\) /g,'').replace(/@State /g,'')+'\n}';
const {KnowledgeAssistant}=compile(source,'KnowledgeAssistant.methods',id=>id.endsWith('/Knowledge')?K:id.endsWith('/CourseStore')?{courseStore:new Proxy({},{get:(_,key)=>store[key]})}:id.endsWith('/CloudClient')?{CloudClient:class{cancel(){}}}:id==='@kit.ArkUI'?{FrameCallback:class{}}:id==='@kit.NetworkKit'?{connection:{hasDefaultNetSync:()=>networkAvailable}}:{});
const frames=[];KnowledgeAssistant.prototype.getUIContext=()=>({postFrameCallback:frame=>frames.push(frame)});
const layout=async()=>{await new Promise(r=>setTimeout(r,5));while(frames.length)frames.shift().onIdle();};
function deferred(){let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b;});return {promise,resolve,reject};}
const flush=async()=>{for(let n=0;n<10;n++)await Promise.resolve();};
function page(){const p=new KnowledgeAssistant();p.ready=true;p.visible=true;p.cloudMode=true;p.endpoint='https://example.invalid';return p;}
(async()=>{
 // Cancellation while awaiting the initial DB read must not start a cloud request.
 let d=deferred(),calls=0;store={version:1,segments:()=>d.promise};let p=page();p.client={cancel(){},embeddings:async()=>{calls++;return{model:'m',vectors:[[1]]};}};
 let work=p.ask('ArkAF');p.stop();d.resolve([]);await work;assert.equal(calls,0);assert.equal(p.messages[0].state,'已停止');
 // Cancellation while vectors are being persisted must not start the next batch.
 const segments=Array.from({length:20},(_,i)=>({id:String(i),documentId:'d',revision:1,title:'ArkAF',text:'意图说明',vector:[],model:'',start:0,end:4,source:'local'}));
 d=deferred();calls=0;store={version:1,segments:async()=>segments,vectors:()=>d.promise};p=page();p.client={cancel(){},embeddings:async(_,texts)=>{calls++;return{model:'m',vectors:texts.map(()=>[1])};}};
 work=p.ask('ArkAF');await flush();assert.equal(calls,2);p.stop();d.resolve();await work;assert.equal(calls,2);
 // A Want arriving during a document transaction is kept until UI/index refresh completes.
 for(const operation of ['save','remove']){
   d=deferred();let requests=[];store={version:1,save:()=>d.promise,remove:()=>d.promise,documents:async()=>[{id:'new',revision:2}]};p=page();p.editTitle='Title';p.editBody='Long enough local document content';p.ask=async q=>{requests.push(q||p.question);p.messages.push({question:q||p.question});};
   work=operation==='save'?p.saveDocument():p.removeDocument('id');assert(p.processing);p.intent=JSON.stringify({question:'最新资料问题',nonce:'1'});p.consumeIntent();assert.equal(requests.length,0);assert.equal(p.seenIntent,'');
   d.resolve();await work;assert.equal(p.processing,false);assert.deepEqual(requests,['最新资料问题']);assert.equal(p.messages.length,1);assert.equal(p.documents[0].revision,2);
 }
 // A failed save retains editable input and permits a second save attempt.
 store={version:1,save:async()=>{throw new Error('模拟保存失败');}};p=page();p.editTitle='Unsaved title';p.editBody='Unsaved document body';await p.saveDocument();assert.equal(p.processing,false);assert.equal(p.editTitle,'Unsaved title');assert.equal(p.editBody,'Unsaved document body');assert.match(p.notice,/保存失败/);
 // Offline mode reports a retriable Chinese error without starting any request.
 let embeddingCalls=0,answerCalls=0,providerFails=false;
 const known={id:'s',documentId:'d',revision:1,title:'ArkAF 意图',text:'ArkAF 支持 question 参数自动提问。',vector:[1],model:'https://example.invalid|m',start:0,end:29,source:'课程资料'};
 store={version:1,segments:async()=>[known],vectors:async()=>{}};
 const client={cancel(){},embeddings:async()=>{embeddingCalls++;return{model:'m',vectors:[[1]]};},answer:async(_,question,evidence,onDelta)=>{answerCalls++;if(providerFails)throw new Error('生成服务暂时不可用，请稍后重试');onDelta('根据课程资料');onDelta('，ArkAF 可携带问题。[1]');}};
 p=page();p.client=client;networkAvailable=false;await p.ask('ArkAF 怎样携带问题？');
 assert.equal(embeddingCalls,0);assert.equal(answerCalls,0);assert.equal(p.messages[0].state,'请求失败');assert.match(p.messages[0].error,/无网络.*重试/);assert.equal(p.busy,false);
 networkAvailable=true;await p.ask(p.messages[0].question);
 assert.equal(p.messages[0].state,'请求失败');assert.equal(p.messages.length,2);assert.equal(p.messages[1].state,'已完成');assert.match(p.messages[1].answer,/ArkAF.*\[1\]/);assert.equal(p.messages[1].evidence.length,1);assert.equal(p.busy,false);
 // A generation request rejection is preserved; retry uses a new message and can complete.
 p=page();p.client=client;providerFails=true;await p.ask('ArkAF 怎样携带问题？');
 assert.equal(p.messages[0].state,'请求失败');assert.match(p.messages[0].error,/暂时不可用.*重试/);assert.equal(p.busy,false);
 providerFails=false;await p.ask(p.messages[0].question);
 assert.equal(p.messages.length,2);assert.equal(p.messages[0].state,'请求失败');assert.equal(p.messages[1].state,'已完成');assert.equal(p.messages[1].error,'');assert.equal(p.messages[1].answer,'根据课程资料，ArkAF 可携带问题。[1]');assert.equal(p.busy,false);
 // Only the new message and completion request a post-layout reveal, never each streamed delta.
 let finish=deferred(),emit;store={version:1,segments:async()=>[known],vectors:async()=>{}};
 p=page();p.client={cancel(){},embeddings:async()=>({model:'m',vectors:[[1]]}),answer:async(_,q,e,onDelta)=>{emit=onDelta;await finish.promise;}};
 work=p.ask('ArkAF');await flush();await layout();assert.equal(p.chatScroll.calls,1);
 emit('第一段');emit('第二段');await layout();assert.equal(p.chatScroll.calls,1);
 finish.resolve();await work;await layout();assert.equal(p.chatScroll.calls,2);
 // Leaving clears the pending timer and invalidates an already queued frame callback.
 p=page();p.revealLatest();p.onPageHide();await layout();assert.equal(p.chatScroll.calls,0);assert.equal(p.scrollTimer,-1);
 p=page();p.revealLatest();await new Promise(r=>setTimeout(r,5));p.onPageHide();while(frames.length)frames.shift().onIdle();assert.equal(p.chatScroll.calls,0);
 console.log('PASS: actual page async controls; cancel before cloud/between batches; intent waits for save/delete refresh; failed save retains text; offline and provider failures show Chinese retry errors; both retries complete with streamed content and evidence; post-layout scroll only at start/end; leaving clears pending reveals.');
})().catch(e=>{console.error(e);process.exitCode=1;});
