const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), crypto = require('node:crypto');
const { findTypeScript, readOptions } = require('./test-support.cjs');
const ts = findTypeScript(readOptions()), root = path.resolve(__dirname, '../entry/src/main/ets');
const overrides = {}, cache = {};
let requestHandler, destroyed = 0;
const network = { http: {
  RequestMethod: { GET: 'GET', POST: 'POST' }, HttpDataType: { STRING: 0, ARRAY_BUFFER: 1 },
  createHttp: () => ({ request: (url, options) => requestHandler(url, options), destroy: () => destroyed++ })
}, connection: {} };
function load(relative) {
  if (overrides[relative]) return overrides[relative];
  if (cache[relative]) return cache[relative];
  const file = path.join(root, relative + '.ets'), exports = {}; cache[relative] = exports;
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const requireLocal = id => {
    if (id === '@kit.NetworkKit') return network;
    if (id === '@kit.CoreFileKit') return { fileIo: fakeFs };
    if (id === '@kit.CryptoArchitectureKit') return { cryptoFramework: { createMd: () => {
      const hash = crypto.createHash('sha256'); return { update: async blob => hash.update(blob.data), digest: async () => ({ data: hash.digest() }) };
    } } };
    if (id.startsWith('.')) return load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), id)));
    return {};
  };
  vm.runInThisContext(`(function(require,exports){${code}\n})`, { filename: file })(requireLocal, exports); return exports;
}
const settings = { endpoint: 'https://api.example.test', deviceId: 'device-for-test', deviceKey: 'a-test-device-key-with-entropy', autoSync: true, modelPath: '/old.onnx', modelVersion: '1.0.0' };
function response(code, body) { return { responseCode: code, result: typeof body === 'string' ? body : JSON.stringify(body) }; }
const files = new Map();
const fakeFs = { accessSync: p => files.has(p), unlinkSync: p => files.delete(p), renameSync: (a, b) => { assert.ok(files.has(a)); files.set(b, files.get(a)); files.delete(a); } };
(async () => {
  const { ApiClient, validateEndpoint } = load('services/ApiClient');
  assert.equal(validateEndpoint('http://127.0.0.1:8765/'), 'http://127.0.0.1:8765');
  for (const address of ['http://example.com', 'https://example.com/path', 'https://user:secret@example.com', 'https://example.com@evil.test']) assert.throws(() => validateEndpoint(address));
  const api = new ApiClient(); api.configure(settings);
  let authCount = 0, firstUnauthorized = true;
  requestHandler = async (url, options) => {
    if (url.endsWith('/token')) { authCount++; return response(200, { accessToken: 'token-' + authCount, expiresIn: 300 }); }
    assert.match(options.header.Authorization, /^Bearer token-/);
    if (firstUnauthorized) { firstUnauthorized = false; return response(401, { error: { code: 'AUTH_REQUIRED', message: 'expired' } }); }
    return response(200, { records: [], total: 0 });
  };
  assert.equal((await api.request('/v1/records')).total, 0); assert.equal(authCount, 2);
  const concurrent = new ApiClient(); concurrent.configure(settings); authCount = 0;
  requestHandler = async url => {
    if (url.endsWith('/token')) { authCount++; await new Promise(r => setTimeout(r, 10)); return response(200, { accessToken: 'shared-token', expiresIn: 300 }); }
    return response(200, { records: [] });
  };
  await Promise.all([concurrent.request('/v1/records'), concurrent.request('/v1/statistics')]); assert.equal(authCount, 1);
  requestHandler = async () => { throw new Error('transport failure'); };
  await assert.rejects(concurrent.request('/v1/records'), /无法连接服务/);
  assert.ok(destroyed >= 8);
  let resolveOld;
  requestHandler = () => new Promise(resolve => { resolveOld = resolve; });
  const obsolete = concurrent.request('/v1/records'); await new Promise(r => setTimeout(r, 0));
  concurrent.configure({ ...settings, endpoint: 'https://new.example.test' }); resolveOld(response(200, {}));
  await assert.rejects(obsolete, /配置已更改/);

  let records = [{ recordId: 'record-1', revision: 1, capturedAt: 1000, updatedAt: 1000, width: 800, height: 600,
    modelVersion: '1.0.0', threshold: .35, items: [], thumbnailPath: '/thumb', syncState: 'pending', attempts: 0 }];
  let sent = 0, fail = true, beforeReturn;
  const store = {
    settings: async () => settings,
    pending: async () => records.filter(r => r.syncState === 'pending').map(r => structuredClone(r)),
    acknowledge: async (id, revision) => { const r = records.find(r => r.recordId === id && r.revision === revision); if (r) r.syncState = 'uploaded'; },
    failed: async (id, revision) => { const r = records.find(r => r.recordId === id && r.revision === revision); if (r) r.attempts++; },
    saveSettings: async next => { store.saved = next; }
  };
  const fakeApi = {
    configured: true,
    request: async (url, method, body) => {
      sent++; if (fail) throw new Error('network offline');
      if (beforeReturn) { beforeReturn(); beforeReturn = undefined; }
      return { accepted: JSON.parse(body).records.map(r => ({ recordId: r.recordId, revision: r.revision, status: 'duplicate' })) };
    },
    download: async () => modelBytes.buffer
  };
  overrides['model/ScanStore'] = { scanStore: store }; overrides['services/ApiClient'] = { apiClient: fakeApi };
  overrides['services/MediaFiles'] = { thumbnailBase64: () => 'sample-jpeg', writeFile: (p, bytes) => files.set(p, bytes), ensureFolders: () => {} };
  const { SyncService } = load('services/SyncService'); const sync = new SyncService();
  const syncMessages = []; sync.start(message => syncMessages.push(message));
  await assert.rejects(sync.sync(), /network offline/); assert.equal(records[0].attempts, 1); assert.equal(records[0].syncState, 'pending');
  assert.equal(syncMessages.at(-1), '', 'failure must not be announced as recovery');
  fail = false; await sync.sync(); assert.equal(records[0].syncState, 'uploaded'); assert.equal(sent, 2);
  assert.match(syncMessages.at(-1), /已同步 1 条/, 'successful recovery must refresh status');
  records[0].syncState = 'pending'; beforeReturn = () => { records[0].revision = 2; };
  await sync.sync(); assert.equal(records[0].syncState, 'pending', 'late revision-1 ack must not clear revision-2 work');
  await sync.sync(); assert.equal(records[0].syncState, 'uploaded');
  records[0].syncState = 'pending'; let releaseUpload;
  fakeApi.request = async (_url, _method, body) => {
    await new Promise(r => { releaseUpload = r; });
    return { accepted: JSON.parse(body).records.map(r => ({ recordId: r.recordId, revision: r.revision, status: 'created' })) };
  };
  const inFlight = sync.sync(); await new Promise(r => setTimeout(r, 0)); assert.match(await sync.sync(), /正在进行/);
  releaseUpload(); await inFlight;
  sync.stop();

  const modelBytes = new Uint8Array(2048).fill(7), modelHash = crypto.createHash('sha256').update(modelBytes).digest('hex');
  let rejectModel = false;
  overrides['services/Inference'] = { inferenceService: { busy: false, inspect: async () => { if (rejectModel) throw new Error('bad graph'); return 'validated'; } } };
  const { updateModel } = load('services/Models');
  const manifest = { version: '1.0.1', sha256: modelHash, size: 2048, inputSize: 640, downloadUrl: '/v1/models/1.0.1/file' };
  for (const bad of [{ ...manifest, sha256: '0'.repeat(64) }, { ...manifest, size: 2049 }, { ...manifest, version: '../escape' }, { ...manifest, downloadUrl: 'https://other.test/model' }]) {
    await assert.rejects(updateModel({ filesDir: '/app' }, settings, bad));
    assert.equal(store.saved, undefined);
  }
  rejectModel = true; await assert.rejects(updateModel({ filesDir: '/app' }, settings, manifest), /bad graph/);
  assert.equal([...files.keys()].filter(p => p.endsWith('.part')).length, 0); assert.equal(store.saved, undefined);
  rejectModel = false; const updated = await updateModel({ filesDir: '/app' }, settings, manifest);
  assert.equal(updated.modelVersion, '1.0.1'); assert.equal(store.saved.modelPath, updated.modelPath);
  assert.ok(files.has(updated.modelPath)); assert.equal(settings.modelPath, '/old.onnx');
  console.log('PASS actual ETS: JWT 401 refresh and coalescing, transport cleanup, configuration races, durable sync recovery, single upload, revision guards, model hash/shape/atomic switch');
})().catch(error => { console.error(error); process.exitCode = 1; });
