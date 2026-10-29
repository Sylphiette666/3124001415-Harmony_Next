import { http } from '@kit.NetworkKit';
import { AppSettings, TokenResponse } from '../model/Types';

interface ErrorInfo { code: string; message: string; }
interface ErrorResponse { error: ErrorInfo; }

export function validateEndpoint(value: string): string {
  const endpoint = value.trim().replace(/\/+$/, '');
  if (!/^https:\/\/[A-Za-z0-9.-]+(?::[0-9]{1,5})?$/.test(endpoint) &&
      !/^http:\/\/(127\.0\.0\.1|localhost)(?::[0-9]{1,5})?$/.test(endpoint)) {
    throw new Error('请输入 HTTPS 服务地址。本地模拟器调试可使用 http://127.0.0.1:8765。');
  }
  return endpoint;
}

export class ApiClient {
  private endpoint: string = '';
  private deviceId: string = '';
  private deviceKey: string = '';
  private token: string = '';
  private expiresAt: number = 0;
  private authenticating: Promise<void> | undefined = undefined;
  private generation: number = 0;
  configure(settings: AppSettings): void {
    if (this.endpoint !== settings.endpoint || this.deviceId !== settings.deviceId || this.deviceKey !== settings.deviceKey) {
      this.generation++; this.token = ''; this.expiresAt = 0; this.authenticating = undefined;
    }
    this.endpoint = settings.endpoint; this.deviceId = settings.deviceId; this.deviceKey = settings.deviceKey;
  }
  get configured(): boolean { return !!this.endpoint && !!this.deviceId && this.deviceKey.length >= 16; }
  private async raw(path: string, method: http.RequestMethod, body: string = '', auth: string = '', binary: boolean = false): Promise<http.HttpResponse> {
    const endpoint = validateEndpoint(this.endpoint); const generation = this.generation;
    const request = http.createHttp();
    try {
      const result = await request.request(endpoint + path, {
        method: method, header: { 'Content-Type': 'application/json', 'Authorization': auth ? 'Bearer ' + auth : '' },
        extraData: body, connectTimeout: 8000, readTimeout: binary ? 120000 : 15000,
        expectDataType: binary ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
        usingCache: false, maxLimit: binary ? 64000000 : 4500000
      });
      if (generation !== this.generation) { throw new Error('连接配置已更改，请重试。'); }
      return result;
    } catch (error) {
      const message = (error as Error).message || '';
      if (message.includes('配置')) { throw error as Error; }
      throw new Error('无法连接服务。请检查网络、服务地址及服务是否启动，待传记录会保留。');
    } finally { request.destroy(); }
  }
  private check(response: http.HttpResponse): void {
    if (response.responseCode >= 200 && response.responseCode < 300) { return; }
    let message = `服务请求失败（${response.responseCode}），请稍后重试。`;
    if (typeof response.result === 'string') {
      try { const detail = JSON.parse(response.result) as ErrorResponse; if (detail.error && detail.error.message) { message = detail.error.message; } } catch {}
    }
    throw new Error(message);
  }
  private async authenticate(): Promise<void> {
    if (!this.configured) { throw new Error('请先在设置中填写设备标识、密钥及服务地址。'); }
    if (this.token && Date.now() < this.expiresAt) { return; }
    if (this.authenticating) { return this.authenticating; }
    const generation = this.generation;
    const job = (async () => {
      const response = await this.raw('/v1/auth/token', http.RequestMethod.POST,
        JSON.stringify({ deviceId: this.deviceId, deviceKey: this.deviceKey }));
      this.check(response);
      const data = JSON.parse(response.result as string) as TokenResponse;
      if (!data.accessToken || !Number.isFinite(data.expiresIn) || data.expiresIn <= 0) { throw new Error('鉴权响应无效，请检查服务。'); }
      if (generation !== this.generation) { throw new Error('连接配置已更改，请重试。'); }
      this.token = data.accessToken; this.expiresAt = Date.now() + Math.max(0, data.expiresIn * 1000 - 5000);
    })();
    this.authenticating = job;
    try { await job; } finally { if (this.authenticating === job) { this.authenticating = undefined; } }
  }
  async request<T>(path: string, method: http.RequestMethod = http.RequestMethod.GET, body: string = ''): Promise<T> {
    await this.authenticate();
    let response = await this.raw(path, method, body, this.token);
    if (response.responseCode === 401) {
      this.token = ''; this.expiresAt = 0; await this.authenticate(); response = await this.raw(path, method, body, this.token);
    }
    this.check(response); return JSON.parse(response.result as string) as T;
  }
  async download(path: string): Promise<ArrayBuffer> {
    await this.authenticate();
    let response = await this.raw(path, http.RequestMethod.GET, '', this.token, true);
    if (response.responseCode === 401) {
      this.token = ''; this.expiresAt = 0; await this.authenticate(); response = await this.raw(path, http.RequestMethod.GET, '', this.token, true);
    }
    this.check(response); return response.result as ArrayBuffer;
  }
}
export const apiClient = new ApiClient();
