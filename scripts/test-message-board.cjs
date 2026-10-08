#!/usr/bin/env node
'use strict';
// Production ETS code; only HarmonyOS Preferences is replaced for deterministic failures.
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const index = process.argv.indexOf('--deveco-home');
const home = index >= 0 ? process.argv[index + 1] : process.env.DEVECO_HOME;
if (!home) throw new Error('Pass --deveco-home DIR or set DEVECO_HOME');
const ts = require(path.join(home, 'tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js'));
const disks = new Map(), cached = new Map();
let failFlush = 0, failPut = 0, failOpen = false, counter = 0;
const preferences = {
  getPreferencesSync(context, { name }) {
    if (failOpen) throw new Error('Cannot open');
    if (cached.has(name)) return cached.get(name);
    const values = new Map(disks.get(name) || []);
    const store = {
      hasSync(key) { return values.has(key); }, getSync(key, fallback) { return values.has(key) ? values.get(key) : fallback; },
      getAllSync() { return Object.fromEntries(values); }, deleteSync(key) { values.delete(key); },
      putSync(key, value) {
        if (failPut > 0 && --failPut === 0) throw new Error('Write failed');
        assert.ok(typeof value !== 'string' || Buffer.byteLength(value, 'utf8') <= 8192, 'Preferences value too large');
        values.set(key, value);
      },
      async flush() { if (failFlush > 0) { failFlush--; throw new Error('Flush failed'); } disks.set(name, new Map(values)); }
    }; cached.set(name, store); return store;
  },
  async removePreferencesFromCache(context, name) { cached.delete(name); }
};
const loaded = new Map();
function load(file) {
  const full = path.resolve(root, file);
  if (loaded.has(full)) return loaded.get(full).exports;
  const module = { exports: {} }; loaded.set(full, module);
  const compiled = ts.transpileModule(fs.readFileSync(full, 'utf8'), {
    fileName: full.replace(/\.ets$/, '.ts'), compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  });
  vm.runInNewContext(compiled.outputText, { module, exports: module.exports, Date, console, setTimeout, clearTimeout,
    require(name) {
      if (name === '@kit.ArkData') return { preferences };
      if (name.startsWith('.')) return load(path.resolve(path.dirname(full), name + '.ets'));
      throw new Error('Unexpected import ' + name);
    }
  }, { filename: full }); return module.exports;
}
const model = load('entry/src/main/ets/model/BoardMessage.ets');
const { MessageStore } = load('entry/src/main/ets/model/MessageStore.ets');
const bridgeModel = load('entry/src/main/ets/services/MessageBoardBridge.ets');
const tick = () => new Promise(resolve => setImmediate(resolve));
const input = (id = 'test_1', body = '中文留言\n第二行 🌱', author = '测试同学') => ({ id, author, body });
function store() { const name = 'qa_board_' + (++counter); return { name, repository: new MessageStore({}, name) }; }
function bridge(repository) {
  const events = [], toasts = [], failures = [];
  const transport = {
    async evaluate(script) {
      const result = vm.runInNewContext(script, { window: { MessageBoard: { receive(event) { events.push(event); return 1; } } } });
      return String(result);
    }, toast(message) { toasts.push(message); }, failed(message) { failures.push(message); }
  };
  const board = new bridgeModel.MessageBoardBridge(); board.configure(repository, transport); board.beginPage();
  return { board, transport, events, toasts, failures };
}
const tests = []; function test(name, run) { tests.push({ name, run }); }
test('native validation rejects missing, whitespace and oversized fields', () => {
  for (const item of [null, {}, input('', 'x'), input('x','','a'), input('x','   ','a'), input('x','x',' '),
    input('x','字'.repeat(501),'a'), input('x','x','字'.repeat(25)), input('bad/id','x','a')]) assert.ok(model.validateMessage(item));
});
test('input boundary handles invalid JSON and trims without stripping literal markup', () => {
  for (const raw of ['{','null','[]','x'.repeat(4097)]) assert.throws(() => model.parseMessageInput(raw));
  const result=model.parseMessageInput(JSON.stringify(input('x',' <b>原文</b> ',' 同学 ')));
  assert.equal(result.author,'同学'); assert.equal(result.body,'<b>原文</b>');
});
test('empty store, save, disk reload and deletion', async () => {
  const s=store(); assert.equal((await s.repository.list()).length,0);
  await s.repository.add(input()); await preferences.removePreferencesFromCache({},s.name);
  const fresh=new MessageStore({},s.name); assert.equal((await fresh.list())[0].body,input().body);
  await fresh.remove('test_1'); await preferences.removePreferencesFromCache({},s.name);
  assert.equal((await new MessageStore({},s.name).list()).length,0);
});
test('Chinese, emoji, quotes, slash and newlines survive storage exactly', async () => {
  const s=store(), text='中文🙂 "引号" \\ 路径\n</script><img src=x onerror=alert(1)>\u2028\u2029';
  await s.repository.add(input('special',text)); assert.equal((await s.repository.list())[0].body,text.trim());
});
test('same request retry is idempotent, changed payload with same ID is rejected', async () => {
  const s=store(); await s.repository.add(input()); await s.repository.add(input());
  assert.equal((await s.repository.list()).length,1);
  await assert.rejects(s.repository.add(input('test_1','different'))); assert.equal((await s.repository.list())[0].body,input().body);
});
test('concurrent store instances serialize writes without losing messages', async () => {
  const s=store(), second=new MessageStore({},s.name);
  await Promise.all(Array.from({length:12},(_,i)=>(i%2?s.repository:second).add(input('race_'+i))));
  const messages=await s.repository.list(); assert.equal(messages.length,12); assert.equal(new Set(messages.map(m=>m.id)).size,12);
});
test('caller mutations cannot change a queued write or loaded record', async () => {
  const s=store(), draft=input(); const pending=s.repository.add(draft); draft.body='mutated'; await pending;
  const messages=await s.repository.list(); assert.equal(messages[0].body,input().body);
  messages[0].body='mutated read'; assert.equal((await s.repository.list())[0].body,input().body);
});
test('maximum-size records and 100 IDs stay under native Preferences value limit', async () => {
  const s=store();
  for(let i=0;i<100;i++) await s.repository.add(input(String(i).padStart(64,'x'),'字'.repeat(500),'名'.repeat(24)));
  assert.equal((await s.repository.list()).length,100);
  await assert.rejects(s.repository.add(input('overflow')));
  await s.repository.add(input('0'.padStart(64,'x'),'字'.repeat(500),'名'.repeat(24)));
  await s.repository.remove('0'.padStart(64,'x')); await s.repository.add(input('after_delete'));
  assert.equal((await s.repository.list()).length,100);
});
test('unknown deletion is idempotent and invalid deletion ID is rejected', async () => {
  const s=store(); await s.repository.add(input()); await s.repository.remove('absent');
  await assert.rejects(s.repository.remove('../index')); assert.equal((await s.repository.list()).length,1);
});
test('flush failure rolls back both index and new record, then retry works', async () => {
  const s=store(); await s.repository.add(input('old')); failFlush=1;
  await assert.rejects(s.repository.add(input('new'))); assert.equal((await s.repository.list()).length,1);
  cached.delete(s.name); assert.equal((await s.repository.list())[0].id,'old');
  await s.repository.add(input('new')); assert.equal((await s.repository.list()).length,2);
});
test('mid-write failure rolls back without orphaning a record', async () => {
  const s=store(); await s.repository.add(input('old')); failPut=2;
  await assert.rejects(s.repository.add(input('new'))); const values=preferences.getPreferencesSync({},s);
  assert.equal(values.hasSync('message_new'),false); assert.equal((await s.repository.list()).length,1);
});
test('failed delete restores the original message on disk', async () => {
  const s=store(); await s.repository.add(input()); failFlush=1; await assert.rejects(s.repository.remove('test_1'));
  cached.delete(s.name); assert.equal((await s.repository.list()).length,1);
});
test('failed rollback evicts memory and surfaces uncertain disk state', async () => {
  const s=store(); await s.repository.add(input('old')); failFlush=2;
  await assert.rejects(s.repository.add(input('new')),/无法确认磁盘状态/); assert.equal(cached.has(s.name),false);
  assert.equal((await s.repository.list())[0].id,'old');
});
test('corrupt history is preserved and cannot be overwritten by a new submission', async () => {
  const s=store(), pref=preferences.getPreferencesSync({},s); pref.putSync('index','{'); await pref.flush();
  await assert.rejects(s.repository.list()); await assert.rejects(s.repository.add(input()));
  assert.equal(pref.getSync('index',''),'{');
});
test('missing index, missing record and duplicate IDs fail safely', async () => {
  for(const kind of ['orphan','missing','duplicate']) {
    const s=store(), pref=preferences.getPreferencesSync({},s);
    if(kind==='orphan') pref.putSync('message_a','{}');
    else pref.putSync('index',JSON.stringify({version:1,ids:kind==='duplicate'?['a','a']:['a']}));
    await pref.flush(); await assert.rejects(s.repository.list());
  }
});
test('opening storage failure does not poison the next request', async () => {
  const s=store(); failOpen=true; await assert.rejects(s.repository.list()); failOpen=false;
  await s.repository.add(input()); assert.equal((await s.repository.list()).length,1);
});
test('bridge is closed before connect and after dispose', async () => {
  const b=bridge(store().repository); assert.equal(JSON.parse(b.board.submitMessage(JSON.stringify(input()))).ok,false);
  await b.board.connect(); b.board.dispose(); assert.equal(JSON.parse(b.board.requestHistory()).ok,false);
});
test('native connect proactively pushes persisted history into a webpage function', async () => {
  const s=store(); await s.repository.add(input()); const b=bridge(s.repository); await b.board.connect();
  assert.equal(b.events[0].kind,'snapshot'); assert.equal(b.events[0].messages[0].body,input().body);
});
test('proxy submission persists first, then sends a saved acknowledgement and native toast', async () => {
  const s=store(), b=bridge(s.repository); await b.board.connect();
  assert.equal(JSON.parse(b.board.submitMessage(JSON.stringify(input()))).ok,true); await tick();
  assert.equal((await s.repository.list()).length,1); assert.equal(b.events.at(-1).kind,'saved');
  assert.equal(b.toasts[0],'留言已保存到本机');
});
test('double tap while pending produces only one save event', async () => {
  const s=store(), b=bridge(s.repository); await b.board.connect();
  b.board.submitMessage(JSON.stringify(input())); b.board.submitMessage(JSON.stringify(input())); await tick();
  assert.equal(b.events.filter(e=>e.kind==='saved').length,1); assert.equal((await s.repository.list()).length,1);
});
test('native validation returns an immediate error and writes nothing', async () => {
  const s=store(), b=bridge(s.repository); await b.board.connect();
  assert.equal(JSON.parse(b.board.submitMessage('{')).ok,false); assert.equal((await s.repository.list()).length,0);
});
test('storage error produces a request-correlated failure with no success toast', async () => {
  const s=store(), b=bridge(s.repository); await b.board.connect(); failFlush=1;
  b.board.submitMessage(JSON.stringify(input())); await tick();
  assert.equal(b.events.at(-1).kind,'error'); assert.equal(b.events.at(-1).requestId,'test_1'); assert.equal(b.toasts.length,0);
});
test('initial history failure reaches webpage and can be retried', async () => {
  const s=store(), b=bridge(s.repository); failOpen=true; await b.board.connect();
  assert.equal(b.events[0].kind,'error'); failOpen=false; b.board.requestHistory(); await tick();
  assert.equal(b.events.at(-1).kind,'snapshot');
});
test('native notification and webpage toast use distinct directions', async () => {
  const b=bridge(store().repository); await b.board.connect(); await b.board.notify();
  assert.equal(b.events.at(-1).kind,'notice'); assert.ok(b.events.at(-1).message.includes('来自应用'));
  assert.equal(JSON.parse(b.board.showToast('网页发起的提示')).ok,true); assert.equal(b.toasts[0],'网页发起的提示');
  assert.equal(JSON.parse(b.board.showToast('x'.repeat(81))).ok,false);
});
test('delete proxy returns the remaining history', async () => {
  const s=store(); await s.repository.add(input()); const b=bridge(s.repository); await b.board.connect();
  b.board.deleteMessage('test_1'); await tick(); assert.equal(b.events.at(-1).kind,'deleted'); assert.equal(b.events.at(-1).messages.length,0);
});
test('JavaScript payload serialization cannot escape into executable code', () => {
  const event=new bridgeModel.BoardEvent(); event.message='" );globalThis.hacked=true;//\u2028\u2029</script>';
  let received; const context={window:{MessageBoard:{receive(e){received=e;return 1;}}}};
  assert.equal(vm.runInNewContext(bridgeModel.boardEventScript(event),context),1);
  assert.equal(context.hacked,undefined); assert.equal(received.message,event.message);
});
test('old document callbacks never reach a new page or a disposed controller', async () => {
  let resolve; const waiting=new Promise(r=>{resolve=r;}); const s=store();
  const repository={list:()=>s.repository.list(),add:()=>waiting,remove:()=>s.repository.remove('test_1')};
  const b=bridge(repository); await b.board.connect(); b.board.submitMessage(JSON.stringify(input()));
  b.board.beginPage(); await b.board.connect(); const count=b.events.length;
  resolve([]); await tick(); assert.equal(b.events.length,count); assert.equal(b.toasts.length,0);
  b.board.dispose(); await b.board.notify(); assert.equal(b.events.length,count);
});
test('missing webpage receiver fails handshake, transport failure closes bridge', async () => {
  const b=bridge(store().repository); b.transport.evaluate=async()=> 'false'; await assert.rejects(b.board.connect());
  b.transport.evaluate=async()=>{throw new Error('Renderer gone');}; b.board.requestHistory(); await tick();
  assert.equal(b.failures.length,1); assert.equal(JSON.parse(b.board.submitMessage(JSON.stringify(input()))).ok,false);
});
test('only exact trusted local URL is allowed to navigate', () => {
  assert.equal(bridgeModel.isBoardUrl('resource://rawfile/message-board.html'),true);
  for(const url of ['https://example.com','javascript:alert(1)','resource://rawfile/other.html',
    'resource://rawfile/message-board.html#remote','file:///data/secret']) assert.equal(bridgeModel.isBoardUrl(url),false);
});
(async()=>{
  let passed=0;
  for(const t of tests){let timer;try{
    await Promise.race([Promise.resolve().then(t.run),new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Timeout')),8000);})]);
    passed++; console.log('PASS '+t.name);
  }catch(error){console.error('FAIL '+t.name,error);process.exitCode=1;}finally{clearTimeout(timer);failFlush=0;failPut=0;failOpen=false;}}
  console.log(`Message board: ${passed}/${tests.length} passed`);
})();
