import assert from 'node:assert/strict';
import { busyMemberIds, memberProgress, toRoomRounds, toTeamWork } from '../main/ets/logic/GroupProgress';

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

test('work 投影保留群成员、独立 Bot 与审批，忽略坏记录', () => {
  const work = toTeamWork({
    bots: { a: { roomId: 'r', tool: 'shell', since: 1 }, bad: 'x' },
    rooms: { r: [{ botId: 'b', speaking: true }, { tool: 'bad' }] },
    approvals: [{ id: 'p', botId: 'c', roomId: 'r', answerable: true }, { id: 'bad' }]
  });
  assert.equal(work.bots.a.tool, 'shell');
  assert.equal(work.rooms.r.length, 1);
  assert.equal(work.rooms.r[0].speaking, true);
  assert.deepEqual(work.approvals.map(item => item.botId), ['c']);
});

test('room-progress 过滤畸形轮次与回复', () => {
  const rounds = toRoomRounds([
    { callId: 'one', speaking: 'b', replies: [{ botId: 'a', kind: 'lookup' }, { kind: 'bad' }] },
    { callId: 'missing-replies' },
    null
  ]);
  assert.equal(rounds.length, 1);
  assert.equal(rounds[0].speaking, 'b');
  assert.deepEqual(rounds[0].replies.map(reply => reply.botId), ['a']);
});

test('成员状态使用审批、输入和最新回复优先级', () => {
  const work = toTeamWork({
    rooms: { r: [{ botId: 'speaker', speaking: true }, { botId: 'worker' }] },
    approvals: [{ id: 'p', botId: 'waiting', roomId: 'r' }]
  });
  const rounds = toRoomRounds([{ callId: 'one', speaking: null, replies: [
    { botId: 'failed', kind: 'failed' }, { botId: 'lookup', kind: 'lookup' }, { botId: 'done' }
  ] }]);
  assert.equal(memberProgress('waiting', 'r', rounds, work).status, '等待审批');
  assert.equal(memberProgress('speaker', 'r', rounds, work).status, '正在输入…');
  assert.equal(memberProgress('failed', 'r', rounds, work).status, '未能回答');
  assert.equal(memberProgress('lookup', 'r', rounds, work).status, '正在回看聊天');
  assert.equal(memberProgress('done', 'r', rounds, work).status, '已回复');
  assert.equal(memberProgress('worker', 'r', rounds, work).status, '工作中');
});

test('忙碌成员只返回当前群成员且兼容 bots.roomId', () => {
  const work = toTeamWork({ bots: { a: { roomId: 'r' }, foreign: { roomId: 'other' } }, approvals: [
    { id: 'p', botId: 'b', roomId: 'r' }
  ] });
  assert.deepEqual(busyMemberIds(['a', 'b', 'foreign', 'idle'], 'r', work), ['a', 'b']);
});

let passed = 0;
const failures = [];
for (const entry of tests) {
  try { entry.fn(); passed += 1; console.log('ok   ' + entry.name); }
  catch (error) { failures.push(entry); console.log('FAIL ' + entry.name); console.log('     ' + error.message); }
}
console.log('');
console.log(passed + ' passed / ' + failures.length + ' failed');
if (failures.length > 0) process.exitCode = 1;
export { tests };
