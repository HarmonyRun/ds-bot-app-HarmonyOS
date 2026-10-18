/*
 * logic/Agents.ets 的回归用例（P2-9 Agent 管理）。
 *
 * 关键点：
 * - Agent 会话靠 `kind === 'agent'` 从普通会话里筛出来；
 * - **每个团队只能有一个 Agent**（宿主会抛错，提前拦下少一次往返）；
 * - 标题不能为空/超长（宿主 `renameAgentSession` 会拒绝空标题）。
 *
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import {
  addAgentBlockedReason, archivePrompt, canAddAgent, groupAgentConversations, isAgentConversation,
  removePrompt, titleProblem
} from '../main/ets/logic/Agents.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

const conversations = [
  { id: 'c1', kind: 'room', name: '研发小组', sessionId: 's1' },
  { id: 'agent:a1:s2', kind: 'agent', name: 'Agent 会话 1', sessionId: 's2', agentId: 'a1' },
  { id: 'agent:a1:s3', kind: 'agent', name: 'Agent 会话 2', sessionId: 's3', agentId: 'a1' },
  { id: 'c2', kind: 'bot', name: 'Chief', sessionId: 's4' }
];

test('识别 Agent 会话', () => {
  assert.equal(isAgentConversation(conversations[1]), true);
  assert.equal(isAgentConversation(conversations[0]), false);
});

test('分组：取出 Agent 会话与去重后的 agentId', () => {
  const groups = groupAgentConversations(conversations);
  assert.equal(groups.conversations.length, 2);
  assert.deepEqual(groups.agentIds, ['a1']);
});

test('分组：没有 Agent 时为空', () => {
  const groups = groupAgentConversations([conversations[0]]);
  assert.equal(groups.conversations.length, 0);
  assert.equal(groups.agentIds.length, 0);
});

test('分组：缺 agentId 的会话仍列出但不产生 id', () => {
  const groups = groupAgentConversations([{ id: 'x', kind: 'agent', name: 'n', sessionId: 's' }]);
  assert.equal(groups.conversations.length, 1);
  assert.equal(groups.agentIds.length, 0);
});

test('标题校验', () => {
  assert.equal(titleProblem(''), '标题不能为空');
  assert.equal(titleProblem('   '), '标题不能为空');
  assert.equal(titleProblem('a'.repeat(61)).includes('60'), true);
  assert.equal(titleProblem('正常标题'), '');
});

test('创建 Agent：已有则不允许', () => {
  assert.equal(canAddAgent([]), true);
  assert.equal(canAddAgent(['a1']), false);
  assert.equal(addAgentBlockedReason([]), '');
  assert.equal(addAgentBlockedReason(['a1']).includes('只能有一个'), true);
});

test('确认文案', () => {
  assert.equal(archivePrompt({ id: 'x', kind: 'agent', name: '会议记录', sessionId: 's' })
    .includes('会议记录'), true);
  assert.equal(removePrompt([]), '团队还没有 DSH Agent。');
  assert.equal(removePrompt(['a1']).includes('会话会被归档'), true);
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
