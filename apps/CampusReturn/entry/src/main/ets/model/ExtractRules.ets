import { StructuredFields } from './CampusTypes';

export function formatTime(stamp: number): string {
  const d = new Date(stamp + 8 * 3600000); const two = (v: number): string => v.toString().padStart(2, '0');
  return `${d.getUTCFullYear()}-${two(d.getUTCMonth() + 1)}-${two(d.getUTCDate())} ${two(d.getUTCHours())}:${two(d.getUTCMinutes())}`;
}
export function parseTime(value: string): number {
  if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(value)) { throw new Error('时间请填写 YYYY-MM-DD HH:mm'); }
  const stamp = Date.parse(value.replace(' ', 'T') + ':00+08:00');
  if (!Number.isFinite(stamp) || formatTime(stamp) !== value) { throw new Error('时间不存在，请检查日期和小时'); }
  return stamp;
}
export function extractRules(text: string, now: number = Date.now()): StructuredFields {
  const categories = ['校园卡', '学生卡', '身份证', '证件', '书籍', '课本', '书本', '雨伞', '水杯', '保温杯', '钥匙', '手机', '电脑', '笔记本电脑', '背包', '书包', '耳机'];
  const mapped = ['校园卡', '校园卡', '证件', '证件', '书籍', '书籍', '书籍', '雨伞', '水杯', '水杯', '钥匙', '手机', '电脑', '电脑', '背包', '背包', '耳机'];
  let category = ''; for (let i = 0; i < categories.length; i++) { if (text.includes(categories[i])) { category = mapped[i]; break; } }
  const color = ['蓝色', '黑色', '白色', '红色', '绿色', '黄色', '紫色', '粉色', '灰色', '银色'].find((v: string) => text.includes(v)) || '';
  const places = ['图书馆北门', '图书馆正门', '图书馆门口', '第一食堂', '第二食堂', '一饭', '二饭', '教学楼A栋', '教学楼', '图书馆', '宿舍', '操场'];
  let place = places.find((v: string) => text.includes(v)) || ''; if (place === '一饭') { place = '第一食堂'; } if (place === '二饭') { place = '第二食堂'; }
  let date = ''; const exact = text.match(/(20\d{2})[-/年](\d{1,2})[-/月](\d{1,2})日?(?:\s*(\d{1,2})[:点时](\d{1,2})?分?)?/);
  const two = (v: string): string => v.padStart(2, '0');
  if (exact) { date = `${exact[1]}-${two(exact[2])}-${two(exact[3])} ${two(exact[4] || '12')}:${two(exact[5] || '00')}`; }
  else if (text.includes('今天') || text.includes('昨天') || text.includes('前天')) {
    const offset = text.includes('前天') ? 2 : text.includes('昨天') ? 1 : 0; const day = formatTime(now - offset * 86400000).slice(0, 10);
    const hour = text.match(/(\d{1,2})[:点时](\d{1,2})?分?/); date = day + ' ' + (hour ? two(hour[1]) + ':' + two(hour[2] || '00') : '12:00');
  }
  return { category: category, color: color, place: place, timeText: date, words: [], note: '本地校园词表与时间规则，请确认后发布' };
}
