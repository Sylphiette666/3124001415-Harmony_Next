import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { AppSettings, ModelManifest } from '../model/Types';
import { apiClient } from './ApiClient';
import { ensureFolders, writeFile } from './MediaFiles';
import { scanStore } from '../model/ScanStore';
import { inferenceService } from './Inference';

export async function sha256(bytes: ArrayBuffer): Promise<string> {
  const md = cryptoFramework.createMd('SHA256');
  await md.update({ data: new Uint8Array(bytes) });
  const digest = await md.digest(); let value = '';
  digest.data.forEach((byte: number) => { value += byte.toString(16).padStart(2, '0'); }); return value;
}
export async function prepareBundledModel(context: common.Context, settings: AppSettings): Promise<AppSettings> {
  ensureFolders(context);
  if (settings.modelPath && fs.accessSync(settings.modelPath)) { return settings; }
  const path = context.filesDir + '/models/yolov13n-1.0.0.onnx';
  const data = await context.resourceManager.getRawFileContent('yolov13n.onnx');
  writeFile(path + '.part', data.slice().buffer as ArrayBuffer); fs.renameSync(path + '.part', path);
  const prepared: AppSettings = { endpoint: settings.endpoint, deviceId: settings.deviceId, deviceKey: settings.deviceKey,
    autoSync: settings.autoSync, modelPath: path, modelVersion: '1.0.0' };
  await scanStore.saveSettings(prepared); return prepared;
}
export async function updateModel(context: common.Context, current: AppSettings, manifest: ModelManifest): Promise<AppSettings> {
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$/.test(manifest.version) || !/^[a-f0-9]{64}$/.test(manifest.sha256) ||
      manifest.inputSize !== 640 || manifest.size < 1000 || manifest.size > 64000000 ||
      manifest.downloadUrl !== `/v1/models/${manifest.version}/file`) { throw new Error('模型清单无效，保留当前可用版本。'); }
  if (inferenceService.busy) { throw new Error('请等待当前识别完成，再更新模型。'); }
  const bytes = await apiClient.download(manifest.downloadUrl);
  if (bytes.byteLength !== manifest.size || await sha256(bytes) !== manifest.sha256) { throw new Error('模型长度或 SHA256 校验失败，已保留旧模型。'); }
  const target = context.filesDir + '/models/yolov13n-' + manifest.version + '-' + manifest.sha256.slice(0, 12) + '.onnx';
  const temporary = target + '.part';
  try {
    writeFile(temporary, bytes);
    await inferenceService.inspect(temporary);
    if (fs.accessSync(target)) { fs.unlinkSync(target); }
    fs.renameSync(temporary, target);
    const next: AppSettings = { endpoint: current.endpoint, deviceId: current.deviceId, deviceKey: current.deviceKey,
      autoSync: current.autoSync, modelPath: target, modelVersion: manifest.version };
    await scanStore.saveSettings(next); return next;
  } catch (error) {
    if (fs.accessSync(temporary)) { fs.unlinkSync(temporary); }
    throw error as Error;
  }
}
