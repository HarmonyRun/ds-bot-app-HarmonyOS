import { Message } from '../model/Models';

/**
 * 会话导出（P2-9）。
 *
 * 把一段消息导出成 **Markdown** 或 **JSON**，用于备份、贴到工单、或喂给别的工具。
 *
 * 为什么抽成纯函数：
 * - 导出内容是要"离开 App"的东西，格式错了用户很难发现（不会报错，只是内容缺了）；
 * - 转义规则（Markdown 表格竖线、代码围栏、JSON 换行）必须能脱离设备验证。
 */

/** 导出格式。 */
export type ExportFormat = 'markdown' | 'json';

/**
 * 取消息正文（**可能是 undefined**）。
 *
 * 主机对「只有工具调用、没有文本」的消息不下发 `text` 字段；
 * 模型里 `text: string` 是必填是为了让界面好写，但运行时必须按可选处理。
 * 2026-10-18 真机：直接 `message.text.length` 会在导出时崩掉整个 App。
 */
function bodyOf(message: Message): string {
  const value = message.text;
  return typeof value === 'string' ? value : '';
}

/** 说话人显示名。 */
function roleLabel(role: string): string {
  if (role === 'user') return '用户';
  if (role === 'assistant') return '助手';
  if (role === 'system') return '系统';
  return role;
}

/** 把毫秒时间戳格式化成 `YYYY-MM-DD HH:mm:ss`（本地时区）。 */
export function formatTime(value: number | string): string {
  const time = typeof value === 'number' ? value : Date.parse(value);
  if (!Number.isFinite(time)) return '';
  const date = new Date(time);
  const pad = (input: number): string => (input < 10 ? `0${input}` : `${input}`);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

/**
 * 防止内容里的代码围栏把自己的围栏提前闭合。
 *
 * 做法：把输出围栏长度动态提高到「内容里最长连续反引号 + 1」。
 * 这是 CommonMark 允许的写法，比替换反引号更保真。
 */
function fenceFor(content: string): string {
  let longest = 0;
  let current = 0;
  for (let i = 0; i < content.length; i++) {
    if (content[i] === '`') {
      current += 1;
      if (current > longest) longest = current;
    } else {
      current = 0;
    }
  }
  const size = longest < 3 ? 3 : longest + 1;
  let fence = '';
  for (let i = 0; i < size; i++) fence += '`';
  return fence;
}

/** 把工具调用渲染成一行摘要。 */
function toolLine(message: Message): string {
  const tool = message.tool;
  if (tool === undefined) return '';
  const parts: string[] = [`🔧 \`${tool.name}\``];
  if (tool.durationMs !== undefined) parts.push(`${tool.durationMs}ms`);
  if (tool.isError === true) parts.push('失败');
  return parts.join(' · ');
}

/** 导出 Markdown。 */
export function toMarkdown(messages: Message[], title: string, exportedAt: number): string {
  const lines: string[] = [];
  lines.push(`# ${title}`);
  lines.push('');
  lines.push(`> 导出时间：${formatTime(exportedAt)}　共 ${messages.length} 条消息`);
  lines.push('');
  for (let i = 0; i < messages.length; i++) {
    const message = messages[i];
    const time = formatTime(message.createdAt);
    lines.push(`## ${roleLabel(message.role)}${time.length > 0 ? `　${time}` : ''}`);
    lines.push('');
    if (message.reasoning !== undefined && message.reasoning.length > 0) {
      const fence = fenceFor(message.reasoning);
      lines.push('<details><summary>思考过程</summary>');
      lines.push('');
      lines.push(fence + 'text');
      lines.push(message.reasoning);
      lines.push(fence);
      lines.push('');
      lines.push('</details>');
      lines.push('');
    }
    const body = bodyOf(message);
    if (body.length > 0) {
      lines.push(body);
      lines.push('');
    }
    const tool = toolLine(message);
    if (tool.length > 0) {
      lines.push(tool);
      if (message.tool?.input !== undefined && message.tool.input.length > 0) {
        const fence = fenceFor(message.tool.input);
        lines.push('');
        lines.push(fence + 'json');
        lines.push(message.tool.input);
        lines.push(fence);
      }
      lines.push('');
    }
  }
  return lines.join('\n');
}

/** 导出 JSON（保留原始字段，便于程序处理）。 */
export function toJson(messages: Message[], title: string, exportedAt: number): string {
  const items: ExportMessage[] = [];
  for (let i = 0; i < messages.length; i++) {
    const message = messages[i];
    const item: ExportMessage = {
      role: message.role,
      text: bodyOf(message),
      createdAt: message.createdAt,
      seq: message.seq
    };
    if (message.reasoning !== undefined && message.reasoning.length > 0) item.reasoning = message.reasoning;
    if (message.tool !== undefined) {
      const tool: ExportTool = { name: message.tool.name, state: message.tool.state };
      if (message.tool.input !== undefined) tool.input = message.tool.input;
      if (message.tool.output !== undefined) tool.output = message.tool.output;
      if (message.tool.isError === true) tool.isError = true;
      item.tool = tool;
    }
    items.push(item);
  }
  const payload: ExportDocument = { title: title, exportedAt: exportedAt, count: items.length, messages: items };
  return JSON.stringify(payload, null, 2);
}

/** 按格式导出。 */
export function exportConversation(messages: Message[], title: string, format: string, exportedAt: number): string {
  return format === 'json' ? toJson(messages, title, exportedAt) : toMarkdown(messages, title, exportedAt);
}

/** 建议的文件名（去掉路径分隔符等非法字符）。 */
export function exportFileName(title: string, format: string, exportedAt: number): string {
  const date = new Date(exportedAt);
  const pad = (input: number): string => (input < 10 ? `0${input}` : `${input}`);
  const stamp = `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-`
    + `${pad(date.getHours())}${pad(date.getMinutes())}`;
  let safe = '';
  for (let i = 0; i < title.length; i++) {
    const ch = title[i];
    safe += '/\\:*?"<>|'.includes(ch) || ch === '\n' ? '_' : ch;
  }
  const trimmed = safe.trim().length > 0 ? safe.trim() : 'conversation';
  return `${trimmed.slice(0, 40)}-${stamp}.${format === 'json' ? 'json' : 'md'}`;
}

/** 导出文档里的一条消息。 */
export interface ExportMessage {
  role: string;
  text: string;
  createdAt: number | string;
  seq: number;
  reasoning?: string;
  tool?: ExportTool;
}

/** 导出文档里的工具调用。 */
export interface ExportTool {
  name: string;
  state: string;
  input?: string;
  output?: string;
  isError?: boolean;
}

/** 导出文档（JSON 格式的顶层结构）。 */
export interface ExportDocument {
  title: string;
  exportedAt: number;
  count: number;
  messages: ExportMessage[];
}
