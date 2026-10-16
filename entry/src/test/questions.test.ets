import assert from 'node:assert/strict';
import { questionsForConversation, toQuestions } from '../main/ets/logic/Questions';

const tests = [];
function test(name, fn) { tests.push({ name, fn }); }

test('问题投影保留选项描述、单选多选与自定义回答开关', () => {
  const result = toQuestions({
    session: {
      id: 'q1', header: '计划', question: '下一步？', detail: '选择一个方向',
      options: ['直接做', { label: '先验证', value: 'verify', description: '风险更低' }],
      multiSelect: true, allowCustom: true, conversationId: 'chief'
    }
  });
  assert.equal(result.session.sessionId, 'session');
  assert.equal(result.session.options[0].label, '直接做');
  assert.equal(result.session.options[1].value, 'verify');
  assert.equal(result.session.options[1].description, '风险更低');
  assert.equal(result.session.multiSelect, true);
  assert.equal(result.session.allowCustom, true);
});

test('问题投影忽略坏记录和无标签选项', () => {
  const result = toQuestions({ broken: { text: 'missing id' }, valid: { id: 'q', options: [{ description: 'bad' }, 'Yes'] } });
  assert.equal(result.broken, undefined);
  assert.deepEqual(result.valid.options.map(option => option.label), ['Yes']);
});

test('conversationId 优先归属，旧数据回退 sessionId', () => {
  const questions = toQuestions({
    hidden: { id: 'group-q', conversationId: 'room', options: [] },
    chiefSession: { id: 'bot-q', options: [] },
    elsewhere: { id: 'other-q', conversationId: 'other', options: [] }
  });
  const team = {
    bots: [{ id: 'chief', name: 'Chief', sessionId: 'chiefSession' }],
    rooms: [{ id: 'room', name: 'Group', members: ['chief'] }],
    models: [], questions: questions
  };
  const botRows = questionsForConversation(team, { id: 'bot:chief', kind: 'bot', name: 'Chief', sessionId: 'chiefSession' });
  const roomRows = questionsForConversation(team, { id: 'room', kind: 'room', name: 'Group', sessionId: 'publicRoom' });
  assert.deepEqual(botRows.map(row => row.question.id), ['bot-q']);
  assert.deepEqual(roomRows.map(row => row.question.id), ['group-q']);
  assert.equal(roomRows[0].sessionId, 'hidden');
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
