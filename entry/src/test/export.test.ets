/*
 * logic/Export.ets 的回归用例（P2-9 会话导出）。
 *
 * 导出内容会离开 App（贴工单、备份、喂给别的工具），
 * 格式错了不会报错，只是内容悄悄缺失——所以必须用测试锁住。
 *
 * 直接运行：node entry/src/test/run.mjs
 */
import assert from 'node:assert/strict';
import {
  exportConversation, exportFileName, formatTime, toJson, toMarkdown
} from '../main/ets/logic/Export.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

const AT = new Date('2026-10-18T10:30:00').getTime();

function messages() {
  return [
    { id: 'm1', sessionId: 's', seq: 1, role: 'user', text: '你好', createdAt: AT },
    { id: 'm2', sessionId: 's', seq: 2, role: 'assistant', text: '你好，有什么可以帮你？',
      reasoning: '用户打了招呼，回一句', createdAt: AT + 1000 },
    { id: 'm3', sessionId: 's', seq: 3, role: 'assistant', text: '',
      tool: { callId: 'c1', name: 'web_search', state: 'ok', durationMs: 1200, input: '{"q":"x"}' },
      createdAt: AT + 2000 }
  ];
}

test('时间格式化', () => {
  assert.equal(formatTime(AT).length, 19);
  assert.equal(formatTime('not-a-date'), '');
  assert.equal(formatTime(AT).startsWith('2026-10-18'), true);
});

test('Markdown 含标题、导出信息与每条消息', () => {
  const md = toMarkdown(messages(), '研发小组', AT);
  assert.equal(md.startsWith('# 研发小组'), true);
  assert.equal(md.includes('共 3 条消息'), true);
  assert.equal(md.includes('用户'), true);
  assert.equal(md.includes('助手'), true);
  assert.equal(md.includes('你好，有什么可以帮你？'), true);
});

test('Markdown 里思考过程用折叠块包裹', () => {
  const md = toMarkdown(messages(), 't', AT);
  assert.equal(md.includes('<details><summary>思考过程</summary>'), true);
  assert.equal(md.includes('用户打了招呼'), true);
});

test('Markdown 里工具调用渲染成一行', () => {
  const md = toMarkdown(messages(), 't', AT);
  assert.equal(md.includes('web_search'), true);
  assert.equal(md.includes('1200ms'), true);
});

test('代码围栏会随内容里最长反引号变长（不会提前闭合）', () => {
  const tricky = [{ id: 'm', sessionId: 's', seq: 1, role: 'assistant', text: '',
    reasoning: '这里有 ``` 三个反引号', createdAt: AT }];
  const md = toMarkdown(tricky, 't', AT);
  // 内容的 ``` 不能被当成结束围栏 → 输出围栏必须是 4 个反引号
  assert.equal(md.includes('````text'), true);
});

test('JSON 结构完整且可解析', () => {
  const text = toJson(messages(), '研发小组', AT);
  const parsed = JSON.parse(text);
  assert.equal(parsed.title, '研发小组');
  assert.equal(parsed.count, 3);
  assert.equal(parsed.messages.length, 3);
  assert.equal(parsed.messages[0].role, 'user');
  assert.equal(parsed.messages[1].reasoning, '用户打了招呼，回一句');
  assert.equal(parsed.messages[2].tool.name, 'web_search');
  assert.equal(parsed.messages[2].tool.input, '{"q":"x"}');
});

test('JSON 不带空的 reasoning/tool 字段', () => {
  const parsed = JSON.parse(toJson([{ id: 'm', sessionId: 's', seq: 1, role: 'user', text: 'x', createdAt: AT }], 't', AT));
  assert.equal('reasoning' in parsed.messages[0], false);
  assert.equal('tool' in parsed.messages[0], false);
});

test('没有 text 字段的工具消息也能导出（真机崩溃回归）', () => {
  // 主机对「只有工具调用」的消息不下发 text；这里必须不抛异常
  // 类型上 text 必填，运行时缺省 —— 用断言把这种"主机真实下发"的形状塞进去
  const onlyTool = [{ id: 'm', sessionId: 's', seq: 1, role: 'assistant',
    text: undefined as unknown as string,
    tool: { callId: 'c', name: 'web_search', state: 'ok' }, createdAt: AT }];
  const md = toMarkdown(onlyTool, 't', AT);
  assert.equal(md.includes('web_search'), true);
  const json = JSON.parse(toJson(onlyTool, 't', AT));
  assert.equal(json.messages[0].text, '');
});

test('空会话也能导出', () => {
  assert.equal(toMarkdown([], '空', AT).includes('共 0 条消息'), true);
  assert.equal(JSON.parse(toJson([], '空', AT)).count, 0);
});

test('exportConversation 按格式分发', () => {
  assert.equal(exportConversation(messages(), 't', 'markdown', AT).startsWith('#'), true);
  assert.equal(exportConversation(messages(), 't', 'json', AT).startsWith('{'), true);
});

test('文件名：去掉非法字符、带时间戳与扩展名', () => {
  const name = exportFileName('研发/小组:test', 'markdown', AT);
  assert.equal(name.endsWith('.md'), true);
  assert.equal(name.includes('/'), false);
  assert.equal(name.includes(':'), false);
  assert.equal(name.includes('20261018'), true);
  const json = exportFileName('x', 'json', AT);
  assert.equal(json.endsWith('.json'), true);
});

test('文件名为空时用兜底名', () => {
  const name = exportFileName('   ', 'markdown', AT);
  assert.equal(name.startsWith('conversation-'), true);
});

test('文件名过长会被截断', () => {
  const name = exportFileName('a'.repeat(100), 'markdown', AT);
  const base = name.substring(0, name.lastIndexOf('-2026'));
  assert.equal(base.length <= 40, true);
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
