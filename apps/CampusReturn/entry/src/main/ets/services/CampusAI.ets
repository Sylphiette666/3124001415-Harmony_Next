import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { textRecognition, objectDetection, visionBase } from '@kit.CoreVisionKit';
import { textProcessing, EntityType } from '@kit.NaturalLanguageKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs } from '@kit.CoreFileKit';
import { PhotoAnalysis, StructuredFields } from '../model/CampusTypes';
import { extractRules } from '../model/ExtractRules';
import { inferenceService } from './Inference';
import { writeFile, ensureFolders } from './MediaFiles';

async function bounded<T>(job: Promise<T>, label: string): Promise<T> {
  let timer = -1;
  try { return await Promise.race([job, new Promise<T>((resolve: (value: T) => void, reject: (error: Error) => void) => { timer = setTimeout(() => { reject(new Error(label + '超时')); }, 12000); })]); }
  finally { clearTimeout(timer); }
}
async function ocrJob(path: string): Promise<string> {
  const src = image.createImageSource(path); const pixel = await src.createPixelMap();
  try { return (await textRecognition.recognizeText({ pixelMap: pixel })).value; }
  finally { await pixel.release(); await src.release(); }
}
async function classifyJob(path: string): Promise<string> {
  const src = image.createImageSource(path); const pixel = await src.createPixelMap(); let engine: objectDetection.ObjectDetector | undefined = undefined;
  try {
    engine = await objectDetection.ObjectDetector.create(); const request = new visionBase.Request(); request.inputData = { pixelMap: pixel };
    const result = await engine.process(request); const objects = result.objects.slice().sort((a: objectDetection.VisionObject, b: objectDetection.VisionObject) => b.score - a.score);
    for (let i = 0; i < objects.length; i++) { if (objects[i].labels.includes(22)) { return '校园卡'; } if (objects[i].labels.includes(21)) { return '书籍'; } }
    return '';
  } finally { if (engine) { await engine.destroy(); } await pixel.release(); await src.release(); }
}
export async function analyzePhoto(context: common.Context, path: string): Promise<PhotoAnalysis> {
  const notes: string[] = []; let ocrText = ''; let category = '';
  try { ocrText = await bounded(ocrJob(path), 'OCR'); notes.push(ocrText ? 'Core Vision OCR已识别文字' : 'Core Vision OCR未发现文字'); }
  catch { notes.push('Core Vision OCR暂不可用，可手动填写文字线索'); }
  try { category = await bounded(classifyJob(path), '图像分类'); if (category) { notes.push('Core Vision分类标签建议：' + category); } }
  catch { notes.push('Core Vision分类暂不可用，改用本机YOLO补充类别'); }
  const clue = extractRules(ocrText).category;
  if (clue) { category = clue; }
  if (!category) {
    try {
      ensureFolders(context); const model = context.filesDir + '/models/yolov13n.onnx';
      if (!fs.accessSync(model)) { const bytes = await context.resourceManager.getRawFileContent('yolov13n.onnx'); writeFile(model, bytes.slice().buffer as ArrayBuffer); }
      const result = await inferenceService.run({ imagePath: path, modelPath: model, threshold: .25, mode: 'TaskPool' });
      for (let i = 0; i < result.detections.length; i++) {
        const label = result.detections[i].name;
        if (['书本', '雨伞', '瓶子', '杯子', '手机', '笔记本电脑', '背包', '手提包', '行李箱'].includes(label)) {
          category = label === '书本' ? '书籍' : ['瓶子', '杯子'].includes(label) ? '水杯' : label === '笔记本电脑' ? '电脑' : ['手提包', '行李箱'].includes(label) ? '背包' : label; break;
        }
      }
      notes.push(category ? 'YOLO端侧类别建议：' + category : '未得到可靠类别，请手动选择');
    } catch { notes.push('端侧分类未完成，请手动选择类别后重试'); }
  }
  return { category: category, ocrText: ocrText, note: notes.join('；') };
}
export async function recognizeEvidence(path: string): Promise<string> { return await bounded(ocrJob(path), '证据OCR'); }
export async function extractText(text: string): Promise<StructuredFields> {
  const result = extractRules(text);
  try {
    await bounded(textProcessing.init(), '自然语言服务');
    const words = await bounded(textProcessing.getWordSegment(text), '分词'); result.words = words.map((w: textProcessing.WordSegment) => w.word);
    const entities = await bounded(textProcessing.getEntity(text, { entityTypes: [EntityType.LOCATION, EntityType.DATETIME] }), '实体抽取');
    entities.forEach((e: textProcessing.Entity) => { if (e.type === EntityType.LOCATION && !result.place) { result.place = e.text; } if (e.type === EntityType.DATETIME && !result.timeText) { result.timeText = extractRules(e.text).timeText; } });
    result.note = 'Natural Language Kit分词/实体抽取＋校园类别颜色词表，请确认回填字段';
  } catch { result.note = 'Natural Language Kit暂不可用，已用明确标注的本地校园规则抽取，可修改并重试'; }
  return result;
}
export async function uploadImage(path: string): Promise<string> {
  const src = image.createImageSource(path); const packer = image.createImagePacker(); let pixel: image.PixelMap | undefined = undefined;
  try {
    const info = await src.getImageInfo(); const scale = Math.min(1, 1000 / Math.max(info.size.width, info.size.height));
    pixel = await src.createPixelMap({ desiredSize: { width: Math.max(1, Math.round(info.size.width * scale)), height: Math.max(1, Math.round(info.size.height * scale)) } });
    const bytes = await packer.packing(pixel, { format: 'image/jpeg', quality: 85 });
    if (bytes.byteLength > 1500000) { throw new Error('图片压缩后仍过大，请选择更小的图片'); }
    return new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes));
  } finally { if (pixel) { await pixel.release(); } await src.release(); await packer.release(); }
}
