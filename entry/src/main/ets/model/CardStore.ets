import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessCard, copyCard, validateCard } from './BusinessCard';

const MANIFEST_KEY: string = 'cards_manifest';
const CHUNK_PREFIX: string = 'cards_chunk_';
// Preferences 单字符串有长度限制，分块保存后可管理多张含中文备注的名片。
const CHUNK_SIZE: number = 2048;
const MAX_CHUNKS: number = 1024;

class CardManifest {
  version: number = 1;
  chunks: number = 0;
}

class CardDocument {
  version: number = 1;
  cards: BusinessCard[] = [];
}

class PreferenceSnapshot {
  key: string = '';
  exists: boolean = false;
  value: preferences.ValueType = '';
}

const CARD_KEYS: string[] = ['id', 'name', 'organization', 'title', 'phone', 'email', 'address',
  'note', 'group', 'favorite', 'createdAt', 'updatedAt'];

export class CardStore {
  private context: common.Context;
  private storageName: string;
  // 同一存储的写操作排队，快速收藏/保存或多个页面实例不会互相覆盖。
  private static writeQueues: Map<string, Promise<void>> = new Map<string, Promise<void>>();

  constructor(context: common.Context, storageName: string = 'course_business_cards') {
    this.context = context;
    this.storageName = storageName;
  }

  load(): BusinessCard[] {
    const store = this.preferencesStore();
    return this.readCards(store);
  }

  async save(card: BusinessCard): Promise<BusinessCard> {
    const validation = validateCard(card);
    if (validation.length > 0) {
      throw new Error(validation);
    }
    const edited = copyCard(card);
    edited.name = edited.name.trim();
    edited.organization = edited.organization.trim();
    edited.title = edited.title.trim();
    edited.phone = edited.phone.trim();
    edited.email = edited.email.trim();
    edited.address = edited.address.trim();
    edited.note = edited.note.trim();
    return this.enqueue(async () => {
      const store = this.preferencesStore();
      const cards = this.readCards(store);
      const now = Date.now();
      if (edited.id.length === 0) {
        edited.id = util.generateRandomUUID(true);
        while (cards.some((existing: BusinessCard) => existing.id === edited.id)) {
          edited.id = util.generateRandomUUID(true);
        }
        edited.createdAt = now;
        edited.updatedAt = now;
        cards.push(edited);
      } else {
        const index = cards.findIndex((existing: BusinessCard) => existing.id === edited.id);
        if (index < 0) {
          throw new Error('这张名片已不存在，请返回列表后重试');
        }
        edited.createdAt = cards[index].createdAt;
        edited.updatedAt = Math.max(now, cards[index].updatedAt + 1);
        cards[index] = edited;
      }
      await this.writeCards(store, cards);
      return copyCard(edited);
    });
  }

  async remove(id: string): Promise<void> {
    return this.enqueue(async () => {
      const store = this.preferencesStore();
      const cards = this.readCards(store);
      const index = cards.findIndex((card: BusinessCard) => card.id === id);
      if (index < 0) {
        throw new Error('这张名片已不存在，请返回列表后重试');
      }
      cards.splice(index, 1);
      await this.writeCards(store, cards);
    });
  }

  async toggleFavorite(id: string): Promise<BusinessCard> {
    return this.enqueue(async () => {
      const store = this.preferencesStore();
      const cards = this.readCards(store);
      const index = cards.findIndex((card: BusinessCard) => card.id === id);
      if (index < 0) {
        throw new Error('这张名片已不存在，请返回列表后重试');
      }
      cards[index].favorite = !cards[index].favorite;
      cards[index].updatedAt = Math.max(Date.now(), cards[index].updatedAt + 1);
      await this.writeCards(store, cards);
      return copyCard(cards[index]);
    });
  }

  private preferencesStore(): preferences.Preferences {
    try {
      return preferences.getPreferencesSync(this.context, { name: this.storageName });
    } catch (error) {
      throw error as Error;
    }
  }

  // 在 API 边界捕获并原样传递异常，保留错误详情，交给页面决定如何提示和重试。
  private readValue(store: preferences.Preferences, key: string): preferences.ValueType {
    try {
      return store.getSync(key, '');
    } catch (error) {
      throw error as Error;
    }
  }

  private hasValue(store: preferences.Preferences, key: string): boolean {
    try {
      return store.hasSync(key);
    } catch (error) {
      throw error as Error;
    }
  }

  private storedKeys(store: preferences.Preferences): string[] {
    try {
      return Object.keys(store.getAllSync());
    } catch (error) {
      throw error as Error;
    }
  }

  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const previous = CardStore.writeQueues.get(this.storageName) ?? Promise.resolve();
    const result = previous.then(operation);
    // 失败只传给调用者；之后的重试仍能执行。
    CardStore.writeQueues.set(this.storageName, result.then(() => {}, () => {}));
    return result;
  }

  private readManifest(store: preferences.Preferences): CardManifest {
    const raw = this.readValue(store, MANIFEST_KEY);
    if (typeof raw !== 'string' || raw.length === 0) {
      throw new Error('本地名片索引损坏，原始数据已保留');
    }
    let manifest: CardManifest;
    try {
      manifest = JSON.parse(raw) as CardManifest;
    } catch (error) {
      throw new Error('本地名片索引无法解析，原始数据已保留');
    }
    if (manifest === null || typeof manifest !== 'object' || Array.isArray(manifest) ||
      Object.keys(manifest).length !== 2 || manifest.version !== 1 ||
      typeof manifest.chunks !== 'number' || !Number.isInteger(manifest.chunks) ||
      manifest.chunks < 1 || manifest.chunks > MAX_CHUNKS) {
      throw new Error('本地名片索引格式不正确，原始数据已保留');
    }
    return manifest;
  }

  private readCards(store: preferences.Preferences): BusinessCard[] {
    const storedChunkKeys = this.storedKeys(store).filter((key: string) =>
      key.indexOf(CHUNK_PREFIX) === 0);
    if (!this.hasValue(store, MANIFEST_KEY)) {
      if (storedChunkKeys.length > 0) {
        throw new Error('本地名片索引缺失，原始数据已保留');
      }
      return [];
    }
    const manifest = this.readManifest(store);
    if (storedChunkKeys.length !== manifest.chunks) {
      throw new Error('本地名片数据不完整，原始数据已保留');
    }
    let json = '';
    for (let index = 0; index < manifest.chunks; index++) {
      const key = CHUNK_PREFIX + index;
      const chunk = this.readValue(store, key);
      if (!this.hasValue(store, key) || typeof chunk !== 'string' || chunk.length === 0 ||
        chunk.length > CHUNK_SIZE) {
        throw new Error('本地名片数据块损坏，原始数据已保留');
      }
      json += chunk;
    }
    let document: CardDocument;
    try {
      document = JSON.parse(json) as CardDocument;
    } catch (error) {
      throw new Error('本地名片数据无法解析，原始数据已保留');
    }
    if (document === null || typeof document !== 'object' || Array.isArray(document) ||
      Object.keys(document).length !== 2 || document.version !== 1 || !Array.isArray(document.cards)) {
      throw new Error('本地名片数据格式不正确，原始数据已保留');
    }
    const ids: Set<string> = new Set<string>();
    const cards: BusinessCard[] = [];
    for (let index = 0; index < document.cards.length; index++) {
      const card = document.cards[index];
      if (validateCard(card).length > 0 || Object.keys(card).length !== CARD_KEYS.length ||
        Object.keys(card).some((key: string) => CARD_KEYS.indexOf(key) < 0) ||
        !/^[A-Za-z0-9_-]{1,80}$/.test(card.id) || ids.has(card.id) ||
        !Number.isSafeInteger(card.createdAt) || !Number.isSafeInteger(card.updatedAt) ||
        card.createdAt <= 0 || card.updatedAt < card.createdAt) {
        throw new Error('本地名片内容损坏，原始数据已保留');
      }
      ids.add(card.id);
      cards.push(copyCard(card));
    }
    return cards;
  }

  private async writeCards(store: preferences.Preferences, cards: BusinessCard[]): Promise<void> {
    const document = new CardDocument();
    document.cards = cards;
    const json = JSON.stringify(document);
    const chunks: string[] = [];
    let offset = 0;
    while (offset < json.length) {
      let end = Math.min(offset + CHUNK_SIZE, json.length);
      // Emoji 等字符由一对 UTF-16 单元组成，不能在写入原生存储时将它们拆开。
      if (end < json.length && json.charCodeAt(end - 1) >= 0xD800 &&
        json.charCodeAt(end - 1) <= 0xDBFF && json.charCodeAt(end) >= 0xDC00 &&
        json.charCodeAt(end) <= 0xDFFF) {
        end--;
      }
      chunks.push(json.slice(offset, end));
      offset = end;
    }
    const newManifest = new CardManifest();
    newManifest.chunks = chunks.length;
    if (newManifest.chunks > MAX_CHUNKS) {
      throw new Error('本地名片存储空间已满，请先删除不需要的名片');
    }
    const oldCount = this.hasValue(store, MANIFEST_KEY) ? this.readManifest(store).chunks : 0;
    const touchedKeys: string[] = [MANIFEST_KEY];
    for (let index = 0; index < Math.max(oldCount, newManifest.chunks); index++) {
      touchedKeys.push(CHUNK_PREFIX + index);
    }
    const snapshots: PreferenceSnapshot[] = touchedKeys.map((key: string) => {
      const snapshot = new PreferenceSnapshot();
      snapshot.key = key;
      snapshot.exists = this.hasValue(store, key);
      snapshot.value = this.readValue(store, key);
      return snapshot;
    });
    try {
      for (let index = 0; index < newManifest.chunks; index++) {
        store.putSync(CHUNK_PREFIX + index, chunks[index]);
      }
      for (let index = newManifest.chunks; index < oldCount; index++) {
        store.deleteSync(CHUNK_PREFIX + index);
      }
      store.putSync(MANIFEST_KEY, JSON.stringify(newManifest));
      await store.flush();
    } catch (error) {
      // 恢复写入前缓存并尝试落盘；任何失败都传给页面，不显示虚假的保存成功。
      try {
        for (let index = 0; index < snapshots.length; index++) {
          const snapshot = snapshots[index];
          if (snapshot.exists) {
            store.putSync(snapshot.key, snapshot.value);
          } else {
            store.deleteSync(snapshot.key);
          }
        }
        await store.flush();
      } catch (rollbackError) {
        try {
          await preferences.removePreferencesFromCache(this.context, this.storageName);
        } catch (cacheError) {
          // 继续上报原始保存失败，不能用清空存储来掩盖错误。
        }
        throw new Error('名片保存失败且无法确认磁盘状态，请稍后重试');
      }
      throw new Error('名片保存失败，已恢复操作前的数据，请重试');
    }
  }
}
