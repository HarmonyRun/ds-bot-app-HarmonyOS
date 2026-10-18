import { NotificationItem, NotificationPreferences } from '../model/Models';

/**
 * 通知中心的**纯逻辑**（P3-4）。
 *
 * 宿主 inbox 的字段：`{ id, conversationId, kind, title, body?, createdAt, read }`；
 * 类别由宿主定义（`reply` 回复 / `question` 提问 / `approval` 审批）。
 *
 * 抽出来的原因：未读数、类别过滤、"全部已读用哪个游标"都是错了会静默出错的地方
 * （比如未读数不准，或者把没读的通知标成已读）。
 */

/** 支持的通知类别（与宿主 `kinds` 一致）。 */
export const NOTIFICATION_KINDS: string[] = ['reply', 'question', 'approval'];

/** 类别展示名。 */
export function kindLabel(kind: string): string {
  if (kind === 'reply') return '回复';
  if (kind === 'question') return '提问';
  if (kind === 'approval') return '审批';
  if (kind === 'test') return '测试';
  return kind;
}

/** 类别的图标字符（不依赖图片资源）。 */
export function kindGlyph(kind: string): string {
  if (kind === 'reply') return '💬';
  if (kind === 'question') return '❓';
  if (kind === 'approval') return '✅';
  return '🔔';
}

/** 未读数量。 */
export function unreadCount(items: NotificationItem[] | undefined): number {
  if (items === undefined) return 0;
  let count = 0;
  for (let i = 0; i < items.length; i++) {
    if (items[i].read !== true) count += 1;
  }
  return count;
}

/** 按偏好过滤（enabled 关闭时返回空）。 */
export function filterByPreferences(items: NotificationItem[] | undefined,
  preferences: NotificationPreferences | undefined): NotificationItem[] {
  const result: NotificationItem[] = [];
  if (items === undefined) return result;
  if (preferences !== undefined && preferences.enabled === false) return result;
  const categories = preferences?.categories ?? NOTIFICATION_KINDS;
  for (let i = 0; i < items.length; i++) {
    if (categories.includes(items[i].kind)) result.push(items[i]);
  }
  return result;
}

/**
 * "全部已读"应该用的游标。
 *
 * 必须是主机返回的 `cursor`（递增序号），**不能用通知 id 或条数**——
 * 宿主比较的是 `item.id <= readThrough`，用错值会把后续新通知也标成已读。
 */
export function readThroughCursor(pageCursor: number | undefined): number {
  return typeof pageCursor === 'number' && Number.isFinite(pageCursor) && pageCursor > 0 ? pageCursor : 0;
}

/** 时间显示：今天显示 HH:mm，更早显示 MM-DD。 */
export function describeTime(createdAt: number | undefined, now: number): string {
  if (createdAt === undefined || !Number.isFinite(createdAt)) return '';
  const date = new Date(createdAt);
  const today = new Date(now);
  const pad = (value: number): string => (value < 10 ? `0${value}` : `${value}`);
  const sameDay = date.getFullYear() === today.getFullYear()
    && date.getMonth() === today.getMonth() && date.getDate() === today.getDate();
  if (sameDay) return `${pad(date.getHours())}:${pad(date.getMinutes())}`;
  return `${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/** 通知是否值得弹系统横幅（未读 + 类别订阅 + 主机开关打开）。 */
export function shouldNotify(item: NotificationItem,
  preferences: NotificationPreferences | undefined): boolean {
  if (preferences !== undefined && preferences.enabled === false) return false;
  if (item.read === true) return false;
  const categories = preferences?.categories ?? NOTIFICATION_KINDS;
  return categories.includes(item.kind);
}

/** 偏好校验：类别必须来自白名单。 */
export function preferencesProblem(existing: string[]): string {
  for (let i = 0; i < existing.length; i++) {
    if (!NOTIFICATION_KINDS.includes(existing[i])) return `未知的通知类别：${existing[i]}`;
  }
  return '';
}

/** 给设置页展示的摘要。 */
export function preferencesSummary(preferences: NotificationPreferences | undefined): string {
  if (preferences !== undefined && preferences.enabled === false) return '已关闭';
  const categories = preferences?.categories ?? NOTIFICATION_KINDS;
  if (categories.length === 0) return '已开启 · 未订阅任何类别';
  const labels: string[] = [];
  for (let i = 0; i < categories.length; i++) labels.push(kindLabel(categories[i]));
  return `已开启 · ${labels.join('、')}`;
}
