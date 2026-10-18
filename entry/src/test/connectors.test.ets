/*
 * logic/Connectors.ets 的回归用例。
 *
 * 规则来源：宿主 `src/host/connectors.js`
 * - 状态：off / connecting / ready / error
 * - `connector-connect` 需要非空 token；`disconnect` 删除密钥
 *
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import {
  actionLabel, isBusy, isConnected, needsToken, stateColor, stateLabel, tokenProblem
} from '../main/ets/logic/Connectors.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

const colors = { success: '#159A72', danger: '#C93F49', warning: '#B86A16', muted: '#657086' };

test('状态文案：未连接/连接中/已连接/失败', () => {
  assert.equal(stateLabel({ id: 'github', name: 'GitHub', state: 'off' }), '未连接');
  assert.equal(stateLabel({ id: 'github', name: 'GitHub', state: 'connecting' }), '连接中…');
  assert.equal(stateLabel({ id: 'github', name: 'GitHub', state: 'ready' }), '已连接');
  assert.equal(stateLabel({ id: 'github', name: 'GitHub', state: 'error' }), '连接失败');
});

test('已连接时带账号名', () => {
  assert.equal(stateLabel({ id: 'g', name: 'G', state: 'ready', account: 'octocat' }), '已连接 · octocat');
  assert.equal(stateLabel({ id: 'g', name: 'G', state: 'ready', account: null }), '已连接');
  assert.equal(stateLabel({ id: 'g', name: 'G', state: 'ready', account: '' }), '已连接');
});

test('状态色', () => {
  assert.equal(stateColor({ id: 'g', name: 'G', state: 'ready' }, colors), colors.success);
  assert.equal(stateColor({ id: 'g', name: 'G', state: 'error' }, colors), colors.danger);
  assert.equal(stateColor({ id: 'g', name: 'G', state: 'connecting' }, colors), colors.warning);
  assert.equal(stateColor({ id: 'g', name: 'G', state: 'off' }, colors), colors.muted);
});

test('isConnected / isBusy', () => {
  assert.equal(isConnected({ id: 'g', name: 'G', state: 'ready' }), true);
  assert.equal(isConnected({ id: 'g', name: 'G', state: 'off' }), false);
  assert.equal(isBusy({ id: 'g', name: 'G', state: 'connecting' }), true);
  assert.equal(isBusy({ id: 'g', name: 'G', state: 'ready' }), false);
});

test('按钮文案随状态变化', () => {
  assert.equal(actionLabel({ id: 'g', name: 'G', state: 'off' }), '连接');
  assert.equal(actionLabel({ id: 'g', name: 'G', state: 'error' }), '重试');
  assert.equal(actionLabel({ id: 'g', name: 'G', state: 'ready' }), '断开');
  assert.equal(actionLabel({ id: 'g', name: 'G', state: 'connecting' }), '连接中');
});

test('只有未连接时才需要 token', () => {
  assert.equal(needsToken({ id: 'g', name: 'G', state: 'off' }), true);
  assert.equal(needsToken({ id: 'g', name: 'G', state: 'error' }), false);
  assert.equal(needsToken({ id: 'g', name: 'G', state: 'ready' }), false);
});

test('token 校验', () => {
  assert.equal(tokenProblem(''), '请粘贴访问令牌');
  assert.equal(tokenProblem('   '), '请粘贴访问令牌');
  assert.equal(tokenProblem('a'.repeat(513)).includes('过长'), true);
  assert.equal(tokenProblem('ghp_abcdef'), '');
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
