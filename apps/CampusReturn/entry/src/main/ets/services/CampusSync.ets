import { connection, http } from '@kit.NetworkKit';
import { cacheStore } from '../model/CacheStore';
import { SyncPage, UploadAck } from '../model/CampusTypes';
import { apiClient } from './ApiClient';

export class CampusSync {
  busy: boolean = false;
  private timer: number = -1;
  private net: connection.NetConnection | undefined = undefined;
  private changed: ((message: string, failed: boolean) => void) | undefined = undefined;
  start(changed: (message: string, failed: boolean) => void): void {
    this.changed = changed;
    if (this.timer >= 0) { return; }
    this.timer = setInterval(() => { this.auto(); }, 15000);
    try { this.net = connection.createNetConnection(); this.net.on('netAvailable', () => { this.auto(); }); this.net.register(() => {}); } catch {}
  }
  stop(): void {
    if (this.timer >= 0) { clearInterval(this.timer); this.timer = -1; }
    if (this.net) { this.net.unregister(() => {}); this.net = undefined; } this.changed = undefined;
  }
  private async auto(): Promise<void> {
    try { if (apiClient.configured && !this.busy) { await this.run(false); } } catch {}
  }
  async run(force: boolean = true): Promise<string> {
    if (this.busy) { return '正在同步，请稍候'; }
    if (!apiClient.configured) { throw new Error('请先连接服务；已缓存的内容可离线浏览'); }
    this.busy = true; let message = ''; let failed = false;
    try {
      const work = await cacheStore.pending(force);
      for (let i = 0; i < work.length; i++) {
        const entry = work[i];
        try {
          const ack = await apiClient.request<UploadAck>('/v1/items', http.RequestMethod.POST, JSON.stringify(entry.payload));
          if (ack.itemId !== entry.itemId || !['created', 'duplicate'].includes(ack.status)) { throw new Error('未收到发布确认，已保留待传记录'); }
          await cacheStore.acknowledge(entry.itemId);
        } catch (error) { await cacheStore.failed(entry.itemId, entry.attempts, (error as Error).message); throw error as Error; }
      }
      let cursor = await cacheStore.cursor(); let remaining = true;
      for (let i = 0; i < 100 && remaining; i++) {
        const page = await apiClient.request<SyncPage>(`/v1/sync?cursor=${cursor}&limit=2`);
        if (!Array.isArray(page.items) || page.cursor < cursor || (page.hasMore && page.cursor === cursor)) { throw new Error('增量同步响应无效，请重试'); }
        await cacheStore.apply(page); cursor = page.cursor; remaining = page.hasMore;
      }
      message = work.length ? `已同步${work.length}条待传发布，列表已更新` : '已连接，缓存已更新'; return message;
    } catch (error) { failed = true; message = (error as Error).message; throw error as Error; }
    finally { this.busy = false; if (this.changed) { this.changed(message, failed); } }
  }
}
export const campusSync = new CampusSync();
