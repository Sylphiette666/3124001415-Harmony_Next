import { common } from '@kit.AbilityKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { util } from '@kit.ArkTS';

export function writeFile(path: string, buffer: ArrayBuffer): void {
  const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
  try { if (fs.writeSync(file.fd, buffer) !== buffer.byteLength) { throw new Error('文件写入未完成，请重试。'); } } finally { fs.closeSync(file); }
}
export function readFile(path: string): ArrayBuffer {
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try { const size = fs.statSync(file.fd).size; const buffer = new ArrayBuffer(size); if (fs.readSync(file.fd, buffer) !== size) { throw new Error('文件读取未完成，请重试。'); } return buffer; }
  finally { fs.closeSync(file); }
}
export function ensureFolders(context: common.Context): void {
  for (const folder of ['images', 'thumbs', 'models']) {
    const path = context.filesDir + '/' + folder;
    if (!fs.accessSync(path)) { fs.mkdirSync(path); }
  }
}
export async function importPhoto(context: common.Context, uri: string): Promise<string> {
  ensureFolders(context);
  const source = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  const path = context.filesDir + '/images/photo-' + util.generateRandomUUID() + '.jpg';
  try {
    if (fs.statSync(source.fd).size > 40000000) { throw new Error('图片文件过大，请选择 40MB 以内的图片。'); }
    // Copy to app storage: picker URI permissions need not survive a restart.
    const target = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try { fs.copyFileSync(source.fd, target.fd); } finally { fs.closeSync(target); }
    return path;
  } finally { fs.closeSync(source); }
}
export async function makeThumbnail(context: common.Context, path: string, id: string): Promise<string> {
  const source = image.createImageSource(path); let pixel: image.PixelMap | undefined = undefined;
  const packer = image.createImagePacker();
  try {
    const info = await source.getImageInfo(); const ratio = Math.min(1, 240 / Math.max(info.size.width, info.size.height));
    pixel = await source.createPixelMap({ desiredSize: { width: Math.max(1, Math.round(info.size.width * ratio)), height: Math.max(1, Math.round(info.size.height * ratio)) } });
    const bytes = await packer.packing(pixel, { format: 'image/jpeg', quality: 70 });
    const target = context.filesDir + '/thumbs/' + id + '.jpg'; writeFile(target, bytes); return target;
  } finally { if (pixel) { await pixel.release(); } await source.release(); await packer.release(); }
}
export function thumbnailBase64(path: string): string {
  return new util.Base64Helper().encodeToStringSync(new Uint8Array(readFile(path)));
}

// A system confirmation grants access to the chosen new asset only.
export async function exportPhoto(context: common.Context, path: string): Promise<boolean> {
  const source = image.createImageSource(path); const packer = image.createImagePacker();
  let pixel: image.PixelMap | undefined = undefined;
  const temporary = context.cacheDir + '/export-' + util.generateRandomUUID() + '.jpg';
  const helper = photoAccessHelper.getPhotoAccessHelper(context);
  try {
    pixel = await source.createPixelMap();
    const jpeg = await packer.packing(pixel, { format: 'image/jpeg', quality: 90 });
    writeFile(temporary, jpeg); await pixel.release(); pixel = undefined;
    const config: photoAccessHelper.PhotoCreationConfig = { title: '识物-' + Date.now(), fileNameExtension: 'jpg', photoType: photoAccessHelper.PhotoType.IMAGE };
    const uris = await helper.showAssetsCreationDialog([fileUri.getUriFromPath(temporary)], [config]);
    if (!uris.length) { return false; }
    const input = fs.openSync(temporary, fs.OpenMode.READ_ONLY);
    try {
      const output = fs.openSync(uris[0], fs.OpenMode.WRITE_ONLY);
      try { fs.copyFileSync(input.fd, output.fd); } finally { fs.closeSync(output); }
    } finally { fs.closeSync(input); }
    return true;
  } finally {
    if (pixel) { await pixel.release(); }
    await source.release(); await packer.release(); await helper.release();
    if (fs.accessSync(temporary)) { fs.unlinkSync(temporary); }
  }
}
