/*
 * logic/Rooms.ets 的回归用例（P2-6 群管理）。
 *
 * 最危险的是「成员差异」与「管理员约束」：
 * - 成员 diff 算错会静默踢人或加错人；
 * - 管理员不在成员里时，"管理员先回答"会指向一个不在群里的人。
 *
 * 规则来源：宿主 `src/host/roster.js`（updateRoom）与 `groups.js`（mode 语义）。
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import {
  botNameOf, buildRoomPatch, describeMode, diffMembers, formOfRoom, translateChanges,
  validateRoomForm
} from '../main/ets/logic/Rooms.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

function room(overrides = {}) {
  return Object.assign({
    id: 'room-1', name: '研发小组', members: ['bot-a', 'bot-b'],
    admin: 'bot-a', notice: '每日 10 点同步', mode: 'admin'
  }, overrides);
}

test('表单校验：空名/超长/无成员', () => {
  const base = formOfRoom(room());
  assert.equal(validateRoomForm(Object.assign({}, base, { name: '   ' })).ok, false);
  assert.equal(validateRoomForm(Object.assign({}, base, { name: 'x'.repeat(61) })).ok, false);
  assert.equal(validateRoomForm(Object.assign({}, base, { members: [] })).ok, false);
});

test('表单校验：管理员必须在成员里', () => {
  const base = formOfRoom(room());
  assert.equal(validateRoomForm(Object.assign({}, base, { admin: 'bot-z' })).ok, false);
  assert.equal(validateRoomForm(Object.assign({}, base, { admin: 'bot-b' })).ok, true);
  // 允许不设管理员
  assert.equal(validateRoomForm(Object.assign({}, base, { admin: '' })).ok, true);
});

test('formOfRoom：mode 缺省按 admin', () => {
  assert.equal(formOfRoom(room({ mode: undefined })).mode, 'admin');
  assert.equal(formOfRoom(room({ mode: 'everyone' })).mode, 'everyone');
});

test('成员差异计算', () => {
  const diff = diffMembers(['a', 'b'], ['b', 'c']);
  assert.deepEqual(diff.added, ['c']);
  assert.deepEqual(diff.removed, ['a']);
  assert.deepEqual(diffMembers(['a'], ['a']).added, []);
  assert.deepEqual(diffMembers([], ['a']).removed, []);
});

test('没有任何变化时不生成载荷', () => {
  const before = room();
  assert.equal(buildRoomPatch(before, formOfRoom(before)), undefined);
});

test('只提交变化的字段', () => {
  const before = room();
  const form = formOfRoom(before);
  form.name = '新名字';
  const patch = buildRoomPatch(before, form);
  assert.equal(patch.name, '新名字');
  assert.equal(patch.notice, undefined);   // 没改的不出现
  assert.equal(patch.members, undefined);
  assert.equal(patch.mode, undefined);
});

test('改名去空格', () => {
  const before = room();
  const form = formOfRoom(before);
  form.name = '  新名字  ';
  assert.equal(buildRoomPatch(before, form).name, '新名字');
});

test('成员变化时提交全量成员', () => {
  const before = room();
  const form = formOfRoom(before);
  form.members = ['bot-a', 'bot-b', 'bot-c'];
  const patch = buildRoomPatch(before, form);
  assert.deepEqual(patch.members, ['bot-a', 'bot-b', 'bot-c']);
});

test('模式切换生成 mode', () => {
  const before = room({ mode: 'admin' });
  const form = formOfRoom(before);
  form.mode = 'everyone';
  assert.equal(buildRoomPatch(before, form).mode, 'everyone');
});

test('模式文案', () => {
  assert.equal(describeMode('admin'), '管理员先回答');
  assert.equal(describeMode('everyone'), '成员轮流回答');
  assert.equal(describeMode(undefined), '管理员先回答');
});

test('宿主变更说明翻译', () => {
  const lines = translateChanges([
    'plain messages now go to the admin first',
    'every member now replies in turn'
  ]);
  assert.deepEqual(lines, ['消息改为先交给管理员', '改为成员轮流回答']);
  // 未收录的原样返回
  assert.deepEqual(translateChanges(['something else']), ['something else']);
  assert.deepEqual(translateChanges(undefined), []);
});

test('Bot 名解析：找不到时回退 id', () => {
  const bots = [{ id: 'bot-a', name: 'Chief' }];
  assert.equal(botNameOf(bots, 'bot-a'), 'Chief');
  assert.equal(botNameOf(bots, 'bot-x'), 'bot-x');
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
