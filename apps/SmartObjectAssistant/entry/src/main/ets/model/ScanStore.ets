import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { ScanRecord, Detection, AppSettings } from './Types';

export class ScanStore {
  private db: relationalStore.RdbStore | undefined = undefined;
  private queue: Promise<void> = Promise.resolve();
  private serial<T>(action: () => Promise<T>): Promise<T> {
    const result = this.queue.then(action); this.queue = result.then(() => {}, () => {}); return result;
  }
  private database(): relationalStore.RdbStore {
    if (!this.db) { throw new Error('本地记录尚未加载，请重试。'); } return this.db;
  }
  async init(context: common.Context): Promise<void> {
    return this.serial(async () => {
      if (this.db) { return; }
      const db = await relationalStore.getRdbStore(context, { name: 'smart_objects.db', securityLevel: relationalStore.SecurityLevel.S2 });
      await db.executeSql('CREATE TABLE IF NOT EXISTS records (id TEXT PRIMARY KEY, captured INTEGER NOT NULL, revision INTEGER NOT NULL, payload TEXT NOT NULL, sync_state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0, next_retry INTEGER NOT NULL DEFAULT 0, last_error TEXT NOT NULL DEFAULT \'\')');
      await db.executeSql('CREATE INDEX IF NOT EXISTS records_time ON records(captured)');
      await db.executeSql('CREATE TABLE IF NOT EXISTS record_items (record_id TEXT NOT NULL, item_id TEXT NOT NULL, category TEXT NOT NULL, PRIMARY KEY(record_id,item_id))');
      await db.executeSql('CREATE INDEX IF NOT EXISTS records_category ON record_items(category)');
      await db.executeSql('CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
      this.db = db;
    });
  }
  async settings(): Promise<AppSettings> {
    return this.serial(async () => {
      const rows = await this.database().querySql("SELECT value FROM settings WHERE key='app'");
      try {
        if (rows.goToNextRow()) { return JSON.parse(rows.getString(0)) as AppSettings; }
      } finally { rows.close(); }
      const settings: AppSettings = { endpoint: 'http://127.0.0.1:8765', deviceId: util.generateRandomUUID(), deviceKey: '',
        autoSync: true, modelPath: '', modelVersion: '1.0.0' };
      await this.database().executeSql("INSERT INTO settings VALUES ('app',?)", [JSON.stringify(settings)]); return settings;
    });
  }
  async saveSettings(settings: AppSettings): Promise<void> {
    return this.serial(async () => { await this.database().executeSql("INSERT OR REPLACE INTO settings VALUES ('app',?)", [JSON.stringify(settings)]); });
  }
  async save(record: ScanRecord): Promise<void> {
    return this.serial(async () => {
      const db = this.database(); db.beginTransaction();
      try {
        await db.executeSql('INSERT OR REPLACE INTO records VALUES (?,?,?,?,?,?,?,?)', [record.recordId, record.capturedAt, record.revision,
          JSON.stringify(record), 'pending', 0, 0, '']);
        await db.executeSql('DELETE FROM record_items WHERE record_id=?', [record.recordId]);
        for (let i = 0; i < record.items.length; i++) {
          const item = record.items[i];
          await db.executeSql('INSERT INTO record_items VALUES (?,?,?)', [record.recordId, item.id, item.name]);
        }
        db.commit();
      } catch (error) { db.rollBack(); throw error as Error; }
    });
  }
  private fromRow(rows: relationalStore.ResultSet): ScanRecord {
    const record = JSON.parse(rows.getString(3)) as ScanRecord;
    record.syncState = rows.getString(4); record.attempts = rows.getLong(5);
    record.nextRetry = rows.getLong(6); record.lastError = rows.getString(7); return record;
  }
  async records(category: string = '', start: number = 0, end: number = 32503680000000): Promise<ScanRecord[]> {
    return this.serial(async () => {
      const rows = await this.database().querySql("SELECT * FROM records r WHERE captured>=? AND captured<=? AND (?='' OR EXISTS (SELECT 1 FROM record_items i WHERE i.record_id=r.id AND instr(lower(i.category),lower(?))>0)) ORDER BY captured DESC,id LIMIT 200",
        [start, end, category.trim(), category.trim()]);
      const result: ScanRecord[] = [];
      try { while (rows.goToNextRow()) { result.push(this.fromRow(rows)); } } finally { rows.close(); } return result;
    });
  }
  async pending(force: boolean = false): Promise<ScanRecord[]> {
    return this.serial(async () => {
      const rows = await this.database().querySql("SELECT * FROM records WHERE sync_state='pending' AND next_retry<=? ORDER BY captured LIMIT 20", [force ? 32503680000000 : Date.now()]);
      const result: ScanRecord[] = [];
      try { while (rows.goToNextRow()) { result.push(this.fromRow(rows)); } } finally { rows.close(); } return result;
    });
  }
  async acknowledge(id: string, revision: number): Promise<void> {
    return this.serial(async () => { await this.database().executeSql("UPDATE records SET sync_state='uploaded',attempts=0,next_retry=0,last_error='' WHERE id=? AND revision=?", [id, revision]); });
  }
  async failed(id: string, revision: number, attempts: number, error: string): Promise<void> {
    const next = Date.now() + Math.min(300000, 2000 * Math.pow(2, Math.min(attempts, 8)));
    return this.serial(async () => { await this.database().executeSql("UPDATE records SET attempts=attempts+1,next_retry=?,last_error=? WHERE id=? AND revision=? AND sync_state='pending'", [next, error.slice(0, 250), id, revision]); });
  }
  async remove(id: string): Promise<void> {
    return this.serial(async () => {
      const db = this.database(); db.beginTransaction();
      try { await db.executeSql('DELETE FROM record_items WHERE record_id=?', [id]); await db.executeSql('DELETE FROM records WHERE id=?', [id]); db.commit(); }
      catch (error) { db.rollBack(); throw error as Error; }
    });
  }
}
export const scanStore = new ScanStore();
