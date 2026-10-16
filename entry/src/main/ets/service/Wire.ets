/**
 * 传输层专用类型。
 *
 * 分工（单一事实源）：
 * - `model/Models.ets` 是**协议类型的唯一来源**：`MobileEvent`、`QueueItem`、`ConversationStatus`
 *   等线帧类型都由它定义，本文件只做 re-export，避免两个模块各自声明同名类型互相冲突。
 * - 本文件只放「传输层自己派生出来的状态」：连接状态枚举、已解析的会话状态、
 *   以及 Models 里没有的少量小类型。
 */
import { ConversationStatus, QueueItem } from '../model/Models';

export type {
  ConversationPart,
  ConversationStatus,
  HistoryPage,
  MobileEvent,
  MobileEventError,
  PartsPage,
  QueueItem,
  SystemEvent
} from '../model/Models';

/** 事件流连接状态，与上游 `ConnectionStatus` 对齐。 */
export type StreamStatus = 'idle' | 'connecting' | 'connected' | 'reconnecting' | 'closed' | 'unauthorized';

/**
 * `status` 帧「解析后」的会话状态：所有字段都已落到确定值，
 * 缺省字段由上一帧补齐。界面直接读这个结构，不需要再处理可空性。
 */
export interface ResolvedConversationStatus {
  conversationId: string;
  sessionId: string;
  running: boolean;
  phase: string;
  attemptId: string;
  /** 只有当帧里带了 `eventSeq` 时才更新，否则沿用上一帧的值（断线续传游标）。 */
  eventSeq: number;
  queue: QueueItem[];
  activity: string;
}

export const EMPTY_STATUS: ResolvedConversationStatus = {
  conversationId: '',
  sessionId: '',
  running: false,
  phase: '',
  attemptId: '',
  eventSeq: 0,
  queue: [],
  activity: ''
};

/** 提交回执（`/submissions` 与 `/submissions/{requestId}`）。 */
export interface WireSubmissionReceipt {
  requestId: string;
  status: string;
  conversationId?: string;
  sessionId?: string;
}

/** 推理档位（`efforts` action）。 */
export interface EffortOption {
  id: string;
  name: string;
  description?: string;
}
