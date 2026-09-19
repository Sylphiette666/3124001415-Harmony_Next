export class WeatherCity {
  id: string;
  province: string;
  name: string;
  latitude: number;
  longitude: number;
  constructor(id: string, province: string, name: string, latitude: number, longitude: number) {
    this.id = id; this.province = province; this.name = name;
    this.latitude = latitude; this.longitude = longitude;
  }
}

export interface CurrentWeatherDto {
  time: string;
  temperature_2m: number | null;
  relative_humidity_2m: number | null;
  apparent_temperature: number | null;
  weather_code: number | null;
  wind_speed_10m: number | null;
  wind_direction_10m: number | null;
  is_day: number | null;
}
export interface DailyWeatherDto {
  time: string[];
  weather_code: (number | null)[];
  temperature_2m_max: (number | null)[];
  temperature_2m_min: (number | null)[];
  precipitation_probability_max: (number | null)[];
  wind_speed_10m_max: (number | null)[];
}
export interface WeatherDto {
  current: CurrentWeatherDto;
  daily: DailyWeatherDto;
  utc_offset_seconds: number;
}
export class ForecastDay {
  date: string = '';
  condition: string = '';
  icon: string = 'cloud';
  high: string = '—';
  low: string = '—';
  rain: string = '—';
  wind: string = '—';
}
export class WeatherReport {
  cityId: string = '';
  province: string = '';
  cityName: string = '';
  observedAt: string = '';
  fetchedAt: number = 0;
  temperature: string = '—';
  feelsLike: string = '—';
  humidity: string = '—';
  condition: string = '';
  icon: string = 'cloud';
  wind: string = '—';
  direction: string = '—';
  days: ForecastDay[] = [];
}
export class WeatherFailure extends Error {
  kind: string;
  constructor(kind: string, message: string) { super(message); this.kind = kind; }
}
export interface WeatherCodeLabel { label: string; icon: string; }

export function weatherLabel(code: number | null, isDay: boolean = true): WeatherCodeLabel {
  switch (code) {
    case 0: return { label: '晴', icon: isDay ? 'sun' : 'moon' };
    case 1: return { label: '晴间多云', icon: 'cloud' };
    case 2: return { label: '多云', icon: 'cloud' };
    case 3: return { label: '阴', icon: 'cloud' };
    case 45: case 48: return { label: '雾', icon: 'fog' };
    case 51: case 53: case 55: return { label: '毛毛雨', icon: 'rain' };
    case 56: case 57: case 66: case 67: return { label: '冻雨', icon: 'rain' };
    case 61: return { label: '小雨', icon: 'rain' };
    case 63: return { label: '中雨', icon: 'rain' };
    case 65: return { label: '大雨', icon: 'rain' };
    case 71: return { label: '小雪', icon: 'snow' };
    case 73: return { label: '中雪', icon: 'snow' };
    case 75: return { label: '大雪', icon: 'snow' };
    case 77: return { label: '雪粒', icon: 'snow' };
    case 80: case 81: case 82: return { label: '阵雨', icon: 'rain' };
    case 85: case 86: return { label: '阵雪', icon: 'snow' };
    case 95: return { label: '雷雨', icon: 'storm' };
    case 96: case 99: return { label: '雷雨伴冰雹', icon: 'storm' };
    default: return { label: '天气状况暂无', icon: 'cloud' };
  }
}

function validNumber(value: number | null, min: number, max: number): boolean {
  return typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
}
export function temperatureText(value: number | null): string {
  return validNumber(value, -100, 70) ? Math.round(value as number).toString() + '°' : '—';
}
export function windLevel(speed: number | null): string {
  if (!validNumber(speed, 0, 150)) { return '—'; }
  const limits: number[] = [0.3, 1.6, 3.4, 5.5, 8, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7];
  let level = 0;
  while (level < limits.length && (speed as number) >= limits[level]) { level++; }
  return level.toString() + (level === 12 ? '级及以上' : '级');
}
export function windDirection(degrees: number | null): string {
  if (!validNumber(degrees, 0, 360)) { return '—'; }
  const names: string[] = ['北风', '东北风', '东风', '东南风', '南风', '西南风', '西风', '西北风'];
  return names[Math.round((degrees as number) / 45) % 8];
}

// Time strings are interpreted in the explicitly requested Asia/Shanghai time zone.
export function parseWeather(raw: string, city: WeatherCity, fetchedAt: number = Date.now()): WeatherReport {
  try {
    const dto = JSON.parse(raw) as WeatherDto;
    const current = dto.current;
    const daily = dto.daily;
    if (!current || !daily || dto.utc_offset_seconds !== 28800 ||
      typeof current.time !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(current.time) ||
      !validNumber(current.temperature_2m, -100, 70) ||
      !Array.isArray(daily.time) || daily.time.length < 3 || daily.time.length > 16) {
      throw new Error('Invalid weather data');
    }
    const arrays: (number | null)[][] = [daily.weather_code, daily.temperature_2m_max,
      daily.temperature_2m_min, daily.precipitation_probability_max, daily.wind_speed_10m_max];
    if (arrays.some((values: (number | null)[]) => !Array.isArray(values) || values.length !== daily.time.length)) {
      throw new Error('Invalid forecast arrays');
    }
    const report = new WeatherReport();
    report.cityId = city.id; report.province = city.province; report.cityName = city.name;
    report.observedAt = current.time; report.fetchedAt = fetchedAt;
    report.temperature = temperatureText(current.temperature_2m);
    report.feelsLike = temperatureText(current.apparent_temperature);
    report.humidity = validNumber(current.relative_humidity_2m, 0, 100) ?
      Math.round(current.relative_humidity_2m as number).toString() + '%' : '—';
    const label = weatherLabel(current.weather_code, current.is_day !== 0);
    report.condition = label.label; report.icon = label.icon;
    report.wind = windLevel(current.wind_speed_10m);
    report.direction = windDirection(current.wind_direction_10m);
    for (let index = 0; index < Math.min(7, daily.time.length); index++) {
      const date = daily.time[index];
      if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
        !Number.isFinite(Date.parse(date + 'T00:00:00+08:00')) ||
        (index > 0 && date <= daily.time[index - 1])) { throw new Error('Invalid forecast date'); }
      const day = new ForecastDay();
      const dayLabel = weatherLabel(daily.weather_code[index]);
      day.date = date; day.condition = dayLabel.label; day.icon = dayLabel.icon;
      day.high = temperatureText(daily.temperature_2m_max[index]);
      day.low = temperatureText(daily.temperature_2m_min[index]);
      const rain = daily.precipitation_probability_max[index];
      day.rain = validNumber(rain, 0, 100) ? Math.round(rain as number).toString() + '%' : '—';
      day.wind = windLevel(daily.wind_speed_10m_max[index]);
      report.days.push(day);
    }
    return report;
  } catch {
    throw new WeatherFailure('data', '天气数据暂时不完整，请稍后重试');
  }
}

export function forecastDateLabel(date: string, now: number = Date.now()): string {
  const today = new Date(now + 8 * 3600000).toISOString().slice(0, 10);
  const tomorrow = new Date(now + 32 * 3600000).toISOString().slice(0, 10);
  if (date === today) { return '今天'; }
  if (date === tomorrow) { return '明天'; }
  const weekday = new Date(date + 'T00:00:00Z').getUTCDay();
  return ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][weekday];
}

export function weatherIconPath(icon: string): string { return 'weather_' + icon + '.svg'; }
