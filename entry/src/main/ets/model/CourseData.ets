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
  constructor(id: string, title: string, date: string, summary: string, requirements: string[]) {
    this.id = id;
    this.title = title;
    this.date = date;
    this.summary = summary;
    this.requirements = requirements;
  }
}
// 后续任务在这里追加，列表按钮和详情会自动生成。
export const COURSE_TASKS: CourseTask[] = [
  new CourseTask('01', '课程学习项目', '2026.09.03',
    '搭建课程应用，展示个人信息，通过任务列表进入每次作业的详情。',
    ['主界面：展示课程学习项目的标题和个人信息。',
      '任务列表：每次布置的任务有独立的入口按钮。',
      '任务详情：点击任务按钮进入对应详细页面，支持返回任务列表。'])
];
export interface TaskRouteParams { taskId: string; }
export const INK: string = '#182D3B';
export const MUTED: string = '#647888';
export const ACCENT: string = '#087E8B';
export const PAGE_BG: string = '#F3F6F8';
