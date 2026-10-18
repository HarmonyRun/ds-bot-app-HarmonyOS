/*
 * service/Projection.ets 里能力解析的回归用例（P2-7 能力分配）。
 *
 * 能力库是「团队级清单 + 每个 Bot 的挂载状态」两层结构，
 * 名字是唯一操作键——解析时丢掉名字或误留未知 kind，
 * 界面就会出现「点了没反应」或「显示未知状态」。
 *
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import { toCapabilityStatuses, toCapabilities } from '../main/ets/service/Projection.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

test('解析三种 kind，其余丢弃', () => {
  const result = toCapabilities([
    { name: 'web-search', kind: 'mcp', description: '搜索', transport: 'stdio', approved: true },
    { name: 'review', kind: 'skill', description: '代码评审' },
    { name: 'starter', kind: 'pack', items: ['web-search', 'review'] },
    { name: 'weird', kind: 'unknown' },
    { name: 'mystery' }
  ]);
  assert.equal(result.length, 3);
  assert.equal(result[0].name, 'web-search');
  assert.equal(result[0].transport, 'stdio');
  assert.equal(result[0].approved, true);
  assert.deepEqual(result[2].items, ['web-search', 'review']);
});

test('缺 name 的条目被丢弃（名字是操作键）', () => {
  assert.equal(toCapabilities([{ kind: 'skill', description: 'x' }]).length, 0);
  assert.equal(toCapabilities([{ name: '', kind: 'skill' }]).length, 0);
});

test('缺失/空输入返回空数组', () => {
  assert.equal(toCapabilities(undefined).length, 0);
  assert.equal(toCapabilities([]).length, 0);
});

test('状态解析：只保留四种已知 state', () => {
  const result = toCapabilityStatuses({
    'bot-a': {
      'web-search': { state: 'ready' },
      'broken': { state: 'error', error: '认证失败' },
      'weird': { state: 'unknown-state' },
      'no-state': { error: 'x' }
    }
  });
  const statuses = result['bot-a'];
  assert.equal(Object.keys(statuses).length, 2);
  assert.equal(statuses['web-search'].state, 'ready');
  assert.equal(statuses['broken'].error, '认证失败');
  assert.equal(statuses['weird'], undefined);
});

test('状态解析：非法内层与空值不崩', () => {
  assert.deepEqual(toCapabilityStatuses(undefined), {});
  const result = toCapabilityStatuses({ 'bot-a': null, 'bot-b': 'oops' });
  assert.equal(Object.keys(result).length, 0);
});

test('needs-approval 状态被保留（需要提示用户）', () => {
  const result = toCapabilityStatuses({ 'bot-a': { 'x': { state: 'needs-approval' } } });
  assert.equal(result['bot-a']['x'].state, 'needs-approval');
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
