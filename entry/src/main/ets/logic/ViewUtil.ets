/**
 * 展示与判定用的纯函数（抽自 `Index.ets`，P1 视图拆分）。
 *
 * 这几个函数原本是页面里的私有方法，但它们**零状态依赖**，属于典型可测逻辑：
 * 却因为没有独立模块而从未被断言覆盖。其中 `isAuthFailure` 尤其关键——
 * 它的判定结果决定「是否清空凭据并回到连接页」，判错会让用户卡在死路或误登出。
 */
import { Message } from '../model/Models';

/** 带 `statusCode` / `code` 的错误形状（与 `MobileApiError` 结构一致，避免强耦合）。 */
export interface FailureLike {
  statusCode?: number;
  code?: string;
}

/** 是否为「需要重新配对」的鉴权失败（401/403 或明确的鉴权错误码）。 */
export function isAuthFailure(error: Object): boolean {
  const failure = error as FailureLike;
  if (failure.statusCode === 401 || failure.statusCode === 403) return true;
  return failure.code === 'unauthorized' || failure.code === 'server_changed' ||
    failure.code === 'invalid_session';
}

/**
 * 会话列表右上角的时间（`HH:mm`，本地时区）。
 *
 * 边界：`updatedAt` 缺失、非数字、不可解析时一律返回空串——
 * 上游数据可能给字符串时间戳或 ISO 串，`new Date` 解析失败会得到 `Invalid Date`，
 * 直接格式化会渲染出 `NaN:NaN`。
 */
export function conversationTime(raw: number | string | undefined): string {
  if (raw === undefined) return '';
  // **数值字符串必须显式转数字**：`new Date("1792132200000")` 在 JS 里返回 Invalid Date
  // （它只把数字当时间戳，字符串会走日期解析）。而 `updatedAt` 的类型是 `number | string`，
  // 主机 JSON 常把时间戳序列化成字符串毫秒数——不处理的话会话时间会静默空白。
  // 2026-10-16 由单测发现。
  const millis = typeof raw === 'string' && raw.trim().length > 0 && !Number.isNaN(Number(raw))
    ? Number(raw)
    : raw;
  const date = new Date(millis);
  if (!Number.isFinite(date.getTime())) return '';
  const hours = date.getHours().toString().padStart(2, '0');
  const minutes = date.getMinutes().toString().padStart(2, '0');
  return `${hours}:${minutes}`;
}

/**
 * 本地乐观消息是否已被主机确认。
 *
 * 判定：本条是本地占位（id 以 `local-` 开头）、带 requestId，
 * 且已加载列表里存在**另一条**同 requestId 的正式消息。
 */
export function isConfirmedLocally(item: Message, loaded: Message[]): boolean {
  if (item.requestId === undefined || item.requestId.length === 0) return false;
  if (item.id.startsWith('local-') !== true) return false;
  return loaded.some((other: Message) =>
    other.requestId === item.requestId && other.id !== item.id);
}

/** 提问卡的去重键（sessionId + questionId）。 */
export function questionKeyOf(sessionId: string, questionId: string): string {
  return `${sessionId}:${questionId}`;
}
