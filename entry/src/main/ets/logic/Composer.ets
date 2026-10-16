import { Bot, Room } from '../model/Models';

/** 聊天输入框中一个已选择的只读会话引用。 */
export interface ChatReference {
  sessionId: string;
  label: string;
  mention: string;
}

/** 主机 `reference-chats` action 返回的一行。 */
export interface ReferenceChat {
  sessionId: string;
  label: string;
  botId?: string;
  kind: string;
}

export interface ReferenceChatsResult {
  available: boolean;
  chats: ReferenceChat[];
}

export interface DraftParts {
  text: string;
  references: ChatReference[];
}

export interface TextSelection {
  start: number;
  end: number;
}

export interface MentionQuery {
  start: number;
  end: number;
  query: string;
}

export interface MentionCandidate {
  name: string;
  bot?: Bot;
}

const BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function utf8Bytes(value: string): number[] {
  const encoded = encodeURIComponent(value);
  const bytes: number[] = [];
  for (let index = 0; index < encoded.length; index++) {
    if (encoded[index] === '%' && index + 2 < encoded.length) {
      bytes.push(Number.parseInt(encoded.slice(index + 1, index + 3), 16));
      index += 2;
    } else {
      bytes.push(encoded.charCodeAt(index));
    }
  }
  return bytes;
}

function base64UrlEncode(value: string): string {
  const bytes = utf8Bytes(value);
  let result = '';
  for (let index = 0; index < bytes.length; index += 3) {
    const first = bytes[index];
    const second = index + 1 < bytes.length ? bytes[index + 1] : 0;
    const third = index + 2 < bytes.length ? bytes[index + 2] : 0;
    const bits = (first << 16) | (second << 8) | third;
    result += BASE64.charAt((bits >> 18) & 63);
    result += BASE64.charAt((bits >> 12) & 63);
    if (index + 1 < bytes.length) result += BASE64.charAt((bits >> 6) & 63);
    if (index + 2 < bytes.length) result += BASE64.charAt(bits & 63);
  }
  return result.replace(/\+/gu, '-').replace(/\//gu, '_');
}

function base64UrlDecode(value: string): string | undefined {
  const source = value.replace(/-/gu, '+').replace(/_/gu, '/');
  const bytes: number[] = [];
  let buffer = 0;
  let bits = 0;
  for (let index = 0; index < source.length; index++) {
    const digit = BASE64.indexOf(source[index]);
    if (digit < 0) return undefined;
    buffer = (buffer << 6) | digit;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((buffer >> bits) & 255);
      buffer &= (1 << bits) - 1;
    }
  }
  let encoded = '';
  for (const byte of bytes) encoded += `%${byte.toString(16).padStart(2, '0')}`;
  try {
    return decodeURIComponent(encoded);
  } catch (_error) {
    return undefined;
  }
}

function safeLabel(value: string): string {
  let result = '';
  for (const mark of value.replace(/[\r\n]/gu, ' ')) {
    result += mark === '\\' || mark === ']' ? `\\${mark}` : mark;
  }
  return result;
}

/** DSH 规范会话引用：base64url(JSON.stringify(sessionId))。 */
export function sessionMention(sessionId: string, label: string): string {
  return `@[${safeLabel(label)}](dsh-session:${base64UrlEncode(JSON.stringify(sessionId))})`;
}

/**
 * 从持久化草稿头部拆出最多三条会话引用。
 * 非法引用保持为普通正文，避免用户编辑内容被静默吞掉。
 */
export function referenceDraft(draft: string): DraftParts {
  const references: ChatReference[] = [];
  let text = draft;
  while (references.length < 3) {
    const match = /^(@\[((?:\\.|[^\\\]])*)\]\(dsh-session:([A-Za-z0-9_-]+)\))(?:\n|$)/u.exec(text);
    if (match === null) break;
    const decoded = base64UrlDecode(match[3]);
    if (decoded === undefined) break;
    try {
      const sessionId = JSON.parse(decoded) as Object;
      if (typeof sessionId !== 'string' || sessionId.length === 0) break;
      references.push({
        sessionId: sessionId,
        label: match[2].replace(/\\([\\\]])/gu, '$1'),
        mention: match[1]
      });
      text = text.slice(match[0].length);
    } catch (_error) {
      break;
    }
  }
  if (references.length > 0 && text.startsWith('\n')) text = text.slice(1);
  return { text: text, references: references };
}

/** 把 UI 中的引用芯片重新序列化到缓存/发送使用的草稿头部。 */
export function composeReferenceDraft(text: string, references: ChatReference[]): string {
  if (references.length === 0) return text;
  return `${references.map((item: ChatReference) => item.mention).join('\n')}\n\n${text}`;
}

/** 找光标前正在输入的 @ 查询；排除邮箱、路径、链接和代码。 */
export function mentionQuery(text: string, selection: TextSelection): MentionQuery | undefined {
  if (selection.start !== selection.end || selection.start > text.length) return undefined;
  const before = text.slice(0, selection.start);
  const at = before.lastIndexOf('@');
  if (at < 0 || (at > 0 && /[a-z0-9_./]/iu.test(before[at - 1]))) return undefined;
  const fences = before.match(/```/gu);
  if ((fences === null ? 0 : fences.length) % 2 !== 0) return undefined;
  const line = before.slice(before.lastIndexOf('\n') + 1);
  const ticks = line.match(/`/gu);
  if ((ticks === null ? 0 : ticks.length) % 2 !== 0) return undefined;
  const query = before.slice(at + 1);
  if (query.length > 100 || /[\r\n`[\]()<>/\\]/u.test(query)) return undefined;
  return { start: at, end: selection.start, query: query };
}

/** 单聊排除自身；群聊只列成员，并在多人群聊末尾加入“所有人”。 */
export function mentionCandidates(bots: Bot[], botId: string | undefined, room: Room | undefined,
  query: string, everyone: string): MentionCandidate[] {
  const available: Bot[] = [];
  if (room !== undefined) {
    for (const id of room.members) {
      const bot = bots.find((item: Bot) => item.id === id);
      if (bot !== undefined) available.push(bot);
    }
  } else {
    for (const bot of bots) if (bot.id !== botId) available.push(bot);
  }
  const needle = query.trim().toLowerCase();
  if (query.endsWith(' ')) {
    const exact = available.some((bot: Bot) => bot.name.toLowerCase() === needle) ||
      everyone.toLowerCase() === needle;
    if (exact) return [];
  }
  const rows: MentionCandidate[] = [];
  for (const bot of available) {
    if (bot.name.toLowerCase().includes(needle)) rows.push({ name: bot.name, bot: bot });
  }
  if (room !== undefined && available.length > 1) {
    const allNames = [everyone, 'all', 'everyone', '所有人', '全体'];
    if (allNames.some((name: string) => name.toLowerCase().startsWith(needle))) rows.push({ name: everyone });
  }
  return rows;
}
