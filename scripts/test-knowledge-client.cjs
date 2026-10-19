const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const path=require('node:path');
const {findTypeScript,readOptions}=require('./test-knowledge-support.cjs');
const ts=findTypeScript(readOptions());
let responseCode=200,chunks=[],destroyed=0;
const native={http:{RequestMethod:{POST:'POST'},createHttp:()=>{let receive;return{on:(name,cb)=>receive=cb,destroy:()=>destroyed++,requestInStream:async()=>{for(const chunk of chunks)receive(chunk.buffer.slice(chunk.byteOffset,chunk.byteOffset+chunk.byteLength));return responseCode;}};}}};
function load(file){const exports={};const code=ts.transpileModule(fs.readFileSync(path.resolve(__dirname,'..',file),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;vm.runInThisContext(`(function(require,exports){${code}\n})`)(name=>name==='@kit.NetworkKit'?native:name==='@kit.ArkTS'?{util:{TextDecoder:{create:()=>{const d=new TextDecoder();return{decodeToString:(b,o)=>d.decode(b,o)};}}}}:{},exports);return exports;}
(async()=>{const{CloudClient}=load('entry/src/main/ets/services/CloudClient.ets');
const client=new CloudClient();const bytes=Buffer.from('data: {"delta":"课程😀"}\r\n\r\ndata: {"delta":"有来源[1]"}\n\ndata: {"done":true}\n\n');chunks=[...bytes].map(n=>Uint8Array.of(n));let text='';await client.answer('https://test.invalid','问题',[],s=>text+=s);assert.equal(text,'课程😀有来源[1]');
chunks=[Buffer.from('data: {"delta":"未完成"}\n\n')];await assert.rejects(client.answer('https://test.invalid','问题',[],()=>{}),/未完成/);
chunks=[Buffer.from('data: {"error":"服务失败"}\n\n')];await assert.rejects(client.answer('https://test.invalid','问题',[],()=>{}),/服务失败/);
chunks=[];responseCode=503;await assert.rejects(client.answer('https://test.invalid','问题',[],()=>{}),/503/);
await assert.rejects(client.answer('http://test.invalid','问题',[],()=>{}),/HTTPS/);assert(destroyed>=5);
console.log('PASS: native SSE UTF-8/CRLF; truncation/error/status; HTTPS guard and resource cleanup.');
})().catch(e=>{console.error(e);process.exitCode=1;});
