#!/usr/bin/env node
'use strict';

// Runs the real ArkTS speech service against controlled native-engine callbacks.
// No audio device, network, package installation, or emitted build files are used.
// Usage: node scripts/test-calculator-speech.cjs --deveco-home "D:\HUAWEI\DevEco Studio"
// Alternatively set DEVECO_HOME or pass --typescript /path/to/typescript.js.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function option(name) {
  const index = process.argv.indexOf(name);
  return index < 0 ? undefined : process.argv[index + 1];
}

function findTypeScript() {
  const explicit = option('--typescript');
  const home = option('--deveco-home') || option('-DevEcoHome') || process.env.DEVECO_HOME;
  const roots = home ? [home] : [
    'D:\\HUAWEI\\DevEco Studio',
    path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Huawei', 'DevEco Studio')
  ];
  const candidates = explicit ? [explicit] : roots.flatMap((root) => [
    path.join(root, 'tools', 'hvigor', 'hvigor', 'node_modules', 'typescript', 'lib', 'typescript.js'),
    path.join(root, 'plugins', 'codelinter', 'node_modules', 'typescript', 'lib', 'typescript.js'),
    path.join(root, 'sdk', 'default', 'openharmony', 'ets', 'build-tools', 'ets-loader', 'node_modules', 'typescript', 'lib', 'typescript.js')
  ]);
  const match = candidates.find((candidate) => fs.existsSync(candidate));
  if (!match) throw new Error('TypeScript not found. Pass --deveco-home or --typescript, or set DEVECO_HOME.');
  return require(match);
}

const ts = findTypeScript();
const sourcePath = path.join(__dirname, '..', 'entry', 'src', 'main', 'ets', 'services', 'CalculatorSpeech.ets');
const transpiled = ts.transpileModule(fs.readFileSync(sourcePath, 'utf8'), {
  fileName: 'CalculatorSpeech.ts',
  compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS },
  reportDiagnostics: true
});
const errors = (transpiled.diagnostics || []).filter((item) => item.category === ts.DiagnosticCategory.Error);
assert.equal(errors.length, 0, errors.map((item) => ts.flattenDiagnosticMessageText(item.messageText, '\n')).join('\n'));

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

class FakeEngine {
  constructor() {
    this.calls = [];
    this.listener = undefined;
    this.activeRequest = '';
    this.failNextSpeak = false;
  }
  setListener(listener) {
    this.listener = listener;
    this.calls.push({ kind: 'setListener' });
  }
  speak(text, params) {
    this.calls.push({ kind: 'speak', text, params });
    if (this.failNextSpeak) {
      this.failNextSpeak = false;
      throw Object.assign(new Error('simulated native speak failure'), { code: 401 });
    }
    this.activeRequest = params.requestId;
  }
  stop() {
    this.calls.push({ kind: 'stop' });
    const requestId = this.activeRequest;
    this.activeRequest = '';
    if (this.listener && requestId) {
      // Official API ordering: a manual stop can emit completion before onStop.
      this.listener.onComplete(requestId, { type: 1, message: 'stopped' });
      this.listener.onStop(requestId, { type: 0, message: 'stopped' });
    }
  }
  shutdown() { this.calls.push({ kind: 'shutdown' }); }
  start(requestId = this.activeRequest) { this.listener.onStart(requestId, {}); }
  complete(type, requestId = this.activeRequest) {
    if (type === 1 && requestId === this.activeRequest) this.activeRequest = '';
    this.listener.onComplete(requestId, { type, message: 'complete' });
  }
  error(code = 1002300005, requestId = this.activeRequest) {
    this.listener.onError(requestId, code, 'simulated native error');
  }
  spoken() { return this.calls.filter((call) => call.kind === 'speak'); }
  count(kind) { return this.calls.filter((call) => call.kind === kind).length; }
}

function harness(factory) {
  const states = [];
  const creates = [];
  const logs = [];
  const fakeModules = {
    '@kit.CoreSpeechKit': {
      textToSpeech: {
        createEngine: (params) => {
          creates.push(params);
          return factory(creates.length);
        }
      }
    },
    '@kit.PerformanceAnalysisKit': {
      hilog: Object.fromEntries(['info', 'warn', 'error'].map((level) => [
        level, (...args) => logs.push({ level, args })
      ]))
    },
    '@kit.BasicServicesKit': {}
  };
  const module = { exports: {} };
  const context = vm.createContext({
    module,
    exports: module.exports,
    require: (name) => {
      assert.ok(Object.hasOwn(fakeModules, name), `Unexpected module: ${name}`);
      return fakeModules[name];
    }
  });
  new vm.Script(transpiled.outputText, { filename: sourcePath }).runInContext(context);
  const service = new module.exports.CalculatorSpeech((status) => states.push({ ...status }));
  return { service, states, creates, logs, latest: () => states[states.length - 1] };
}

const cases = [];
function test(name, run) { cases.push({ name, run }); }

test('FIFO waits for playback completion, ignores synthesis and duplicate completion', async () => {
  const engine = new FakeEngine();
  const h = harness(() => Promise.resolve(engine));
  await h.service.initialize();
  assert.equal(h.creates[0].online, 1, 'Speech must stay local');
  assert.equal(h.creates[0].language, 'zh-CN');
  ['一', '加', '二', '等于，三'].forEach((phrase) => h.service.speak(phrase));
  assert.deepEqual(engine.spoken().map((call) => call.text), ['一']);
  const first = engine.spoken()[0].params.requestId;
  engine.start();
  assert.equal(h.latest().speaking, true);
  engine.complete(0);
  assert.equal(engine.spoken().length, 1, 'Synthesis completion must not start another utterance');
  engine.complete(1);
  engine.complete(1, first);
  assert.equal(engine.spoken().length, 2, 'An old completion must not advance the queue again');
  for (let i = 0; i < 3; i++) engine.complete(1);
  assert.deepEqual(engine.spoken().map((call) => call.text), ['一', '加', '二', '等于，三']);
  assert.equal(new Set(engine.spoken().map((call) => call.params.requestId)).size, 4);
  engine.spoken().forEach((call) => assert.equal(call.params.extraParams.queueMode, 0));
  assert.equal(h.latest().speaking, false);
  h.service.dispose();
});

test('stop and mute clear pending feedback even when stop emits onComplete synchronously', async () => {
  const engine = new FakeEngine();
  const h = harness(() => Promise.resolve(engine));
  await h.service.initialize();
  h.service.speak('一');
  h.service.speak('二');
  h.service.stop();
  assert.equal(engine.spoken().length, 1);
  h.service.speak('三');
  h.service.speak('四');
  h.service.setEnabled(false);
  await h.service.initialize();
  h.service.speak('五');
  assert.deepEqual(engine.spoken().map((call) => call.text), ['一', '三']);
  assert.match(h.latest().message, /关闭/);
  h.service.setEnabled(true);
  h.service.speak('六');
  assert.deepEqual(engine.spoken().map((call) => call.text), ['一', '三', '六']);
  h.service.dispose();
});

test('disposing during initialization shuts down the late engine without publishing to the page', async () => {
  const pending = deferred();
  const engine = new FakeEngine();
  const h = harness(() => pending.promise);
  const initializing = h.service.initialize();
  h.service.speak('一');
  h.service.dispose();
  const published = h.states.length;
  pending.resolve(engine);
  await initializing;
  assert.equal(engine.count('shutdown'), 1);
  assert.equal(engine.spoken().length, 0);
  assert.equal(h.states.length, published);
  await h.service.initialize();
  h.service.setEnabled(true);
  h.service.speak('二');
  h.service.dispose();
  assert.equal(h.creates.length, 1);
  assert.equal(h.states.length, published);
});

test('native playback error releases the failed engine and retry accepts only fresh input', async () => {
  const oldEngine = new FakeEngine();
  const newEngine = new FakeEngine();
  const h = harness((attempt) => Promise.resolve(attempt === 1 ? oldEngine : newEngine));
  await h.service.initialize();
  h.service.speak('一');
  h.service.speak('二');
  const oldRequest = oldEngine.activeRequest;
  oldEngine.error();
  assert.equal(oldEngine.count('shutdown'), 1);
  assert.equal(oldEngine.spoken().length, 1);
  assert.equal(h.latest().ready, false);
  assert.match(h.latest().message, /重试/);
  await h.service.initialize();
  h.service.speak('三');
  oldEngine.complete(1, oldRequest);
  oldEngine.error(1002300005, oldRequest);
  assert.deepEqual(newEngine.spoken().map((call) => call.text), ['三']);
  assert.equal(newEngine.count('shutdown'), 0);
  assert.equal(h.latest().ready, true);
  h.service.dispose();
});

test('failed initialization discards old keys and logs the native error code', async () => {
  const pending = deferred();
  const engine = new FakeEngine();
  const h = harness((attempt) => attempt === 1 ? pending.promise : Promise.resolve(engine));
  const initializing = h.service.initialize();
  h.service.speak('一');
  h.service.speak('二');
  pending.reject(Object.assign(new Error('missing local voice'), { code: 1002300005 }));
  await initializing;
  assert.equal(h.latest().ready, false);
  assert.ok(h.logs.some((entry) => entry.args.includes(1002300005)));
  await h.service.initialize();
  assert.equal(engine.spoken().length, 0);
  h.service.speak('三');
  assert.deepEqual(engine.spoken().map((call) => call.text), ['三']);
  h.service.dispose();
});

test('more than 32 rapid keys are merged and spoken in order without dropping input', async () => {
  const engine = new FakeEngine();
  const h = harness(() => Promise.resolve(engine));
  await h.service.initialize();
  const input = Array.from({ length: 80 }, (_, index) => `按键${index}`);
  input.forEach((phrase) => h.service.speak(phrase));
  let completed = 0;
  while (completed < engine.spoken().length) {
    assert.ok(completed < 100, 'Queue did not terminate');
    const requestId = engine.spoken()[completed++].params.requestId;
    engine.complete(1, requestId);
  }
  const spoken = engine.spoken().map((call) => call.text);
  assert.ok(spoken.some((phrase) => phrase.includes('，')), 'Rapid feedback should be grouped');
  assert.deepEqual(spoken.flatMap((phrase) => phrase.split('，')), input);
  h.service.dispose();
});

test('mute during initialization releases late resources and does not publish a ready state', async () => {
  const pending = deferred();
  const oldEngine = new FakeEngine();
  const newEngine = new FakeEngine();
  const h = harness((attempt) => attempt === 1 ? pending.promise : Promise.resolve(newEngine));
  const initializing = h.service.initialize();
  h.service.speak('一');
  h.service.setEnabled(false);
  const mutedPublications = h.states.length;
  pending.resolve(oldEngine);
  await initializing;
  assert.equal(oldEngine.count('shutdown'), 1);
  assert.equal(oldEngine.spoken().length, 0);
  assert.equal(h.states.length, mutedPublications);
  h.service.setEnabled(true);
  await h.service.initialize();
  h.service.speak('二');
  assert.deepEqual(newEngine.spoken().map((call) => call.text), ['二']);
  h.service.dispose();
});

test('a synchronous native speak exception is recoverable and does not replay a backlog', async () => {
  const engine = new FakeEngine();
  engine.failNextSpeak = true;
  const replacement = new FakeEngine();
  const h = harness((attempt) => Promise.resolve(attempt === 1 ? engine : replacement));
  await h.service.initialize();
  h.service.speak('一');
  assert.equal(h.latest().ready, false);
  assert.equal(engine.count('shutdown'), 1);
  await h.service.initialize();
  h.service.speak('二');
  assert.deepEqual(replacement.spoken().map((call) => call.text), ['二']);
  h.service.dispose();
});

(async () => {
  let passed = 0;
  for (const item of cases) {
    try {
      await item.run();
      console.log(`PASS ${item.name}`);
      passed++;
    } catch (error) {
      console.error(`FAIL ${item.name}`);
      console.error(error);
      process.exitCode = 1;
    }
  }
  console.log(`Speech service tests: ${passed}/${cases.length} passed`);
})();
