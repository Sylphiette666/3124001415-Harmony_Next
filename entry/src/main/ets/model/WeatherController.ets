import { WeatherCity, WeatherReport, WeatherFailure, parseWeather } from './WeatherData';
import { WeatherSource } from '../services/WeatherHttpClient';

export interface WeatherCacheEntry { cityId: string; raw: string; savedAt: number; }
export interface WeatherStorage {
  read(cityId: string): WeatherCacheEntry | undefined;
  write(entry: WeatherCacheEntry): Promise<void>;
  lastCity(): string;
  select(cityId: string): Promise<void>;
}
export class WeatherViewState {
  status: string = 'idle';
  message: string = '';
  storageWarning: string = '';
  report: WeatherReport | undefined = undefined;
  cached: boolean = false;
}

// Entire page state is replaced on each transition, avoiding nested @State mutations.
export class WeatherController {
  private serial: number = 0;
  private current: WeatherCity | undefined = undefined;
  private state: WeatherViewState = new WeatherViewState();
  private source: WeatherSource;
  private storage: WeatherStorage;
  private update: (state: WeatherViewState) => void;
  constructor(source: WeatherSource, storage: WeatherStorage, update: (state: WeatherViewState) => void) {
    this.source = source; this.storage = storage; this.update = update;
  }
  async load(city: WeatherCity): Promise<void> {
    this.current = city;
    const ticket = ++this.serial;
    this.source.cancel();
    const state = new WeatherViewState();
    state.status = 'loading'; state.message = '正在获取' + city.name + '的天气…';
    try {
      const cache = this.storage.read(city.id);
      if (cache && cache.cityId === city.id && Number.isFinite(cache.savedAt) &&
        cache.savedAt <= Date.now() && Date.now() - cache.savedAt <= 86400000) {
        state.report = parseWeather(cache.raw, city, cache.savedAt); state.cached = true;
      }
    } catch { state.storageWarning = '本地缓存不可用，正在尝试联网获取'; }
    this.state = state; this.update(state);
    try { await this.storage.select(city.id); } catch { state.storageWarning = '城市选择未能保存，下次打开请重新选择'; }
    if (ticket !== this.serial) { return; }
    try {
      const raw = await this.source.fetch(city);
      if (ticket !== this.serial) { return; }
      const report = parseWeather(raw, city);
      // Cache only validated data, and report disk errors independently of network success.
      try { await this.storage.write({ cityId: city.id, raw: raw, savedAt: report.fetchedAt }); }
      catch { state.storageWarning = '天气已更新，但未能保存离线缓存'; }
      if (ticket !== this.serial) { return; }
      const ready = new WeatherViewState();
      ready.status = 'success'; ready.report = report; ready.storageWarning = state.storageWarning;
      this.state = ready; this.update(ready);
    } catch (error) {
      if (ticket !== this.serial) { return; }
      const failed = new WeatherViewState();
      const failure = error instanceof WeatherFailure ? error : new WeatherFailure('network', '天气查询失败，请重试');
      failed.status = failure.kind === 'offline' ? 'offline' : 'error';
      failed.message = failure.message; failed.report = state.report; failed.cached = state.cached;
      failed.storageWarning = state.storageWarning;
      this.state = failed; this.update(failed);
    }
  }
  retry(): Promise<void> { return this.current ? this.load(this.current) : Promise.resolve(); }
  dispose(): void { this.serial++; this.source.cancel(); }
}
