import { BoardMessage, MessageInput, MessageRepository, parseMessageInput, validMessageId } from '../model/BoardMessage';

export const BOARD_URL: string = 'resource://rawfile/message-board.html';
export const BOARD_PROXY_METHODS: string[] = ['submitMessage', 'requestHistory', 'deleteMessage', 'showToast'];
export const BOARD_PROXY_PERMISSION: string = '{"javascriptProxyPermission":{"urlPermissionList":' +
  '[{"scheme":"resource","host":"rawfile","port":"","path":"/message-board.html"}]}}';

export interface BoardTransport {
  evaluate: (script: string) => Promise<string>;
  toast: (message: string) => void;
  failed: (message: string) => void;
}
export class BoardEvent {
  kind: string = 'snapshot';
  requestId: string = '';
  message: string = '';
  messages: BoardMessage[] = [];
  sequence: number = 0;
}
interface BridgeReply { ok: boolean; message: string; }
function reply(ok: boolean, message: string = ''): string {
  const result: BridgeReply = { ok: ok, message: message }; return JSON.stringify(result);
}
export function isBoardUrl(url: string): boolean { return url === BOARD_URL; }
export function boardEventScript(event: BoardEvent): string {
  // Pass a JSON literal, never splice user text into executable code or innerHTML.
  const json = JSON.stringify(event).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
  return 'typeof window.MessageBoard === "object" && window.MessageBoard.receive(' + json + ')';
}

export class MessageBoardBridge {
  private repository: MessageRepository | undefined = undefined;
  private transport: BoardTransport | undefined = undefined;
  private active: boolean = false;
  private epoch: number = 0;
  private sequence: number = 0;
  private pending: Set<string> = new Set<string>();
  private lastToastAt: number = 0;

  configure(repository: MessageRepository, transport: BoardTransport): void {
    this.repository = repository; this.transport = transport;
  }
  beginPage(): void { this.active = false; this.epoch++; this.sequence = 0; this.pending.clear(); }
  dispose(): void { this.beginPage(); this.repository = undefined; this.transport = undefined; }
  private usable(): boolean { return this.active && this.repository !== undefined && this.transport !== undefined; }
  private errorText(error: Error): string { return error.message || '操作失败，请重试'; }

  async connect(): Promise<void> {
    if (!this.repository || !this.transport) { throw new Error('原生留言服务尚未初始化'); }
    this.active = true;
    await this.history(this.epoch);
  }
  private async send(event: BoardEvent, epoch: number): Promise<void> {
    if (epoch !== this.epoch || !this.usable()) { return; }
    event.sequence = ++this.sequence;
    const result = await this.transport!.evaluate(boardEventScript(event));
    if (epoch !== this.epoch || !this.usable()) { return; }
    if (result !== '1') { throw new Error('网页通信未就绪，请重新加载'); }
  }
  private async history(epoch: number): Promise<void> {
    const event = new BoardEvent();
    try { event.messages = await this.repository!.list(); }
    catch (error) { event.kind = 'error'; event.message = this.errorText(error as Error); }
    await this.send(event, epoch);
  }
  private failed(error: Error, epoch: number): void {
    if (epoch === this.epoch && this.usable()) {
      this.active = false; this.transport!.failed(this.errorText(error));
    }
  }
  requestHistory(): string {
    if (!this.usable()) { return reply(false, '留言板正在连接，请稍候或刷新'); }
    const epoch = this.epoch;
    this.history(epoch).catch((error: Error) => this.failed(error, epoch));
    return reply(true);
  }
  submitMessage(raw: string): string {
    if (!this.usable()) { return reply(false, '留言板尚未连接，请刷新后重试'); }
    let input: MessageInput;
    try { input = parseMessageInput(raw); } catch (error) { return reply(false, this.errorText(error as Error)); }
    if (this.pending.has(input.id)) { return reply(true); }
    if (this.pending.size >= 4) { return reply(false, '正在保存，请稍候再提交'); }
    const epoch = this.epoch;
    this.pending.add(input.id);
    this.save(input, epoch).catch((error: Error) => this.failed(error, epoch));
    return reply(true);
  }
  private async save(input: MessageInput, epoch: number): Promise<void> {
    const event = new BoardEvent(); event.requestId = input.id;
    try {
      event.messages = await this.repository!.add(input);
      event.kind = 'saved'; event.message = '留言已保存到本机';
    } catch (error) { event.kind = 'error'; event.message = this.errorText(error as Error); }
    try {
      await this.send(event, epoch);
      if (event.kind === 'saved' && epoch === this.epoch && this.usable()) { this.showToast(event.message); }
    } finally { if (epoch === this.epoch) { this.pending.delete(input.id); } }
  }
  deleteMessage(id: string): string {
    if (!this.usable() || !validMessageId(id)) { return reply(false, '留言板未就绪或留言编号不正确'); }
    const epoch = this.epoch;
    this.remove(id, epoch).catch((error: Error) => this.failed(error, epoch));
    return reply(true);
  }
  private async remove(id: string, epoch: number): Promise<void> {
    const event = new BoardEvent(); event.requestId = id;
    try {
      event.messages = await this.repository!.remove(id); event.kind = 'deleted'; event.message = '留言已删除';
    } catch (error) { event.kind = 'error'; event.message = this.errorText(error as Error); }
    await this.send(event, epoch);
  }
  showToast(message: string): string {
    if (!this.usable()) { return reply(false, '应用未连接'); }
    if (typeof message !== 'string' || !message.trim() || message.length > 80) { return reply(false, '提示内容需为 1 至 80 个字'); }
    if (Date.now() - this.lastToastAt < 800) { return reply(true); }
    try { this.transport!.toast(message.trim()); this.lastToastAt = Date.now(); return reply(true); }
    catch { return reply(false, '系统提示暂时不可用'); }
  }
  async notify(): Promise<void> {
    if (!this.usable()) { return; }
    const event = new BoardEvent(); event.kind = 'notice';
    event.message = '来自应用的通知：你的留言保存在本机，退出应用后仍可查看。';
    const epoch = this.epoch;
    try { await this.send(event, epoch); } catch (error) { this.failed(error as Error, epoch); }
  }
}
