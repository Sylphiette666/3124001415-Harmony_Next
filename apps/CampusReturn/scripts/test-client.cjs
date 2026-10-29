const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), os = require('node:os');
const { DatabaseSync } = require('node:sqlite');
const { findTypeScript, readOptions } = require('./test-support.cjs');
const ts = findTypeScript(readOptions()), root = path.resolve(__dirname, '../entry/src/main/ets');
const cache = {}, overrides = {}; let failSql = '', transactions = 0;
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'campus-return-test-')), database = new DatabaseSync(path.join(temp, 'cache.db'));
const db = {
  executeSql: async (sql, values = []) => { if (failSql && sql.includes(failSql)) throw Error('injected storage failure'); database.prepare(sql).run(...values); },
  querySql: async (sql, values = []) => { const rows = database.prepare(sql).all(...values); let index = -1; return { goToNextRow: () => ++index < rows.length, goToFirstRow: () => { index = 0; return rows.length > 0; }, getString: i => String(Object.values(rows[index])[i]), getLong: i => Number(Object.values(rows[index])[i]), close: () => {} }; },
  beginTransaction: () => { transactions++; database.exec('BEGIN IMMEDIATE'); }, commit: () => database.exec('COMMIT'), rollBack: () => database.exec('ROLLBACK')
};
function load(relative) {
  if (overrides[relative]) return overrides[relative]; if (cache[relative]) return cache[relative];
  const exports = {}; cache[relative] = exports;
  const code = ts.transpileModule(fs.readFileSync(path.join(root, relative + '.ets'), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const requireLocal = id => {
    if (id === '@kit.ArkData') return { relationalStore: { getRdbStore: async () => db, SecurityLevel: { S2: 2 } } };
    if (id === '@kit.NetworkKit') return { http: { RequestMethod: { POST: 'POST' } }, connection: {} };
    if (id.startsWith('.')) return load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), id)));
    return {};
  };
  vm.runInThisContext(`(function(require,exports){${code}\n})`, { filename: relative })(requireLocal, exports); return exports;
}
(async () => {
  const { formatTime, parseTime, extractRules } = load('model/ExtractRules');
  assert.equal(formatTime(parseTime('2026-10-29 10:15')), '2026-10-29 10:15');
  for (const v of ['2026-02-30 10:00', '2026-10-29 25:00', 'tomorrow']) assert.throws(() => parseTime(v));
  const fields = extractRules('昨天14点在图书馆北门丢了蓝色校园卡', parseTime('2026-10-29 10:00'));
  assert.equal(fields.timeText, '2026-10-28 14:00'); assert.equal(fields.category, '校园卡'); assert.equal(fields.color, '蓝色'); assert.equal(fields.place, '图书馆北门');
  assert.equal(extractRules('二饭拾到雨伞').place, '第二食堂');
  const { CacheStore } = load('model/CacheStore'), store = new CacheStore(); await store.init({}); store.scope = 'server|alice';
  const payload = { itemId: 'item-a', kind: 'lost', category: '校园卡', color: '蓝色', place: '图书馆', occurredAt: Date.now() - 1000, description: 'test', ocrText: '', imageBase64: 'test', question: '', answer: '' };
  await store.enqueue(payload, 'A'); assert.equal((await store.pending()).length, 1); assert.equal((await store.items())[0].state, '待上传');
  await store.enqueue(payload, 'A'); assert.equal((await store.pending()).length, 1);
  await store.failed('item-a', 0, 'offline'); assert.equal((await store.pending()).length, 0); assert.equal((await store.pending(true))[0].attempts, 1);
  const restored = new CacheStore(); await restored.init({}); restored.scope = store.scope; assert.equal((await restored.pending(true))[0].error, 'offline');
  store.scope = 'server|bob'; assert.equal((await store.items()).length, 0); assert.equal((await store.pending(true)).length, 0); store.scope = 'server|alice';
  const item = { ...payload, ownerId: 'alice', ownerName: 'A', state: '待匹配', version: 1, ocrHint: '', imagePrivate: false, completedMatchId: '' };
  failSql = 'sync_cursor'; await assert.rejects(store.apply({ items: [{ ...item, itemId: 'rollback' }], cursor: 9, hasMore: false })); failSql = '';
  assert.equal((await store.items()).length, 1); assert.equal(await store.cursor(), 0);
  await store.apply({ items: [item], cursor: 3, hasMore: false }); assert.equal(await store.cursor(), 3); assert.equal((await store.items())[0].state, '待匹配');
  failSql = 'cached_items'; await assert.rejects(store.enqueue({ ...payload, itemId: 'atomic' }, 'A')); failSql = ''; assert.equal((await store.pending(true)).length, 1);
  let fail = true, badAck = false, badCursor = false, sends = 0;
  const api = { configured: true, request: async (url, method, body) => {
    if (fail) throw Error('offline');
    if (url === '/v1/items') { sends++; return { itemId: badAck ? 'wrong' : JSON.parse(body).itemId, status: 'duplicate' }; }
    return { items: [], cursor: badCursor ? 2 : 4, hasMore: false };
  } };
  overrides['model/CacheStore'] = { cacheStore: store }; overrides['services/ApiClient'] = { apiClient: api };
  const { CampusSync } = load('services/CampusSync'), sync = new CampusSync();
  await assert.rejects(sync.run(), /offline/); assert.equal(sync.busy, false); assert.equal((await store.pending(true)).length, 1);
  fail = false; badAck = true; await assert.rejects(sync.run(), /确认/); assert.equal((await store.pending(true)).length, 1);
  badAck = false; badCursor = true; await assert.rejects(sync.run(), /同步响应/); assert.equal((await store.pending(true)).length, 0); assert.equal(await store.cursor(), 3);
  badCursor = false; await sync.run(); assert.equal(await store.cursor(), 4); assert.equal((await store.items()).length, 1); assert.equal(sends, 2);
  await Promise.all([store.enqueue({ ...payload, itemId: 'parallel1' }, 'A'), store.enqueue({ ...payload, itemId: 'parallel2' }, 'A')]); assert.equal((await store.pending(true)).length, 2);
  assert.ok(transactions >= 7); console.log('PASS: extraction, invalid dates, durable outbox, account isolation, SQLite rollback, idempotence, backoff, serial writes, sync retry, ACK and cursor validation');
})().finally(() => { database.close(); fs.rmSync(temp, { recursive: true, force: true }); }).catch(error => { console.error(error); process.exitCode = 1; });
