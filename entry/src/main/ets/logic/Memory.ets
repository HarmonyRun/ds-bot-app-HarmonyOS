import { MemoryChange, MemoryEntry, MemoryLimits, MemoryView } from '../model/Models';

/**
 * 记忆面板的**纯逻辑**（P2-4）。
 *
 * 宿主把「Bot 私有记忆」和「团队共享记忆」合并成一个列表返回（用 `scope` 区分），
 * 这里负责分组、统计与校验。
 *
 * 为什么抽出来：容量上限（每条 300 字、私有 4000、团队 16000）由宿主管，
 * 但「还差多少字」「这条会不会超」要在提交前算清楚，
 * 否则用户写完才被主机拒绝。这类计算必须能脱离设备验证。
 */

/** 分组后的记忆（面板按这两组渲染）。 */
export interface MemoryGroups {
  /** Bot 私有 */
  own: MemoryEntry[];
  /** 团队共享 */
  team: MemoryEntry[];
}

/** 一条记忆的展示信息。 */
export interface MemoryRow {
  scope: string;
  topic: string;
  text: string;
  /** 来源说明（谁写的 / 什么时候） */
  meta: string;
  /**
   * 原始条目（删除时要用它的 scope/topic/text 精确匹配主机记录）。
   * 展示与操作共享同一个对象，避免"界面显示的文本"与"要删的文本"不一致。
   */
  entry: MemoryEntry;
}

/** 默认容量上限（宿主 MEMORY_LIMITS，取不到 limits 时兜底）。 */
const DEFAULT_LIMITS: MemoryLimits = { entry: 300, main: 4000, topic: 16000, topics: 40 };

/** 取入口容量上限。 */
export function entryLimit(limits: MemoryLimits | undefined): number {
  const value = limits?.entry;
  return typeof value === 'number' && value > 0 ? value : 300;
}

/** 取某作用域的总容量上限。 */
export function scopeLimit(limits: MemoryLimits | undefined, scope: string): number {
  const base = limits ?? DEFAULT_LIMITS;
  if (scope === 'team') {
    const value = base.topic;
    return typeof value === 'number' && value > 0 ? value : 16000;
  }
  const value = base.main;
  return typeof value === 'number' && value > 0 ? value : 4000;
}

/** 把入口按 scope 分组（未知 scope 归到 own，避免条目消失）。 */
export function groupEntries(entries: MemoryEntry[] | undefined): MemoryGroups {
  const own: MemoryEntry[] = [];
  const team: MemoryEntry[] = [];
  if (entries !== undefined) {
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      if (entry.scope === 'team') team.push(entry);
      else own.push(entry);
    }
  }
  return { own: own, team: team };
}

/** 组装展示行（topic 为空、meta 为空时给稳定占位，不渲染空括号）。 */
export function toRows(entries: MemoryEntry[]): MemoryRow[] {
  const rows: MemoryRow[] = [];
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    const topic = entry.topic !== undefined && entry.topic !== null && entry.topic.length > 0
      ? entry.topic : '未分类';
    const parts: string[] = [];
    if (entry.by !== undefined && entry.by !== null && entry.by.length > 0) parts.push(entry.by);
    if (entry.added !== undefined && entry.added !== null && entry.added.length > 0) parts.push(entry.added);
    if (entry.source !== undefined && entry.source !== null && entry.source.length > 0) parts.push(entry.source);
    rows.push({ scope: entry.scope, topic: topic, text: entry.text, meta: parts.join(' · '), entry: entry });
  }
  return rows;
}

/** 某作用域已用字符数（优先用宿主给的 sizes，缺失时本地累加）。 */
export function usedChars(view: MemoryView, scope: string): number {
  const sizes = view.sizes;
  const reported = scope === 'team' ? sizes?.team : sizes?.own;
  if (typeof reported === 'number' && reported >= 0) return reported;
  let total = 0;
  const entries = view.entries ?? [];
  for (let i = 0; i < entries.length; i++) {
    const entry = entries[i];
    if ((entry.scope === 'team') === (scope === 'team')) total += entry.text.length;
  }
  return total;
}

/** 容量百分比（0~100），用于进度条。 */
export function usedPercent(view: MemoryView, scope: string): number {
  const used = usedChars(view, scope);
  const limit = scopeLimit(view.limits, scope);
  if (limit <= 0) return 0;
  const percent = Math.round((used / limit) * 100);
  return percent > 100 ? 100 : percent;
}

/** 问答输入校验：空内容不提交，超长截断提示。 */
export interface MemoryAskValidation {
  ok: boolean;
  error: string;
  text: string;
}

/** 宿主对问答文本的上限（`ASK_TEXT_MAX`）。 */
const ASK_TEXT_MAX = 2000;

/** 校验「问一句话/让主机改记忆」的输入。 */
export function validateAsk(text: string): MemoryAskValidation {
  const trimmed = text.trim();
  if (trimmed.length === 0) return { ok: false, error: '写下要问的或要改的内容', text: '' };
  if (trimmed.length > ASK_TEXT_MAX) {
    return { ok: false, error: `内容请控制在 ${ASK_TEXT_MAX} 字以内`, text: '' };
  }
  return { ok: true, error: '', text: trimmed };
}

/** 校验一条记忆能否加入（用于前端提示；真正的校验在主机）。 */
export function validateEntryText(text: string, limits: MemoryLimits | undefined): string {
  const trimmed = text.trim();
  if (trimmed.length === 0) return '内容不能为空';
  const limit = entryLimit(limits);
  if (trimmed.length > limit) return `单条记忆请控制在 ${limit} 字以内`;
  return '';
}

/** 把问答返回的变更列表说成人话（面板展示用）。 */
export function describeChanges(changes: MemoryChange[] | undefined): string[] {
  const lines: string[] = [];
  if (changes === undefined) return lines;
  for (let i = 0; i < changes.length; i++) {
    const change = changes[i];
    const scope = change.scope === 'team' ? '团队' : '私有';
    const op = change.op === 'add' ? '新增' : change.op === 'edit' ? '修改' : change.op === 'remove' ? '删除' : change.op;
    const status = change.ok === true ? '' : `（失败：${change.error ?? '未知原因'}）`;
    lines.push(`${op}${scope}记忆${status}：${change.text}`);
  }
  return lines;
}
