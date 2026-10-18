/*
 * logic/Notifications.ets 的回归用例（P3-4 通知）。
 *
 * 关键点：未读数、"全部已读"用哪个游标、类别过滤。
 * 规则来源：宿主 `src/mobile/notifications.js`
 * （`item.id <= prefs.readThrough`、`preferences.categories` 过滤）。
 *
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import {
  describeTime, filterByPreferences, kindGlyph, kindLabel, NOTIFICATION_KINDS,
  preferencesProblem, preferencesSummary, readThroughCursor, shouldNotify, unreadCount
} from '../main/ets/logic/Notifications.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

const items = [
  { id: 1, conversationId: 'c1', kind: 'reply', title: 'Chief 回复了你', read: true },
  { id: 2, conversationId: 'c2', kind: 'question', title: '需要你确认', read: false },
  { id: 3, conversationId: 'c3', kind: 'approval', title: '请求写入文件', read: false }
];

test('未读计数', () => {
  assert.equal(unreadCount(items), 2);
  assert.equal(unreadCount([]), 0);
  assert.equal(unreadCount(undefined), 0);
  assert.equal(unreadCount([{ id: 1, conversationId: 'c', kind: 'reply', title: 't' }]), 1);
});

test('类别展示名与图标', () => {
  assert.equal(kindLabel('reply'), '回复');
  assert.equal(kindLabel('question'), '提问');
  assert.equal(kindLabel('approval'), '审批');
  assert.equal(kindLabel('other'), 'other');
  assert.equal(kindGlyph('reply'), '💬');
  assert.equal(NOTIFICATION_KINDS.length, 3);
});

test('按偏好过滤：关闭时为空', () => {
  assert.equal(filterByPreferences(items, { enabled: false }).length, 0);
  assert.equal(filterByPreferences(items, { enabled: true }).length, 3);
});

test('按偏好过滤：只保留订阅类别', () => {
  const only = filterByPreferences(items, { enabled: true, categories: ['approval'] });
  assert.equal(only.length, 1);
  assert.equal(only[0].kind, 'approval');
});

test('"全部已读"使用主机游标而不是条数', () => {
  assert.equal(readThroughCursor(42), 42);
  assert.equal(readThroughCursor(0), 0);
  assert.equal(readThroughCursor(undefined), 0);
});

test('时间显示：今天 HH:mm，往日 MM-DD', () => {
  const now = new Date('2026-10-18T12:00:00').getTime();
  const today = new Date('2026-10-18T09:05:00').getTime();
  const past = new Date('2026-10-02T09:05:00').getTime();
  assert.equal(describeTime(today, now), '09:05');
  assert.equal(describeTime(past, now), '10-02');
  assert.equal(describeTime(undefined, now), '');
});

test('是否该弹横幅', () => {
  assert.equal(shouldNotify({ id: 2, conversationId: 'c', kind: 'question', title: 't' }, { enabled: true }), true);
  assert.equal(shouldNotify({ id: 2, conversationId: 'c', kind: 'question', title: 't', read: true }, { enabled: true }), false);
  assert.equal(shouldNotify({ id: 2, conversationId: 'c', kind: 'question', title: 't' }, { enabled: false }), false);
  assert.equal(shouldNotify({ id: 2, conversationId: 'c', kind: 'reply', title: 't' }, { enabled: true, categories: ['approval'] }), false);
});

test('偏好校验与摘要', () => {
  assert.equal(preferencesProblem(['reply']), '');
  assert.equal(preferencesProblem(['bogus']).includes('bogus'), true);
  assert.equal(preferencesSummary({ enabled: false }), '已关闭');
  assert.equal(preferencesSummary({ enabled: true, categories: ['reply', 'approval'] }), '已开启 · 回复、审批');
  assert.equal(preferencesSummary({ enabled: true, categories: [] }), '已开启 · 未订阅任何类别');
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
