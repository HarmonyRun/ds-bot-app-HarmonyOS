export interface PairingCode {
  url: string;
  code: string;
  serverId: string;
  tlsPin?: string;
}

export interface ServerInfo {
  protocolVersion: number;
  serverId: string;
  name?: string;
}

export interface PairingStart {
  claimToken: string;
  requestId: string;
  status: string;
}

export interface Session {
  accessToken: string;
  refreshToken: string;
  deviceId: string;
  serverId: string;
  expiresAt: number | string;
  serverUrl?: string;
  tlsPin?: string;
}

export interface ClientProfile {
  serverUrl: string;
  serverName: string;
  tlsPin: string;
  session: Session;
}

export interface Avatar {
  shape?: string;
  image?: string;
  color?: string;
}

export interface Bot {
  id: string;
  name: string;
  role?: string;
  color?: string;
  instructions?: string;
  model?: string;
  /** 当前 Bot 的推理档位；空值表示跟随模型默认值。 */
  effort?: string;
  sessionId?: string;
  waiting?: boolean;
  avatar?: Avatar;
  workDir?: string;
  pinned?: boolean;
  hidden?: boolean;
}

export interface Room {
  id: string;
  name: string;
  members: string[];
  admin?: string;
  notice?: string;
  pinned?: boolean;
  hidden?: boolean;
}

export interface ModelOption {
  ref: string;
  name: string;
  providerName?: string;
}

export interface QuestionOption {
  label: string;
  value?: string;
  description?: string;
}

/** 主机工具执行期间等待用户回答的问题。 */
export interface Question {
  id: string;
  sessionId?: string;
  conversationId?: string;
  question?: string;
  prompt?: string;
  text?: string;
  header?: string;
  detail?: string;
  multiSelect?: boolean;
  allowCustom?: boolean;
  options: QuestionOption[];
}

/** `/state.work.rooms` 中一个群成员当前的工作证据。 */
export interface MemberWork {
  botId: string;
  since?: number;
  tool?: string;
  speaking?: boolean;
}

export interface BotWork {
  tool?: string;
  since?: number;
  roomId?: string;
  speaking?: boolean;
}

export interface WorkApproval {
  id: string;
  botId: string;
  roomId?: string;
  sessionId?: string;
  answerable?: boolean;
}

export interface TeamWork {
  bots: Record<string, BotWork>;
  rooms: Record<string, MemberWork[]>;
  approvals: WorkApproval[];
}

/** `room-progress` 返回的一轮群聊执行进度。 */
export interface RoundReply {
  botId: string;
  kind?: string;
}

export interface RoomRound {
  callId: string;
  speaking?: string;
  replies: RoundReply[];
}

export interface TeamState {
  bots: Bot[];
  rooms: Room[];
  models: ModelOption[];
  mainBotId?: string;
  mainBotIds?: string[];
  questions?: Record<string, Question>;
  work?: TeamWork;
  readOnly?: string;
}

export interface Conversation {
  id: string;
  kind: string;
  name: string;
  role?: string;
  sessionId: string;
  waiting?: string;
  pinned?: boolean;
  hidden?: boolean;
  updatedAt?: number | string;
  mode?: string;
  notice?: string;
  admin?: string;
  parts?: string[];
  model?: string;
  createdAt?: number;
}

export interface ConversationList {
  conversations: Conversation[];
}

export interface ToolActivity {
  durationMs?: number;
  callId: string;
  name: string;
  state: string;
  input?: string;
  output?: string;
  isError?: boolean;
  truncated?: boolean;
}

/** 群聊消息的作者（主机下发 `author: { id, name }`）。 */
export interface Author {
  id?: string;
  name?: string;
}

export interface SystemEvent {
  kind: string;
  name?: string;
}

export interface Attachment {
  id?: string;
  type?: 'image' | 'file';
  receiptId?: string;
  name: string;
  mediaType?: string;
  size?: number;
  sessionId?: string;
}

export interface Message {
  id: string;
  sessionId: string;
  seq: number;
  role: string;
  text: string;
  createdAt: number | string;
  reasoning?: string;
  interrupted?: boolean;
  pending?: boolean;
  tool?: ToolActivity;
  turn?: number;
  step?: number;
  requestId?: string;
  /** Last event represented by an updatable tool card; seq remains its call position. */
  updatedSeq?: number;
  /** Cumulative stream snapshot index for a pending attempt message. */
  streamIndex?: number;
  attemptId?: string;
  systemEvent?: SystemEvent;
  attachments?: Attachment[];
  /**
   * 群聊里该条回复的作者。
   * 主机 `projection.js` 下发的是 `{ id, name }`（`author: { id, name }`），
   * 旧模型声明成 `string` 是错的——群聊因此无法显示是谁在说话。
   */
  author?: Author;
}

export interface MessagePage {
  messages: Message[];
  cursor?: string;
  sessionId: string;
}

export interface Target {
  conversationId: string;
  sessionId: string;
  revision: string | number;
}

export interface Submission {
  conversationId: string;
  sessionId: string;
  requestId: string;
  text: string;
}

export interface SubmissionReceipt {
  requestId: string;
  status: string;
  conversationId?: string;
  sessionId?: string;
}

export interface ActionEnvelope {
  endpoint: string;
  payload: object;
}

export interface ErrorPayload {
  error?: string;
  message?: string;
  code?: string;
}

export class EmptyPayload {}

export interface RefreshPayload {
  refreshToken: string;
}

export interface PairPayload {
  code: string;
  deviceName: string;
}

export interface PairCompletePayload {
  claimToken: string;
}

export interface ApprovalDecisionPayload {
  id: string;
  decision: string;
}

export interface DeviceListItem {
  id: string;
  name?: string;
  deviceName?: string;
}

export interface DeviceList {
  devices: DeviceListItem[];
  currentDeviceId?: string;
}

export interface ReadMarkerPayload {
  conversationId: string;
  seq: number;
}

export interface Approval {
  id: string;
  conversationId: string;
  sessionId: string;
  toolName: string;
  reason?: string;
  callId?: string;
  createdAt?: number;
  displayReason?: string;
  answerable?: boolean;
}

export interface ApprovalList {
  requests: Approval[];
}

export type MobileEventType = string;

export interface MobileEventError {
  code: string;
  message: string;
}

export interface QueueItem {
  id: string;
  target: string;
  text: string;
  requestId?: string;
}

export interface ConversationStatus {
  conversationId?: string;
  sessionId?: string;
  running?: boolean;
  phase?: string;
  queue?: QueueItem[];
  activity?: string;
  attemptId?: string;
  eventSeq?: number;
}

export interface MobileEvent {
  type: MobileEventType;
  conversationId?: string;
  sessionId?: string;
  /** `ready` 帧携带的主机身份，用于校验事件流确实连到了配对的那台主机。 */
  serverId?: string;
  attemptId?: string;
  replaceAttemptId?: string;
  text?: string;
  reasoning?: string;
  index?: number;
  replace?: boolean;
  clearAttempt?: boolean;
  message?: Message;
  messages?: Message[];
  cursor?: string;
  eventSeq?: number;
  queue?: QueueItem[];
  activity?: string;
  running?: boolean;
  phase?: string;
  status?: string;
  error?: MobileEventError;
}

export interface HistoryPage {
  messages: Message[];
  cursor?: string;
  sessionId: string;
}

export interface ConversationPart {
  sessionId: string;
  number: number;
  current: boolean;
  cursor: string;
  startedAt?: number;
  endedAt?: number;
}

export interface PartsPage {
  conversationId: string;
  currentSessionId: string;
  parts: ConversationPart[];
}
