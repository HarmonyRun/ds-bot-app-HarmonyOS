/*
 * logic/Schedules.ets 的回归用例（P2-3 定时任务）。
 *
 * 这些是"错了也像是对的"的地方：
 * - 时间表达式翻译错，用户会以为任务会在别的时间跑；
 * - 表单校验与宿主规则不一致，创建会被主机拒绝（或更糟：存了错的时间）。
 *
 * 规则来源：宿主 `ds-bot/src/host/schedules.js` 的 `selectorOf`。
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import {
  describeEvery, describeSchedule, describeWeekdays, isExpired, localDateTime,
  normalizeTime, validateScheduleForm
} from '../main/ets/logic/Schedules.ets';
import { ScheduleTiming } from '../main/ets/model/Models.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

function form(overrides) {
  return Object.assign({
    target: 'bot-chief',
    title: '每日汇报',
    prompt: '汇总今天的进展',
    kind: 'daily',
    atLocal: '',
    time: '09:30',
    weekdays: [],
    minutes: 30,
    timeZone: 'Asia/Shanghai'
  }, overrides);
}

test('间隔秒数翻译', () => {
  assert.equal(describeEvery(60), '每 1 分钟');
  assert.equal(describeEvery(60 * 30), '每 30 分钟');
  assert.equal(describeEvery(3600), '每 1 小时');
  assert.equal(describeEvery(3600 * 5), '每 5 小时');
  assert.equal(describeEvery(86400), '每 1 天');
  assert.equal(describeEvery(undefined), '间隔未设置');
  assert.equal(describeEvery(0), '间隔未设置');
});

test('时刻规范化：合法保留、非法清空', () => {
  assert.equal(normalizeTime('09:30'), '09:30');
  assert.equal(normalizeTime('9:30'), '');
  assert.equal(normalizeTime('23:59'), '23:59');
  assert.equal(normalizeTime('24:00'), '');
  assert.equal(normalizeTime('12:60'), '');
  assert.equal(normalizeTime(undefined), '');
});

test('星期翻译（ISO 1=周一）', () => {
  assert.equal(describeWeekdays([1, 3, 5]), '周一、周三、周五');
  assert.equal(describeWeekdays([7]), '周日');
  assert.equal(describeWeekdays([]), '');
  assert.equal(describeWeekdays([0, 8, 2]), '周二'); // 越界项被忽略
});

test('任务时间描述覆盖四种形态', () => {
  assert.equal(describeSchedule({ kind: 'every', everySeconds: 900 } as ScheduleTiming), '每 15 分钟');
  assert.equal(describeSchedule({ kind: 'daily', time: '09:30' } as ScheduleTiming), '每天 09:30');
  assert.equal(describeSchedule({ kind: 'weekly', time: '08:00', weekdays: [1, 3] } as ScheduleTiming), '每周 周一、周三 08:00');
  assert.equal(describeSchedule({ kind: 'cron' } as ScheduleTiming), '自定义规则');
  assert.equal(describeSchedule({ kind: 'daily' } as ScheduleTiming), '每天');
  assert.equal(describeSchedule({} as ScheduleTiming), '未设置时间');
});

test('一次性任务的时刻描述', () => {
  const iso = new Date('2026-10-20T10:05:00').toISOString();
  const text = describeSchedule({ kind: 'at', scheduledAt: iso } as ScheduleTiming);
  assert.equal(text.startsWith('一次性 · '), true);
  assert.equal(text.includes('10:05'), true);
});

test('校验：缺目标/标题/内容都报错', () => {
  assert.equal(validateScheduleForm(form({ target: '' }), 0).ok, false);
  assert.equal(validateScheduleForm(form({ title: '   ' }), 0).ok, false);
  assert.equal(validateScheduleForm(form({ prompt: '' }), 0).ok, false);
});

test('校验：标题超 120 字被拒（与宿主一致）', () => {
  const long = 'a'.repeat(121);
  assert.equal(validateScheduleForm(form({ title: long }), 0).ok, false);
  assert.equal(validateScheduleForm(form({ title: 'a'.repeat(120) }), 0).ok, true);
});

test('校验：daily 生成 {kind,time,timeZone}', () => {
  const result = validateScheduleForm(form({ kind: 'daily', time: '07:15' }), 0);
  assert.equal(result.ok, true);
  assert.equal(result.when.kind, 'daily');
  assert.equal(result.when.time, '07:15');
  assert.equal(result.when.timeZone, 'Asia/Shanghai');
});

test('校验：daily 时刻非法被拒', () => {
  assert.equal(validateScheduleForm(form({ kind: 'daily', time: '7:15' }), 0).ok, false);
  assert.equal(validateScheduleForm(form({ kind: 'daily', time: '' }), 0).ok, false);
});

test('校验：weekly 去重并排序；为空被拒', () => {
  const result = validateScheduleForm(form({ kind: 'weekly', weekdays: [5, 1, 5, 3] }), 0);
  assert.equal(result.ok, true);
  assert.deepEqual(result.when.weekdays, [1, 3, 5]);
  assert.equal(validateScheduleForm(form({ kind: 'weekly', weekdays: [] }), 0).ok, false);
});

test('校验：at 必须晚于现在', () => {
  const now = new Date('2026-10-17T12:00:00').getTime();
  const future = localDateTime(new Date(now + 3600 * 1000));
  const past = localDateTime(new Date(now - 3600 * 1000));
  assert.equal(validateScheduleForm(form({ kind: 'at', atLocal: future }), now).ok, true);
  assert.equal(validateScheduleForm(form({ kind: 'at', atLocal: past }), now).ok, false);
  assert.equal(validateScheduleForm(form({ kind: 'at', atLocal: '' }), now).ok, false);
  assert.equal(validateScheduleForm(form({ kind: 'at', atLocal: 'not-a-date' }), now).ok, false);
});

test('校验：every 范围 1 分钟 ~ 7 天', () => {
  assert.equal(validateScheduleForm(form({ kind: 'every', minutes: 0 }), 0).ok, false);
  assert.equal(validateScheduleForm(form({ kind: 'every', minutes: 1 }), 0).ok, true);
  assert.equal(validateScheduleForm(form({ kind: 'every', minutes: 7 * 24 * 60 }), 0).ok, true);
  assert.equal(validateScheduleForm(form({ kind: 'every', minutes: 7 * 24 * 60 + 1 }), 0).ok, false);
  assert.equal(validateScheduleForm(form({ kind: 'every', minutes: 1.5 }), 0).ok, false);
});

test('校验成功时回传 trim 后的标题与内容', () => {
  const result = validateScheduleForm(form({ title: '  每日汇报  ', prompt: '  汇总  ' }), 0);
  assert.equal(result.title, '每日汇报');
  assert.equal(result.prompt, '汇总');
});

test('一次性任务过期判定', () => {
  const now = new Date('2026-10-17T12:00:00').getTime();
  const past = new Date(now - 1000).toISOString();
  const future = new Date(now + 1000).toISOString();
  assert.equal(isExpired({ kind: 'at', scheduledAt: past } as ScheduleTiming, now), true);
  assert.equal(isExpired({ kind: 'at', scheduledAt: future } as ScheduleTiming, now), false);
  // 重复任务不会"过期"
  assert.equal(isExpired({ kind: 'daily', time: '09:00' } as ScheduleTiming, now), false);
});

test('localDateTime 输出可被 Date 解析回来', () => {
  const date = new Date('2026-10-20T08:05:00');
  const text = localDateTime(date);
  assert.equal(text.length, 16);
  assert.equal(new Date(text).getTime(), date.getTime());
});

// ---- 运行器 ----
const passed = [];
const failed = [];
for (const { name, fn } of tests) {
  try {
    fn();
    passed.push(name);
    console.log(`  ✓ ${name}`);
  } catch (error) {
    failed.push(name);
    console.log(`  ✗ ${name}`);
    console.log(`     ${error.message}`);
  }
}
console.log(`\n${passed.length} passed / ${failed.length} failed`);
if (failed.length > 0) process.exitCode = 1;
export { tests };
