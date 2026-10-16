/*
 * ViewUtil.ets 的回归用例。
 *
 * 直接运行：node entry/src/test/run.mjs
 *
 * 这三个函数原本是 Index 里的私有方法，零状态依赖却从无断言。
 * 其中 `isAuthFailure` 决定「是否清凭据回连接页」，判错的后果是用户卡死路或误登出。
 */

import assert from 'node:assert/strict';
import {
  conversationTime, isAuthFailure, isConfirmedLocally, questionKeyOf
} from '../main/ets/logic/ViewUtil.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

test('isAuthFailure：401/403 一律视为需要重新配对', () => {
  assert.equal(isAuthFailure({ statusCode: 401 }), true);
  assert.equal(isAuthFailure({ statusCode: 403 }), true);
});

test('isAuthFailure：明确的鉴权错误码也视为失败', () => {
  assert.equal(isAuthFailure({ code: 'unauthorized' }), true);
  assert.equal(isAuthFailure({ code: 'server_changed' }), true);
  assert.equal(isAuthFailure({ code: 'invalid_session' }), true);
});

test('isAuthFailure：其它错误不算鉴权失败（不能误登出）', () => {
  assert.equal(isAuthFailure({ statusCode: 500 }), false);
  assert.equal(isAuthFailure({ statusCode: 404, code: 'not_found' }), false);
  assert.equal(isAuthFailure({ code: 'network_error' }), false);
  assert.equal(isAuthFailure({}), false);
  assert.equal(isAuthFailure(new Error('boom')), false);
});

test('isAuthFailure：statusCode 优先于 code 的组合也要正确', () => {
  assert.equal(isAuthFailure({ statusCode: 403, code: 'forbidden' }), true);
  assert.equal(isAuthFailure({ statusCode: 200, code: 'unauthorized' }), true);
});

test('conversationTime：输出补零的 HH:mm（本地时区）', () => {
  // 用本地时间构造，避免测试受时区影响
  const morning = new Date(2026, 9, 16, 9, 5).getTime();
  assert.equal(conversationTime(morning), '09:05');
  const evening = new Date(2026, 9, 16, 23, 59).getTime();
  assert.equal(conversationTime(evening), '23:59');
});

test('conversationTime：字符串时间戳与 ISO 串都能解析', () => {
  const base = new Date(2026, 9, 16, 14, 30);
  assert.equal(conversationTime(String(base.getTime())), '14:30');
  assert.equal(conversationTime(base.toISOString()), '14:30');
});

test('conversationTime：缺失或不可解析时返回空串（不渲染 NaN）', () => {
  assert.equal(conversationTime(undefined), '');
  assert.equal(conversationTime('not-a-date'), '');
  assert.equal(conversationTime(NaN), '');
});

test('isConfirmedLocally：本地占位被同 requestId 的正式消息确认', () => {
  const local = { id: 'local-1', sessionId: 's', seq: 1, role: 'user', text: 'x', requestId: 'req-1', createdAt: 0 };
  const confirmed = [
    local,
    { id: 'server-9', sessionId: 's', seq: 1, role: 'user', text: 'x', requestId: 'req-1', createdAt: 0 }
  ];
  assert.equal(isConfirmedLocally(local, confirmed), true);
});

test('isConfirmedLocally：只有自己一条时不算确认', () => {
  const local = { id: 'local-1', sessionId: 's', seq: 1, role: 'user', text: 'x', requestId: 'req-1', createdAt: 0 };
  assert.equal(isConfirmedLocally(local, [local]), false);
});

test('isConfirmedLocally：非本地消息、无 requestId、requestId 不匹配都算未确认', () => {
  const server = { id: 'server-1', sessionId: 's', seq: 1, role: 'user', text: 'x', requestId: 'req-1', createdAt: 0 };
  assert.equal(isConfirmedLocally(server, [server, { ...server, id: 'server-2' }]), false);

  const noRequest = { id: 'local-2', sessionId: 's', seq: 2, role: 'user', text: 'y', createdAt: 0 };
  assert.equal(isConfirmedLocally(noRequest, [noRequest]), false);

  const local = { id: 'local-3', sessionId: 's', seq: 3, role: 'user', text: 'z', requestId: 'req-3', createdAt: 0 };
  const other = { id: 'server-4', sessionId: 's', seq: 3, role: 'user', text: 'z', requestId: 'req-other', createdAt: 0 };
  assert.equal(isConfirmedLocally(local, [local, other]), false);
});

test('isConfirmedLocally：空列表不算确认', () => {
  const local = { id: 'local-1', sessionId: 's', seq: 1, role: 'user', text: 'x', requestId: 'req-1', createdAt: 0 };
  assert.equal(isConfirmedLocally(local, []), false);
});

test('questionKeyOf：拼接 sessionId 与 questionId', () => {
  assert.equal(questionKeyOf('sess-1', 'q-1'), 'sess-1:q-1');
  assert.equal(questionKeyOf('', 'q'), ':q');
});

const passed = [];
const failed = [];
for (const item of tests) {
  try {
    item.fn();
    passed.push(item.name);
    console.log(`ok   ${item.name}`);
  } catch (error) {
    failed.push(item.name);
    console.log(`FAIL ${item.name}`);
    console.log(`     ${error.message}`);
  }
}
console.log(`\n${passed.length} passed / ${failed.length} failed`);
if (failed.length > 0) process.exitCode = 1;
export { tests };
