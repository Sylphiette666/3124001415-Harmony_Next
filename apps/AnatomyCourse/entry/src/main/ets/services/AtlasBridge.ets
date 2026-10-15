import { common } from '@kit.AbilityKit';
export interface AtlasEvent { type: string; id?: string; name?: string; system?: string; conceptId?: string; description?: string; progress?: number; message?: string; }
export interface AtlasConcept { id: string; name: string; elements: string[]; }
export function parseConcepts(json: string): AtlasConcept[] {
  // ArkWeb can JSON-encode the JavaScript string result again at the native boundary.
  const parsed = JSON.parse(json) as AtlasConcept[] | string;
  const result = typeof parsed === 'string' ? JSON.parse(parsed) as AtlasConcept[] : parsed;
  if (!Array.isArray(result)) { throw new Error('网页搜索结果格式不正确'); }
  return result.filter((c: AtlasConcept) => typeof c.id === 'string' && typeof c.name === 'string' && Array.isArray(c.elements)).slice(0, 80);
}
export class AtlasProxy {
  callback: (event: AtlasEvent) => void = () => {};
  onEvent(json: string): void {
    if (json.length > 20000) { return; }
    try { const event = JSON.parse(json) as AtlasEvent; this.callback(event); } catch { /* Reject malformed messages. */ }
  }
}
export function localResponse(context: common.Context, url: string): WebResourceResponse {
  const response = new WebResourceResponse();
  response.setResponseEncoding('utf-8');
  try {
    if (!url.startsWith('https://atlas.local/')) { throw new Error('External resource blocked'); }
    const path = decodeURIComponent(url.slice('https://atlas.local/'.length).split('?')[0]);
    if (!path || path.includes('..') || path.includes('\\') || path.includes('\0')) { throw new Error('Invalid resource'); }
    const data = context.resourceManager.getRawFileContentSync('atlas/' + path);
    response.setResponseData(data.buffer as ArrayBuffer);
    response.setResponseCode(200); response.setReasonMessage('OK');
    let mime = 'application/octet-stream';
    if (path.endsWith('.html')) { mime = 'text/html'; }
    else if (path.endsWith('.js')) { mime = 'text/javascript'; }
    else if (path.endsWith('.css')) { mime = 'text/css'; }
    else if (path.endsWith('.json')) { mime = 'application/json'; }
    else if (path.endsWith('.svg')) { mime = 'image/svg+xml'; }
    response.setResponseMimeType(mime);
    response.setResponseHeader([{ headerKey: 'Cache-Control', headerValue: 'no-store' }]);
  } catch { response.setResponseCode(404); response.setReasonMessage('Not Found'); response.setResponseData('Local resource unavailable'); }
  return response;
}
