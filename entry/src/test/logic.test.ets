/*
 * Merge.ets / applyConversationEvent 的纯函数测试。
 *
 * 直接用仓库自带的执行器运行（会做 .ets → .ts → .mjs 的类型擦除与路径改写）：
 *     node entry/src/test/run.mjs
 *     期望输出：17 passed / 0 failed
 *
 * 执行器实现见 entry/src/test/run.mjs；它用 DevEco Studio 自带的 tsc 擦类型，
 * 不引入任何 npm 依赖，也不修改本文件。
 *
 * 本文件保持「纯 JavaScript 语义」：只有 ESM import/export、函数、类与对象字面量，
 * 这样即使不经过 ArkTS 编译器也能被 Node 直接执行（执行器还会把
 * `../main/ets/logic/Merge.ets` 改写成临时目录里的相对路径）。
 */

import assert from 'node:assert/strict';
import { mergeMessages, applyConversationEvent, cloneMessage } from '../main/ets/logic/Merge.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

/** Base message factory; `over` overrides individual fields. */
function m(over) {
  const base = { id: 'id', sessionId: 's', seq: 1, role: 'assistant', text: '', createdAt: 1000 };
  return Object.assign(base, over || {});
}

function ids(list) {
  return list.map((item) => item.id);
}

function byId(list, id) {
  return list.find((item) => item.id === id);
}

// 1. New messages are ordered by seq ascending within the same session.
test('sorts new messages by seq ascending', () => {
  const result = mergeMessages([], [m({ id: 'a', seq: 2 }), m({ id: 'b', seq: 1 })]);
  assert.deepEqual(ids(result), ['b', 'a']);
});

// 2. Pending messages sort last, whatever their seq.
test('sorts pending messages last', () => {
  const result = mergeMessages([], [
    m({ id: 'p', seq: 1, pending: true }),
    m({ id: 'n', seq: 5 })
  ]);
  assert.deepEqual(ids(result), ['n', 'p']);
});

// 3. A stale incoming copy (lower updatedSeq) must not overwrite stored fields.
test('keeps existing fields when incoming version is lower', () => {
  const existing = [m({ id: 'x', seq: 5, updatedSeq: 10, text: 'old', pending: false })];
  const incoming = [m({ id: 'x', seq: 5, updatedSeq: 3, text: 'new', role: 'user' })];
  const result = mergeMessages(existing, incoming);
  assert.equal(result.length, 1);
  assert.equal(result[0].text, 'old');
  assert.equal(result[0].updatedSeq, 10);
  assert.equal(result[0].role, 'assistant');
});

// 4. A newer incoming copy (higher updatedSeq) overwrites stored fields.
test('overwrites fields when incoming version is higher', () => {
  const existing = [m({ id: 'x', seq: 5, updatedSeq: 3, text: 'old' })];
  const incoming = [m({ id: 'x', seq: 5, updatedSeq: 10, text: 'new' })];
  const result = mergeMessages(existing, incoming);
  assert.equal(result.length, 1);
  assert.equal(result[0].text, 'new');
  assert.equal(result[0].updatedSeq, 10);
});

// 5. Both sides carry a tool card: the fields are merged.
test('merges tool fields when both sides have a tool', () => {
  const existing = [m({
    id: 't', seq: 1, createdAt: 10, updatedSeq: 1,
    tool: { callId: 'c1', name: 'Bash', state: 'running', input: 'ls' }
  })];
  const incoming = [m({
    id: 't', seq: 1, createdAt: 20, updatedSeq: 2,
    tool: { callId: 'c1', name: 'Bash', state: 'completed', output: 'ok' }
  })];
  const result = mergeMessages(existing, incoming);
  assert.equal(result.length, 1);
  assert.equal(result[0].tool.name, 'Bash');
  assert.equal(result[0].tool.state, 'completed');
  assert.equal(result[0].tool.output, 'ok');
  assert.equal(result[0].tool.input, 'ls');
});

// 6. A placeholder tool name 'Tool' is replaced by the real name, and text follows.
test("replaces placeholder tool name 'Tool' with the real name", () => {
  const existing = [m({
    id: 't', seq: 1, updatedSeq: 1, text: 'Tool',
    tool: { callId: 'c1', name: 'Read', state: 'running' }
  })];
  const incoming = [m({
    id: 't', seq: 1, updatedSeq: 2, text: 'Tool',
    tool: { callId: 'c1', name: 'Tool', state: 'completed' }
  })];
  const result = mergeMessages(existing, incoming);
  assert.equal(result.length, 1);
  assert.equal(result[0].tool.name, 'Read');
  assert.equal(result[0].text, 'Read');
  assert.equal(result[0].tool.state, 'completed');
});

// 7. With both seq finite, the smaller seq (and its createdAt) wins for the tool card.
test('takes the smaller seq and its createdAt when both are finite', () => {
  const existing = [m({
    id: 't', seq: 10, createdAt: 500, updatedSeq: 10, text: 'call',
    tool: { callId: 'c1', name: 'Bash', state: 'running' }
  })];
  const incoming = [m({
    id: 't', seq: 3, createdAt: 100, updatedSeq: 20, text: 'result',
    tool: { callId: 'c1', name: 'Bash', state: 'completed', output: 'done' }
  })];
  const result = mergeMessages(existing, incoming);
  assert.equal(result.length, 1);
  assert.equal(result[0].seq, 3);
  assert.equal(result[0].createdAt, 100);
  assert.equal(result[0].tool.output, 'done');
  assert.equal(result[0].tool.state, 'completed');
});

// 8. Entries whose id is not a string are ignored.
test('ignores entries without a string id', () => {
  const noId = { sessionId: 's', seq: 1, role: 'assistant', text: 'ghost', createdAt: 1000 };
  const badId = m({ id: 42, text: 'numeric id' });
  const good = m({ id: 'keep', seq: 2, text: 'kept' });
  const result = mergeMessages([noId, badId], [good]);
  assert.deepEqual(ids(result), ['keep']);
  assert.equal(result[0].text, 'kept');
});

// 9. reset drops every pending message and merges the snapshot.
test('cloneMessage keeps the group author object', () => {
  // 主机下发 author: { id, name }；模型曾经误声明为 string，
  // 导致群聊无法显示发言人。这条用例防止类型再漂回去。
  const source = m({ id: 'g1', author: { id: 'bot-7', name: 'Searcher' } });
  const copy = cloneMessage(source);
  assert.equal(copy.author.name, 'Searcher');
  assert.equal(copy.author.id, 'bot-7');
  // 深拷贝：改副本不应影响原对象
  copy.author.name = 'changed';
  assert.equal(source.author.name, 'Searcher');
});

test('two pending messages keep their own createdAt order', () => {
  // 本地乐观消息没有真实 seq，若不比较 createdAt，用户消息会漂到助手回复之后
  const user = m({ id: 'local-1', pending: true, seq: Number.MAX_SAFE_INTEGER, createdAt: 1000, role: 'user' });
  const assistant = m({ id: 'stream:s:1', pending: true, seq: Number.MAX_SAFE_INTEGER, createdAt: 2000, role: 'assistant' });
  const merged = mergeMessages([assistant], [user]);
  assert.deepEqual(merged.map(x => x.id), ['local-1', 'stream:s:1']);
});

test('reset drops pending messages and merges the snapshot', () => {
  const messages = [
    m({ id: 'stream:s:1', sessionId: 's', seq: Number.MAX_SAFE_INTEGER, pending: true, attemptId: '1' }),
    m({ id: 'keep', seq: 1, text: 'kept' })
  ];
  const event = { type: 'reset', messages: [m({ id: 'snap', seq: 4, text: 'snapshot' })] };
  const result = applyConversationEvent(messages, event);
  assert.deepEqual(ids(result), ['keep', 'snap']);
  assert.equal(result.every((item) => !item.pending), true);
});

// 10. delta creates a pending 'stream:<sessionId>:<attemptId>' message.
test('delta creates a pending stream message', () => {
  const event = {
    type: 'delta', conversationId: 'c', sessionId: 's1', attemptId: 'a1',
    text: '收到', reasoning: '', index: 1, replace: true
  };
  const result = applyConversationEvent([], event);
  assert.equal(result.length, 1);
  const message = result[0];
  assert.equal(message.id, 'stream:s1:a1');
  assert.equal(message.sessionId, 's1');
  assert.equal(message.role, 'assistant');
  assert.equal(message.text, '收到');
  assert.equal(message.pending, true);
  assert.equal(message.attemptId, 'a1');
  assert.equal(message.streamIndex, 1);
  assert.equal(message.seq, Number.MAX_SAFE_INTEGER);
  assert.equal(message.reasoning, '');
});

// 11. A retried cumulative snapshot with a smaller index changes nothing.
test('ignores a repeated delta with a smaller index', () => {
  const live = applyConversationEvent([], {
    type: 'delta', sessionId: 's1', attemptId: 'a1', text: '收到', index: 3
  });
  const again = applyConversationEvent(live, {
    type: 'delta', sessionId: 's1', attemptId: 'a1', text: '收', index: 2
  });
  assert.equal(again, live);
  assert.equal(again[0].text, '收到');
  assert.equal(again[0].streamIndex, 3);
});

// 12. A newer delta snapshot replaces the text but keeps the original createdAt.
test('replaces delta text and keeps createdAt when index grows', () => {
  const live = [
    m({
      id: 'stream:s1:a1', sessionId: 's1', seq: Number.MAX_SAFE_INTEGER, role: 'assistant',
      text: '收', createdAt: 1234, pending: true, attemptId: 'a1', streamIndex: 1, reasoning: 'r1'
    })
  ];
  const result = applyConversationEvent(live, {
    type: 'delta', sessionId: 's1', attemptId: 'a1', text: '收到', index: 2, replace: true
  });
  assert.equal(result.length, 1);
  assert.equal(result[0].text, '收到');
  assert.equal(result[0].createdAt, 1234);
  assert.equal(result[0].streamIndex, 2);
  assert.equal(result[0].pending, true);
  assert.equal(result[0].reasoning, 'r1');
});

// 13. A committed message with replaceAttemptId removes the matching pending message.
test('message with replaceAttemptId removes the matching pending message', () => {
  const messages = [
    m({ id: 'stream:s1:a1', sessionId: 's1', seq: Number.MAX_SAFE_INTEGER, pending: true, attemptId: 'a1', text: '收到' }),
    m({ id: 'stream:s1:a2', sessionId: 's1', seq: Number.MAX_SAFE_INTEGER, pending: true, attemptId: 'a2', text: '别的' }),
    m({ id: 's1:8', sessionId: 's1', seq: 8, text: 'earlier' })
  ];
  const event = {
    type: 'message',
    message: m({ id: 's1:9', sessionId: 's1', seq: 9, text: 'final', createdAt: 2000 }),
    replaceAttemptId: 'a1'
  };
  const result = applyConversationEvent(messages, event);
  assert.deepEqual(ids(result), ['s1:8', 's1:9', 'stream:s1:a2']);
  assert.equal(byId(result, 's1:9').text, 'final');
});

// 14. status + clearAttempt removes the pending message for that attempt.
test('status with clearAttempt removes the matching pending message', () => {
  const messages = [
    m({ id: 'stream:s1:a1', sessionId: 's1', seq: Number.MAX_SAFE_INTEGER, pending: true, attemptId: 'a1' }),
    m({ id: 'stream:s1:a2', sessionId: 's1', seq: Number.MAX_SAFE_INTEGER, pending: true, attemptId: 'a2' }),
    m({ id: 's1:8', sessionId: 's1', seq: 8 })
  ];
  const result = applyConversationEvent(messages, {
    type: 'status', sessionId: 's1', attemptId: 'a1', phase: 'committed', clearAttempt: true
  });
  // Upstream returns the filtered array as-is here (no re-sort), so relative input order is kept.
  assert.deepEqual(ids(result), ['stream:s1:a2', 's1:8']);
  assert.equal(byId(result, 'stream:s1:a1'), undefined);
});

// 15. A delta carrying only reasoning keeps the previous text.
test('delta carrying only reasoning keeps the previous text', () => {
  const live = [
    m({
      id: 'stream:s1:a1', sessionId: 's1', seq: Number.MAX_SAFE_INTEGER, role: 'assistant',
      text: '收到', createdAt: 777, pending: true, attemptId: 'a1', streamIndex: 1
    })
  ];
  const untouched = applyConversationEvent(live, {
    type: 'delta', sessionId: 's1', attemptId: 'a1', reasoning: 'thinking', index: 2
  });
  assert.equal(untouched, live);
  assert.equal(untouched[0].text, '收到');

  const updated = applyConversationEvent(live, {
    type: 'delta', sessionId: 's1', attemptId: 'a1', text: '收到', reasoning: 'thinking', index: 2
  });
  assert.equal(updated[0].text, '收到');
  assert.equal(updated[0].reasoning, 'thinking');
  assert.equal(updated[0].createdAt, 777);
});

// 16. Any other event type is returned untouched (same array identity).
test('returns messages untouched for unknown event types', () => {
  const messages = [m({ id: 'n1', seq: 1 })];
  const result = applyConversationEvent(messages, {
    type: 'ready', conversationId: 'c', serverId: 'd80ef80e'
  });
  assert.equal(result, messages);

  const statusOnly = applyConversationEvent(messages, {
    type: 'status', sessionId: 's', running: false, phase: 'idle', eventSeq: 56
  });
  assert.equal(statusOnly, messages);
});

// Bonus: cloneMessage produces an independent copy, including nested tool state.
test('cloneMessage copies fields without sharing nested tool state', () => {
  const original = m({
    id: 'copy', seq: 3, text: 'hi', reasoning: 'r', pending: true, attemptId: 'a',
    tool: { callId: 'c1', name: 'Bash', state: 'running' },
    attachments: [{ name: 'a.png', type: 'image' }]
  });
  const copy = cloneMessage(original);
  assert.deepEqual(copy, original);
  assert.notEqual(copy, original);
  assert.notEqual(copy.tool, original.tool);
  assert.notEqual(copy.attachments, original.attachments);
  copy.tool.state = 'completed';
  assert.equal(original.tool.state, 'running');
});

let passed = 0;
const failures = [];
for (const entry of tests) {
  try {
    entry.fn();
    passed += 1;
    console.log('ok   ' + entry.name);
  } catch (error) {
    failures.push(entry);
    console.log('FAIL ' + entry.name);
    console.log('     ' + (error && error.message ? error.message : String(error)));
  }
}

console.log('');
console.log(passed + ' passed / ' + failures.length + ' failed');
if (failures.length > 0) {
  process.exitCode = 1;
}

export { tests };
