export interface Detection {
  id: string;
  classId: number;
  name: string;
  score: number;
  x1: number;
  y1: number;
  x2: number;
  y2: number;
}
export interface Letterbox {
  width: number;
  height: number;
  inputSize: number;
  ratio: number;
  scaleX: number;
  scaleY: number;
  padX: number;
  padY: number;
  resizedWidth: number;
  resizedHeight: number;
}
export interface Timings {
  decodeMs: number;
  preprocessMs: number;
  loadMs: number;
  inferenceMs: number;
  postprocessMs: number;
  totalMs: number;
  uiDelayMs: number;
  mode: string;
}
export interface InferenceRequest {
  imagePath: string;
  modelPath: string;
  threshold: number;
  mode: string;
}
export interface InferenceResult {
  detections: Detection[];
  geometry: Letterbox;
  timings: Timings;
}
export interface ScanRecord {
  recordId: string;
  capturedAt: number;
  updatedAt: number;
  revision: number;
  imagePath: string;
  thumbnailPath: string;
  width: number;
  height: number;
  modelVersion: string;
  threshold: number;
  items: Detection[];
  timings: Timings;
  syncState: string;
  attempts: number;
  nextRetry: number;
  lastError: string;
}
export interface AppSettings {
  endpoint: string;
  deviceId: string;
  deviceKey: string;
  autoSync: boolean;
  modelPath: string;
  modelVersion: string;
}
export interface UploadRecord {
  recordId: string;
  capturedAt: number;
  updatedAt: number;
  revision: number;
  width: number;
  height: number;
  modelVersion: string;
  threshold: number;
  items: Detection[];
  thumbnailBase64: string;
}
export interface SyncAck { recordId: string; revision: number; status: string; }
export interface SyncResponse { accepted: SyncAck[]; }
export interface TokenResponse { accessToken: string; expiresIn: number; tokenType: string; }
export interface ModelManifest {
  version: string;
  sha256: string;
  size: number;
  inputSize: number;
  downloadUrl: string;
}
export interface CloudPage { records: UploadRecord[]; total: number; page: number; pageSize: number; }
export interface CategoryCount { name: string; count: number; }
export interface CloudStats { recordCount: number; objectCount: number; categories: CategoryCount[]; }
export const EMPTY_TIMINGS: Timings = { decodeMs: 0, preprocessMs: 0, loadMs: 0, inferenceMs: 0,
  postprocessMs: 0, totalMs: 0, uiDelayMs: 0, mode: 'TaskPool' };
