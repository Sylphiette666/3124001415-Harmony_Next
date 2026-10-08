import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BoardMessage, MessageInput, MessageRepository, MAX_MESSAGES, validateMessage, validMessageId } from './BoardMessage';

interface MessageIndex { version: number; ids: string[]; }
interface StoredValue { key: string; exists: boolean; value: preferences.ValueType; }

// Each record is smaller than Preferences' value limit. No HTML/localStorage persistence.
export class MessageStore implements MessageRepository {
  private context: common.Context;
  private name: string;
  private static queues: Map<string, Promise<void>> = new Map<string, Promise<void>>();
  constructor(context: common.Context, name: string = 'course_message_board_v1') {
    this.context = context; this.name = name;
  }
  private store(): preferences.Preferences {
    try { return preferences.getPreferencesSync(this.context, { name: this.name }); }
    catch { throw new Error('留言存储暂时不可用，请稍后重试'); }
  }
  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const result = (MessageStore.queues.get(this.name) || Promise.resolve()).then(operation);
    MessageStore.queues.set(this.name, result.then(() => {}, () => {}));
    return result;
  }
  private read(store: preferences.Preferences): BoardMessage[] {
    try {
      if (!store.hasSync('index')) {
        if (Object.keys(store.getAllSync()).some((key: string) => key.startsWith('message_'))) {
          throw new Error('Missing index');
        }
        return [];
      }
      const index = JSON.parse(store.getSync('index', '') as string) as MessageIndex;
      if (!index || index.version !== 1 || !Array.isArray(index.ids) || index.ids.length > MAX_MESSAGES) {
        throw new Error('Invalid index');
      }
      const seen = new Set<string>();
      const messages: BoardMessage[] = [];
      for (const id of index.ids) {
        if (!validMessageId(id) || seen.has(id)) { throw new Error('Invalid id'); }
        seen.add(id);
        const item = JSON.parse(store.getSync('message_' + id, '') as string) as BoardMessage;
        if (!item || item.id !== id || validateMessage(item) ||
          !Number.isSafeInteger(item.createdAt) || item.createdAt <= 0) { throw new Error('Invalid record'); }
        messages.push(item);
      }
      return messages;
    } catch { throw new Error('历史留言读取失败，原始数据已保留，请重试'); }
  }
  list(): Promise<BoardMessage[]> { return this.enqueue(async () => this.read(this.store())); }

  add(input: MessageInput): Promise<BoardMessage[]> {
    const error = validateMessage(input);
    if (error) { return Promise.reject(new Error(error)); }
    // Capture input before enqueuing so callers cannot mutate a pending write.
    const captured: MessageInput = { id: input.id, author: input.author.trim(), body: input.body.trim() };
    return this.enqueue(async () => {
      const store = this.store();
      const messages = this.read(store);
      const existing = messages.find((message: BoardMessage) => message.id === captured.id);
      if (existing) {
        if (existing.author !== captured.author || existing.body !== captured.body) {
          throw new Error('留言请求编号重复，请重新提交');
        }
        return messages; // Idempotent retry after a lost webpage acknowledgement.
      }
      if (messages.length >= MAX_MESSAGES) { throw new Error('已保存 100 条留言，请先删除不需要的留言'); }
      const message: BoardMessage = { id: captured.id, author: captured.author, body: captured.body, createdAt: Date.now() };
      messages.unshift(message);
      await this.commit(store, message.id, JSON.stringify(message), messages);
      return messages;
    });
  }

  remove(id: string): Promise<BoardMessage[]> {
    if (!validMessageId(id)) { return Promise.reject(new Error('留言编号不正确')); }
    return this.enqueue(async () => {
      const store = this.store();
      const messages = this.read(store);
      if (!messages.some((message: BoardMessage) => message.id === id)) { return messages; }
      const remaining = messages.filter((message: BoardMessage) => message.id !== id);
      await this.commit(store, id, undefined, remaining);
      return remaining;
    });
  }

  private async commit(store: preferences.Preferences, id: string, value: string | undefined,
    messages: BoardMessage[]): Promise<void> {
    const key = 'message_' + id;
    let previous: StoredValue[];
    try {
      previous = [key, 'index'].map((name: string): StoredValue => {
        return { key: name, exists: store.hasSync(name), value: store.getSync(name, '') };
      });
    } catch { throw new Error('无法读取保存前的留言状态，请重试'); }
    try {
      if (value === undefined) { store.deleteSync(key); } else { store.putSync(key, value); }
      const index: MessageIndex = { version: 1, ids: messages.map((message: BoardMessage) => message.id) };
      store.putSync('index', JSON.stringify(index));
      await store.flush();
    } catch {
      try {
        for (const old of previous) {
          if (old.exists) { store.putSync(old.key, old.value); } else { store.deleteSync(old.key); }
        }
        await store.flush();
      } catch {
        try { await preferences.removePreferencesFromCache(this.context, this.name); } catch { /* Preserve disk data. */ }
        throw new Error('保存失败，无法确认磁盘状态，请重新读取留言后重试');
      }
      throw new Error('留言保存失败，已恢复原数据，请重试');
    }
  }
}
