/*
 * ConversationAvatar.ets 的回归用例。
 *
 * 直接运行：node entry/src/test/run.mjs
 *
 * 这些是**纯几何/推导**断言，不需要设备就能跑——这正是把它们从 3000 行的页面里
 * 抽出来的价值：叠加头像的边长与位置以前只能靠截图目测。
 */

import assert from 'node:assert/strict';
import {
  botOf, isMainAvatar, isMainBotIdOf, isMainConversation,
  mainBotIdsOf, memberSlotCount, memberSlotOffset, memberSlotSize, roomMembersOf
} from '../main/ets/logic/ConversationAvatar.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

/** 构造一个团队：主 Bot 为 chief，成员按需指定。 */
function makeTeam(memberIds) {
  const bots = [
    { id: 'chief', name: 'Chief', sessionId: 's-chief' },
    { id: 'a', name: 'A', sessionId: 's-a' },
    { id: 'b', name: 'B', sessionId: 's-b' },
    { id: 'c', name: 'C', sessionId: 's-c' },
    { id: 'd', name: 'D', sessionId: 's-d' }
  ];
  return {
    bots: bots,
    rooms: memberIds === undefined ? [] : [{ id: 'room-1', members: memberIds, name: 'R' }],
    models: [],
    mainBotId: 'chief',
    mainBotIds: ['chief']
  };
}

function roomConversation(id) {
  return { id: id, kind: 'room', name: 'R', sessionId: 's-room' };
}

test('主 Bot 列表：优先 mainBotIds，回退 mainBotId，都没有则空', () => {
  assert.deepEqual(mainBotIdsOf(makeTeam(['chief'])), ['chief']);
  assert.deepEqual(mainBotIdsOf({ bots: [], rooms: [], models: [], mainBotId: 'x' }), ['x']);
  assert.deepEqual(mainBotIdsOf({ bots: [], rooms: [], models: [], mainBotIds: [] }), []);
  assert.deepEqual(mainBotIdsOf({ bots: [], rooms: [], models: [] }), []);
});

test('isMainConversation 兼容 bot: 前缀', () => {
  const team = makeTeam(['chief']);
  assert.equal(isMainConversation(team, { id: 'chief', kind: 'bot', name: 'C', sessionId: 's' }), true);
  assert.equal(isMainConversation(team, { id: 'bot:chief', kind: 'bot', name: 'C', sessionId: 's' }), true);
  assert.equal(isMainConversation(team, { id: 'other', kind: 'bot', name: 'O', sessionId: 's' }), false);
});

test('botOf 兼容裸 id、bot: 前缀与会话 sessionId', () => {
  const team = makeTeam(['chief']);
  assert.equal(botOf(team, { id: 'a', kind: 'bot', name: 'A', sessionId: 'x' })?.id, 'a');
  assert.equal(botOf(team, { id: 'bot:b', kind: 'bot', name: 'B', sessionId: 'x' })?.id, 'b');
  assert.equal(botOf(team, { id: 'nope', kind: 'bot', name: 'N', sessionId: 's-c' })?.id, 'c');
  assert.equal(botOf(team, { id: 'nope', kind: 'bot', name: 'N', sessionId: 'zz' }), undefined);
});

test('群成员按 Room.members 顺序解析；未知 id 被跳过', () => {
  const team = makeTeam(['b', 'chief', 'ghost']);
  const members = roomMembersOf(team, roomConversation('room-1'));
  assert.deepEqual(members.map((m) => m.id), ['b', 'chief']);
});

test('群成员为空时回退为该团队第一个 Bot（上游规则）', () => {
  const team = makeTeam([]);
  const members = roomMembersOf(team, roomConversation('room-1'));
  assert.deepEqual(members.map((m) => m.id), ['chief']);
});

test('找不到 room 时返回空（不误回退）', () => {
  const team = makeTeam(['chief']);
  assert.deepEqual(roomMembersOf(team, roomConversation('other-room')), []);
});

test('叠加个数：1 显示 1，5 人以上截断为 4', () => {
  const one = makeTeam(['chief']);
  assert.equal(memberSlotCount(one, roomConversation('room-1')), 1);

  const two = makeTeam(['chief', 'a']);
  assert.equal(memberSlotCount(two, roomConversation('room-1')), 2);

  const five = makeTeam(['chief', 'a', 'b', 'c', 'd']);
  assert.equal(memberSlotCount(five, roomConversation('room-1')), 4);
});

test('叠加边长：1 人铺满 / 2 人 0.66 / 3 人以上 0.54', () => {
  const size = 50;
  assert.equal(memberSlotSize(makeTeam(['chief']), roomConversation('room-1'), size), 50);
  assert.equal(memberSlotSize(makeTeam(['chief', 'a']), roomConversation('room-1'), size), 33);
  const three = makeTeam(['chief', 'a', 'b']);
  assert.equal(memberSlotSize(three, roomConversation('room-1'), size), 27);
});

test('2 人对角摆放：左上 + 右下', () => {
  const team = makeTeam(['chief', 'a']);
  const item = roomConversation('room-1');
  const size = 50;
  assert.deepEqual(memberSlotOffset(team, item, 0, size), { x: 0, y: 0 });
  assert.deepEqual(memberSlotOffset(team, item, 1, size), { x: 50 - 33, y: 50 - 33 });
});

test('3 人呈上中 + 左下 + 右下', () => {
  const team = makeTeam(['chief', 'a', 'b']);
  const item = roomConversation('room-1');
  const size = 50;
  const inner = 27;
  assert.deepEqual(memberSlotOffset(team, item, 0, size), { x: 50 * 0.23, y: 0 });
  assert.deepEqual(memberSlotOffset(team, item, 1, size), { x: 0, y: 50 - inner });
  assert.deepEqual(memberSlotOffset(team, item, 2, size), { x: 50 - inner, y: 50 - inner });
});

test('4 人为四角', () => {
  const team = makeTeam(['chief', 'a', 'b', 'c']);
  const item = roomConversation('room-1');
  const size = 50;
  const inner = 27;
  assert.deepEqual(memberSlotOffset(team, item, 0, size), { x: 0, y: 0 });
  assert.deepEqual(memberSlotOffset(team, item, 1, size), { x: 50 - inner, y: 0 });
  assert.deepEqual(memberSlotOffset(team, item, 2, size), { x: 0, y: 50 - inner });
  assert.deepEqual(memberSlotOffset(team, item, 3, size), { x: 50 - inner, y: 50 - inner });
});

test('所有叠加头像都落在群头像外框内', () => {
  const size = 50;
  for (const ids of [['chief'], ['chief', 'a'], ['chief', 'a', 'b'], ['chief', 'a', 'b', 'c']]) {
    const team = makeTeam(ids);
    const item = roomConversation('room-1');
    const inner = memberSlotSize(team, item, size);
    for (let index = 0; index < memberSlotCount(team, item); index++) {
      const offset = memberSlotOffset(team, item, index, size);
      assert.ok(offset.x >= 0 && offset.y >= 0, `x/y 应为非负：${JSON.stringify(offset)}`);
      assert.ok(offset.x + inner <= size + 0.001, `右边界越出：${JSON.stringify(offset)}`);
      assert.ok(offset.y + inner <= size + 0.001, `下边界越出：${JSON.stringify(offset)}`);
    }
  }
});

test('isMainAvatar：Bot 会话看 Bot 是否主 Bot，群会话回退会话判定', () => {
  const team = makeTeam(['chief']);
  assert.equal(isMainAvatar(team, { id: 'chief', kind: 'bot', name: 'C', sessionId: 's-chief' }), true);
  assert.equal(isMainAvatar(team, { id: 'a', kind: 'bot', name: 'A', sessionId: 's-a' }), false);
  // 群会话没有对应 Bot，回退到 isMainConversation（room id 不在主 Bot 列表 → false）
  assert.equal(isMainAvatar(team, roomConversation('room-1')), false);
});

test('isMainBotIdOf 与 mainBotIdsOf 一致', () => {
  const team = makeTeam(['chief']);
  assert.equal(isMainBotIdOf(team, 'chief'), true);
  assert.equal(isMainBotIdOf(team, 'a'), false);
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
