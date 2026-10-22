import { connection, http } from '@kit.NetworkKit';
import { AppSettings, ScanRecord, UploadRecord, SyncResponse } from '../model/Types';
import { scanStore } from '../model/ScanStore';
import { apiClient } from './ApiClient';
import { thumbnailBase64 } from './MediaFiles';

export class SyncService {
  private running: boolean = false;
  private timer: number = -1;
  private observer: connection.NetConnection | undefined = undefined;
  private changed: ((message: string) => void) | undefined = undefined;
  get busy(): boolean { return this.running; }
  start(changed: (message: string) => void): void {
    if (this.timer >= 0) { return; }
    this.changed = changed;
    this.timer = setInterval(() => { this.auto(); }, 15000);
    try {
      const observer = connection.createNetConnection();
      observer.on('netAvailable', () => { this.auto(); }); observer.register(() => {}); this.observer = observer;
    } catch {}
  }
  stop(): void {
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
    if (this.observer) { this.observer.unregister(() => {}); this.observer = undefined; }
    this.changed = undefined;
  }
  async auto(): Promise<void> {
    try {
      const settings = await scanStore.settings();
      if (settings.autoSync && settings.deviceKey) { await this.sync(false); }
    } catch {} // Each failed record retains its own actionable error in RDB.
  }
  async sync(force: boolean = true): Promise<string> {
    if (this.running) { return '同步正在进行，请稍候。'; }
    if (!apiClient.configured) { throw new Error('请先在设置中配置服务与设备密钥。'); }
    this.running = true;
    let completed = '';
    let records: ScanRecord[] = [];
    try {
      records = await scanStore.pending(force);
      if (!records.length) { return '没有需要上传的记录。'; }
      const payload: UploadRecord[] = records.map((record: ScanRecord): UploadRecord => {
        return { recordId: record.recordId, capturedAt: record.capturedAt, updatedAt: record.updatedAt, revision: record.revision,
          width: record.width, height: record.height, modelVersion: record.modelVersion, threshold: record.threshold,
          items: record.items, thumbnailBase64: thumbnailBase64(record.thumbnailPath) };
      });
      const result = await apiClient.request<SyncResponse>('/v1/records/batch', http.RequestMethod.POST, JSON.stringify({ records: payload }));
      if (!Array.isArray(result.accepted)) { throw new Error('上传响应无效，记录保留待重试。'); }
      for (let i = 0; i < records.length; i++) {
        const record = records[i];
        const ack = result.accepted.find((item) => item.recordId === record.recordId && item.revision === record.revision);
        if (!ack || !['created', 'updated', 'duplicate'].includes(ack.status)) { throw new Error('部分记录未获确认，请检查版本后重试。'); }
      }
      for (let i = 0; i < records.length; i++) { await scanStore.acknowledge(records[i].recordId, records[i].revision); }
      completed = `已同步 ${records.length} 条记录。重复上传不会重复入库。`;
      return completed;
    } catch (error) {
      const message = (error as Error).message || '上传失败，网络恢复后将重试。';
      for (let i = 0; i < records.length; i++) {
        const record = records[i]; await scanStore.failed(record.recordId, record.revision, record.attempts, message);
      }
      throw new Error(message);
    } finally { this.running = false; if (this.changed) { this.changed(completed); } }
  }
}
export const syncService = new SyncService();
