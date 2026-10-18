import { ScheduleTask, ScheduleTiming, ScheduleWhen } from '../model/Models';

/**
 * 定时任务的**纯逻辑**（P2-3）。
 *
 * 主机把任务时间拆成多种字段（`kind` + `scheduledAt/everySeconds/time/weekdays/expression`），
 * 这里负责：
 * - 把任务翻译成一句人话（列表展示）；
 * - 校验创建表单并生成宿主要求的 `when` 选择器；
 * - 生成新任务的本地乐观占位（创建成功后由宿主返回的列表覆盖）。
 *
 * 抽出来的原因：时间表达式与校验规则是"错了也像是对的"的地方，必须能脱离设备测试。
 */

/** 支持的重复形态（与宿主 selectorOf 对齐）。 */
export type ScheduleKind = 'at' | 'daily' | 'weekly' | 'every';

/** 一周七天的中文短名（ISO：1=周一）。 */
const WEEKDAY_NAMES: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/** 把间隔秒数说成人话。 */
export function describeEvery(seconds: number | undefined): string {
  if (seconds === undefined || !Number.isFinite(seconds) || seconds <= 0) return '间隔未设置';
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `每 ${minutes} 分钟`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `每 ${hours} 小时`;
  const days = Math.round(hours / 24);
  return `每 ${days} 天`;
}

/** 把 `HH:mm` 补成 `HH:mm`；非法返回空串。 */
export function normalizeTime(value: string | undefined): string {
  if (value === undefined) return '';
  const text = value.trim();
  const match = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(text);
  return match === null ? '' : `${match[1]}:${match[2]}`;
}

/** 把 ISO 时间说成 `MM-DD HH:mm`；非法返回空串。 */
export function describeMoment(iso: string | undefined): string {
  if (iso === undefined || iso.length === 0) return '';
  const date = new Date(iso);
  const time = date.getTime();
  if (!Number.isFinite(time)) return '';
  const pad = (input: number): string => (input < 10 ? `0${input}` : `${input}`);
  return `${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** 把星期数组（ISO 1..7）说成「周三、周五」。 */
export function describeWeekdays(days: number[] | undefined): string {
  if (days === undefined || days.length === 0) return '';
  const names: string[] = [];
  for (let i = 0; i < days.length; i++) {
    const day = days[i];
    if (Number.isInteger(day) && day >= 1 && day <= 7) {
      names.push(WEEKDAY_NAMES[day - 1]);
    }
  }
  return names.join('、');
}

/** 把任务的时间部分翻译成一句人话。 */
export function describeSchedule(task: ScheduleTiming): string {
  const kind = task.kind ?? '';
  if (kind === 'at' || kind === 'after') {
    const moment = describeMoment(task.scheduledAt);
    return moment.length > 0 ? `一次性 · ${moment}` : '一次性';
  }
  if (kind === 'every') return describeEvery(task.everySeconds);
  if (kind === 'daily') {
    const time = normalizeTime(task.time);
    return time.length > 0 ? `每天 ${time}` : '每天';
  }
  if (kind === 'weekly') {
    const time = normalizeTime(task.time);
    const days = describeWeekdays(task.weekdays);
    if (days.length > 0 && time.length > 0) return `每周 ${days} ${time}`;
    if (days.length > 0) return `每周 ${days}`;
    return '每周';
  }
  if (kind === 'cron') return '自定义规则';
  return '未设置时间';
}

/** 任务归属显示名（Bot 或群聊）。 */
export function describeTarget(task: ScheduleTask, botNames: Map<string, string>, roomNames: Map<string, string>): string {
  if (task.botId !== undefined && task.botId.length > 0) {
    return botNames.get(task.botId) ?? 'Bot';
  }
  if (task.roomId !== undefined && task.roomId.length > 0) {
    return roomNames.get(task.roomId) ?? '群聊';
  }
  return '未知目标';
}

/** 创建表单的原始输入（界面上收集到的）。 */
export interface ScheduleForm {
  target: string;
  title: string;
  prompt: string;
  kind: ScheduleKind;
  /** at 用：`YYYY-MM-DDTHH:mm`（本地时间） */
  atLocal: string;
  /** daily/weekly 用：`HH:mm` */
  time: string;
  /** weekly 用：ISO 1..7 */
  weekdays: number[];
  /** every 用：分钟 */
  minutes: number;
  /** 时区（IANA） */
  timeZone: string;
}

/** 表单校验结果：`ok` 为 true 时 `when` 有值，否则 `error` 是给用户看的一句话。 */
export interface ScheduleValidation {
  ok: boolean;
  error: string;
  when?: ScheduleWhen;
  title?: string;
  prompt?: string;
}

/** 校验并生成 `when`（与宿主 selectorOf 的规则保持一致）。 */
export function validateScheduleForm(form: ScheduleForm, nowMs: number): ScheduleValidation {
  const title = form.title.trim();
  const prompt = form.prompt.trim();
  if (form.target.length === 0) return { ok: false, error: '选择一个 Bot 或群聊' };
  if (title.length === 0) return { ok: false, error: '给任务起个名字' };
  if (title.length > 120) return { ok: false, error: '名字请控制在 120 字以内' };
  if (prompt.length === 0) return { ok: false, error: '写下 Bot 要做什么' };

  if (form.kind === 'at') {
    if (form.atLocal.length === 0) return { ok: false, error: '选择执行时间' };
    const at = new Date(form.atLocal);
    const time = at.getTime();
    if (!Number.isFinite(time)) return { ok: false, error: '执行时间格式不正确' };
    if (time <= nowMs) return { ok: false, error: '执行时间要晚于现在' };
    const when = new ScheduleWhen('at');
    when.at = at.toISOString();
    return { ok: true, error: '', when: when, title: title, prompt: prompt };
  }

  if (form.kind === 'daily' || form.kind === 'weekly') {
    const time = normalizeTime(form.time);
    if (time.length === 0) return { ok: false, error: '选择执行时刻（HH:mm）' };
    if (form.kind === 'weekly') {
      const days: number[] = [];
      for (let i = 0; i < form.weekdays.length; i++) {
        const day = form.weekdays[i];
        if (Number.isInteger(day) && day >= 1 && day <= 7 && !days.includes(day)) days.push(day);
      }
      if (days.length === 0) return { ok: false, error: '至少选择一天' };
      days.sort();
      const when = new ScheduleWhen('weekly');
      when.time = time;
      when.timeZone = form.timeZone;
      when.weekdays = days;
      return { ok: true, error: '', when: when, title: title, prompt: prompt };
    }
    const when = new ScheduleWhen('daily');
    when.time = time;
    when.timeZone = form.timeZone;
    return { ok: true, error: '', when: when, title: title, prompt: prompt };
  }

  // every：宿主接受 1 分钟 ~ 7 天
  if (!Number.isInteger(form.minutes) || form.minutes < 1 || form.minutes > 7 * 24 * 60) {
    return { ok: false, error: '间隔请填 1 分钟到 7 天之间' };
  }
  const when = new ScheduleWhen('every');
  when.minutes = form.minutes;
  return { ok: true, error: '', when: when, title: title, prompt: prompt };
}

/** 把表单的「本地时间」拼成 `<input type=datetime>` 等价的字符串。 */
export function localDateTime(date: Date): string {
  const pad = (input: number): string => (input < 10 ? `0${input}` : `${input}`);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/** 是否已过期（一次性任务）。 */
export function isExpired(task: ScheduleTiming, nowMs: number): boolean {
  if (task.kind !== 'at' && task.kind !== 'after') return false;
  const moment = describeMoment(task.scheduledAt);
  if (moment.length === 0) return false;
  const time = new Date(task.scheduledAt ?? '').getTime();
  return Number.isFinite(time) && time <= nowMs;
}
