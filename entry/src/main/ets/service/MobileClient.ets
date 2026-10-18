import { http } from '@kit.NetworkKit';
import { webSocket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  AgentRecord, BotPatch, BotRef, ConversationStatus, EnabledPatch, HistoryPage, MainBotPatch,
  MemoryAskResult, MemoryView, MobileEvent, NotificationsPage, PartsPage, PluginsPage,
  RoomPatch, ScheduleWhen, SchedulesPage, Session, SkillDetail, SkillsPage, UsagePage
} from '../model/Models';
import {
  EMPTY_STATUS,
  EffortOption,
  ResolvedConversationStatus,
  StreamStatus,
  WireSubmissionReceipt
} from './Wire';

/**
 * 把一帧 `status` 合并进上一次的解析结果。
 * 心跳帧只带 `running`/`phase`，其他字段沿用旧值；`attemptId`/`activity` 属于「本帧语义」，
 * 不携带时清空，避免界面把上一轮的 attempt 当成当前 attempt。
 */
function readStatus(event: ConversationStatus, previous: ResolvedConversationStatus,
  conversationId: string): ResolvedConversationStatus {
  return {
    conversationId: conversationId,
    sessionId: event.sessionId === undefined ? previous.sessionId : event.sessionId,
    running: event.running === undefined ? previous.running : event.running,
    phase: event.phase === undefined ? previous.phase : event.phase,
    attemptId: event.attemptId === undefined ? '' : event.attemptId,
    eventSeq: event.eventSeq === undefined ? previous.eventSeq : event.eventSeq,
    queue: event.queue === undefined ? previous.queue : event.queue,
    activity: event.activity === undefined ? '' : event.activity
  };
}

/** 传输层错误。`code` 与主机的错误码或本层自定义码一致。 */
export class MobileApiError extends Error {
  readonly statusCode: number;
  readonly code: string;

  constructor(message: string, statusCode: number = 0, code: string = 'request_failed') {
    super(message);
    this.name = 'MobileApiError';
    this.statusCode = statusCode;
    this.code = code;
  }
}

/** 空 JSON 体（POST 需要 body 时使用）。 */
class EmptyPayload {}

/** `/auth/refresh` 请求体。 */
interface RefreshRequest {
  refreshToken: string;
}

/** `/pairings` 请求体。 */
interface PairRequest {
  code: string;
  deviceName: string;
}

/** `/pairings/complete` 请求体。 */
interface PairCompleteRequest {
  claimToken: string;
}

/** `/actions` 请求信封。 */
interface ActionEnvelope {
  endpoint: string;
  payload: object;
}

/** `/read-markers` 请求体。 */
interface ReadMarkerRequest {
  conversationId: string;
  seq: number;
}

/** `openStream` 发送的 auth 帧（`after` 仅在有续传游标时携带）。 */
interface AuthFrame {
  type: string;
  token: string;
  conversationId: string;
  after?: number;
}

/** `/state` 与 `/conversations` 的最小投影；界面层会再转成 `TeamState` / `Conversation[]`。 */
export interface RawState {
  bots?: object[];
  rooms?: object[];
  models?: object[];
  /** 能力库（P2-7）：团队级可复用能力清单 */
  capabilities?: object[];
  /** 连接器（GitHub 等） */
  connectors?: object[];
  /** botId → 能力名 → 运行状态 */
  capabilityStatuses?: Record<string, Object>;
  mainBotId?: string;
  mainBotIds?: string[];
  questions?: object;
  work?: object;
  readOnly?: string;
}

/** `update-room` 的返回（P2-6）。 */
export interface RoomUpdateResult {
  room?: object;
  changes?: string[];
}

export interface RawConversationList {
  conversations: object[];
}

export interface RawPairingStart {
  claimToken: string;
  requestId: string;
  status: string;
}

export interface RawDeviceList {
  devices: object[];
  currentDeviceId?: string;
}

export interface RawTarget {
  conversationId: string;
  sessionId: string;
  revision: string | number;
}

export interface RawApprovalList {
  requests: object[];
}

export interface RawServerInfo {
  protocolVersion: number;
  serverId: string;
  name?: string;
}

/** 主机错误响应体。 */
interface ErrorPayload {
  error?: string;
  message?: string;
  code?: string;
}

/** 只带会话 id 的 action 载荷（`parts` 等）。 */
class ConversationRef {
  conversationId: string;

  constructor(conversationId: string) {
    this.conversationId = conversationId;
  }
}

/** 群聊删除载荷（`delete-room`）。 */
class RoomRef {
  id: string;

  constructor(id: string) {
    this.id = id;
  }
}

/** 能力挂载载荷（`bot-capability`，P2-7）。 */
class BotCapabilityBody {
  botId: string;
  name: string;
  attached: boolean;

  constructor(botId: string, name: string, attached: boolean) {
    this.botId = botId;
    this.name = name;
    this.attached = attached;
  }
}

/** 创建 Agent 载荷（`add-agent`，无参数）。 */
class AddAgentBody {
}

/** Agent 会话操作载荷（`agent-rename` / `agent-archive`）。 */
class AgentSessionBody {
  agentId: string;
  sessionId: string;
  title?: string;

  constructor(agentId: string, sessionId: string, title: string) {
    this.agentId = agentId;
    this.sessionId = sessionId;
    if (title.length > 0) this.title = title;
  }
}

/** 移除 Agent 载荷（`remove-agent`）。 */
class AgentRef {
  agentId: string;

  constructor(agentId: string) {
    this.agentId = agentId;
  }
}

/** 通知已读载荷（`notifications-read`）：要么给 ids，要么给 through 游标。 */
class NotificationReadBody {
  ids?: number[];
  through?: number;

  constructor(ids: number[], through: number) {
    if (ids.length > 0) this.ids = ids;
    else this.through = through;
  }
}

/** 通知偏好载荷（`notifications-preferences`）。 */
class NotificationPreferencesBody {
  enabled: boolean;
  categories: string[];

  constructor(enabled: boolean, categories: string[]) {
    this.enabled = enabled;
    this.categories = categories;
  }
}

/** 连接器动作的返回（宿主直接回连接器列表）。 */
export interface ConnectorList {
  connectors?: object[];
}

/** 连接器 token 载荷（`connector-connect`）。 */
class ConnectorConnectBody {
  id: string;
  token: string;

  constructor(id: string, token: string) {
    this.id = id;
    this.token = token;
  }
}

/** 连接器引用载荷（`connector-retry` / `connector-disconnect`）。 */
class ConnectorRef {
  id: string;

  constructor(id: string) {
    this.id = id;
  }
}

/** 技能列表载荷（`skills-list`，P2-8）：可选按会话过滤。 */
class SkillsQuery {
  conversationId?: string;

  constructor(conversationId: string) {
    if (conversationId.length > 0) this.conversationId = conversationId;
  }
}

/** 技能详情载荷（`skills-get`）。 */
class SkillDetailQuery {
  name: string;
  conversationId?: string;

  constructor(name: string, conversationId: string) {
    this.name = name;
    if (conversationId.length > 0) this.conversationId = conversationId;
  }
}

/** 记忆查看载荷（`memory-view`，P2-4）。字段与宿主白名单一致。 */
class MemoryViewBody {
  botId: string;
  /** 请求主机重新生成摘要 */
  summarize: boolean;
  /** 强制重新生成（忽略缓存） */
  regenerate: boolean;

  constructor(botId: string, summarize: boolean, regenerate: boolean) {
    this.botId = botId;
    this.summarize = summarize;
    this.regenerate = regenerate;
  }
}

/** 记忆删除载荷（`memory-forget`）。 */
class MemoryForgetBody {
  botId: string;
  scope: string;
  text: string;

  constructor(botId: string, scope: string, text: string) {
    this.botId = botId;
    this.scope = scope;
    this.text = text;
  }
}

/** 记忆问答载荷（`memory-ask`）。 */
class MemoryAskBody {
  botId: string;
  text: string;

  constructor(botId: string, text: string) {
    this.botId = botId;
    this.text = text;
  }
}

/** 定时任务创建载荷（`schedule-create`，P2-3）。字段与宿主白名单一致。 */
class ScheduleCreateBody {
  target: string;
  title: string;
  prompt: string;
  when: ScheduleWhen;

  constructor(target: string, title: string, prompt: string, when: ScheduleWhen) {
    this.target = target;
    this.title = title;
    this.prompt = prompt;
    this.when = when;
  }
}

/** 定时任务删除载荷（`schedule-delete`）。 */
class ScheduleDeleteBody {
  sessionId: string;
  id: string;

  constructor(sessionId: string, id: string) {
    this.sessionId = sessionId;
    this.id = id;
  }
}

/** 用量查询载荷（`usage`，P2-2）。 */
class UsageQuery {
  timeZone: string;

  constructor(timeZone: string) {
    this.timeZone = timeZone;
  }
}

/** 只带分段 id 与游标的 action 载荷（`earlier` 等）。 */
class CursorRef {
  sessionId: string;
  cursor: string;

  constructor(sessionId: string, cursor: string) {
    this.sessionId = sessionId;
    this.cursor = cursor;
  }
}

/** `/uploads` 回执（附件上传，P3 使用）。 */
export interface AttachmentReceipt {
  id?: string;
  receiptId?: string;
  name?: string;
  mediaType?: string;
  size?: number;
}

/** 提交请求体（`/submissions`）。`attachments` 留给 P3 附件。 */
export interface SubmissionRequest {
  conversationId: string;
  sessionId: string;
  requestId: string;
  text: string;
  /** 已上传附件的 receiptId（P3-1）。为空/缺省表示纯文本消息。 */
  attachments?: string[];
}

/** 事件流回调集合。 */
export interface StreamHandlers {
  onEvent: (event: MobileEvent) => void;
  onStatus: (status: StreamStatus) => void;
  onError: (message: string, code: string) => void;
}

const REFRESH_MARGIN_MS = 15000;
const DEFAULT_RECONNECT_DELAY_MS = 750;
const MAX_RECONNECT_DELAY_MS = 15000;
const MAX_RECONNECT_DOUBLINGS = 8;
const HANDSHAKE_TIMEOUT_MS = 20000;

function normalizedOrigin(value: string): string {
  const candidate = value.trim().replace(/\/+$/u, '');
  if (!candidate.startsWith('https://')) {
    throw new MobileApiError('服务器地址必须使用 HTTPS。', 0, 'insecure_url');
  }
  if (candidate.includes('?') || candidate.includes('#')) {
    throw new MobileApiError('服务器地址不能包含查询参数或片段。', 0, 'invalid_url');
  }
  const remainder = candidate.slice('https://'.length);
  const slash = remainder.indexOf('/');
  const authority = slash < 0 ? remainder : remainder.slice(0, slash);
  const path = slash < 0 ? '' : remainder.slice(slash);
  if (authority.length === 0 || authority.includes('@') || (path.length > 0 && path !== '/mobile/v1')) {
    throw new MobileApiError('服务器地址格式无效。', 0, 'invalid_url');
  }
  return `https://${authority}`;
}

/** `sha256:<64 hex>` → Network Kit 需要的 Base64 公钥摘要。 */
function pinToBase64(value: string): string {
  if (!/^sha256:[a-f0-9]{64}$/u.test(value)) {
    throw new MobileApiError('配对码中的电脑身份指纹无效。', 0, 'invalid_tls_pin');
  }
  const hex = value.slice(7);
  const bytes = new Uint8Array(32);
  for (let index = 0; index < 32; index++) {
    bytes[index] = Number.parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  }
  return new util.Base64Helper().encodeToStringSync(bytes, util.Type.BASIC);
}

function responseText(result: string | object | ArrayBuffer): string {
  if (typeof result === 'string') return result;
  if (result instanceof ArrayBuffer) return '';
  return JSON.stringify(result);
}

function parseJson<T>(text: string): T | undefined {
  if (text.length === 0) return undefined;
  try {
    return JSON.parse(text) as T;
  } catch (_error) {
    return undefined;
  }
}


/**
 * DS Bot 移动协议的 ArkTS 客户端。
 *
 * 与旧 `MobileApi` 的差别：
 * 1. 复用同一个 `http.HttpRequest`，并在 `dispose()` 统一销毁；
 * 2. 用 generation 机制让登出 / 换主机后所有在途请求立即失效；
 * 3. 新增事件流 `openStream()`（`/mobile/v1/events`），带 `eventSeq` 续传与指数退避重连；
 * 4. 新增分页 `messages(cursor)`、`submission()`、`parts()`、`uploads`、`attachments`。
 *
 * **证书锁定说明**：HTTP 走 Network Kit 的 `certificatePinning`（SPKI Base64）。
 * WebSocket 的 `WebSocketRequestOptions` 没有 pinning 字段，只有
 * `skipServerCertVerification`，因此事件流的 TLS 校验强度低于 HTTP；
 * 见 `docs/translation-plan.md` 的 D1 与最终交接报告。
 */
export class MobileClient {
  private readonly origin: string;
  private readonly tlsPin: string;
  private readonly wsUrl: string;
  private session?: Session;
  private serverId: string = '';
  private generation: number = 0;
  private refreshing?: Promise<Session>;
  private httpClient?: http.HttpRequest;
  private socket?: webSocket.WebSocket;
  private socketHandlers?: StreamHandlers;
  private streamConversationId: string = '';
  private streamAfter: number = 0;
  private reconnectAttempts: number = 0;
  private reconnectTimer: number = -1;
  private handshakeTimer: number = -1;
  private streamClosedByUser: boolean = true;
  private lastStatus: ResolvedConversationStatus = EMPTY_STATUS;

  constructor(serverUrl: string, tlsPin: string = '', session?: Session) {
    this.origin = normalizedOrigin(serverUrl);
    this.tlsPin = tlsPin;
    this.session = session;
    this.wsUrl = `${this.origin.replace(/^https/u, 'wss')}/mobile/v1/events`;
    if (session !== undefined) {
      this.serverId = session.serverId;
      if (session.serverUrl !== undefined && normalizedOrigin(session.serverUrl) !== this.origin) {
        throw new MobileApiError('会话所属服务器地址已改变，请重新配对。', 0, 'server_changed');
      }
      if (session.tlsPin !== undefined && session.tlsPin !== this.tlsPin) {
        throw new MobileApiError('电脑身份指纹已改变，请重新配对。', 0, 'server_changed');
      }
    }
  }

  getSession(): Session | undefined {
    return this.session;
  }

  getOrigin(): string {
    return this.origin;
  }

  getStatus(): ResolvedConversationStatus {
    return this.lastStatus;
  }

  /** 兼容旧调用点：事件流用不到，但保留以便界面读取最近一次状态帧。 */
  setStatus(status: ResolvedConversationStatus): void {
    this.lastStatus = status;
  }

  // ---------------------------------------------------------------- HTTP 基础

  private client(): http.HttpRequest {
    if (this.httpClient === undefined) {
      this.httpClient = http.createHttp();
    }
    return this.httpClient;
  }

  private buildOptions(method: http.RequestMethod, body: Object | undefined, authenticated: boolean,
    expectBinary: boolean, binary: ArrayBuffer | undefined = undefined): http.HttpRequestOptions {
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      // 二进制上传（附件）必须是裸字节流，不能用 JSON 的 Content-Type
      'Content-Type': binary === undefined ? 'application/json' : 'application/octet-stream'
    };
    if (authenticated) {
      if (this.session === undefined) throw new MobileApiError('设备尚未配对。', 401, 'unauthorized');
      headers['Authorization'] = `Bearer ${this.session.accessToken}`;
    }
    const options: http.HttpRequestOptions = {
      method: method,
      header: headers,
      extraData: binary !== undefined ? binary : (body === undefined ? undefined : JSON.stringify(body)),
      expectDataType: expectBinary ? http.HttpDataType.ARRAY_BUFFER : http.HttpDataType.STRING,
      usingCache: false,
      connectTimeout: 15000,
      readTimeout: 45000,
      maxLimit: 20 * 1024 * 1024
    };
    if (this.tlsPin.length > 0) {
      options.remoteValidation = 'skip';
      options.certificatePinning = {
        publicKeyHash: pinToBase64(this.tlsPin),
        hashAlgorithm: 'SHA-256'
      };
    }
    return options;
  }

  private async send<T>(path: string, method: http.RequestMethod, body: Object | undefined,
    authenticated: boolean, retry: boolean, expectBinary: boolean = false,
    binary: ArrayBuffer | undefined = undefined): Promise<T> {
    const active = this.generation;
    try {
      const response = await this.client().request(`${this.origin}/mobile/v1${path}`,
        this.buildOptions(method, body, authenticated, expectBinary, binary));
      if (this.generation !== active) throw new MobileApiError('会话已切换。', 0, 'session_changed');
      if ((response.responseCode === 401 || response.responseCode === 403) && authenticated && retry) {
        await this.refresh();
        return this.send<T>(path, method, body, authenticated, false, expectBinary, binary);
      }
      const text = responseText(response.result);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        const failure = parseJson<ErrorPayload>(text);
        const message = failure === undefined ? '' : (failure.message ?? failure.error ?? '');
        const code = failure === undefined ? '' : (failure.code ?? '');
        throw new MobileApiError(message.length > 0 ? message : `请求失败（HTTP ${response.responseCode}）`,
          response.responseCode, code.length > 0 ? code : 'request_failed');
      }
      if (expectBinary) return response.result as T;
      if (text.length === 0) return new EmptyPayload() as T;
      const parsed = parseJson<T>(text);
      if (parsed === undefined) throw new MobileApiError('主机返回了无法解析的响应。', 0, 'invalid_response');
      return parsed;
    } finally {
      // 客户端在 dispose() 里统一销毁；这里不做 per-request destroy。
    }
  }

  private async refresh(): Promise<Session> {
    if (this.session === undefined) throw new MobileApiError('设备尚未配对。', 401, 'unauthorized');
    if (this.refreshing !== undefined) return this.refreshing;
    const promise = this.performRefresh();
    this.refreshing = promise;
    try {
      return await promise;
    } finally {
      this.refreshing = undefined;
    }
  }

  private async performRefresh(): Promise<Session> {
    if (this.session === undefined) throw new MobileApiError('设备尚未配对。', 401, 'unauthorized');
    const stale = this.session.accessToken;
    const refreshed = await this.send<Session>('/auth/refresh', http.RequestMethod.POST,
      { refreshToken: this.session.refreshToken } as RefreshRequest, false, false);
    if (this.session === undefined || this.session.accessToken !== stale) {
      // 另一个并发路径已经刷新过了。
      return this.session as Session;
    }
    if (refreshed.serverId !== this.session.serverId) {
      throw new MobileApiError('服务器身份已改变，请重新配对。', 401, 'server_changed');
    }
    refreshed.serverUrl = this.origin;
    refreshed.tlsPin = this.tlsPin;
    this.session = refreshed;
    return refreshed;
  }

  private async validSession(): Promise<Session> {
    if (this.serverId.length === 0) await this.info();
    const session = this.session;
    if (session === undefined) throw new MobileApiError('设备尚未配对。', 401, 'unauthorized');
    const expires = typeof session.expiresAt === 'number' ? session.expiresAt : Date.parse(session.expiresAt as string);
    if (Number.isFinite(expires) && expires <= Date.now() + REFRESH_MARGIN_MS) return this.refresh();
    return session;
  }

  // ------------------------------------------------------------ 配对与身份

  async info(): Promise<RawServerInfo> {
    const info = await this.send<RawServerInfo>('/info', http.RequestMethod.GET, undefined, false, false);
    const protocolVersion = info.protocolVersion;
    if (protocolVersion !== 1) {
      throw new MobileApiError('应用与主机的移动协议版本不一致，请同时更新。', 0, 'incompatible_protocol');
    }
    const serverId = info.serverId;
    if (serverId.length === 0) {
      throw new MobileApiError('服务器未返回有效身份。', 0, 'invalid_server');
    }
    if (this.serverId.length > 0 && this.serverId !== serverId) {
      throw new MobileApiError('服务器身份已改变，请重新配对。', 0, 'server_changed');
    }
    this.serverId = serverId;
    return info;
  }

  pair(code: string, deviceName: string): Promise<RawPairingStart> {
    return this.send<RawPairingStart>('/pairings', http.RequestMethod.POST,
      { code: code, deviceName: deviceName } as PairRequest, false, true);
  }

  async completePairing(claimToken: string): Promise<Session | undefined> {
    if (this.serverId.length === 0) await this.info();
    const session = await this.send<Session>('/pairings/complete', http.RequestMethod.POST,
      { claimToken: claimToken } as PairCompleteRequest, false, true);
    if (typeof session.accessToken !== 'string' || session.accessToken.length === 0) return undefined;
    if (session.serverId !== this.serverId) {
      throw new MobileApiError('配对响应来自另一台服务器，请重新配对。', 0, 'server_changed');
    }
    session.serverUrl = this.origin;
    session.tlsPin = this.tlsPin;
    this.session = session;
    return session;
  }

  // ------------------------------------------------------------------ 读取

  state(): Promise<RawState> {
    return this.send<RawState>('/state', http.RequestMethod.GET, undefined, true, true);
  }

  conversations(): Promise<RawConversationList> {
    return this.send<RawConversationList>('/conversations', http.RequestMethod.GET, undefined, true, true);
  }

  /** 分页读取消息。`cursor` 为空表示最新一页；返回的 `cursor` 用于继续向更早翻页。 */
  messages(conversationId: string, cursor: string = '', limit: number = 80): Promise<HistoryPage> {
    let path = `/conversations/${encodeURIComponent(conversationId)}/messages?limit=${limit}`;
    if (cursor.length > 0) path += `&cursor=${encodeURIComponent(cursor)}`;
    return this.send<HistoryPage>(path, http.RequestMethod.GET, undefined, true, true);
  }

  /**
   * 创建团队的 DSH Agent（`add-agent`，P2-9）。
   *
   * 宿主**每个团队最多一个**，已存在时会抛错——调用前应先用 state 判断。
   */
  addAgent(): Promise<AgentRecord> {
    return this.action<AgentRecord>('add-agent', new AddAgentBody());
  }

  /** 重命名 Agent 的某个会话（`agent-rename`）。 */
  agentRename(agentId: string, sessionId: string, title: string): Promise<boolean> {
    return this.action<boolean>('agent-rename', new AgentSessionBody(agentId, sessionId, title));
  }

  /** 归档 Agent 的某个会话（`agent-archive`）：会话从 Agent 移出并归档。 */
  agentArchive(agentId: string, sessionId: string): Promise<boolean> {
    return this.action<boolean>('agent-archive', new AgentSessionBody(agentId, sessionId, ''));
  }

  /** 移除整个 Agent（`remove-agent`）。 */
  removeAgent(agentId: string): Promise<RawState> {
    return this.action<RawState>('remove-agent', new AgentRef(agentId));
  }

  /**
   * 列出可用技能（`skills-list`，P2-8）。
   *
   * 不传 `conversationId` 时按工作区目录取；传入则按该会话的 cwd 取
   * （不同会话可能在不同目录，技能可见范围不同）。
   */
  skills(conversationId: string): Promise<SkillsPage> {
    return this.action<SkillsPage>('skills-list', new SkillsQuery(conversationId));
  }

  /** 读取技能全文（`skills-get`）：宿主只允许 `userInvocable` 的技能。 */
  skillDetail(name: string, conversationId: string): Promise<SkillDetail> {
    return this.action<SkillDetail>('skills-get', new SkillDetailQuery(name, conversationId));
  }

  /** 列出插件与插件包（`plugins-list`）。 */
  plugins(): Promise<PluginsPage> {
    return this.action<PluginsPage>('plugins-list', new EmptyPayload());
  }

  /** 启用/停用单个插件。 */
  setPluginEnabled(id: string, enabled: boolean): Promise<object> {
    return this.action<object>('plugins-set-enabled', new EnabledPatch(id, enabled));
  }

  /** 启用/停用插件包。 */
  setBundleEnabled(id: string, enabled: boolean): Promise<object> {
    return this.action<object>('bundle-set-enabled', new EnabledPatch(id, enabled));
  }

  /**
   * 更新 Bot（`update-bot`，P2-5）。
   *
   * 宿主返回更新后的 **bot 对象**（不是整份 state），
   * 所以调用方要自己合并或刷新。
   */
  updateBot(patch: BotPatch): Promise<object> {
    return this.action<object>('update-bot', toBotRequest(patch));
  }

  /** 复制 Bot（`duplicate-bot`）：返回新 bot。 */
  duplicateBot(id: string): Promise<object> {
    return this.action<object>('duplicate-bot', new BotRef(id));
  }

  /** 删除 Bot（`delete-bot`）：返回最新 state。 */
  deleteBot(id: string): Promise<RawState> {
    return this.action<RawState>('delete-bot', new BotRef(id));
  }

  /** 设置/取消主 Bot（`set-main`）：返回最新 state。 */
  setMain(id: string, main: boolean, primary: boolean, replace: string): Promise<RawState> {
    const patch = new MainBotPatch(id, main);
    if (primary) patch.primary = true;
    if (replace.length > 0) patch.replace = replace;
    return this.action<RawState>('set-main', patch);
  }

  /**
   * 更新群聊（`update-room`，P2-6）。
   *
   * 宿主返回 `{ room, changes }`：`changes` 是给人看的变更说明，
   * 直接展示比"操作成功"更有用。注意**不返回整份 state**，
   * 所以调用方需要用返回的 room 局部更新，或重新拉 state。
   */
  updateRoom(patch: RoomPatch): Promise<RoomUpdateResult> {
    return this.action<RoomUpdateResult>('update-room', patch);
  }

  /** 删除群聊（`delete-room`）：返回最新 state。 */
  deleteRoom(id: string): Promise<RawState> {
    return this.action<RawState>('delete-room', new RoomRef(id));
  }

  /** 给 Bot 挂载 / 卸载一个能力；P2-7。返回最新 state（宿主按动作回快照）。 */
  botCapability(botId: string, name: string, attached: boolean): Promise<RawState> {
    return this.action<RawState>('bot-capability', new BotCapabilityBody(botId, name, attached));
  }

  /** 读取某 Bot 的记忆（含团队共享部分）；P2-4。 */
  memoryView(botId: string, summarize: boolean, regenerate: boolean): Promise<MemoryView> {
    return this.action<MemoryView>('memory-view', new MemoryViewBody(botId, summarize, regenerate));
  }

  /** 删除一条记忆；返回删除后的完整视图。 */
  memoryForget(botId: string, scope: string, text: string): Promise<MemoryView> {
    return this.action<MemoryView>('memory-forget', new MemoryForgetBody(botId, scope, text));
  }

  /** 用自然语言让主机增删改记忆（模型解析）；P2-4。 */
  memoryAsk(botId: string, text: string): Promise<MemoryAskResult> {
    return this.action<MemoryAskResult>('memory-ask', new MemoryAskBody(botId, text));
  }

  /** 读取通知中心（P3-4）。 */
  notifications(): Promise<NotificationsPage> {
    return this.action<NotificationsPage>('notifications-list', new EmptyPayload());
  }

  /**
   * 标记已读（P3-4）。
   *
   * 传 `ids` 标记具体几条；只传 `through` 表示"这个游标之前全部已读"。
   * 两种都走同一个接口，宿主按「有没有 ids」分支处理。
   */
  markNotificationsRead(ids: number[], through: number): Promise<EmptyPayload> {
    return this.action<EmptyPayload>('notifications-read', new NotificationReadBody(ids, through));
  }

  /** 保存通知偏好（P3-4）。 */
  setNotificationPreferences(enabled: boolean, categories: string[]): Promise<EmptyPayload> {
    return this.action<EmptyPayload>('notifications-preferences',
      new NotificationPreferencesBody(enabled, categories));
  }

  /** 用一个 token 连接外部账号（`connector-connect`），返回最新连接器列表。 */
  connectorConnect(id: string, token: string): Promise<ConnectorList> {
    return this.action<ConnectorList>('connector-connect', new ConnectorConnectBody(id, token));
  }

  /** 重试连接（`connector-retry`）。 */
  connectorRetry(id: string): Promise<ConnectorList> {
    return this.action<ConnectorList>('connector-retry', new ConnectorRef(id));
  }

  /** 断开连接（`connector-disconnect`）。 */
  connectorDisconnect(id: string): Promise<ConnectorList> {
    return this.action<ConnectorList>('connector-disconnect', new ConnectorRef(id));
  }

  /** 读取定时任务列表（P2-3）。 */
  schedules(): Promise<SchedulesPage> {
    // ArkTS 不允许无类型对象字面量，空载荷用显式空类
    return this.action<SchedulesPage>('schedules', new EmptyPayload());
  }

  /** 创建定时任务；返回创建后的完整列表（宿主直接回列表，省一次请求）。 */
  createSchedule(target: string, title: string, prompt: string, when: ScheduleWhen): Promise<SchedulesPage> {
    return this.action<SchedulesPage>('schedule-create', new ScheduleCreateBody(target, title, prompt, when));
  }

  /** 删除定时任务。 */
  deleteSchedule(sessionId: string, id: string): Promise<SchedulesPage> {
    return this.action<SchedulesPage>('schedule-delete', new ScheduleDeleteBody(sessionId, id));
  }

  /**
   * 读取用量（P2-2）。
   *
   * `timeZone` 传设备时区，主机按该时区切"小时"桶——
   * 不传会按主机时区，跨时区时"今天的用量"会错位。
   */
  usage(timeZone: string): Promise<UsagePage> {
    return this.action<UsagePage>('usage', new UsageQuery(timeZone));
  }

  parts(conversationId: string): Promise<PartsPage> {
    return this.action<PartsPage>('parts', new ConversationRef(conversationId));
  }

  /** 继续读取某个历史分段的更早消息（`earlier` action）。 */
  earlier(sessionId: string, cursor: string): Promise<HistoryPage> {
    return this.action<HistoryPage>('earlier', new CursorRef(sessionId, cursor));
  }

  target(conversationId: string): Promise<RawTarget> {
    return this.send<RawTarget>(
      `/conversations/${encodeURIComponent(conversationId)}/target`, http.RequestMethod.GET, undefined, true, true);
  }

  /** 查询一次提交的最终回执，用于「结果未知」时的对账。 */
  submission(requestId: string): Promise<WireSubmissionReceipt> {
    return this.send<WireSubmissionReceipt>(`/submissions/${encodeURIComponent(requestId)}`,
      http.RequestMethod.GET, undefined, true, true);
  }

  devices(): Promise<RawDeviceList> {
    return this.send<RawDeviceList>('/devices', http.RequestMethod.GET, undefined, true, true);
  }

  // ------------------------------------------------------------------ 写入

  submit(submission: SubmissionRequest): Promise<WireSubmissionReceipt> {
    return this.send<WireSubmissionReceipt>('/submissions', http.RequestMethod.POST, submission, true, true);
  }

  cancel(conversationId: string): Promise<EmptyPayload> {
    return this.send<EmptyPayload>(`/conversations/${encodeURIComponent(conversationId)}/cancel`,
      http.RequestMethod.POST, new EmptyPayload(), true, true);
  }

  action<T>(endpoint: string, payload: object = new EmptyPayload()): Promise<T> {
    return this.send<T>('/actions', http.RequestMethod.POST,
      { endpoint: endpoint, payload: payload } as ActionEnvelope, true, true);
  }

  approvals(): Promise<RawApprovalList> {
    return this.action<RawApprovalList>('approvals');
  }

  revokeDevice(deviceId: string): Promise<EmptyPayload> {
    return this.send<EmptyPayload>(`/devices/${encodeURIComponent(deviceId)}`,
      http.RequestMethod.DELETE, undefined, true, true);
  }

  markRead(conversationId: string, seq: number): Promise<EmptyPayload> {
    return this.send<EmptyPayload>('/read-markers', http.RequestMethod.POST,
      { conversationId: conversationId, seq: seq } as ReadMarkerRequest, true, true);
  }

  /**
   * 上传附件（P3-1）。
   *
   * 协议是 **裸字节 + 查询参数**，不是 multipart：
   * `POST /uploads?conversationId=&sessionId=&name=&mediaType=`，body 为文件本身。
   * 之前这个方法把 `body` 丢了（只发了 query），等于永远上传失败。
   *
   * 返回的 `receiptId` 要放进下单条消息的 `attachments` 里才会真正发送。
   */
  upload(conversationId: string, sessionId: string, name: string, mediaType: string,
    body: ArrayBuffer): Promise<AttachmentReceipt> {
    const query = `conversationId=${encodeURIComponent(conversationId)}&sessionId=${encodeURIComponent(sessionId)}` +
      `&name=${encodeURIComponent(name)}&mediaType=${encodeURIComponent(mediaType)}`;
    return this.send<AttachmentReceipt>(`/uploads?${query}`, http.RequestMethod.POST, undefined,
      true, true, false, body);
  }

  /** 下载附件（图片 / 文件）。 */
  attachment(conversationId: string, sessionId: string, attachmentId: string, seq: number): Promise<ArrayBuffer> {
    const query = `conversationId=${encodeURIComponent(conversationId)}&sessionId=${encodeURIComponent(sessionId)}&seq=${seq}`;
    return this.send<ArrayBuffer>(`/attachments/${encodeURIComponent(attachmentId)}?${query}`,
      http.RequestMethod.GET, undefined, true, true, true);
  }

  // ------------------------------------------------------------ 事件流

  /**
   * 打开某个会话的事件流。
   *
   * - `after` 为上次收到的最大 `eventSeq`，用于断线续传；不传则从主机当前快照开始。
   * - 收到 `ready` 判定连接成功；收到 `4401`/`4403` 关闭码时先刷新令牌再重连。
   * - 其他断开按 `750ms × 2^n` 退避（上限 15s，最多翻倍 8 次）。
   */
  openStream(conversationId: string, after: number, handlers: StreamHandlers): void {
    this.closeStream();
    this.streamConversationId = conversationId;
    this.streamAfter = after;
    this.socketHandlers = handlers;
    this.streamClosedByUser = false;
    this.reconnectAttempts = 0;
    this.openSocket(false);
  }

  /** 关闭事件流并停止重连。 */
  closeStream(): void {
    this.streamClosedByUser = true;
    this.clearTimers();
    this.detachSocket();
    this.socketHandlers = undefined;
    this.streamConversationId = '';
  }

  private clearTimers(): void {
    if (this.reconnectTimer >= 0) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
    if (this.handshakeTimer >= 0) {
      clearTimeout(this.handshakeTimer);
      this.handshakeTimer = -1;
    }
  }

  private detachSocket(): void {
    const socket = this.socket;
    this.socket = undefined;
    if (socket === undefined) return;
    try {
      socket.off('open');
      socket.off('message');
      socket.off('close');
      socket.off('error');
      socket.close();
    } catch (_error) {
      // 关闭失败无需上报，连接已被丢弃。
    }
  }

  private emitStatus(status: StreamStatus): void {
    if (this.socketHandlers !== undefined) this.socketHandlers.onStatus(status);
  }

  private emitError(message: string, code: string): void {
    if (this.socketHandlers !== undefined) this.socketHandlers.onError(message, code);
  }

  private async openSocket(refreshFirst: boolean): Promise<void> {
    if (this.streamClosedByUser) return;
    const handlers = this.socketHandlers;
    if (handlers === undefined) return;
    this.emitStatus(this.reconnectAttempts === 0 ? 'connecting' : 'reconnecting');
    let session: Session;
    try {
      session = refreshFirst ? await this.refresh() : await this.validSession();
    } catch (error) {
      const failure = error as MobileApiError;
      this.emitError(failure.message, failure.code);
      if (failure.statusCode === 401 || failure.statusCode === 403 ||
        failure.code === 'unauthorized' || failure.code === 'server_changed') {
        this.emitStatus('unauthorized');
        this.streamClosedByUser = true;
        return;
      }
      this.scheduleReconnect();
      return;
    }
    if (this.streamClosedByUser) return;

    const socket = webSocket.createWebSocket();
    this.socket = socket;
    const options: webSocket.WebSocketRequestOptions = {};
    // ⚠️ 已知阻塞（2026-10-15 实测，见 docs/handoff-p0.md §6.2）：
    // 主机 `server.js` 的 `checkOrigin()` 只放行 publicUrl（含端口，例如
    // `https://192.168.x.x:8788`），而鸿蒙 WebSocket 强制发送
    // `Origin: https://192.168.1.100`（示例，无端口）；`options.header` 是**追加**语义
    // （实测会变成 `a, b` 两个值），无法覆盖或清空，因此握手被主机 403 拒绝，
    // 客户端只看到「升级响应不是 101」。修复需要主机侧放宽 origin 校验。
    // 在修复之前，界面用 `StreamStatus` 驱动 REST 轮询兜底，聊天功能不受影响。
    if (this.tlsPin.length > 0) {
      // 已知限制：WebSocket 无 pinning 选项，只能跳过系统校验。见类注释。
      options.skipServerCertVerification = true;
    }
    socket.on('open', () => {
      if (this.socket !== socket) return;
      this.reconnectAttempts = 0;
      const payload: AuthFrame = this.streamAfter > 0 ?
        {
          type: 'auth',
          token: session.accessToken,
          conversationId: this.streamConversationId,
          after: this.streamAfter
        } :
        { type: 'auth', token: session.accessToken, conversationId: this.streamConversationId };
      socket.send(JSON.stringify(payload));
    });
    socket.on('message', (error: Error, value: string | ArrayBuffer) => {
      if (error !== undefined || this.socket !== socket) return;
      const text = typeof value === 'string' ? value : '';
      if (text.length === 0) return;
      const event = parseJson<MobileEvent>(text);
      if (event === undefined) {
        this.emitError('主机发来了无法解析的事件。', 'invalid_event');
        return;
      }
      if (event.conversationId !== undefined && event.conversationId !== this.streamConversationId) return;
      if (event.type === 'ready') {
        if (this.handshakeTimer >= 0) {
          clearTimeout(this.handshakeTimer);
          this.handshakeTimer = -1;
        }
        this.emitStatus('connected');
      }
      if (event.eventSeq !== undefined) this.streamAfter = event.eventSeq;
      if (event.type === 'status') {
        // 把帧字段显式搬进 `ConversationStatus`（ArkTS 不支持结构类型，必须先构造再传参）。
        const frame: ConversationStatus = {
          conversationId: event.conversationId,
          sessionId: event.sessionId,
          running: event.running,
          phase: event.phase,
          queue: event.queue,
          activity: event.activity,
          attemptId: event.attemptId,
          eventSeq: event.eventSeq
        };
        this.lastStatus = readStatus(frame, this.lastStatus, this.streamConversationId);
      }
      if (event.type === 'error') {
        const code = (event.error === undefined ? '' : event.error.code).toLowerCase();
        if (code === 'unauthorized' || code === 'token_expired' || code === 'invalid_token') {
          this.detachSocket();
          if (!this.streamClosedByUser) void this.openSocket(true);
          return;
        }
      }
      handlers.onEvent(event);
    });
    socket.on('close', (error: Error, value: webSocket.CloseResult) => {
      if (error !== undefined || this.socket !== socket) return;
      this.clearTimers();
      this.socket = undefined;
      const code = value === undefined ? 0 : value.code;
      if (code === 4401 || code === 4403) {
        if (!this.streamClosedByUser) void this.openSocket(true);
        return;
      }
      this.scheduleReconnect();
    });
    socket.on('error', (error: Error) => {
      if (error === undefined || this.socket !== socket) return;
      this.detachSocket();
      this.scheduleReconnect();
    });
    try {
      await socket.connect(this.wsUrl, options);
      this.handshakeTimer = setTimeout(() => {
        this.handshakeTimer = -1;
        if (this.socket === socket) {
          this.detachSocket();
          this.scheduleReconnect();
        }
      }, HANDSHAKE_TIMEOUT_MS);
    } catch (error) {
      const failure = error as Error;
      this.socket = undefined;
      this.emitError(`事件流连接失败：${failure.message}`, 'stream_connect_failed');
      this.scheduleReconnect();
    }
  }

  private scheduleReconnect(): void {
    if (this.streamClosedByUser || this.reconnectTimer >= 0) return;
    this.emitStatus('reconnecting');
    const doublings = Math.min(this.reconnectAttempts, MAX_RECONNECT_DOUBLINGS);
    const delay = Math.min(MAX_RECONNECT_DELAY_MS, DEFAULT_RECONNECT_DELAY_MS * Math.pow(2, doublings));
    this.reconnectAttempts++;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      void this.openSocket(false);
    }, delay);
  }

  // ------------------------------------------------------------------ 生命周期

  /**
   * 登录状态变化后调用：让所有在途请求与事件流立即失效。
   * 返回新的 generation，界面无需关心其数值。
   */
  invalidate(): number {
    this.generation++;
    this.closeStream();
    return this.generation;
  }

  /** 释放网络资源；页面销毁时必须调用。 */
  dispose(): void {
    this.generation++;
    this.closeStream();
    const client = this.httpClient;
    this.httpClient = undefined;
    if (client !== undefined) {
      try {
        client.destroy();
      } catch (_error) {
        // 已销毁则忽略。
      }
    }
  }
}

/**
 * `BotPatch` → `update-bot` 的请求体（P3-1 反馈）。
 *
 * 宿主 `cleanAvatar` 只接受 `{ shape?, image? }` 形状，
 * 所以 `avatarImage` 必须包成 `avatar: { image }`；
 * 清除头像时传 `avatar: null`，宿主会 `delete bot.avatar`。
 */
function toBotRequest(patch: BotPatch): BotUpdateRequest {
  const body = new BotUpdateRequest(patch.id);
  body.name = patch.name;
  body.role = patch.role;
  body.instructions = patch.instructions;
  body.model = patch.model;
  body.effort = patch.effort;
  if (patch.avatarImage !== undefined) {
    body.avatar = patch.avatarImage.length > 0 ? new AvatarPayload(patch.avatarImage) : null;
  }
  return body;
}

/** 头像请求体。 */
class AvatarPayload {
  image: string;

  constructor(image: string) {
    this.image = image;
  }
}

/** `update-bot` 请求体（字段为 undefined 时不会被 JSON.stringify 输出）。 */
class BotUpdateRequest {
  id: string;
  name?: string;
  role?: string;
  instructions?: string;
  model?: string;
  effort?: string;
  avatar?: AvatarPayload | null;

  constructor(id: string) {
    this.id = id;
  }
}
