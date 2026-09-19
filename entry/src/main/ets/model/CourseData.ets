export class StudentProfile {
  name: string = '';
  studentId: string = '3124001415';
  className: string = '';
}
export class CourseTask {
  id: string;
  title: string;
  date: string;
  summary: string;
  requirements: string[];
  pageUrl: string;
  constructor(id: string, title: string, date: string, summary: string, requirements: string[], pageUrl: string = '') {
    this.id = id;
    this.title = title;
    this.date = date;
    this.summary = summary;
    this.requirements = requirements;
    this.pageUrl = pageUrl;
  }
}
// 后续任务在这里追加，列表按钮和详情会自动生成。
export const COURSE_TASKS: CourseTask[] = [
  new CourseTask('01', '课程学习项目', '2026.09.03',
    '搭建课程应用，展示个人信息，通过任务列表进入每次作业的详情。',
    ['主界面：展示课程学习项目的标题和个人信息。',
      '任务列表：每次布置的任务有独立的入口按钮。',
      '任务详情：点击任务按钮进入对应详细页面，支持返回任务列表。']),
  new CourseTask('02', '电子名片管理', '2026.09.07',
    '建立本地名片夹，管理联系信息，通过搜索、分组与收藏快速找到联系人。',
    ['基本管理：新增、查看、编辑和删除电子名片。',
      '本地保存：名片数据保存在当前设备，退出应用后仍可读取。',
      '特色功能：关键词搜索、联系人分组、收藏筛选和长按复制。',
      '提交时间：2026 年 9 月 11 日前更新到课程代码仓库。'], 'pages/BusinessCards'),
  new CourseTask('03', '有声计算器', '2026.09.13',
    '标准四则计算器，按键和计算结果支持中文语音播报。',
    ['计算器：支持数字、小数、四则运算、百分比、清除、退格和常用一元运算。',
      '语音交互：按键会读出内容，等号会播报计算结果，可随时静音或重播结果。',
      '工程实践：计算状态与语音服务分离，页面离开时停止播报并释放引擎。'], 'pages/Calculator'),
  new CourseTask('04', '天气预报', '2026.09.18',
    '按省市查询当前天气与未来七日预报，支持断网提示、重试和本地缓存。',
    ['省市选择：查询温度、天气状况、体感温度、湿度、风向和风力。',
      '未来预报：展示七日天气、最高最低温、降水概率及最大风力。',
      '友好交互：加载、失败、无网络均有提示，可重试并查看明确标记的历史缓存。',
      '工程实践：网络、数据解析、存储与界面分离；文档保存在根目录 doc。',
      '提交时间：2026 年 9 月 24 日前更新课程代码仓库。'], 'pages/Weather')
];
export interface TaskRouteParams { taskId: string; }
export const INK: string = '#182D3B';
export const MUTED: string = '#647888';
export const ACCENT: string = '#087E8B';
export const PAGE_BG: string = '#F3F6F8';
