import { Detection, Letterbox, CategoryCount } from './Types';

export const LABELS: string[] = ['人', '自行车', '汽车', '摩托车', '飞机', '公交车', '火车', '卡车', '船', '红绿灯',
  '消防栓', '停车标志', '停车计时器', '长椅', '鸟', '猫', '狗', '马', '羊', '牛', '大象', '熊', '斑马', '长颈鹿',
  '背包', '雨伞', '手提包', '领带', '行李箱', '飞盘', '滑雪板', '单板滑雪板', '运动球', '风筝', '棒球棒',
  '棒球手套', '滑板', '冲浪板', '网球拍', '瓶子', '高脚杯', '水杯', '叉子', '刀', '勺子', '碗', '香蕉', '苹果',
  '三明治', '橙子', '西兰花', '胡萝卜', '热狗', '披萨', '甜甜圈', '蛋糕', '椅子', '沙发', '盆栽', '床',
  '餐桌', '马桶', '电视', '笔记本电脑', '鼠标', '遥控器', '键盘', '手机', '微波炉', '烤箱', '烤面包机',
  '水槽', '冰箱', '书本', '时钟', '花瓶', '剪刀', '玩具熊', '吹风机', '牙刷'];

export function letterboxGeometry(width: number, height: number, size: number = 640): Letterbox {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1 || size < 1) {
    throw new Error('图片尺寸无效');
  }
  const ratio = Math.min(size / width, size / height);
  const resizedWidth = Math.max(1, Math.round(width * ratio));
  const resizedHeight = Math.max(1, Math.round(height * ratio));
  return { width: width, height: height, inputSize: size, ratio: ratio,
    scaleX: resizedWidth / width, scaleY: resizedHeight / height,
    padX: Math.floor((size - resizedWidth) / 2), padY: Math.floor((size - resizedHeight) / 2),
    resizedWidth: resizedWidth, resizedHeight: resizedHeight };
}

// Bilinear RGB letterbox, padding 114, /255 normalization, contiguous CHW planes.
export function preprocess(rgba: Uint8Array, geometry: Letterbox): Float32Array {
  const g = geometry;
  if (rgba.length !== g.width * g.height * 4) { throw new Error('图片像素长度不匹配'); }
  const size = g.inputSize; const plane = size * size;
  const tensor = new Float32Array(3 * plane); tensor.fill(114 / 255);
  for (let y = 0; y < g.resizedHeight; y++) {
    const fy = Math.max(0, Math.min(g.height - 1, (y + 0.5) / g.scaleY - 0.5));
    const y0 = Math.floor(fy); const y1 = Math.min(y0 + 1, g.height - 1); const dy = fy - y0;
    for (let x = 0; x < g.resizedWidth; x++) {
      const fx = Math.max(0, Math.min(g.width - 1, (x + 0.5) / g.scaleX - 0.5));
      const x0 = Math.floor(fx); const x1 = Math.min(x0 + 1, g.width - 1); const dx = fx - x0;
      const a = (y0 * g.width + x0) * 4; const b = (y0 * g.width + x1) * 4;
      const c = (y1 * g.width + x0) * 4; const d = (y1 * g.width + x1) * 4;
      const target = (y + g.padY) * size + x + g.padX;
      for (let channel = 0; channel < 3; channel++) {
        const top = rgba[a + channel] * (1 - dx) + rgba[b + channel] * dx;
        const bottom = rgba[c + channel] * (1 - dx) + rgba[d + channel] * dx;
        tensor[channel * plane + target] = (top * (1 - dy) + bottom * dy) / 255;
      }
    }
  }
  return tensor;
}
export function iou(a: Detection, b: Detection): number {
  const overlap = Math.max(0, Math.min(a.x2, b.x2) - Math.max(a.x1, b.x1)) *
    Math.max(0, Math.min(a.y2, b.y2) - Math.max(a.y1, b.y1));
  const union = (a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - overlap;
  return union > 0 ? overlap / union : 0;
}
export function nms(boxes: Detection[], threshold: number = 0.45, limit: number = 100): Detection[] {
  const sorted = boxes.slice().sort((a: Detection, b: Detection) => b.score - a.score).slice(0, 1000);
  const selected: Detection[] = [];
  for (let i = 0; i < sorted.length && selected.length < limit; i++) {
    const candidate = sorted[i];
    if (!selected.some((accepted: Detection) => accepted.classId === candidate.classId && iou(accepted, candidate) > threshold)) {
      selected.push(candidate);
    }
  }
  return selected;
}
export function postprocess(data: Float32Array, dims: number[], geometry: Letterbox, confidence: number): Detection[] {
  if (dims.length !== 3 || dims[0] !== 1 || (dims[1] !== 84 && dims[2] !== 84)) { throw new Error('模型输出格式不受支持'); }
  const channelsFirst = dims[1] === 84; const count = channelsFirst ? dims[2] : dims[1];
  if (data.length !== count * 84 || !Number.isFinite(confidence) || confidence < 0 || confidence > 1) {
    throw new Error('模型输出长度或阈值无效');
  }
  const boxes: Detection[] = [];
  for (let i = 0; i < count; i++) {
    let classId = 0; let score = -1;
    for (let c = 0; c < 80; c++) {
      const value = data[channelsFirst ? (c + 4) * count + i : i * 84 + c + 4];
      if (Number.isFinite(value) && value > score) { score = value; classId = c; }
    }
    if (score < confidence || score > 1) { continue; }
    const cx = data[channelsFirst ? i : i * 84]; const cy = data[channelsFirst ? count + i : i * 84 + 1];
    const width = data[channelsFirst ? count * 2 + i : i * 84 + 2]; const height = data[channelsFirst ? count * 3 + i : i * 84 + 3];
    if (![cx, cy, width, height].every((v: number) => Number.isFinite(v)) || width <= 0 || height <= 0) { continue; }
    const x1 = Math.max(0, Math.min(geometry.width, (cx - width / 2 - geometry.padX) / geometry.scaleX));
    const y1 = Math.max(0, Math.min(geometry.height, (cy - height / 2 - geometry.padY) / geometry.scaleY));
    const x2 = Math.max(0, Math.min(geometry.width, (cx + width / 2 - geometry.padX) / geometry.scaleX));
    const y2 = Math.max(0, Math.min(geometry.height, (cy + height / 2 - geometry.padY) / geometry.scaleY));
    if (x2 <= x1 || y2 <= y1) { continue; }
    boxes.push({ id: `box-${i}`, classId: classId, name: LABELS[classId], score: score, x1: x1, y1: y1, x2: x2, y2: y2 });
  }
  return nms(boxes);
}
export function summarize(items: Detection[]): CategoryCount[] {
  const counts = new Map<string, number>();
  items.forEach((item: Detection) => { counts.set(item.name, (counts.get(item.name) || 0) + 1); });
  const result: CategoryCount[] = [];
  counts.forEach((count: number, name: string) => { result.push({ name: name, count: count }); });
  return result.sort((a: CategoryCount, b: CategoryCount) => b.count - a.count || a.name.localeCompare(b.name));
}
