const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm');
const { DatabaseSync } = require('node:sqlite');
const { findTypeScript, readOptions } = require('./test-support.cjs');
const ts = findTypeScript(readOptions()), root = path.resolve(__dirname, '../entry/src/main/ets');
const db = new DatabaseSync(':memory:');
let failInsert = false;
const native = {
  executeSql: async (sql, params = []) => {
    if (failInsert && sql.startsWith('INSERT INTO record_items')) throw new Error('disk write failure');
    db.prepare(sql).run(...params);
  },
  querySql: async (sql, params = []) => {
    const stmt = db.prepare(sql); stmt.setReturnArrays(true); const rows = stmt.all(...params); let index = -1;
    return { goToNextRow: () => ++index < rows.length, getString: i => String(rows[index][i]), getLong: i => Number(rows[index][i]), close: () => {} };
  },
  beginTransaction: () => db.exec('BEGIN'), commit: () => db.exec('COMMIT'), rollBack: () => db.exec('ROLLBACK')
};
const cache = {};
function load(relative) {
  if (cache[relative]) return cache[relative];
  const exports = {}; cache[relative] = exports;
  const file = path.join(root, relative + '.ets');
  const code = ts.transpileModule(fs.readFileSync(file, 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const requireLocal = id => {
    if (id === '@kit.ArkData') return { relationalStore: { getRdbStore: async () => native, SecurityLevel: { S2: 2 } } };
    if (id === '@kit.ArkTS') return { util: { generateRandomUUID: () => 'a-device-id-for-test' } };
    if (id.startsWith('.')) return load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), id)));
    return {};
  };
  vm.runInThisContext(`(function(require,exports){${code}\n})`, { filename: file })(requireLocal, exports); return exports;
}
function close(a, b) { assert.ok(Math.abs(a - b) < 1e-5, `${a} != ${b}`); }
function fixture(id, captured = 1000, revision = 1, name = '水杯') {
  return { recordId: id, capturedAt: captured, updatedAt: captured, revision, imagePath: '/photo.jpg', thumbnailPath: '/thumb.jpg',
    width: 1280, height: 720, modelVersion: '1.0.0', threshold: .35,
    items: [{ id: 'b1', classId: 41, name, score: .9, x1: 200, y1: 100, x2: 400, y2: 300 }], timings: {},
    syncState: 'pending', attempts: 0, nextRetry: 0, lastError: '' };
}
(async () => {
  const math = load('model/DetectionMath');
  assert.equal(math.LABELS.length, 80); assert.equal(math.LABELS[67], '手机');
  const landscape = math.letterboxGeometry(1280, 720);
  assert.equal(landscape.padY, 140); assert.equal(landscape.padX, 0); assert.equal(landscape.ratio, .5);
  const portrait = math.letterboxGeometry(720, 1280); assert.equal(portrait.padX, 140);
  assert.throws(() => math.letterboxGeometry(0, 3));
  const tiny = math.letterboxGeometry(1, 1, 4);
  const normalized = math.preprocess(new Uint8Array([10, 20, 30, 255]), tiny);
  assert.equal(normalized.length, 48); close(normalized[0], 10 / 255); close(normalized[16], 20 / 255); close(normalized[47], 30 / 255);
  const padded = math.preprocess(new Uint8Array([255, 0, 0, 255, 255, 0, 0, 255]), math.letterboxGeometry(2, 1, 4));
  close(padded[0], 114 / 255); close(padded[4], 1); close(padded[16 + 4], 0);
  assert.throws(() => math.preprocess(new Uint8Array(3), tiny));
  const candidates = 4, raw = new Float32Array(84 * candidates);
  function box(i, cx, cy, width, height, category, score) {
    raw[i] = cx; raw[candidates + i] = cy; raw[2 * candidates + i] = width; raw[3 * candidates + i] = height;
    raw[(4 + category) * candidates + i] = score;
  }
  box(0, 150, 240, 100, 100, 41, .9); box(1, 151, 240, 100, 100, 41, .8);
  box(2, 150, 240, 100, 100, 67, .85); box(3, NaN, 200, 30, 30, 73, .99);
  const detected = math.postprocess(raw, [1, 84, candidates], landscape, .35);
  assert.equal(detected.length, 2); assert.equal(detected[0].name, '水杯'); assert.equal(detected[1].name, '手机');
  close(detected[0].x1, 200); close(detected[0].y1, 100); close(detected[0].x2, 400); close(detected[0].y2, 300);
  const transposed = new Float32Array(raw.length);
  for (let i = 0; i < candidates; i++) for (let c = 0; c < 84; c++) transposed[i * 84 + c] = raw[c * candidates + i];
  assert.deepEqual(math.postprocess(transposed, [1, candidates, 84], landscape, .35), detected);
  assert.equal(math.postprocess(raw, [1, 84, candidates], landscape, .95).length, 0);
  assert.throws(() => math.postprocess(raw, [1, 85, 4], landscape, .35));
  assert.throws(() => math.postprocess(raw, [1, 84, 4], landscape, NaN));
  assert.deepEqual(math.summarize([detected[0], detected[0]]), [{ name: '水杯', count: 2 }]);

  const { ScanStore } = load('model/ScanStore'); const store = new ScanStore(); await store.init({});
  assert.equal((await store.settings()).deviceId, 'a-device-id-for-test');
  await store.save(fixture('record-1')); await store.save(fixture('record-2', 2000, 1, '手机'));
  assert.equal((await store.records('水杯')).length, 1); assert.equal((await store.records('', 1500, 2500)).length, 1);
  assert.equal((await store.records("' OR 1=1--")).length, 0);
  await store.acknowledge('record-1', 1); assert.equal((await store.pending()).length, 1);
  await store.save(fixture('record-1', 1000, 2, '书本'));
  await store.acknowledge('record-1', 1); assert.equal((await store.records('书本'))[0].syncState, 'pending');
  await store.failed('record-1', 1, 0, 'stale failure'); assert.equal((await store.records('书本'))[0].attempts, 0);
  await store.failed('record-1', 2, 0, '网络中断');
  const failed = (await store.records('书本'))[0]; assert.equal(failed.attempts, 1); assert.ok(failed.nextRetry > Date.now());
  assert.equal((await store.pending(false)).length, 1); assert.equal((await store.pending(true)).length, 2);
  failInsert = true;
  await assert.rejects(store.save(fixture('record-1', 1000, 3, '回滚测试')), /disk write failure/); failInsert = false;
  assert.equal((await store.records('书本'))[0].revision, 2); assert.equal((await store.records('回滚测试')).length, 0);
  const restarted = new ScanStore(); await restarted.init({}); assert.equal((await restarted.records()).length, 2);
  await restarted.remove('record-1'); assert.equal((await store.records()).length, 1);
  assert.equal(db.prepare('SELECT count(*) n FROM record_items WHERE record_id=?').get('record-1').n, 0);
  db.close(); console.log('PASS actual ETS: letterbox RGB/NCHW, inverse coordinates, class-aware NMS, RDB transactions, filters, durable retry, stale acknowledgements');
})().catch(error => { console.error(error); process.exitCode = 1; });
