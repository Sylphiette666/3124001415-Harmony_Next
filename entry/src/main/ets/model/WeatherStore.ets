import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { WeatherCacheEntry, WeatherStorage } from './WeatherController';

// Separate preferences file: weather never reads or writes student/contact information.
export class WeatherStore implements WeatherStorage {
  private context: common.Context;
  constructor(context: common.Context) { this.context = context; }
  private store(): preferences.Preferences {
    try { return preferences.getPreferencesSync(this.context, { name: 'course_weather_v1' }); }
    catch { throw new Error('天气存储暂时不可用'); }
  }
  private entries(): WeatherCacheEntry[] {
    let raw: string;
    try { raw = this.store().getSync('cities', '[]') as string; }
    catch { throw new Error('天气缓存读取失败'); }
    const entries = JSON.parse(raw) as WeatherCacheEntry[];
    if (!Array.isArray(entries)) { return []; }
    return entries.filter((item: WeatherCacheEntry) => item && typeof item.cityId === 'string' &&
      typeof item.raw === 'string' && item.raw.length <= 131072 && typeof item.savedAt === 'number').slice(0, 12);
  }
  read(cityId: string): WeatherCacheEntry | undefined { return this.entries().find((item: WeatherCacheEntry) => item.cityId === cityId); }
  async write(entry: WeatherCacheEntry): Promise<void> {
    let entries: WeatherCacheEntry[] = [];
    try { entries = this.entries(); } catch { /* Recover a damaged weather cache after a successful fetch. */ }
    entries = entries.filter((item: WeatherCacheEntry) => item.cityId !== entry.cityId);
    entries.unshift(entry);
    const store = this.store();
    try {
      store.putSync('cities', JSON.stringify(entries.slice(0, 12)));
      await store.flush();
    } catch { throw new Error('天气缓存保存失败'); }
  }
  lastCity(): string {
    try { return this.store().getSync('lastCity', '') as string; }
    catch { throw new Error('城市选择读取失败'); }
  }
  async select(cityId: string): Promise<void> {
    try { const store = this.store(); store.putSync('lastCity', cityId); await store.flush(); }
    catch { throw new Error('城市选择保存失败'); }
  }
}
