import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Evidence } from '../model/Knowledge';

interface StreamEvent { delta?: string; error?: string; done?: boolean; }
export interface Embeddings { vectors: number[][]; model: string; }
interface EmbeddingBody { texts: string[]; }
interface ContextItem { number: number; title: string; text: string; }
interface AnswerBody { question: string; context: ContextItem[]; }

export class CloudClient {
  private active: http.HttpRequest | undefined = undefined;
  cancel(): void { if (this.active) { this.active.destroy(); this.active = undefined; } }
  private url(endpoint: string, path: string): string {
    if (!/^https:\/\/[^\s/?#]+(?::\d+)?(?:\/[^\s?#]*)?$/.test(endpoint)) { throw new Error('请填写有效的 HTTPS 服务地址'); }
    return endpoint.replace(/\/$/, '') + path;
  }
  async embeddings(endpoint: string, texts: string[]): Promise<Embeddings> {
    const client = http.createHttp(); this.active = client;
    const body: EmbeddingBody = { texts: texts };
    try {
      const result = await client.request(this.url(endpoint, '/embeddings'), { method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' }, extraData: JSON.stringify(body), connectTimeout: 10000, readTimeout: 60000 });
      if (result.responseCode !== 200) { throw new Error(`向量服务失败（${result.responseCode}）`); }
      const parsed = JSON.parse(result.result as string) as Embeddings;
      if (!parsed.model || !Array.isArray(parsed.vectors) || parsed.vectors.length !== texts.length ||
        parsed.vectors.some((v: number[]) => !Array.isArray(v) || v.length === 0 || v.some((n: number) => !Number.isFinite(n)))) {
        throw new Error('向量服务数据格式错误');
      }
      return parsed;
    } finally { client.destroy(); if (this.active === client) { this.active = undefined; } }
  }
  async answer(endpoint: string, question: string, evidence: Evidence[], delta: (text: string) => void): Promise<void> {
    const client = http.createHttp(); this.active = client;
    let buffer = ''; let completed = false; let streamError = '';
    const decoder = util.TextDecoder.create('utf-8');
    const consume = (text: string): void => {
      buffer += text.replace(/\r/g, '');
      if (buffer.length > 200000) { streamError = '回答超出长度限制'; return; }
      let boundary = buffer.indexOf('\n\n');
      while (boundary >= 0) {
        const block = buffer.slice(0, boundary); buffer = buffer.slice(boundary + 2);
        const data = block.split('\n').filter((line: string) => line.startsWith('data:')).map((line: string) => line.slice(5).trim()).join('\n');
        if (data) {
          try { const event = JSON.parse(data) as StreamEvent;
            if (event.error) { streamError = event.error; }
            if (event.delta && !streamError) { delta(event.delta); }
            if (event.done) { completed = true; }
          } catch { streamError = '服务返回了无法解析的流式数据'; }
        }
        boundary = buffer.indexOf('\n\n');
      }
    };
    client.on('dataReceive', (data: ArrayBuffer) => { consume(decoder.decodeToString(new Uint8Array(data), { stream: true })); });
    const body: AnswerBody = { question: question, context: evidence.map((e: Evidence, i: number): ContextItem => ({ number: i + 1, title: e.segment.title, text: e.segment.text })) };
    try {
      const code = await client.requestInStream(this.url(endpoint, '/answer'), { method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Accept': 'text/event-stream' }, extraData: JSON.stringify(body), connectTimeout: 10000, readTimeout: 60000 });
      consume(decoder.decodeToString(new Uint8Array(0), { stream: false }));
      if (code !== 200) { throw new Error(`生成服务请求失败（${code}）`); }
      if (streamError) { throw new Error(streamError); }
      if (!completed) { throw new Error('连接提前结束，回答未完成，请重试'); }
    } finally { client.destroy(); if (this.active === client) { this.active = undefined; } }
  }
}
