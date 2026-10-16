import assert from 'node:assert/strict';
import {
  composeReferenceDraft,
  mentionCandidates,
  mentionQuery,
  referenceDraft,
  sessionMention
} from '../main/ets/logic/Composer';
import { Bot, Room } from '../main/ets/model/Models';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

test('会话引用可保存 Unicode、右括号、反斜杠和正文缩进', () => {
  const sessionId = '会话/🪄';
  const label = '资料 ] 与 \\ notes';
  const mention = sessionMention(sessionId, label);
  const reference = { sessionId: sessionId, label: label, mention: mention };
  const text = '    code stays indented\n\nMore text';
  const draft = composeReferenceDraft(text, [reference]);
  assert.deepEqual(referenceDraft(draft), { text: text, references: [reference] });
  assert.equal(composeReferenceDraft(referenceDraft(draft).text, referenceDraft(draft).references), draft);
});

test('损坏的引用保持为可编辑正文', () => {
  const text = '@[broken](dsh-session:not-valid)\n\nkeep me';
  assert.deepEqual(referenceDraft(text), { text: text, references: [] });
});

test('@ 补全跟随光标并排除邮箱、链接、路径、选区和代码', () => {
  assert.deepEqual(mentionQuery('hello @Ma later', { start: 9, end: 9 }),
    { start: 6, end: 9, query: 'Ma' });
  const ignored = ['a@Ma', 'example.com/@Ma', '@docs/file', '@docs\\file', '`@Ma', '```js\n@Ma'];
  for (const text of ignored) {
    assert.equal(mentionQuery(text, { start: text.length, end: text.length }), undefined, text);
  }
  assert.equal(mentionQuery('@Ma', { start: 1, end: 3 }), undefined);
});

test('单聊提及排除自身，群聊按成员顺序并提供所有人', () => {
  const bots: Bot[] = [
    { id: 'a', name: 'Alpha' },
    { id: 'b', name: 'Beta' },
    { id: 'c', name: 'New Bot' }
  ];
  const room: Room = { id: 'g', name: 'Group', members: ['c', 'a'] };
  assert.deepEqual(mentionCandidates(bots, 'a', undefined, '', '所有人').map(row => row.name),
    ['Beta', 'New Bot']);
  assert.deepEqual(mentionCandidates(bots, undefined, room, '', '所有人').map(row => row.name),
    ['New Bot', 'Alpha', '所有人']);
  assert.equal(mentionCandidates(bots, 'a', undefined, 'New Bot ', '所有人').length, 0);
  assert.equal(mentionCandidates(bots, 'a', undefined, 'New ', '所有人').length, 1);
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
if (failures.length > 0) process.exitCode = 1;
export { tests };
