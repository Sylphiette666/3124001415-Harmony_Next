export const MAX_MESSAGES: number = 100;
export const MAX_AUTHOR: number = 24;
export const MAX_BODY: number = 500;

export interface MessageInput { id: string; author: string; body: string; }
export interface BoardMessage extends MessageInput { createdAt: number; }
export interface MessageRepository {
  list(): Promise<BoardMessage[]>;
  add(input: MessageInput): Promise<BoardMessage[]>;
  remove(id: string): Promise<BoardMessage[]>;
}
export function validMessageId(id: string): boolean {
  return typeof id === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(id);
}
export function validateMessage(input: MessageInput): string {
  if (!input || typeof input !== 'object' || !validMessageId(input.id)) { return '留言请求格式不正确，请重试'; }
  if (typeof input.author !== 'string' || !input.author.trim()) { return '请填写称呼'; }
  if (input.author.trim().length > MAX_AUTHOR) { return '称呼最多 24 个字'; }
  if (typeof input.body !== 'string' || !input.body.trim()) { return '请填写留言内容'; }
  if (input.body.trim().length > MAX_BODY) { return '留言最多 500 个字'; }
  return '';
}
export function parseMessageInput(raw: string): MessageInput {
  if (typeof raw !== 'string' || raw.length > 4096) { throw new Error('留言请求过大或格式不正确'); }
  let input: MessageInput;
  try { input = JSON.parse(raw) as MessageInput; } catch { throw new Error('留言请求无法解析'); }
  const error = validateMessage(input);
  if (error) { throw new Error(error); }
  return { id: input.id, author: input.author.trim(), body: input.body.trim() };
}
