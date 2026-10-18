/*
 * logic/Memory.ets 的回归用例（P2-4 记忆面板）。
 *
 * 关键点：宿主把私有与团队记忆合并返回，靠 `scope` 区分；
 * 容量上限由宿主给，但面板要在提交前算清楚——算错会让用户写完才被拒。
 *
 * 规则来源：宿主 `ds-bot/src/host/memory.js`（MEMORY_LIMITS / ASK_TEXT_MAX）。
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import {
  describeChanges, entryLimit, groupEntries, scopeLimit, toRows, usedChars, usedPercent,
  validateAsk, validateEntryText
} from '../main/ets/logic/Memory.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

const view = {
  entries: [
    { scope: 'own', topic: '工作方式', text: '先给结论', by: 'user', added: '2026-10-17', source: '对话' },
    { scope: 'team', topic: '项目', text: '鸿蒙移植中', by: 'user', added: '2026-10-16', source: null },
    { scope: 'own', topic: null, text: '偏好中文', by: null, added: null, source: null }
  ],
  sizes: { own: 1234, team: 567 },
  limits: { entry: 300, main: 4000, topic: 16000, topics: 40 }
};

test('按 scope 分组', () => {
  const groups = groupEntries(view.entries);
  assert.equal(groups.own.length, 2);
  assert.equal(groups.team.length, 1);
});

test('未知 scope 归入私有（条目不会消失）', () => {
  const groups = groupEntries([{ scope: 'unknown', text: 'x' }]);
  assert.equal(groups.own.length, 1);
  assert.equal(groups.team.length, 0);
});

test('空/缺失 entries 不崩', () => {
  assert.equal(groupEntries(undefined).own.length, 0);
  assert.equal(groupEntries([]).team.length, 0);
});

test('展示行：topic 与 meta 有稳定占位', () => {
  const rows = toRows(view.entries);
  assert.equal(rows[0].topic, '工作方式');
  assert.equal(rows[0].meta, 'user · 2026-10-17 · 对话');
  assert.equal(rows[2].topic, '未分类');
  assert.equal(rows[2].meta, ''); // 三个字段都空时不出现空括号
});

test('已用字符优先用宿主 sizes', () => {
  assert.equal(usedChars(view, 'own'), 1234);
  assert.equal(usedChars(view, 'team'), 567);
});

test('宿主没给 sizes 时本地按文本累加', () => {
  const noSizes = { entries: view.entries };
  assert.equal(usedChars(noSizes, 'own'), '先给结论'.length + '偏好中文'.length);
  assert.equal(usedChars(noSizes, 'team'), '鸿蒙移植中'.length);
});

test('容量百分比与上限对齐', () => {
  assert.equal(scopeLimit(view.limits, 'own'), 4000);
  assert.equal(scopeLimit(view.limits, 'team'), 16000);
  assert.equal(usedPercent(view, 'own'), Math.round((1234 / 4000) * 100));
  assert.equal(usedPercent(view, 'team'), Math.round((567 / 16000) * 100));
});

test('上限缺失时用宿主默认值兜底', () => {
  assert.equal(entryLimit(undefined), 300);
  assert.equal(scopeLimit(undefined, 'own'), 4000);
  assert.equal(scopeLimit(undefined, 'team'), 16000);
});

test('百分比不越界', () => {
  const full = { sizes: { own: 999999, team: 0 }, limits: { main: 4000, topic: 100 } };
  assert.equal(usedPercent(full, 'own'), 100);
});

test('问答校验：空/超长/正常', () => {
  assert.equal(validateAsk('   ').ok, false);
  assert.equal(validateAsk('a'.repeat(2001)).ok, false);
  const ok = validateAsk('  记住我喜欢简洁  ');
  assert.equal(ok.ok, true);
  assert.equal(ok.text, '记住我喜欢简洁');
});

test('单条记忆长度校验', () => {
  assert.equal(validateEntryText('', undefined), '内容不能为空');
  assert.equal(validateEntryText('a'.repeat(301), undefined), '单条记忆请控制在 300 字以内');
  assert.equal(validateEntryText('正常内容', undefined), '');
});

test('变更描述：成功与失败都能读', () => {
  const lines = describeChanges([
    { op: 'add', scope: 'team', text: '团队规则A', ok: true },
    { op: 'remove', scope: 'own', text: '旧偏好', ok: false, error: '找不到' }
  ]);
  assert.equal(lines.length, 2);
  assert.equal(lines[0], '新增团队记忆：团队规则A');
  assert.equal(lines[1].includes('删除私有记忆'), true);
  assert.equal(lines[1].includes('找不到'), true);
});

test('变更描述：缺失时不崩', () => {
  assert.equal(describeChanges(undefined).length, 0);
  assert.equal(describeChanges([]).length, 0);
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
