import { taskpool } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import detector from 'libdetector.so';
import { InferenceRequest, InferenceResult } from '../model/Types';
import { letterboxGeometry, preprocess, postprocess } from '../model/DetectionMath';

@Concurrent
export async function inferenceTask(request: InferenceRequest): Promise<InferenceResult> {
  const started = Date.now(); const source = image.createImageSource(request.imagePath);
  let pixels: image.PixelMap | undefined = undefined;
  try {
    const info = await source.getImageInfo();
    if (info.size.width * info.size.height > 16000000) { throw new Error('图片过大，请选择 1600 万像素以内的图片。'); }
    pixels = await source.createPixelMap({ desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
    const decodedInfo = await pixels.getImageInfo();
    const rgba = new ArrayBuffer(decodedInfo.size.width * decodedInfo.size.height * 4);
    await pixels.readPixelsToBuffer(rgba);
    const decoded = Date.now();
    const geometry = letterboxGeometry(decodedInfo.size.width, decodedInfo.size.height);
    const input = preprocess(new Uint8Array(rgba), geometry); const prepared = Date.now();
    const output = detector.infer(request.modelPath, input.buffer as ArrayBuffer); const inferred = Date.now();
    const detections = postprocess(new Float32Array(output.data), output.dims, geometry, request.threshold);
    const ended = Date.now();
    return { detections: detections, geometry: geometry,
      timings: { decodeMs: decoded - started, preprocessMs: prepared - decoded, loadMs: output.loadMs,
        inferenceMs: output.inferenceMs, postprocessMs: ended - inferred, totalMs: ended - started,
        uiDelayMs: 0, mode: request.mode } };
  } finally { if (pixels) { await pixels.release(); } await source.release(); }
}

@Concurrent
export function inspectModelTask(path: string): string {
  const info = detector.inspect(path);
  return `${info.runtime} · ${info.input} → ${info.output} [${info.dims.join(',')}]`;
}

export class InferenceService {
  private running: boolean = false;
  get busy(): boolean { return this.running; }
  async run(request: InferenceRequest): Promise<InferenceResult> {
    if (this.running) { throw new Error('正在识别，请等待本次任务完成。'); }
    this.running = true;
    let lastTick = Date.now(); let largestDelay = 0;
    const heartbeat = setInterval(() => { const now = Date.now(); largestDelay = Math.max(largestDelay, now - lastTick - 50); lastTick = now; }, 50);
    try {
      const result = request.mode === '同步' ? await inferenceTask(request) :
        await taskpool.execute(new taskpool.Task(inferenceTask, request)) as InferenceResult;
      // Let the heartbeat observe a synchronous main-thread stall before clearing it.
      await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 60); });
      result.timings.uiDelayMs = Math.max(0, largestDelay);
      return result;
    } finally { clearInterval(heartbeat); this.running = false; }
  }
  async inspect(path: string): Promise<string> {
    if (this.running) { throw new Error('请等待识别完成后检查模型。'); }
    return await taskpool.execute(new taskpool.Task(inspectModelTask, path)) as string;
  }
}
export const inferenceService = new InferenceService();
