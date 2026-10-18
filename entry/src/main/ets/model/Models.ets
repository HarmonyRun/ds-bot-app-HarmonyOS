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
  /** 该 Bot 已挂载的能力名（`state.bots[].capabilities`） */
  capabilities?: string[];
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
  /** 群聊模式：admin（管理员先答）/ everyone（成员轮流） */
  mode?: string;
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

/**
 * 技能（`skills-list` / `skills-get`，P2-8）。
 *
 * `invocation` 说明这个技能谁能调用：
 * - `modelInvocable`：模型可以自己决定用；
 * - `userInvocable`：用户可以直接点名用（`skills-get` 只允许这一种）。
 */
export interface SkillInvocation {
  modelInvocable?: boolean;
  userInvocable?: boolean;
}

export interface SkillItem {
  name: string;
  description?: string;
  whenToUse?: string;
  source?: string;
  provider?: string;
  invocation?: SkillInvocation;
}

export interface SkillsPage {
  /** 主机是否装了技能服务；false 时 skills 为空 */
  available?: boolean;
  skills?: SkillItem[];
}

/** `skills-get` 的响应（含完整内容，可能被截断）。 */
export interface SkillDetail {
  name?: string;
  description?: string;
  content?: string;
  /** 内容超过主机上限被截断 */
  truncated?: boolean;
  source?: string;
  provider?: string;
}

/**
 * 插件（`plugins-list`，P2-8）。
 *
 * 宿主区分两类：`plugins`（单个 DSH 插件）与 `bundles`（打包安装的插件集）。
 * 两者都有 `enabled`，但 id 字段不同：插件用 `entryId`，bundle 用 `name`。
 */
export interface PluginEntry {
  entryId: string;
  moduleName?: string;
  enabled?: boolean;
  fiberPhase?: string | null;
  readOnlyReason?: string;
}

export interface PluginBundle {
  name: string;
  version?: string;
  description?: string;
  enabled?: boolean;
  installed?: boolean;
  optional?: boolean;
  removable?: boolean;
  readOnlyReason?: string;
}

export interface PluginsPage {
  /** 主机是否可写（只读时开关应禁用） */
  writable?: boolean;
  plugins?: PluginEntry[];
  bundles?: PluginBundle[];
}

/** 插件开关载荷（`plugins-set-enabled` / `bundle-set-enabled`）。 */
export class EnabledPatch {
  id: string;
  enabled: boolean;

  constructor(id: string, enabled: boolean) {
    this.id = id;
    this.enabled = enabled;
  }
}

/** 技能名载荷（`skills-get`）。 */
class SkillRef {
  name: string;

  constructor(name: string) {
    this.name = name;
  }
}

/**
 * Bot 更新载荷（`update-bot`，P2-5）。宿主只更新出现的字段。
 *
 * 字段范围与宿主 `roster.js updateBot` + 移动端白名单一致：
 * `id/name/role/instructions/color/avatar/model/effort/permission/workDir`。
 * 这里只暴露移动端能安全表达的子集（头像与工作目录需要系统选择器，见报告）。
 */
export class BotPatch {
  id: string;
  name?: string;
  role?: string;
  instructions?: string;
  /** 空串表示清除（回到默认模型） */
  model?: string;
  /** 空串表示清除；**必须先有模型**，否则宿主会拒绝 */
  effort?: string;
  /**
   * 头像 data URL（`data:image/png;base64,…`）。
   * 空串表示清除位图头像、回到矢量头像。
   */
  avatarImage?: string;

  constructor(id: string) {
    this.id = id;
  }
}

/** `set-main` 载荷（P2-5）。 */
export class MainBotPatch {
  id: string;
  main: boolean;
  primary?: boolean;
  replace?: string;

  constructor(id: string, main: boolean) {
    this.id = id;
    this.main = main;
  }
}

/** `duplicate-bot` / `delete-bot` 载荷。 */
export class BotRef {
  id: string;

  constructor(id: string) {
    this.id = id;
  }
}

/** 群聊更新载荷（`update-room`，P2-6）。宿主只更新出现的字段。 */
export class RoomPatch {
  id: string;
  name?: string;
  notice?: string;
  /** admin | everyone */
  mode?: string;
  admin?: string;
  /** 新的完整成员列表 */
  members?: string[];

  constructor(id: string) {
    this.id = id;
  }
}

/**
 * 能力库条目（P2-7）。
 *
 * 宿主 `capabilities` 是团队的「可复用能力」清单：
 * `kind` 为 `mcp`（外部服务）/ `skill`（技能）/ `pack`（打包的组合）。
 * MCP 额外带 `transport` 与 `approved`；pack 带 `items`（包含的能力名）。
 */
export interface Capability {
  name: string;
  kind: string;
  description?: string;
  transport?: string;
  approved?: boolean;
  items?: string[];
}

/** 某 Bot 上某个能力的运行状态。 */
export interface CapabilityStatus {
  /** ready | connecting | needs-approval | error */
  state: string;
  error?: string;
}

/**
 * 通知中心条目（`notifications-list`，P3-4）。
 *
 * 宿主把「需要你知道的事」聚合成一个 inbox：
 * `kind` 是类别（reply 回复 / question 提问 / approval 审批），`read` 是已读状态。
 */
export interface NotificationItem {
  id: number;
  conversationId: string;
  kind: string;
  title: string;
  body?: string;
  createdAt?: number;
  read?: boolean;
}

/** 通知偏好（按设备保存）。 */
export interface NotificationPreferences {
  enabled?: boolean;
  /** 订阅的类别（与 `NotificationItem.kind` 对应） */
  categories?: string[];
  readThrough?: number;
}

export interface NotificationsPage {
  items?: NotificationItem[];
  preferences?: NotificationPreferences;
  /** 主机侧递增游标：`notifications-read {through}` 用它标记"全部已读" */
  cursor?: number;
  pushRegistered?: boolean;
  pushAvailable?: boolean;
}

/** 连接器（`state.connectors`）：GitHub 等外部账号的接入状态。 */
export interface Connector {
  id: string;
  name: string;
  /** off | connecting | ready | error */
  state: string;
  /** 已连接账号（如 GitHub 登录名） */
  account?: string | null;
  error?: string;
}

export interface TeamState {
  bots: Bot[];
  rooms: Room[];
  models: ModelOption[];
  /** 能力库（团队级清单） */
  capabilities?: Capability[];
  /** 连接器（GitHub 等外部账号） */
  connectors?: Connector[];
  /** botId → 能力名 → 状态 */
  capabilityStatuses?: Record<string, Record<string, CapabilityStatus>>;
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
  /** 仅 `kind === 'agent'` 时存在：这个会话属于哪个 DSH Agent（P2-9） */
  agentId?: string;
}

/** `add-agent` 返回的 Agent。 */
export interface AgentRecord {
  id: string;
  name?: string;
  sessions?: string[];
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
  /** 图片原始像素宽高（宿主 `projection.js` 会给），用于按比例占位 */
  width?: number;
  height?: number;
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

/**
 * 记忆条目（协议 `memory-view`，P2-4）。
 *
 * `scope` 表示这条记忆属于**该 Bot 私有**还是**团队共享**；
 * 宿主把两个作用域合并成一个列表返回，靠这个字段区分。
 */
export interface MemoryEntry {
  scope: string;
  topic?: string | null;
  text: string;
  added?: string | null;
  by?: string | null;
  source?: string | null;
}

/** 记忆容量上限（宿主 `MEMORY_LIMITS`，单位字符）。 */
export interface MemoryLimits {
  entry?: number;
  main?: number;
  topic?: number;
  topics?: number;
}

/** 记忆摘要（由模型生成，可能不存在或过期）。 */
export interface MemorySummary {
  text: string;
  at?: string;
}

/** `memory-view` / `memory-forget` 的响应。 */
export interface MemoryView {
  botId?: string;
  entries?: MemoryEntry[];
  /** 私有 / 团队各自已用字符数 */
  sizes?: MemorySizes;
  limits?: MemoryLimits;
  summary?: MemorySummary | null;
  /** 摘要是否已是最新 */
  fresh?: boolean;
  /** 主机会话摘要进行中 */
  summarizing?: boolean;
  error?: string | null;
}

export interface MemorySizes {
  own?: number;
  team?: number;
}

/** `memory-ask` 的变更结果（每条操作是否生效）。 */
export interface MemoryChange {
  op: string;
  scope: string;
  text: string;
  ok?: boolean;
  error?: string;
  before?: string;
}

/** `memory-ask` 的响应。 */
export interface MemoryAskResult {
  reply: string;
  changes?: MemoryChange[];
  view?: MemoryView;
}

/**
 * 定时任务（协议 `schedules`，P2-3）。
 *
 * 主机返回 `{ available, tasks }`；`tasks` 是「DSH schedule 目录项 + 归属信息」：
 * - `kind` 决定用哪些时间字段：`at/after` 用 `scheduledAt`，`every` 用 `everySeconds`，
 *   `daily/weekly/cron` 用 `time` + `timeZone`（+ `weekdays` / `expression`）；
 * - `botId` / `roomId` 二选一，表示任务挂在哪。
 *
 * 移动端只允许这些字段创建：`target / title / prompt / when`
 * （见宿主 `mobile/adapter.js` 的白名单），其余字段由宿主推导。
 */
/**
 * 只描述「时间」的片段。
 *
 * 展示函数只需要时间字段，不该要求调用方提供完整任务；
 * `ScheduleTask` **继承**本接口而不是"结构相同"——
 * ArkTS 不支持结构性类型（`arkts-no-structural-typing`），必须有显式继承关系。
 */
export interface ScheduleTiming {
  kind?: string;
  scheduledAt?: string;
  everySeconds?: number;
  time?: string;
  timeZone?: string;
  weekdays?: number[];
  expression?: string;
}

export interface ScheduleTask extends ScheduleTiming {
  id: string;
  sessionId: string;
  title: string;
  prompt?: string;
  botId?: string;
  roomId?: string;
  /** 下次执行时间（宿主若提供） */
  nextRunAt?: string;
}

/** 定时任务时间选择（宿主 `selectorOf` 的输入；P2-3）。 */
export class ScheduleWhen {
  /** at | daily | weekly | every */
  kind: string;
  timeZone?: string;
  at?: string;
  time?: string;
  weekdays?: number[];
  minutes?: number;

  constructor(kind: string) {
    this.kind = kind;
  }
}

export interface SchedulesPage {
  /** 主机是否开启了「自动化任务」服务；false 时 tasks 必为空 */
  available?: boolean;
  tasks?: ScheduleTask[];
}

/**
 * 用量数据（协议 `usage`，P2-2）。
 *
 * 主机返回的是**扁平行**而不是对象数组：
 * `rows[i] = [hour, ownerIndex, modelIndex, kindIndex, input, cacheRead, cacheWrite, output, calls]`，
 * 其余字段是对应的字典。这样设计是为了压小体积（一行 9 个数字），
 * 客户端需要按索引还原 —— 见 `logic/Usage.ets`。
 */
export interface UsageOwner {
  owner?: string;
  name?: string;
  kind?: string;
  id?: string;
  deleted?: boolean;
}

export interface UsageModel {
  key?: string;
  provider?: string;
  model?: string;
  name?: string;
  providerName?: string;
}

export interface UsagePage {
  /** 归属者字典（行里的 ownerIndex 指向它） */
  owners?: UsageOwner[];
  /** 模型字典（行里的 modelIndex 指向它） */
  models?: UsageModel[];
  /** 类型字典（行里的 kindIndex 指向它） */
  kinds?: string[];
  /** [hour, owner, model, kind, input, cacheRead, cacheWrite, output, calls] */
  rows?: number[][];
  /** 主机当前小时（用于算时间窗口） */
  now?: number;
  /** 主机是否仍在扫描历史数据 */
  scanning?: boolean;
}

export interface PartsPage {
  conversationId: string;
  currentSessionId: string;
  parts: ConversationPart[];
}
