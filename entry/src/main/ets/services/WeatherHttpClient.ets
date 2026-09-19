import { connection, http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { WeatherCity, WeatherFailure } from '../model/WeatherData';

export interface WeatherSource {
  fetch(city: WeatherCity): Promise<string>;
  cancel(): void;
}

export function weatherUrl(city: WeatherCity): string {
  return 'https://api.open-meteo.com/v1/forecast?latitude=' + city.latitude.toString() +
    '&longitude=' + city.longitude.toString() +
    '&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,wind_direction_10m' +
    '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max' +
    '&timezone=Asia%2FShanghai&temperature_unit=celsius&wind_speed_unit=ms&forecast_days=7';
}

export class WeatherHttpClient implements WeatherSource {
  private active: http.HttpRequest | undefined = undefined;
  private generation: number = 0;
  private isOffline(): boolean {
    try { return !connection.hasDefaultNetSync(); } catch { return false; }
  }
  cancel(): void {
    this.generation++;
    const request = this.active;
    this.active = undefined;
    if (request) { request.destroy(); }
  }
  async fetch(city: WeatherCity): Promise<string> {
    this.cancel();
    const generation = this.generation;
    if (this.isOffline()) { throw new WeatherFailure('offline', '当前无网络，请连接 WLAN 或移动网络后重试'); }
    const request = http.createHttp();
    this.active = request;
    try {
      const response = await request.request(weatherUrl(city), {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 6000,
        readTimeout: 10000,
        maxLimit: 128 * 1024,
        usingCache: false
      });
      if (generation !== this.generation) { throw new WeatherFailure('cancelled', '请求已取消'); }
      if (response.responseCode === 429) { throw new WeatherFailure('server', '查询较频繁，请稍后重试'); }
      if (response.responseCode !== 200) { throw new WeatherFailure('server', '天气服务暂时不可用，请稍后重试'); }
      if (typeof response.result !== 'string') { throw new WeatherFailure('data', '天气数据格式异常，请重试'); }
      return response.result;
    } catch (error) {
      if (generation !== this.generation) { throw new WeatherFailure('cancelled', '请求已取消'); }
      if (error instanceof WeatherFailure) { throw error; }
      if (this.isOffline()) { throw new WeatherFailure('offline', '网络已断开，请连接网络后重试'); }
      const code = (error as BusinessError).code;
      if (code === 2300028) { throw new WeatherFailure('timeout', '连接超时，请检查网络后重试'); }
      throw new WeatherFailure('network', '连接天气服务失败，请检查网络后重试');
    } finally {
      // cancel() already destroys an obsolete request. Never destroy its replacement.
      if (this.active === request) { this.active = undefined; request.destroy(); }
    }
  }
}
