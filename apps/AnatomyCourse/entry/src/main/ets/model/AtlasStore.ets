import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Structure } from './Structure';

export class AtlasStore {
  private db: relationalStore.RdbStore | undefined = undefined;
  private queue: Promise<void> = Promise.resolve();
  private serial<T>(action: () => Promise<T>): Promise<T> {
    const pending = this.queue.then(action); this.queue = pending.then(() => {}, () => {}); return pending;
  }
  private database(): relationalStore.RdbStore {
    if (!this.db) { throw new Error('学习记录尚未就绪，请稍后重试'); } return this.db;
  }
  async init(context: common.Context, name: string = 'anatomy_course.db'): Promise<void> {
    return this.serial(async () => {
      if (this.db) { return; }
      // Keep the existing database and table name so installed users retain their study records.
      // Legacy course tables, if present, are not read, modified or seeded.
      const db = await relationalStore.getRdbStore(context, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
      await db.executeSql('CREATE TABLE IF NOT EXISTS structures (id TEXT PRIMARY KEY, name TEXT NOT NULL, system TEXT NOT NULL, concept_id TEXT NOT NULL, description TEXT NOT NULL, time INTEGER NOT NULL, note TEXT NOT NULL, favorite INTEGER NOT NULL)');
      this.db = db;
    });
  }
  async visit(item: Structure): Promise<void> {
    return this.serial(async () => {
      const db = this.database(); db.beginTransaction();
      try {
        await db.executeSql('INSERT OR IGNORE INTO structures VALUES (?,?,?,?,?,?,?,?)', [item.id, item.name, item.system, item.conceptId, item.description, Date.now(), '', 0]);
        await db.executeSql('UPDATE structures SET time=? WHERE id=?', [Date.now(), item.id]); db.commit();
      } catch (error) { db.rollBack(); throw error as Error; }
    });
  }
  async updateStructure(id: string, favorite: boolean, note: string): Promise<void> {
    if (note.length > 10000) { throw new Error('笔记最多 10000 字'); }
    return this.serial(async () => { await this.database().executeSql('UPDATE structures SET favorite=?, note=? WHERE id=?', [favorite ? 1 : 0, note, id]); });
  }
  async structures(): Promise<Structure[]> {
    return this.serial(async () => {
      // Retain every favorite even when it falls outside the latest 300 browsing records.
      const rows = await this.database().querySql('SELECT * FROM structures WHERE favorite=1 OR id IN (SELECT id FROM structures ORDER BY time DESC LIMIT 300) ORDER BY time DESC');
      const result: Structure[] = [];
      try { while (rows.goToNextRow()) { result.push({ id: rows.getString(0), name: rows.getString(1), system: rows.getString(2),
        conceptId: rows.getString(3), description: rows.getString(4), time: rows.getLong(5), note: rows.getString(6), favorite: rows.getLong(7) === 1 }); } } finally { rows.close(); }
      return result;
    });
  }
}
export const atlasStore: AtlasStore = new AtlasStore();
