export interface TensorResult {
  data: ArrayBuffer;
  dims: number[];
  loadMs: number;
  inferenceMs: number;
}
export interface ModelInfo {
  input: string;
  output: string;
  dims: number[];
  runtime: string;
}
export const infer: (path: string, input: ArrayBuffer) => TensorResult;
export const inspect: (path: string) => ModelInfo;
