import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { AppSettings } from './Types';
import { CampusItem, PublishPayload, OutboxEntry, SyncPage } from './CampusTypes';

export class CacheStore {
  private db: relationalStore.RdbStore | undefined = undefined;
  private tail: Promise<void> = Promise.resolve();
  scope: string = '';
  private serial<T>(work: () => Promise<T>): Promise<T> {
    const result = this.tail.then(work); this.tail = result.then(() => {}, () => {}); return result;
  }
  private database(): relationalStore.RdbStore { if (!this.db) { throw new Error('本地缓存尚未就绪，请重试'); } return this.db; }
  async init(context: common.Context): Promise<void> {
    if (this.db) { return; }
    this.db = await relationalStore.getRdbStore(context, { name: 'campus_return.db', securityLevel: relationalStore.SecurityLevel.S2 });
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS cached_items(scope TEXT,id TEXT,data TEXT,PRIMARY KEY(scope,id))');
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS outbox(scope TEXT,id TEXT,data TEXT,attempts INTEGER,retry_at INTEGER,error TEXT,PRIMARY KEY(scope,id))');
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS sync_cursor(scope TEXT PRIMARY KEY,value INTEGER)');
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT)');
  }
  async settings(): Promise<AppSettings> {
    return this.serial(async () => {
      const r = await this.database().querySql("SELECT value FROM settings WHERE key='connection'");
      try { if (r.goToFirstRow()) { return JSON.parse(r.getString(0)) as AppSettings; } }
      finally { r.close(); }
      return { endpoint: 'http://127.0.0.1:8766', deviceId: '', deviceKey: '', autoSync: true, modelPath: '', modelVersion: '1.0.0' };
    });
  }
  async saveSettings(settings: AppSettings): Promise<void> {
    return this.serial(async () => { await this.database().executeSql("INSERT OR REPLACE INTO settings VALUES ('connection',?)", [JSON.stringify(settings)]); });
  }
  async items(): Promise<CampusItem[]> {
    const scope = this.scope;
    return this.serial(async () => {
      const r = await this.database().querySql('SELECT data FROM cached_items WHERE scope=? ORDER BY rowid DESC', [scope]); const rows: CampusItem[] = [];
      try { while (r.goToNextRow()) { rows.push(JSON.parse(r.getString(0)) as CampusItem); } } finally { r.close(); } return rows.sort((a: CampusItem, b: CampusItem) => b.occurredAt - a.occurredAt);
    });
  }
  async enqueue(payload: PublishPayload, ownerName: string): Promise<void> {
    const scope = this.scope; const owner = scope.split('|').pop() || '';
    return this.serial(async () => {
      const db = this.database(); db.beginTransaction();
      try {
        await db.executeSql("INSERT OR IGNORE INTO outbox VALUES (?,?,?,0,0,'')", [scope, payload.itemId, JSON.stringify(payload)]);
        const item: CampusItem = { itemId: payload.itemId, kind: payload.kind, category: payload.category, color: payload.color,
          place: payload.place, occurredAt: payload.occurredAt, description: payload.description, ocrText: payload.ocrText,
          imageBase64: payload.imageBase64, question: payload.question, ownerId: owner, ownerName: ownerName,
          state: '待上传', version: 0, ocrHint: payload.ocrText ? '含文字线索' : '', imagePrivate: false, completedMatchId: '' };
        await db.executeSql('INSERT OR REPLACE INTO cached_items VALUES (?,?,?)', [scope, payload.itemId, JSON.stringify(item)]); db.commit();
      } catch (error) { db.rollBack(); throw error as Error; }
    });
  }
  async pending(force: boolean = false): Promise<OutboxEntry[]> {
    const scope = this.scope;
    return this.serial(async () => {
      const r = await this.database().querySql('SELECT id,data,attempts,retry_at,error FROM outbox WHERE scope=? AND retry_at<=? ORDER BY rowid LIMIT 10', [scope, force ? 32503680000000 : Date.now()]);
      const result: OutboxEntry[] = [];
      try { while (r.goToNextRow()) { result.push({ itemId: r.getString(0), payload: JSON.parse(r.getString(1)) as PublishPayload, attempts: r.getLong(2), retryAt: r.getLong(3), error: r.getString(4) }); } } finally { r.close(); }
      return result;
    });
  }
  async acknowledge(id: string): Promise<void> {
    const scope = this.scope;
    return this.serial(async () => { await this.database().executeSql('DELETE FROM outbox WHERE scope=? AND id=?', [scope, id]); });
  }
  async failed(id: string, attempts: number, error: string): Promise<void> {
    const scope = this.scope; const retry = Date.now() + Math.min(300000, 2000 * Math.pow(2, Math.min(attempts, 8)));
    return this.serial(async () => { await this.database().executeSql('UPDATE outbox SET attempts=attempts+1,retry_at=?,error=? WHERE scope=? AND id=?', [retry, error.slice(0, 300), scope, id]); });
  }
  async cursor(): Promise<number> {
    const scope = this.scope;
    return this.serial(async () => { const r = await this.database().querySql('SELECT value FROM sync_cursor WHERE scope=?', [scope]); try { return r.goToFirstRow() ? r.getLong(0) : 0; } finally { r.close(); } });
  }
  async apply(page: SyncPage): Promise<void> {
    const scope = this.scope;
    return this.serial(async () => {
      const db = this.database(); db.beginTransaction();
      try {
        for (let i = 0; i < page.items.length; i++) { const item = page.items[i]; await db.executeSql('INSERT OR REPLACE INTO cached_items VALUES (?,?,?)', [scope, item.itemId, JSON.stringify(item)]); }
        await db.executeSql('INSERT OR REPLACE INTO sync_cursor VALUES (?,?)', [scope, page.cursor]); db.commit();
      } catch (error) { db.rollBack(); throw error as Error; }
    });
  }
}
export const cacheStore = new CacheStore();
