/*
 * Markdown.ets 的纯函数测试。
 *
 * 直接运行：
 *     node entry/src/test/run.mjs
 *     期望输出：全部用例 passed、0 failed
 *
 * 执行器（entry/src/test/run.mjs）会把 ../main/ets/logic/Markdown.ets 复制成
 * 临时 .ts 并用 DevEco 自带 tsc 擦除类型后执行；本文件保持纯 JavaScript 语义。
 */

import assert from 'node:assert/strict';
import { parseMarkdown, parseSpans, spansToPlainText, markdownToPlainText, safeMarkdownLink, blockToPlainText } from '../main/ets/logic/Markdown.ets';

const tests = [];
function test(name, fn) {
  tests.push({ name, fn });
}

/** 取第一个块的纯文本。 */
function first(input) {
  return blockToPlainText(parseMarkdown(input)[0]);
}

// ------------------------------------------------------------------ 块级

test('空文本解析为空数组', () => {
  assert.deepEqual(parseMarkdown(''), []);
  assert.deepEqual(parseMarkdown('\n\n  \n'), []);
});

test('普通段落', () => {
  const blocks = parseMarkdown('hello world');
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].kind, 'paragraph');
  assert.equal(first('hello world'), 'hello world');
});

test('多行段落保留换行为 softbreak', () => {
  const spans = parseMarkdown('line one\nline two')[0].spans;
  assert.equal(spans.some(s => s.kind === 'softbreak'), true);
  assert.equal(spansToPlainText(spans), 'line one\nline two');
});

test('两级标题带 level', () => {
  const blocks = parseMarkdown('# Title\n\ntext\n\n### Deep');
  assert.equal(blocks[0].kind, 'heading');
  assert.equal(blocks[0].level, 1);
  assert.equal(blocks[1].kind, 'paragraph');
  assert.equal(blocks[2].kind, 'heading');
  assert.equal(blocks[2].level, 3);
});

test('围栏代码块保留原文与语言名', () => {
  const blocks = parseMarkdown('```ts\nconst a = 1;\n**not bold**\n```');
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].kind, 'code');
  assert.equal(blocks[0].info, 'ts');
  assert.equal(blocks[0].code, 'const a = 1;\n**not bold**');
});

test('未闭合的围栏代码块也能解析', () => {
  const blocks = parseMarkdown('```\nabc');
  assert.equal(blocks[0].kind, 'code');
  assert.equal(blocks[0].code, 'abc');
});

test('分隔线三种写法', () => {
  for (const input of ['---', '***', '___', '- - -']) {
    assert.equal(parseMarkdown(input)[0].kind, 'rule', input);
  }
});

test('无序列表', () => {
  const blocks = parseMarkdown('- one\n- two\n* three');
  assert.equal(blocks[0].kind, 'list');
  assert.equal(blocks[0].list.ordered, false);
  assert.equal(blocks[0].list.items.length, 3);
  assert.equal(first('- one\n- two'), '• one\n• two');
});

test('有序列表保留起始序号', () => {
  const blocks = parseMarkdown('3. three\n4. four');
  assert.equal(blocks[0].list.ordered, true);
  assert.deepEqual(blocks[0].list.items.map(i => i.marker), [3, 4]);
  assert.equal(first('3. three\n4. four'), '3. three\n4. four');
});

test('列表支持一层嵌套', () => {
  const blocks = parseMarkdown('- parent\n  - child');
  const list = blocks[0].list;
  assert.equal(list.items.length, 1);
  assert.equal(list.items[0].child.items.length, 1);
  assert.equal(blockToPlainText(blocks[0]), '• parent\n  • child');
});

test('引用块递归解析', () => {
  const blocks = parseMarkdown('> quoted **bold**\n> second line');
  assert.equal(blocks[0].kind, 'quote');
  assert.equal(blocks[0].blocks.length, 1);
  assert.equal(blocks[0].blocks[0].kind, 'paragraph');
  assert.equal(blockToPlainText(blocks[0]), 'quoted bold\nsecond line');
});

test('表格解析表头与数据行', () => {
  const blocks = parseMarkdown('| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |');
  assert.equal(blocks.length, 1);
  assert.equal(blocks[0].kind, 'table');
  assert.equal(blocks[0].rows.length, 3);
  assert.equal(blocks[0].rows[0].cells[0].header, true);
  assert.equal(blocks[0].rows[0].cells.length, 2);
  assert.equal(blocks[0].rows[2].cells[1].header, false);
  assert.equal(blockToPlainText(blocks[0]), 'A | B\n1 | 2\n3 | 4');
});

test('表格后紧跟段落不会串行', () => {
  const blocks = parseMarkdown('| A |\n| --- |\n| 1 |\n\nafter table');
  assert.equal(blocks[0].kind, 'table');
  assert.equal(blocks[1].kind, 'paragraph');
  assert.equal(blockToPlainText(blocks[1]), 'after table');
});

test('标题内的行内语法生效', () => {
  const block = parseMarkdown('## a `code` b')[0];
  assert.equal(block.level, 2);
  assert.equal(spansToPlainText(block.spans), 'a code b');
  assert.equal(block.spans.some(s => s.kind === 'code'), true);
});

// ------------------------------------------------------------------ 行内

test('粗体与斜体', () => {
  const spans = parseSpans('a **b** c *d* e');
  assert.deepEqual(spans.map(s => s.kind), ['text', 'strong', 'text', 'em', 'text']);
  assert.equal(spansToPlainText(spans), 'a b c d e');
});

test('下划线写法与删除线', () => {
  assert.equal(parseSpans('__bold__')[0].kind, 'strong');
  assert.equal(parseSpans('_italic_')[0].kind, 'em');
  assert.equal(parseSpans('~~gone~~')[0].kind, 'strike');
});

test('行内代码里的星号不被当作强调', () => {
  const spans = parseSpans('use `a ** b` here');
  const code = spans.find(s => s.kind === 'code');
  assert.ok(code);
  assert.equal(code.text, 'a ** b');
  assert.equal(spans.some(s => s.kind === 'strong'), false);
});

test('链接与图片', () => {
  const spans = parseSpans('see [docs](https://example.com/x) and ![pic](https://example.com/p.png)');
  const link = spans.find(s => s.kind === 'link');
  const image = spans.find(s => s.kind === 'image');
  assert.equal(link.text, 'docs');
  assert.equal(link.href, 'https://example.com/x');
  assert.equal(image.text, 'pic');
  assert.equal(image.href, 'https://example.com/p.png');
});

test('裸 URL 自动变成链接', () => {
  const spans = parseSpans('go to https://example.com/a?b=1 now');
  const link = spans.find(s => s.kind === 'link');
  assert.ok(link);
  assert.equal(link.href, 'https://example.com/a?b=1');
  assert.equal(spansToPlainText(spans), 'go to https://example.com/a?b=1 now');
});

test('提及 @名字 被单独切出', () => {
  const spans = parseSpans('hi @Searcher please');
  const mention = spans.find(s => s.kind === 'mention');
  assert.ok(mention);
  assert.equal(mention.text, '@Searcher');
});

test('嵌套强调会带上组合样式', () => {
  // `**bold *and italic***`：外层 strong，内层 em 叠加 strong
  const spans = parseSpans('**bold *and italic***');
  const em = spans.find(s => s.kind === 'em');
  assert.ok(em, '应解析出内层斜体');
  assert.equal(em.extra, 'strong');
  assert.equal(em.text, 'and italic');
  assert.equal(spans.some(s => s.kind === 'strong'), true);
  assert.equal(spansToPlainText(spans), 'bold and italic');

  // 强调内含配对强调，且闭合定界符必须取第一个而不是最后一个
  const mixed = parseSpans('**a *b* c**');
  assert.deepEqual(mixed.map(s => s.kind), ['strong', 'em', 'strong']);
  assert.equal(spansToPlainText(mixed), 'a b c');
});

test('未闭合的标记按普通文本处理', () => {
  const spans = parseSpans('a ** b');
  assert.equal(spansToPlainText(spans), 'a ** b');
});

// ------------------------------------------------------------------ 其它

test('markdownToPlainText 处理混合文档', () => {
  const text = '# T\n\n- a\n- b\n\n```js\nx\n```\n\n> q';
  assert.equal(markdownToPlainText(text), 'T\n• a\n• b\nx\nq');
});

test('safeMarkdownLink 只放行安全协议', () => {
  assert.equal(safeMarkdownLink('https://example.com'), 'https://example.com');
  assert.equal(safeMarkdownLink('http://example.com'), 'http://example.com');
  assert.equal(safeMarkdownLink('mailto:a@b.c'), 'mailto:a@b.c');
  assert.equal(safeMarkdownLink('javascript:alert(1)'), undefined);
  assert.equal(safeMarkdownLink('file:///etc/passwd'), undefined);
  assert.equal(safeMarkdownLink('https://user:pw@example.com'), undefined);
});

test('长文本不会死循环（防回溯保护）', () => {
  const input = ('**a** '.repeat(2000)) + 'tail';
  const spans = parseSpans(input);
  assert.equal(spans.length > 0, true);
});

test('中文与 emoji 不被破坏', () => {
  assert.equal(markdownToPlainText('你好 **世界** 🐳'), '你好 世界 🐳');
});

test('表格紧跟标题行（无空行）不会被吞成段落', () => {
  // 真实回复里的常见写法：`**2) 表格**` 下一行直接就是表格
  const blocks = parseMarkdown([
    '**2) 表格**',
    '| 名称 | 说明 |',
    '| --- | --- |',
    '| a | b |'
  ].join('\n'));
  assert.deepEqual(blocks.map((b) => b.kind), ['paragraph', 'table']);
  assert.equal(blocks[1].rows.length, 2);
  assert.equal(blocks[0].spans.map((s) => s.text).join(''), '2) 表格');
});

test('表格前后都有内容时仍能识别', () => {
  const blocks = parseMarkdown([
    '**1) 代码块**',
    '```ts',
    'const a = 1;',
    '```',
    '',
    '**2) 表格**',
    '| 名称 | 说明 |',
    '| --- | --- |',
    '| a | b |',
    '',
    '**3) 结尾**'
  ].join('\n'));
  assert.deepEqual(blocks.map((b) => b.kind), ['paragraph', 'code', 'paragraph', 'table', 'paragraph']);
  assert.equal(blocks[3].rows.length, 2);
});

test('表格分隔行必须在下一行才算表格', () => {
  // 只有表头、没有分隔行时保持段落，不要误判成表格
  const blocks = parseMarkdown(['| 名称 | 说明 |', '| a | b |'].join('\n'));
  assert.deepEqual(blocks.map((b) => b.kind), ['paragraph']);
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
