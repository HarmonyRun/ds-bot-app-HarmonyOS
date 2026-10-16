/*
 * Efforts.ets 的回归用例。
 *
 * 直接运行：node entry/src/test/run.mjs
 *
 * 背景：2026-10-16 在 API 24 模拟器上用受控模拟主机复现了一个崩溃——
 * 主机对 `efforts` 返回不含 `efforts` 字段的应答时，页面把 `undefined`
 * 写进 `@State effortOptions`，下一次重渲染读 `.length` 直接抛 TypeError。
 * 这些用例锁定「投影永不返回 undefined、永不产出坏档位」这条契约。
 */

import assert from 'node:assert/strict';
import { toEffortOptions, toDefaultEffort } from '../main/ets/logic/Efforts.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

test('缺字段的应答返回空数组而不是 undefined', () => {
  // 崩溃复现：模拟主机返回 {"ok":true}
  assert.deepEqual(toEffortOptions({ ok: true }), []);
  assert.deepEqual(toEffortOptions({}), []);
  assert.deepEqual(toEffortOptions(undefined), []);
  assert.deepEqual(toEffortOptions(null), []);
  // 关键断言：调用方 `.length` 永远安全
  assert.equal(toEffortOptions({ ok: true }).length, 0);
});

test('efforts 不是数组时返回空数组', () => {
  assert.deepEqual(toEffortOptions({ efforts: 'low' }), []);
  assert.deepEqual(toEffortOptions({ efforts: {} }), []);
  assert.deepEqual(toEffortOptions({ efforts: 42 }), []);
});

test('正常应答被投影成强类型档位', () => {
  const result = toEffortOptions({
    efforts: [
      { id: 'low', name: '低', description: '更快' },
      { id: 'high', name: '高' }
    ],
    defaultEffort: 'low'
  });
  assert.equal(result.length, 2);
  assert.equal(result[0].id, 'low');
  assert.equal(result[0].name, '低');
  assert.equal(result[0].description, '更快');
  assert.equal(result[1].name, '高');
  assert.equal(result[1].description, undefined);
});

test('坏档位被丢弃：缺 id、id 非字符串、条目非对象', () => {
  const result = toEffortOptions({
    efforts: [
      { name: '没有 id' },
      { id: '', name: '空 id' },
      { id: 7, name: '数字 id' },
      null,
      'low',
      { id: 'ok', name: '可用' }
    ]
  });
  assert.equal(result.length, 1);
  assert.equal(result[0].id, 'ok');
});

test('name 缺失时回退到 id，保证 UI 有可读文案', () => {
  const result = toEffortOptions({ efforts: [{ id: 'medium' }] });
  assert.equal(result.length, 1);
  assert.equal(result[0].name, 'medium');
});

test('defaultEffort 只在是非空字符串时有效', () => {
  assert.equal(toDefaultEffort({ defaultEffort: 'low' }), 'low');
  assert.equal(toDefaultEffort({ defaultEffort: '' }), '');
  assert.equal(toDefaultEffort({ defaultEffort: 3 }), '');
  assert.equal(toDefaultEffort({}), '');
  assert.equal(toDefaultEffort(undefined), '');
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
