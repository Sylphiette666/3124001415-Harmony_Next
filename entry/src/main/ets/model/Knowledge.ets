export interface CourseDocument {
  id: string; title: string; source: string; body: string; revision: number; updated: number;
}
export interface Segment {
  id: string; documentId: string; title: string; source: string;
  text: string; start: number; end: number; revision: number; vector: number[]; model: string;
}
export interface Evidence { segment: Segment; score: number; }
@Observed
export class ChatMessage {
  private static sequence: number = 0;
  id: string = `${Date.now()}-${++ChatMessage.sequence}`;
  question: string = '';
  answer: string = '';
  evidence: Evidence[] = [];
  state: string = '检索中';
  error: string = '';
  revision: number = 0;
  mode: string = '';
  constructor(question: string, cloud: boolean, revision: number) {
    this.question = question; this.revision = revision;
    this.mode = cloud ? '云端生成 · 混合检索' : '本地资料摘录 · 离线可用';
  }
}
export interface AppSettings { endpoint: string; cloud: boolean; }

export function validateDocument(title: string, body: string): void {
  if (!title.trim() || title.trim().length > 100) { throw new Error('请填写 1—100 字的资料名称'); }
  if (body.trim().length < 20 || body.length > 60000) { throw new Error('正文需为 20—60000 字'); }
}

// Overlapping windows preserve exact offsets into the saved document body.
export function splitDocument(doc: CourseDocument): Segment[] {
  const result: Segment[] = [];
  let start = 0;
  while (start < doc.body.length) {
    let end = Math.min(doc.body.length, start + 440);
    if (end < doc.body.length) {
      for (let cut = end; cut > start + 220; cut--) {
        if ('。！？\n'.includes(doc.body.charAt(cut - 1))) { end = cut; break; }
      }
    }
    // Do not cut a UTF-16 surrogate pair.
    if (end < doc.body.length && doc.body.charCodeAt(end - 1) >= 0xD800 && doc.body.charCodeAt(end - 1) <= 0xDBFF) { end--; }
    const text = doc.body.slice(start, end);
    if (text.trim()) {
      result.push({ id: `${doc.id}:${doc.revision}:${start}`, documentId: doc.id, title: doc.title,
        source: doc.source, text: text, start: start, end: end, revision: doc.revision, vector: [], model: '' });
    }
    if (end === doc.body.length) { break; }
    start = Math.max(start + 1, end - 60);
    if (doc.body.charCodeAt(start) >= 0xDC00 && doc.body.charCodeAt(start) <= 0xDFFF) { start++; }
  }
  return result;
}

export function terms(text: string): string[] {
  const normalized = text.toLowerCase().replace(/怎样|怎么|如何|什么|为什么|请问|一下|告诉我|课程|资料|的|了|呢|吗/g, ' ');
  const result: string[] = [];
  const latin = normalized.match(/[a-z][a-z0-9_-]+/g) || [];
  latin.forEach((term: string) => { if (!result.includes(term)) { result.push(term); } });
  const groups = normalized.match(/[\u4e00-\u9fff]+/g) || [];
  groups.forEach((group: string) => {
    if (group.length === 1) { return; }
    for (let i = 0; i < group.length - 1; i++) {
      const term = group.slice(i, i + 2); if (!result.includes(term)) { result.push(term); }
    }
  });
  const pairs: string[][] = [['数据库', 'rdb'], ['网页', 'arkweb'], ['桥接', 'jsbridge'], ['意图', 'arkaf'],
    ['向量', 'embedding'], ['大模型', 'llm'], ['后台', 'background'], ['播放器', 'avplayer']];
  pairs.forEach((pair: string[]) => {
    if (normalized.includes(pair[0]) || normalized.includes(pair[1])) {
      pair.forEach((term: string) => { if (!result.includes(term)) { result.push(term); } });
    }
  });
  return result;
}

export function cosine(a: number[], b: number[]): number {
  if (a.length === 0 || a.length !== b.length) { return 0; }
  let dot = 0; let aa = 0; let bb = 0;
  for (let i = 0; i < a.length; i++) {
    if (!Number.isFinite(a[i]) || !Number.isFinite(b[i])) { return 0; }
    dot += a[i] * b[i]; aa += a[i] * a[i]; bb += b[i] * b[i];
  }
  return aa > 0 && bb > 0 ? dot / Math.sqrt(aa * bb) : 0;
}

export function retrieve(question: string, segments: Segment[], queryVector: number[] = [], model: string = ''): Evidence[] {
  const query = terms(question);
  const lexical: Evidence[] = [];
  const semantic: Evidence[] = [];
  segments.forEach((segment: Segment) => {
    const haystack = segment.text.toLowerCase(); const title = segment.title.toLowerCase();
    let score = 0;
    query.forEach((term: string) => {
      const df = segments.filter((s: Segment) => (s.title + s.text).toLowerCase().includes(term)).length;
      const idf = Math.log(1 + (segments.length + 1) / (df + 1));
      if (haystack.includes(term)) { score += idf; }
      if (title.includes(term)) { score += 2.2 * idf; }
    });
    if (score > 0) { lexical.push({ segment: segment, score: score }); }
    if (model && segment.model === model) {
      const similarity = cosine(queryVector, segment.vector);
      if (similarity >= 0.3) { semantic.push({ segment: segment, score: similarity }); }
    }
  });
  lexical.sort((a: Evidence, b: Evidence) => b.score - a.score);
  semantic.sort((a: Evidence, b: Evidence) => b.score - a.score);
  // RRF fuses ranks, so incomparable keyword scores and cosine values are not added.
  const combined: Evidence[] = [];
  [lexical, semantic].forEach((list: Evidence[]) => {
    list.slice(0, 12).forEach((item: Evidence, index: number) => {
      const found = combined.find((e: Evidence) => e.segment.id === item.segment.id);
      if (found) { found.score += 1 / (60 + index + 1); }
      else { combined.push({ segment: item.segment, score: 1 / (60 + index + 1) }); }
    });
  });
  combined.sort((a: Evidence, b: Evidence) => b.score - a.score);
  return combined.slice(0, 4);
}

export function localAnswer(question: string, evidence: Evidence[]): string {
  if (evidence.length === 0) { return '未检索到相关内容。请换一个课程关键词，或先在资料库中添加相关资料。'; }
  const query = terms(question);
  const paragraphs: string[] = [];
  evidence.slice(0, 3).forEach((item: Evidence, index: number) => {
    const sentences = item.segment.text.match(/[^。！？\n]+[。！？]?/g) || [item.segment.text];
    const relevant = sentences.filter((sentence: string) => query.some((term: string) => sentence.toLowerCase().includes(term)));
    const excerpt = (relevant.length > 0 ? relevant : sentences).slice(0, 3).join('').trim();
    paragraphs.push(`${index + 1}. ${excerpt} [${index + 1}]`);
  });
  return '依据当前本地资料，相关要点如下：\n\n' + paragraphs.join('\n\n') + '\n\n以上为原文摘录整理，可点击下方来源查看完整上下文。';
}

export function nextCodePoint(text: string, offset: number): number {
  const high = text.charCodeAt(offset);
  return high >= 0xD800 && high <= 0xDBFF && offset + 1 < text.length ? offset + 2 : offset + 1;
}

export function extractQuestion(uri: string, parameter: string = ''): string {
  if (parameter.trim()) { return parameter.trim().slice(0, 600); }
  if (!/^courselearning:\/\/ask(?:[?]|$)/.test(uri)) { return ''; }
  const match = /[?&]question=([^&]*)/.exec(uri);
  if (!match) { return ''; }
  try { return decodeURIComponent(match[1].replace(/\+/g, ' ')).trim().slice(0, 600); } catch { return ''; }
}
