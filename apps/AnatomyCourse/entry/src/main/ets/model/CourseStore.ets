import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { CourseDocument, Segment, Structure, AppSettings, splitDocument, validateDocument } from './Knowledge';

export class CourseStore {
  private db: relationalStore.RdbStore | undefined = undefined;
  private queue: Promise<void> = Promise.resolve();
  version: number = 0;

  private serial<T>(action: () => Promise<T>): Promise<T> {
    const pending = this.queue.then(action); this.queue = pending.then(() => {}, () => {}); return pending;
  }
  private database(): relationalStore.RdbStore {
    if (!this.db) { throw new Error('资料库尚未就绪，请稍后重试'); } return this.db;
  }
  async init(context: common.Context, name: string = 'anatomy_course.db'): Promise<void> {
    return this.serial(async () => {
      if (this.db) { return; }
      const db = await relationalStore.getRdbStore(context, { name: name, securityLevel: relationalStore.SecurityLevel.S1 });
      await db.executeSql('CREATE TABLE IF NOT EXISTS documents (id TEXT PRIMARY KEY, title TEXT NOT NULL, source TEXT NOT NULL, body TEXT NOT NULL, revision INTEGER NOT NULL, updated INTEGER NOT NULL)');
      await db.executeSql('CREATE TABLE IF NOT EXISTS segments (id TEXT PRIMARY KEY, document_id TEXT NOT NULL, title TEXT NOT NULL, source TEXT NOT NULL, text TEXT NOT NULL, start INTEGER NOT NULL, end INTEGER NOT NULL, revision INTEGER NOT NULL, vector TEXT NOT NULL, model TEXT NOT NULL)');
      await db.executeSql('CREATE INDEX IF NOT EXISTS segments_doc ON segments(document_id)');
      await db.executeSql('CREATE TABLE IF NOT EXISTS structures (id TEXT PRIMARY KEY, name TEXT NOT NULL, system TEXT NOT NULL, concept_id TEXT NOT NULL, description TEXT NOT NULL, time INTEGER NOT NULL, note TEXT NOT NULL, favorite INTEGER NOT NULL)');
      await db.executeSql('CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      this.db = db;
      const rows = await db.querySql("SELECT value FROM meta WHERE key='seeded'");
      let seeded = false; try { seeded = rows.goToNextRow(); } finally { rows.close(); }
      if (!seeded) {
        const data = await context.resourceManager.getRawFileContent('course-documents.json');
        const text = util.TextDecoder.create('utf-8').decodeToString(data);
        const documents = JSON.parse(text) as CourseDocument[];
        db.beginTransaction();
        try {
          for (let i = 0; i < documents.length; i++) { await this.writeDocument(documents[i]); }
          await db.executeSql("INSERT INTO meta VALUES ('seeded', '1')"); db.commit();
        } catch (error) { db.rollBack(); this.db = undefined; throw error as Error; }
      }
      this.version++;
    });
  }
  private async writeDocument(doc: CourseDocument): Promise<void> {
    validateDocument(doc.title, doc.body);
    const db = this.database();
    await db.executeSql('INSERT OR REPLACE INTO documents VALUES (?,?,?,?,?,?)', [doc.id, doc.title, doc.source, doc.body, doc.revision, doc.updated]);
    await db.executeSql('DELETE FROM segments WHERE document_id=?', [doc.id]);
    const segments = splitDocument(doc);
    for (let i = 0; i < segments.length; i++) {
      const s = segments[i];
      await db.executeSql('INSERT INTO segments VALUES (?,?,?,?,?,?,?,?,?,?)', [s.id, s.documentId, s.title, s.source, s.text, s.start, s.end, s.revision, '[]', '']);
    }
  }
  async save(doc: CourseDocument): Promise<void> {
    return this.serial(async () => {
      const db = this.database(); db.beginTransaction();
      try {
        const rows = await db.querySql('SELECT revision FROM documents WHERE id=?', [doc.id]);
        let current = 0; try { if (rows.goToNextRow()) { current = rows.getLong(0); } } finally { rows.close(); }
        const updated: CourseDocument = { id: doc.id, title: doc.title.trim(), source: doc.source.trim().slice(0, 500),
          body: doc.body, revision: current + 1, updated: Date.now() };
        await this.writeDocument(updated); db.commit(); this.version++;
      } catch (error) { db.rollBack(); throw error as Error; }
    });
  }
  async remove(id: string): Promise<void> {
    return this.serial(async () => {
      const db = this.database(); db.beginTransaction();
      try {
        await db.executeSql('DELETE FROM segments WHERE document_id=?', [id]);
        await db.executeSql('DELETE FROM documents WHERE id=?', [id]); db.commit(); this.version++;
      } catch (error) { db.rollBack(); throw error as Error; }
    });
  }
  async documents(): Promise<CourseDocument[]> {
    return this.serial(async () => {
      const rows = await this.database().querySql('SELECT * FROM documents ORDER BY updated DESC, id');
      const result: CourseDocument[] = [];
      try { while (rows.goToNextRow()) { result.push({ id: rows.getString(0), title: rows.getString(1), source: rows.getString(2),
        body: rows.getString(3), revision: rows.getLong(4), updated: rows.getLong(5) }); } } finally { rows.close(); }
      return result;
    });
  }
  async segments(): Promise<Segment[]> {
    return this.serial(async () => {
      const rows = await this.database().querySql('SELECT * FROM segments ORDER BY document_id, start');
      const result: Segment[] = [];
      try { while (rows.goToNextRow()) { result.push({ id: rows.getString(0), documentId: rows.getString(1), title: rows.getString(2),
        source: rows.getString(3), text: rows.getString(4), start: rows.getLong(5), end: rows.getLong(6), revision: rows.getLong(7),
        vector: JSON.parse(rows.getString(8)) as number[], model: rows.getString(9) }); } } finally { rows.close(); }
      return result;
    });
  }
  async vectors(segments: Segment[], vectors: number[][], model: string): Promise<void> {
    if (vectors.length !== segments.length || !model) { throw new Error('向量服务返回的数据不完整'); }
    return this.serial(async () => {
      const db = this.database(); db.beginTransaction();
      try {
        for (let i = 0; i < segments.length; i++) {
          // A changed/deleted document has different segment ids. Stale network responses cannot resurrect it.
          await db.executeSql('UPDATE segments SET vector=?, model=? WHERE id=? AND revision=?',
            [JSON.stringify(vectors[i]), model, segments[i].id, segments[i].revision]);
        }
        db.commit();
      } catch (error) { db.rollBack(); throw error as Error; }
    });
  }
  async visit(item: Structure): Promise<void> {
    return this.serial(async () => {
      const db = this.database();
      await db.executeSql('INSERT OR IGNORE INTO structures VALUES (?,?,?,?,?,?,?,?)', [item.id, item.name, item.system, item.conceptId, item.description, Date.now(), '', 0]);
      await db.executeSql('UPDATE structures SET time=? WHERE id=?', [Date.now(), item.id]);
    });
  }
  async updateStructure(id: string, favorite: boolean, note: string): Promise<void> {
    if (note.length > 10000) { throw new Error('笔记最多 10000 字'); }
    return this.serial(async () => { await this.database().executeSql('UPDATE structures SET favorite=?, note=? WHERE id=?', [favorite ? 1 : 0, note, id]); });
  }
  async structures(): Promise<Structure[]> {
    return this.serial(async () => {
      const rows = await this.database().querySql('SELECT * FROM structures ORDER BY time DESC LIMIT 300');
      const result: Structure[] = [];
      try { while (rows.goToNextRow()) { result.push({ id: rows.getString(0), name: rows.getString(1), system: rows.getString(2),
        conceptId: rows.getString(3), description: rows.getString(4), time: rows.getLong(5), note: rows.getString(6), favorite: rows.getLong(7) === 1 }); } } finally { rows.close(); }
      return result;
    });
  }
  async settings(): Promise<AppSettings> {
    return this.serial(async () => {
      const rows = await this.database().querySql("SELECT value FROM meta WHERE key='settings'");
      try { return rows.goToNextRow() ? JSON.parse(rows.getString(0)) as AppSettings : { endpoint: '', cloud: false }; } finally { rows.close(); }
    });
  }
  async saveSettings(settings: AppSettings): Promise<void> {
    return this.serial(async () => { await this.database().executeSql("INSERT OR REPLACE INTO meta VALUES ('settings', ?)", [JSON.stringify(settings)]); });
  }
}
export const courseStore: CourseStore = new CourseStore();
