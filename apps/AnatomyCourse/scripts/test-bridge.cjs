const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const ts = require('../web/node_modules/typescript');
const exportsBridge = {};
const code = ts.transpileModule(fs.readFileSync(path.join(__dirname, '../entry/src/main/ets/services/AtlasBridge.ets'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }
}).outputText;
global.WebResourceResponse = class {
  setResponseEncoding(value) { this.encoding = value; }
  setResponseData(value) { this.data = value; }
  setResponseCode(value) { this.status = value; }
  setReasonMessage(value) { this.reason = value; }
  setResponseMimeType(value) { this.mime = value; }
  setResponseHeader(value) { this.headers = value; }
};
vm.runInThisContext(`(function(require,exports){${code}\n})`)(() => ({}), exportsBridge);
const { parseConcepts, localResponse, AtlasProxy } = exportsBridge;
const concepts = [{ id: 'FMA1', name: 'heart', elements: ['mesh'] }];
assert.deepEqual(parseConcepts(JSON.stringify(concepts)), concepts);
assert.deepEqual(parseConcepts(JSON.stringify(JSON.stringify(concepts))), concepts);
assert.throws(() => parseConcepts('{}'));
const loaded = [];
const context = { resourceManager: { getRawFileContentSync: key => { loaded.push(key); return Uint8Array.of(1,2,3); } } };
const response = localResponse(context, 'https://atlas.local/assets/app.js');
assert.equal(response.status, 200); assert.equal(response.mime, 'text/javascript');
assert.deepEqual(loaded, ['atlas/assets/app.js']);
for (const url of ['https://evil.invalid/app.js', 'https://atlas.local/../x', 'https://atlas.local/%2e%2e/x', 'https://atlas.local/%5cx', 'https://atlas.local/%00x']) {
  assert.equal(localResponse(context, url).status, 404);
}
assert.equal(loaded.length, 1);
const proxy = new AtlasProxy(), events = []; proxy.callback = event => events.push(event);
proxy.onEvent('{broken'); proxy.onEvent('x'.repeat(20001)); proxy.onEvent('{"type":"ready"}');
assert.deepEqual(events, [{ type: 'ready' }]);
console.log('PASS: ArkWeb double JSON; local rawfile origin/MIME; external/traversal rejection; bridge malformed and oversized message guard.');
