const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { DatabaseSync } = require('node:sqlite');
const ts = require('../web/node_modules/typescript');
const root = path.resolve(__dirname, '..');

function loadStore(db) {
  const native = {
    executeSql: async (sql, params = []) => { db.prepare(sql).run(...params); },
    querySql: async (sql, params = []) => {
      const stmt = db.prepare(sql); stmt.setReturnArrays(true);
      const rows = stmt.all(...params); let index = -1;
      return { goToNextRow: () => ++index < rows.length, getString: i => String(rows[index][i]),
        getLong: i => Number(rows[index][i]), close: () => {} };
    },
    beginTransaction: () => db.exec('BEGIN'), commit: () => db.exec('COMMIT'), rollBack: () => db.exec('ROLLBACK')
  };
  const exports = {};
  const code = ts.transpileModule(fs.readFileSync(path.join(root, 'entry/src/main/ets/model/AtlasStore.ets'), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 }
  }).outputText;
  vm.runInThisContext(`(function(require,exports){${code}\n})`)(name => name === '@kit.ArkData' ? {
    relationalStore: { SecurityLevel: { S1: 1 }, getRdbStore: async (_context, config) => {
      assert.equal(config.name, 'anatomy_course.db'); return native;
    } }
  } : {}, exports);
  return new exports.AtlasStore();
}

(async () => {
  const db = new DatabaseSync(':memory:');
  const store = loadStore(db);
  await assert.rejects(store.structures(), /尚未就绪/);
  await store.init({});
  assert.deepEqual(db.prepare("SELECT name FROM sqlite_master WHERE type='table'").all().map(r => r.name), ['structures']);
  const heart = { id: 'heart', name: 'Heart', system: 'cardiac', conceptId: 'heart', description: 'context', time: 0, note: '', favorite: false };
  await store.visit(heart); await store.updateStructure('heart', true, '保留原有笔记'); await store.visit(heart);
  assert.equal((await store.structures())[0].note, '保留原有笔记');
  assert.equal((await store.structures())[0].favorite, true);
  await assert.rejects(store.updateStructure('heart', false, '字'.repeat(10001)), /10000/);
  assert.equal((await store.structures())[0].favorite, true);
  // Simulate the previous installed schema: unrelated legacy records must stay untouched.
  db.exec("CREATE TABLE documents (id TEXT PRIMARY KEY, body TEXT); INSERT INTO documents VALUES ('legacy','user-authored notes');");
  const upgraded = loadStore(db); await upgraded.init({});
  assert.equal((await upgraded.structures())[0].note, '保留原有笔记');
  assert.equal(db.prepare("SELECT body FROM documents WHERE id='legacy'").get().body, 'user-authored notes');
  await Promise.all([upgraded.visit(heart), upgraded.updateStructure('heart', true, '最后一次保存')]);
  assert.equal((await upgraded.structures())[0].note, '最后一次保存');
  db.prepare('UPDATE structures SET time=1 WHERE id=?').run('heart');
  const insert = db.prepare('INSERT INTO structures VALUES (?,?,?,?,?,?,?,?)');
  for (let i = 0; i < 305; i++) insert.run('visit'+i, 'Structure '+i, '', '', '', i+2, '', 0);
  const retained = await upgraded.structures();
  assert.equal(retained.length, 301); assert(retained.some(item => item.id === 'heart' && item.favorite));
  await upgraded.updateStructure('heart', false, '最后一次保存');
  assert.equal((await upgraded.structures()).length, 300);
  db.close();
  console.log('PASS: fresh schema; legacy upgrade compatibility; favorites/notes persistence; validation; serial writes; latest 300 history plus older favorites.');
})().catch(error => { console.error(error); process.exitCode = 1; });
