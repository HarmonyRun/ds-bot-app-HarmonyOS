/**
 * 轻量 Markdown 解析器（P1-3）。
 *
 * 为什么自己写：上游用 `markdown-it`（npm 依赖），而 ArkTS 工程不引入 npm 包。
 * 本解析器只覆盖上游 `MarkdownText.tsx` 实际渲染的那部分语义，并输出一个
 * **扁平、显式**的模型，便于 ArkTS 渲染（ArkTS 不支持结构类型，也不便做递归组件）。
 *
 * 支持：
 * - 块：标题 `#`…`######`、围栏代码 ``` / ~~~、无序与有序列表（含嵌套）、引用 `>`、
 *   分隔线 `---` / `***`、表格（GFM 管道表）、段落
 * - 行内：`**粗体**` / `__粗体__`、`*斜体*` / `_斜体_`、`~~删除线~~`、`` `行内代码` ``、
 *   `[文本](链接)`、`![alt](图片)`、URL 自动链接（http/https）、裸换行
 * - 提及：`@名字` 会被单独切出来（渲染层可高亮）
 *
 * 不支持（与上游的差异，写在这里避免误以为已支持）：
 * - HTML 原文（上游也配置了 `html: false`，即不解析 HTML，行为一致）
 * - 引用式链接、脚注、任务列表复选框、嵌套引用超过一层、行内公式
 *
 * 解析结果是**纯数据**，不依赖 ArkUI，因此可以直接跑 Node 单测（见 entry/src/test）。
 */

/** 行内片段类型。 */
export type SpanKind = 'text' | 'strong' | 'em' | 'strike' | 'code' | 'link' | 'image' | 'mention' | 'softbreak';

/** 行内片段。`href` 仅对 link / image 有意义。 */
export interface Span {
  kind: SpanKind;
  text: string;
  href?: string;
  /** 组合样式（例如 `**_加粗斜体_**`），渲染时叠加。 */
  extra?: string;
}

/** 表格单元格。 */
export interface TableCell {
  header: boolean;
  spans: Span[];
}

/** 表格行。 */
export interface TableRow {
  cells: TableCell[];
}

/** 块类型。 */
export type BlockKind = 'paragraph' | 'heading' | 'code' | 'list' | 'quote' | 'rule' | 'table';

/** 列表项（支持一层嵌套）。 */
export interface ListItem {
  /** 序号（有序列表用），无序列表为 0。 */
  marker: number;
  spans: Span[];
  /** 嵌套的子列表；没有则为 undefined。 */
  child?: ListBlock;
}

/** 列表块。 */
export interface ListBlock {
  ordered: boolean;
  items: ListItem[];
}

/**
 * 块。
 * - `paragraph` / `heading`：用 `spans`，`level` 是标题层级
 * - `code`：用 `code`，`info` 是语言名
 * - `list`：用 `list`
 * - `quote`：用 `blocks`（引用的内容按块递归）
 * - `rule`：无内容
 * - `table`：用 `rows`
 */
export interface Block {
  kind: BlockKind;
  spans: Span[];
  level: number;
  code: string;
  info: string;
  list?: ListBlock;
  blocks: Block[];
  rows: TableRow[];
}

function block(kind: BlockKind): Block {
  return { kind: kind, spans: [], level: 0, code: '', info: '', blocks: [], rows: [] };
}

function span(kind: SpanKind, text: string, href?: string, extra?: string): Span {
  const value: Span = { kind: kind, text: text };
  if (href !== undefined) value.href = href;
  if (extra !== undefined) value.extra = extra;
  return value;
}

/** 把 `extra` 样式标记合并进片段（用于 `**a**` 内再出现 `*b*` 的情况）。 */
function withExtra(item: Span, extra: string): Span {
  const combined = item.extra === undefined ? extra : `${item.extra} ${extra}`;
  return span(item.kind, item.text, item.href, combined);
}

// ---------------------------------------------------------------- 行内解析

const URL_PATTERN = /https?:\/\/[^\s<>()\[\]]+/u;
const MENTION_PATTERN = /@[\w\u4e00-\u9fa5-]{1,32}/u;

/** 一个候选标记在行内的位置与语义。 */
interface Marker {
  index: number;
  length: number;
  kind: SpanKind;
  /** 标记之间的内容（code 是原文，link/image 是标签，其余是内部 Markdown）。 */
  raw: string;
  href?: string;
}

function marker(index: number, length: number, kind: SpanKind, raw: string, href?: string): Marker {
  const value: Marker = { index: index, length: length, kind: kind, raw: raw };
  if (href !== undefined) value.href = href;
  return value;
}

/**
 * 在 `from` 之后按**字符位置**找最早的标记；同一位置按优先级取舍
 * （图片 > 链接 > 行内代码 > 粗体 > 删除线 > 斜体 > 裸链接 > 提及）。
 *
 * 之所以要按位置找而不是「每种模式各自 `indexOf` 再比较」：后者会把 `_italic_` 里的
 * `_` 误判成 `__` 的开头，也会把闭合标记当成起始标记。
 */
function nextMarker(text: string, from: number): Marker | undefined {
  let best: Marker | undefined = undefined;
  const prefer = (candidate: Marker | undefined, priority: number): void => {
    if (candidate === undefined) return;
    if (best === undefined || candidate.index < best.index) {
      best = candidate;
      return;
    }
    if (candidate.index === best.index && priority < priorityOf(best.kind)) best = candidate;
  };

  for (let i = from; i < text.length; i++) {
    const ch = text.charAt(i);
    if (ch === '`') {
      const close = text.indexOf('`', i + 1);
      if (close > i + 1) prefer(marker(i, close - i + 1, 'code', text.slice(i + 1, close)), 0);
    } else if (ch === '!') {
      if (text.charAt(i + 1) === '[') {
        const hit = linkMarker(text, i, true);
        if (hit !== undefined) prefer(hit, 1);
      }
    } else if (ch === '[') {
      const hit = linkMarker(text, i, false);
      if (hit !== undefined) prefer(hit, 2);
    } else if (ch === '*') {
      const strong = text.startsWith('**', i) ? findCloser(text, i + 2, '**') : -1;
      if (strong > i + 2) {
        prefer(marker(i, strong - i + 2, 'strong', text.slice(i + 2, strong)), 3);
      } else if (strong < 0 && !text.startsWith('**', i + 1)) {
        const em = findClosing(text, i, '*');
        if (em > i + 1) prefer(marker(i, em - i + 1, 'em', text.slice(i + 1, em)), 5);
      }
    } else if (ch === '_') {
      const wordBefore = i > 0 && isWordChar(text.charAt(i - 1));
      if (wordBefore) continue;
      const strong = text.startsWith('__', i) ? findCloser(text, i + 2, '__') : -1;
      if (strong > i + 2) {
        prefer(marker(i, strong - i + 2, 'strong', text.slice(i + 2, strong)), 3);
      } else if (strong < 0) {
        const em = findClosing(text, i, '_');
        if (em > i + 1) prefer(marker(i, em - i + 1, 'em', text.slice(i + 1, em)), 5);
      }
    } else if (ch === '~') {
      if (text.startsWith('~~', i)) {
        const close = text.indexOf('~~', i + 2);
        if (close > i + 2) prefer(marker(i, close - i + 2, 'strike', text.slice(i + 2, close)), 4);
      }
    } else if (ch === 'h' && text.startsWith('http', i)) {
      const url = URL_PATTERN.exec(text.slice(i));
      if (url !== null && url.index === 0) prefer(marker(i, url[0].length, 'link', url[0], url[0]), 6);
    } else if (ch === '@') {
      const mention = MENTION_PATTERN.exec(text.slice(i));
      if (mention !== null && mention.index === 0) prefer(marker(i, mention[0].length, 'mention', mention[0]), 7);
    }
  }
  return best;
}

function priorityOf(kind: SpanKind): number {
  if (kind === 'code') return 0;
  if (kind === 'image') return 1;
  if (kind === 'link') return 2;
  if (kind === 'strong') return 3;
  if (kind === 'strike') return 4;
  if (kind === 'em') return 5;
  if (kind === 'mention') return 7;
  return 8;
}

function isWordChar(ch: string): boolean {
  return /[0-9A-Za-z\u4e00-\u9fa5]/u.test(ch);
}

/** 找 `*` / `_` 的闭合位置：跳过行内代码，且不把下一个同类标记当作闭合。 */
function findClosing(text: string, open: number, delimiter: string): number {
  for (let i = open + 1; i < text.length; i++) {
    const ch = text.charAt(i);
    if (ch === '`') {
      const skip = text.indexOf('`', i + 1);
      if (skip > i) {
        i = skip;
        continue;
      }
    }
    if (ch === delimiter) {
      if (delimiter === '_' && i + 1 < text.length && isWordChar(text.charAt(i + 1))) continue;
      return i;
    }
  }
  return -1;
}

/**
 * 找定界符的**第一个**闭合位置。
 *
 * 不能用 `indexOf(pattern, from)`：对 `**bold *and italic***` 它会返回最后一个 `**`
 * （位于 `***` 之间），导致强调体被截短、尾部多出一个孤立的 `*`。
 * 这里逐个候选位置检查「后续不再紧跟同类字符」，取第一个真正的闭合点。
 */
function findCloser(text: string, from: number, pattern: string): number {
  let at = text.indexOf(pattern, from);
  while (at >= 0) {
    const following = text.charAt(at + pattern.length);
    if (following !== pattern.charAt(0)) return at;
    at = text.indexOf(pattern, at + 1);
  }
  return -1;
}

/** 解析 `[text](href)` 或 `![alt](src)`。 */
function linkMarker(text: string, start: number, image: boolean): Marker | undefined {
  const open = image ? start + 1 : start;
  if (text.charAt(open) !== '[') return undefined;
  const closeBracket = text.indexOf(']', open + 1);
  if (closeBracket < 0 || text.charAt(closeBracket + 1) !== '(') return undefined;
  const closeParen = text.indexOf(')', closeBracket + 2);
  if (closeParen < 0) return undefined;
  const label = text.slice(open + 1, closeBracket);
  const href = text.slice(closeBracket + 2, closeParen).trim();
  return marker(start, closeParen - start + 1, image ? 'image' : 'link', label, href);
}

/**
 * 处理强调（`**粗体**` / `*斜体*` / `~~删除~~`）的内容，把可配对的内层强调展开出来。
 *
 * 输入是标记之间的原文，输出是已经分好层的片段列表：
 * - `**bold *and italic***` → strong("bold ") + em("and italic", 叠加 strong) + strong("")
 * - `**plain**`           → strong("plain")
 *
 * 实现要点：**从外到内递归，而不是反复扫描同一段文本**。每一层只找与自己配对的定界符，
 * 找到后把剩余部分继续交给下一层，因此不会在结尾的 `***` 上误判。
 * 只支持一层嵌套（实际回复内容足够）。
 */
function splitEmphasis(content: string, outerKind: SpanKind, depth: number): Span[] {
  const result: Span[] = [];
  const innerDelimiters: string[] = outerKind === 'strong' ? ['*', '_']
    : outerKind === 'em' ? ['**', '__']
      : ['*', '_', '**', '__'];
  if (depth <= 0) {
    if (content.length > 0) result.push(span(outerKind, content));
    return result;
  }
  let rest = content;
  let guard = 0;
  while (rest.length > 0 && guard < 64) {
    guard++;
    let matched = false;
    for (const delimiter of innerDelimiters) {
      const first = rest.indexOf(delimiter);
      if (first < 0) continue;
      const second = rest.indexOf(delimiter, first + delimiter.length);
      if (second < 0) continue;
      if (first > 0) result.push(span(outerKind, rest.slice(0, first)));
      const nestedKind: SpanKind = delimiter.length === 2 ? 'strong' : 'em';
      for (const item of splitEmphasis(rest.slice(first + delimiter.length, second), nestedKind, depth - 1)) {
        result.push(span(item.kind, item.text, item.href, outerKind));
      }
      rest = rest.slice(second + delimiter.length);
      matched = true;
      break;
    }
    if (!matched) break;
  }
  if (rest.length > 0) result.push(span(outerKind, rest));
  return result;
}

/** 解析一行里的行内片段。 */
export function parseSpans(text: string): Span[] {
  const spans: Span[] = [];
  let offset = 0;
  let guard = 0;
  while (offset < text.length && guard < 4000) {
    guard++;
    const hit = nextMarker(text, offset);
    if (hit === undefined) {
      spans.push(span('text', text.slice(offset)));
      break;
    }
    if (hit.index > offset) spans.push(span('text', text.slice(offset, hit.index)));
    if (hit.kind === 'strong' || hit.kind === 'em' || hit.kind === 'strike') {
      // 先剥离内部可配对的强调（`**a *b***` 这类嵌套），再标记本层样式。
      for (const item of splitEmphasis(hit.raw, hit.kind, 1)) spans.push(item);
    } else if (hit.kind === 'code') {
      spans.push(span('code', hit.raw));
    } else if (hit.kind === 'link' || hit.kind === 'image') {
      spans.push(span(hit.kind, hit.raw, hit.href));
    } else {
      spans.push(span(hit.kind, hit.raw));
    }
    offset = hit.index + hit.length;
  }
  if (spans.length === 0) spans.push(span('text', ''));
  return spans;
}

// ---------------------------------------------------------------- 块解析

const HEADING_PATTERN = /^(#{1,6})\s+(.*)$/u;
const FENCE_PATTERN = /^(```+|~~~+)\s*(.*)$/u;
const RULE_PATTERN = /^\s{0,3}([-*_])(?:\s*\1){2,}\s*$/u;
const BULLET_PATTERN = /^(\s*)([-*+])\s+(.*)$/u;
const ORDERED_PATTERN = /^(\s*)(\d{1,9})[.)]\s+(.*)$/u;
const QUOTE_PATTERN = /^\s*>\s?(.*)$/u;
const TABLE_DIVIDER_PATTERN = /^\s*\|?[\s:-]*-[\s:|-]*\|?\s*$/u;

/**
 * 从 `start` 起是否构成一张表：当前行含 `|` 且下一行是分隔行。
 *
 * 抽成函数是为了让「表格检测」与「段落终止条件」共用同一判定——
 * 两处判定分叉正是本文件曾出现过的 bug（段落吞掉表格）。
 */
function isTableStart(lines: string[], start: number): boolean {
  if (start + 1 >= lines.length) return false;
  if (lines[start].indexOf('|') < 0) return false;
  return TABLE_DIVIDER_PATTERN.test(lines[start + 1]);
}

function isBlank(line: string): boolean {
  return line.trim().length === 0;
}

function splitTableRow(line: string): string[] {
  let value = line.trim();
  if (value.startsWith('|')) value = value.slice(1);
  if (value.endsWith('|')) value = value.slice(0, value.length - 1);
  return value.split('|').map(cell => cell.trim());
}

/**
 * 解析 Markdown 文本为块数组。
 *
 * 实现方式：单遍扫描 + 显式下标，不用正则回溯，避免长文本卡顿。
 */
export function parseMarkdown(input: string): Block[] {
  const lines = input.replace(/\r\n/gu, '\n').replace(/\r/gu, '\n').split('\n');
  const blocks: Block[] = [];
  let index = 0;
  while (index < lines.length) {
    const line = lines[index];
    if (isBlank(line)) {
      index++;
      continue;
    }

    // 围栏代码
    const fence = FENCE_PATTERN.exec(line);
    if (fence !== null) {
      const marker = fence[1];
      const info = fence[2].trim();
      const body: string[] = [];
      index++;
      while (index < lines.length && lines[index].trim().indexOf(marker.charAt(0)) !== 0) {
        body.push(lines[index]);
        index++;
      }
      if (index < lines.length) index++; // 跳过收尾围栏
      const item = block('code');
      item.code = body.join('\n');
      item.info = info;
      blocks.push(item);
      continue;
    }

    // 分隔线
    if (RULE_PATTERN.test(line)) {
      blocks.push(block('rule'));
      index++;
      continue;
    }

    // 标题
    const heading = HEADING_PATTERN.exec(line);
    if (heading !== null) {
      const item = block('heading');
      item.level = heading[1].length;
      item.spans = parseSpans(heading[2].trim());
      blocks.push(item);
      index++;
      continue;
    }

    // 表格：当前行含 `|`，下一行是分隔行
    if (isTableStart(lines, index)) {
      const header = splitTableRow(line);
      const rows: TableRow[] = [];
      const headRow: TableRow = { cells: [] };
      for (const cell of header) {
        headRow.cells.push({ header: true, spans: parseSpans(cell) });
      }
      rows.push(headRow);
      index += 2;
      while (index < lines.length && lines[index].indexOf('|') >= 0 && !isBlank(lines[index])) {
        const row: TableRow = { cells: [] };
        for (const cell of splitTableRow(lines[index])) {
          row.cells.push({ header: false, spans: parseSpans(cell) });
        }
        rows.push(row);
        index++;
      }
      const item = block('table');
      item.rows = rows;
      blocks.push(item);
      continue;
    }

    // 引用：连续 `>` 行合并后递归解析
    if (QUOTE_PATTERN.test(line)) {
      const inner: string[] = [];
      while (index < lines.length) {
        const match = QUOTE_PATTERN.exec(lines[index]);
        if (match === null) break;
        inner.push(match[1]);
        index++;
      }
      const item = block('quote');
      item.blocks = parseMarkdown(inner.join('\n'));
      blocks.push(item);
      continue;
    }

    // 列表：连续同类列表行，支持一层缩进嵌套
    const bullet = BULLET_PATTERN.exec(line);
    const ordered = ORDERED_PATTERN.exec(line);
    if (bullet !== null || ordered !== null) {
      const isOrdered = ordered !== null;
      const indent = (isOrdered ? ordered![1] : bullet![1]).length;
      const list: ListBlock = { ordered: isOrdered, items: [] };
      while (index < lines.length) {
        const current = lines[index];
        const currentBullet = BULLET_PATTERN.exec(current);
        const currentOrdered = ORDERED_PATTERN.exec(current);
        const deeper = isOrdered ? currentOrdered : currentBullet;
        if (deeper !== null && deeper[1].length > indent && list.items.length > 0) {
          const child: ListBlock = { ordered: isOrdered, items: [] };
          while (index < lines.length) {
            const nextOrdered = ORDERED_PATTERN.exec(lines[index]);
            const nextBullet = BULLET_PATTERN.exec(lines[index]);
            const hit = isOrdered ? nextOrdered : nextBullet;
            if (hit === null || hit[1].length <= indent) break;
            child.items.push({
              marker: isOrdered ? Number(nextOrdered![2]) : 0,
              spans: parseSpans(hit[3].trim())
            });
            index++;
          }
          list.items[list.items.length - 1].child = child;
          continue;
        }
        if (isOrdered && currentOrdered !== null) {
          list.items.push({ marker: Number(currentOrdered[2]), spans: parseSpans(currentOrdered[3].trim()) });
          index++;
          continue;
        }
        if (!isOrdered && currentBullet !== null) {
          list.items.push({ marker: 0, spans: parseSpans(currentBullet[3].trim()) });
          index++;
          continue;
        }
        break;
      }
      const item = block('list');
      item.list = list;
      blocks.push(item);
      continue;
    }

    // 段落：连续非空行合并，段内换行保留为 softbreak
    const paragraph: string[] = [];
    while (index < lines.length && !isBlank(lines[index]) &&
      HEADING_PATTERN.exec(lines[index]) === null &&
      FENCE_PATTERN.exec(lines[index]) === null &&
      RULE_PATTERN.exec(lines[index]) === null &&
      QUOTE_PATTERN.exec(lines[index]) === null &&
      BULLET_PATTERN.exec(lines[index]) === null &&
      ORDERED_PATTERN.exec(lines[index]) === null &&
      // **表格必须在这里让位**：段落会贪婪吞掉后续行，而表格是「本行含 | 且下一行是分隔行」，
      // 它不属于任何上面这些行首模式。漏掉这一条时，`**2) 表格**` 紧跟表格的常见写法
      // 会把整张表当成段落原样输出（2026-10-16 修复，见下方 isTableStart 说明）。
      !isTableStart(lines, index)) {
      paragraph.push(lines[index]);
      index++;
    }
    const item = block('paragraph');
    for (let n = 0; n < paragraph.length; n++) {
      if (n > 0) item.spans.push(span('softbreak', '\n'));
      const spans = parseSpans(paragraph[n]);
      for (const s of spans) item.spans.push(s);
    }
    blocks.push(item);
  }
  return blocks;
}

/**
 * 行内片段 → 单行纯文本。
 * 「复制消息」用得到，同时便于测试断言。
 */
export function spansToPlainText(spans: Span[]): string {
  const parts: string[] = [];
  for (const item of spans) {
    if (item.kind === 'softbreak') {
      parts.push('\n');
      continue;
    }
    if (item.kind === 'image') {
      parts.push(item.text.length > 0 ? item.text : (item.href ?? ''));
      continue;
    }
    parts.push(item.text);
  }
  return parts.join('');
}

/** 块 → 纯文本（用于消息预览与测试）。 */
export function blockToPlainText(item: Block): string {
  if (item.kind === 'code') return item.code;
  if (item.kind === 'rule') return '---';
  if (item.kind === 'table') {
    const lines: string[] = [];
    for (const row of item.rows) {
      const cells: string[] = [];
      for (const cell of row.cells) cells.push(spansToPlainText(cell.spans));
      lines.push(cells.join(' | '));
    }
    return lines.join('\n');
  }
  if (item.kind === 'list' && item.list !== undefined) {
    const lines: string[] = [];
    for (const entry of item.list.items) {
      const prefix = item.list.ordered ? `${entry.marker}. ` : '• ';
      lines.push(prefix + spansToPlainText(entry.spans));
      if (entry.child !== undefined) {
        for (const nested of entry.child.items) {
          lines.push(`  ${entry.child.ordered ? `${nested.marker}. ` : '• '}${spansToPlainText(nested.spans)}`);
        }
      }
    }
    return lines.join('\n');
  }
  if (item.kind === 'quote') {
    const lines: string[] = [];
    for (const inner of item.blocks) lines.push(blockToPlainText(inner));
    return lines.join('\n');
  }
  return spansToPlainText(item.spans);
}

/** 整段 Markdown → 纯文本。 */
export function markdownToPlainText(input: string): string {
  const blocks = parseMarkdown(input);
  const lines: string[] = [];
  for (const item of blocks) lines.push(blockToPlainText(item));
  return lines.join('\n');
}

/** 只检查链接安全性；与上游 `safeLink` 的允许协议集合一致。 */
export function safeMarkdownLink(value: string): string | undefined {
  const trimmed = value.trim();
  if (!(trimmed.startsWith('https://') || trimmed.startsWith('http://') || trimmed.startsWith('mailto:'))) {
    return undefined;
  }
  if (trimmed.indexOf('@', trimmed.indexOf('://') + 3) >= 0 && trimmed.startsWith('http')) {
    // http(s) 链接里出现 userinfo 属于可疑写法，直接拒绝
    const authority = trimmed.slice(trimmed.indexOf('://') + 3).split('/')[0];
    if (authority.indexOf('@') >= 0) return undefined;
  }
  return trimmed;
}
