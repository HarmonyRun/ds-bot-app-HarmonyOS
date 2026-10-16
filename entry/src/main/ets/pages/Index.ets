import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  Approval,
  ApprovalDecisionPayload,
  Avatar,
  Bot,
  ClientProfile,
  Conversation,
  DeviceListItem,
  Message,
  PairingCode,
  Question,
  QuestionOption,
  Room,
  RoomRound,
  QueueItem,
  Session,
  TeamState,
  ToolActivity
} from '../model/Models';
import { MobileApiError, MobileClient, RawApprovalList, RawConversationList, RawDeviceList, RawServerInfo, RawState, RawTarget, SubmissionRequest } from '../service/MobileClient';
import { MessageCache } from '../service/MessageCache';
import { serverNameOf, toApprovals, toConversations, toDeviceList, toTeamState } from '../service/Projection';
import { ProfileStore } from '../service/ProfileStore';
import { MobileEvent, StreamStatus } from '../service/Wire';
import { EffortOption } from '../service/Wire';
import { applyConversationEvent, mergeMessages } from '../logic/Merge';
import { ConversationQuestion, questionsForConversation } from '../logic/Questions';
import { busyMemberIds, memberProgress, MemberProgress, toRoomRounds } from '../logic/GroupProgress';
import {
  ChatReference,
  composeReferenceDraft,
  mentionCandidates,
  MentionCandidate,
  mentionQuery,
  referenceDraft,
  ReferenceChat,
  ReferenceChatsResult,
  sessionMention
} from '../logic/Composer';
import { StreamProbe } from '../view/StreamProbe';
import { MarkdownView } from '../view/MarkdownView';
import { MessageAction, MessageActionSheet } from '../view/MessageActionSheet';
import { GroupProgressBar, MemberChip } from '../view/GroupProgressBar';
import { QueuePanel } from '../view/QueuePanel';
import { ChatApprovals, DARK_NOTICE_THEME, LIGHT_NOTICE_THEME } from '../view/ChatApprovals';
import { ToolCard } from '../view/ToolCard';
import { QuestionCard } from '../view/QuestionCard';
import { SettingsPage, SettingsTheme, SettingsView } from '../view/SettingsPage';
import { CapabilitiesPage, SecondaryPageTheme, ToolsPage } from '../view/SecondaryPages';
import { ConversationAvatar } from '../view/ConversationAvatarView';
import { ConversationEntry, DesktopSidebar, RailItem, SidebarTheme } from '../view/DesktopSidebar';
import { AvatarSpec, BotAvatar } from '../view/BotAvatar';
import { ThemeTokens, themeOf } from '../view/Theme';
import { toDefaultEffort, toEffortOptions } from '../logic/Efforts';
import {
  conversationTime as conversationTimeOf, isAuthFailure as isAuthFailureOf,
  isConfirmedLocally as isConfirmedLocallyOf, questionKeyOf
} from '../logic/ViewUtil';
import {
  botOf as botOfIn, isMainAvatar as isMainAvatarIn, isMainBotIdOf, isMainConversation as isMainConversationIn,
  mainBotIdsOf, memberSlotCount, memberSlotOffset, memberSlotSize, roomMembersOf
} from '../logic/ConversationAvatar';
import { BotAvatarView } from '../view/BotAvatarView';
import { avatarPalette, avatarShapes as avatarShapeList } from '../view/AvatarData';

type AppSection = 'chat' | 'team' | 'settings';

interface CreateBotPayload {
  name: string;
  role: string;
  instructions: string;
  color: string;
  avatar: object;
  model?: string;
}

interface CreateRoomPayload {
  name: string;
  members: string[];
  admin: string;
  greet: boolean;
}

interface ConversationFlagPayload {
  id: string;
  pinned?: boolean;
  hidden?: boolean;
}

interface EffortResult {
  efforts: EffortOption[];
  defaultEffort?: string;
}

interface UpdateBotEffortPayload {
  id: string;
  effort: string | null;
}

interface ReferenceChatsPayload {
  conversationId: string;
}

interface EffortsPayload {
  ref: string;
}

interface QuestionAnswer {
  selected: string[];
  custom?: string;
}

interface AnswerQuestionPayload {
  sessionId: string;
  questionId: string;
  answer: QuestionAnswer;
}

interface DismissQuestionPayload {
  sessionId: string;
}

interface RoomProgressPayload {
  roomId: string;
}

interface StopMemberWorkPayload {
  roomId: string;
  botId: string;
}

/** `queue-remove` 的载荷。 */
class QueueRemoveRequest {
  conversationId: string;
  sessionId: string;
  itemId: string;

  constructor(conversationId: string, sessionId: string, itemId: string) {
    this.conversationId = conversationId;
    this.sessionId = sessionId;
    this.itemId = itemId;
  }
}


const EMPTY_TEAM: TeamState = { bots: [], rooms: [], models: [] };

@Entry
@Component
struct Index {
  @State ready: boolean = false;
  @State paired: boolean = false;
  @State busy: boolean = false;
  @State refreshing: boolean = false;
  @State online: boolean = false;
  @State windowWidth: number = 390;
  @State section: AppSection = 'chat';
  @State serverName: string = '';
  @State error: string = '';
  @State pairingJson: string = '';
  @State deviceName: string = 'HarmonyOS 设备';
  @State team: TeamState = EMPTY_TEAM;
  @State conversations: Conversation[] = [];
  @State conversationPreviews: Record<string, string> = {};
  @State selectedId: string = '';
  @State messages: Message[] = [];
  @State draft: string = '';
  @State searchText: string = '';
  @State searching: boolean = false;
  @State mobileOverlay: string = '';
  @State newBotName: string = '';
  @State newBotShape: string = 'gumdrop';
  @State newBotColor: string = 'blue';
  @State newGroupName: string = '';
  @State selectedMembers: string[] = [];
  @State approvals: Approval[] = [];
  @State devices: DeviceListItem[] = [];
  @State dark: boolean = false;
  @State showHidden: boolean = false;
  /** 长按首页主 Bot 头像打开事件流验证页（P0-1 产物）。 */
  @State showProbe: boolean = false;
  /** 事件流连接状态（idle/connecting/connected/reconnecting/closed/unauthorized）。 */
  @State streamStatus: string = 'idle';
  /** 主机排队中的待发消息（来自 status 帧的 queue）。 */
  @State queue: QueueItem[] = [];
  /** 是否展开排队列表。 */
  @State showQueue: boolean = true;
  /** 正在加载更早的历史消息。 */
  @State loadingEarlier: boolean = false;
  /** 本地是否还有更早的历史（翻到最早时为 false）。 */
  @State hasEarlier: boolean = true;
  @State historyCursor: string = '';
  private historyInitialized: boolean = false;
  /** 已展开思考过程的消息 id（P1-4）。 */
  @State expandedReasoning: string[] = [];
  /** 长按消息弹出的动作列表。 */
  @State messageActions: MessageAction[] = [];
  @State actionTargetId: string = '';
  /** 是否展示消息操作面板（驱动原生 bindSheet）。 */
  @State messageActionsVisible: boolean = false;
  /** 宽屏分栏宽度（vp）：由 SideBarContainer 决定，用户可拖拽。 */
  @State sideBarWidth: number = 340;
  /** 侧栏当前是否可见（SideBarContainer.onChange）。 */
  @State sideBarShown: boolean = true;
  /** 已展开的工具卡片 callId。 */
  /** 输入框原生选区，用于只在光标所在位置弹出 @ 候选。 */
  @State composerSelectionStart: number = 0;
  @State composerSelectionEnd: number = 0;
  @State composerFocused: boolean = false;
  /** 当前 Bot 模型支持的推理档位。空字符串表示模型默认值。 */
  @State effortOptions: EffortOption[] = [];
  @State selectedEffort: string = '';
  @State effortLoading: boolean = false;
  /** 会话引用使用 ArkUI 原生 bindSheet 展示。 */
  @State referencePickerVisible: boolean = false;
  @State referenceLoading: boolean = false;
  @State referenceAvailable: boolean = false;
  @State referenceQuery: string = '';
  @State referenceChats: ReferenceChat[] = [];
  /** 提问卡的临时选择只存在本页；提交成功后由刷新后的 `/state` 移除卡片。 */
  @State questionBusyKey: string = '';
  @State questionErrorKey: string = '';
  @State questionError: string = '';
  /** 群聊运行轮次由 `room-progress` 每秒更新；`/state.work` 提供工作与审批兜底。 */
  @State roomRounds: RoomRound[] = [];
  @State roomProgressUnavailable: boolean = false;
  @State roomProgressError: string = '';
  @State stoppingMemberId: string = '';
  private apiClient?: MobileClient;
  private profile?: ClientProfile;
  private cache?: MessageCache;
  private scroller: Scroller = new Scroller();
  private composerController: TextAreaController = new TextAreaController();
  /** 已登记的滚动定时器，销毁时统一清理（旧实现从不清理，见缺陷 B3）。 */
  private scrollTimers: number[] = [];
  /** 事件流不可用时的兜底轮询定时器（-1 表示未启动）。 */
  private fallbackTimer: number = -1;
  /** 审批轮询定时器（-1 表示未启动）。 */
  private approvalTimer: number = -1;
  private roomProgressTimer: number = -1;
  private roomProgressLoading: boolean = false;
  private roomProgressGeneration: number = 0;
  private streamConversationId: string = '';
  /** 配对期间专用的 client；失败或页面销毁时可单独 dispose，所以用可选类型。 */
  private pairingClient?: MobileClient;

  aboutToAppear(): void {
    void this.restore();
  }

  /**
   * 页面销毁时必须释放网络资源与定时器，否则事件流和滚动回调会在后台继续跑。
   * 这是 P0-8 修复的缺陷之一（旧实现没有任何清理钩子）。
   */
  aboutToDisappear(): void {
    this.clearScrollTimers();
    this.stopFallbackPoll();
    this.stopApprovalPoll();
    this.stopRoomProgressPoll();
    this.stopStream();
    if (this.pairingClient !== undefined) {
      this.pairingClient.dispose();
      this.pairingClient = undefined;
    }
    if (this.apiClient !== undefined) {
      this.apiClient.dispose();
      this.apiClient = undefined;
    }
  }

  /** 统一登记滚动定时器，便于在页面销毁时一次性清理。 */
  private scrollToBottom(delay: number): void {
    const timer = setTimeout((): void => this.scroller.scrollEdge(Edge.Bottom), delay);
    this.scrollTimers.push(timer);
  }

  private clearScrollTimers(): void {
    for (const timer of this.scrollTimers) {
      clearTimeout(timer);
    }
    this.scrollTimers = [];
  }

  private context(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private updateWindowWidth(width: Length): void {
    const parsed = typeof width === 'number' ? width : Number.parseFloat(width.toString());
    if (Number.isFinite(parsed) && parsed > 0) this.windowWidth = parsed;
  }

  private pageBg(): string {
    return this.dark ? '#101116' : '#F6F7FB';
  }

  private surface(): string {
    return this.dark ? '#1A1C24' : '#FFFFFF';
  }

  private ink(): string {
    return this.dark ? '#F4F5FA' : '#202336';
  }

  private muted(): string {
    return this.dark ? '#A4A9BB' : '#6F758B';
  }

  private line(): string {
    return this.dark ? '#2B2E39' : '#E7E9F1';
  }

  private async restore(): Promise<void> {
    try {
      const saved = await ProfileStore.load(this.context());
      if (saved !== undefined) {
        this.profile = saved;
        this.serverName = saved.serverName;
        this.apiClient = new MobileClient(saved.serverUrl, saved.tlsPin, saved.session);
        this.cache = new MessageCache(saved.session.serverId);
        this.paired = true;
        await this.refreshAll();
      }
    } catch (error) {
      this.error = `恢复连接失败：${(error as Error).message}`;
    } finally {
      this.ready = true;
    }
  }

  /**
   * 配对流程。
   *
   * 与旧实现的差别：
   * - 使用统一传输层 `MobileClient`，配对成功后同一个 client 直接复用，不再重建；
   * - 轮询 `completePairing` 的 80×1500ms 循环改为**可取消**：页面销毁或用户重试时立即停止
   *   （旧实现没有任何取消手段，见 P0 缺陷清单 B1/B3）。
   */
  private async pair(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.error = '';
    let client: MobileClient | undefined = undefined;
    try {
      const value = JSON.parse(this.pairingJson.trim()) as PairingCode;
      if (typeof value.url !== 'string' || value.url.trim().length === 0 ||
        typeof value.code !== 'string' || value.code.trim().length === 0 ||
        typeof value.serverId !== 'string' || value.serverId.trim().length === 0) {
        throw new Error('请粘贴电脑端显示的完整配对 JSON。');
      }
      client = new MobileClient(value.url, value.tlsPin ?? '');
      this.pairingClient = client;
      const info: RawServerInfo = await client.info();
      if (info.serverId !== value.serverId) throw new Error('服务器身份与配对码不一致，请重新生成配对码。');
      const pairing = await client.pair(value.code, this.deviceName.trim());
      this.getUIContext().getPromptAction().showToast({ message: '请在电脑端批准此设备', duration: 2500 });
      let session: Session | undefined = undefined;
      for (let attempt = 0; attempt < 80 && session === undefined && this.pairingClient !== undefined; attempt++) {
        session = await client.completePairing(pairing.claimToken);
        if (session === undefined) await new Promise<void>((resolve) => setTimeout(resolve, 1500));
      }
      if (session === undefined) throw new Error('配对已超时，请重新生成配对码。');
      const profile: ClientProfile = {
        serverUrl: value.url.replace(/\/+$/u, '').replace(/\/mobile\/v1$/u, ''),
        serverName: serverNameOf(info),
        tlsPin: value.tlsPin ?? '',
        session: session
      };
      await ProfileStore.save(this.context(), profile);
      this.profile = profile;
      if (this.apiClient !== undefined) this.apiClient.dispose();
      this.apiClient = client;
      this.cache = new MessageCache(session.serverId);
      this.pairingClient = undefined;
      this.serverName = profile.serverName;
      this.paired = true;
      this.pairingJson = '';
      await this.refreshAll();
    } catch (error) {
      this.error = (error as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async refreshAll(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.refreshing) return;
    this.refreshing = true;
    this.error = '';
    try {
      const rawState: RawState = await api.state();
      const rawConversations: RawConversationList = await api.conversations();
      this.team = toTeamState(rawState);
      const conversations = toConversations(rawConversations);
      this.conversations = conversations;
      void this.loadConversationPreviews(conversations);
      this.online = true;
      if (this.selectedId.length > 0) void this.loadEfforts();
      if (this.selectedId.length === 0 && conversations.length > 0 && this.windowWidth >= 600) {
        await this.selectConversation(conversations[0]);
      } else if (this.selectedId.length > 0) {
        await this.loadMessages();
      }
      const currentSession = api.getSession();
      if (this.profile !== undefined && currentSession !== undefined &&
        currentSession.accessToken !== this.profile.session.accessToken) {
        this.profile.session = currentSession;
        await ProfileStore.save(this.context(), this.profile);
      }
    } catch (error) {
      this.online = false;
      if (this.isAuthFailure(error)) {
        await this.handleSessionLost('设备会话已失效，请重新与电脑配对。');
        return;
      }
      this.error = (error as Error).message;
    } finally {
      this.refreshing = false;
    }
  }

  /** 打开会话：先渲染本机缓存，再拉主机最新页，最后订阅事件流。 */
  private async selectConversation(item: Conversation): Promise<void> {
    this.stopRoomProgressPoll();
    this.selectedId = item.id;
    this.messages = [];
    this.historyCursor = '';
    this.historyInitialized = false;
    this.hasEarlier = true;
    this.loadingEarlier = false;
    this.draft = '';
    this.composerSelectionStart = 0;
    this.composerSelectionEnd = 0;
    this.referencePickerVisible = false;
    this.roomProgressError = '';
    const cached = this.cache === undefined ? [] : await this.cache.messages(this.context(), item.id);
    if (this.selectedId !== item.id) return;
    if (cached.length > 0) {
      this.messages = cached;
      this.scrollToBottom(40);
    }
    const draft = this.cache === undefined ? '' : await this.cache.draft(this.context(), item.id);
    if (this.selectedId === item.id) this.draft = draft;
    void this.loadEfforts();
    await this.loadMessages();
    this.startStream(item.id);
    this.scheduleFallbackPoll();
    void this.loadAdminData();
    this.startApprovalPoll();
  }

  /**
   * 订阅事件流。这是 P0-4/P0-5 的核心：
   * 不再靠轮询猜「回复好了没有」，而是由主机推 `reset` / `delta` / `message` / `status`。
   */
  private startStream(conversationId: string): void {
    const api = this.apiClient;
    if (api === undefined) return;
    this.stopStream();
    this.streamConversationId = conversationId;
    api.openStream(conversationId, 0, {
      onEvent: (event: MobileEvent): void => this.handleStreamEvent(conversationId, event),
      onStatus: (status: StreamStatus): void => {
        this.streamStatus = status;
        this.online = status === 'connected' || status === 'connecting' || status === 'reconnecting';
        this.refreshRoomProgressPoll();
        if (status === 'unauthorized') void this.handleSessionLost('设备会话已失效，请重新与电脑配对。');
      },
      onError: (message: string, _code: string): void => {
        this.error = message;
      }
    });
  }

  private stopStream(): void {
    this.streamConversationId = '';
    this.streamStatus = 'idle';
    if (this.apiClient !== undefined) this.apiClient.closeStream();
  }

  /** 处理一帧事件：合并消息、刷新执行状态、必要时落盘。 */
  private handleStreamEvent(conversationId: string, event: MobileEvent): void {
    if (this.selectedId !== conversationId) return;
    if (event.type === 'reset') {
      this.messages = applyConversationEvent(this.messages, event);
      this.busy = false;
      this.refreshRoomProgressPoll();
      void this.persistMessages(conversationId);
      this.scrollToBottom(40);
      return;
    }
    if (event.type === 'delta') {
      this.busy = true;
      this.refreshRoomProgressPoll();
      const pending = this.pendingFromDelta(event);
      if (pending !== undefined) {
        this.messages = mergeMessages(this.messages, [pending]);
        this.scrollToBottom(30);
      }
      return;
    }
    if (event.type === 'message') {
      const message = event.message;
      if (message !== undefined) {
        this.messages = mergeMessages(this.messages, [message]);
        void this.persistMessages(conversationId);
        this.scrollToBottom(30);
        if (message.role === 'assistant') this.busy = false;
        this.refreshRoomProgressPoll();
      }
      return;
    }
    if (event.type === 'status') {
      const resolved = this.apiClient === undefined ? undefined : this.apiClient.getStatus();
      if (resolved !== undefined) {
        this.busy = resolved.running;
        this.queue = resolved.queue;
        this.refreshRoomProgressPoll();
      }
    }
  }

  /** 把一帧 `delta` 变成界面上的流式占位消息（累积快照，整段替换 text）。 */
  private pendingFromDelta(event: MobileEvent): Message | undefined {
    const attemptId = event.attemptId;
    const text = event.text;
    if (attemptId === undefined || text === undefined) return undefined;
    const sessionId = event.sessionId ?? this.selectedConversation()?.sessionId ?? '';
    const id = `stream:${sessionId}:${attemptId}`;
    const previous = this.messages.find((item: Message) => item.id === id);
    const message: Message = {
      id: id,
      sessionId: sessionId,
      seq: Number.MAX_SAFE_INTEGER,
      role: 'assistant',
      text: text,
      createdAt: previous === undefined ? Date.now() : previous.createdAt,
      pending: true,
      attemptId: attemptId
    };
    if (event.index !== undefined) message.streamIndex = event.index;
    if (event.reasoning !== undefined) message.reasoning = event.reasoning;
    else if (previous !== undefined && previous.reasoning !== undefined) message.reasoning = previous.reasoning;
    return message;
  }

  /**
   * 会话失效（401/403/unauthorized）时清理本机凭据并回到连接页。
   * 旧实现在这种情况下只弹一条错误横幅，用户会卡在「没有找到会话」的死路上。
   */
  private async handleSessionLost(reason: string): Promise<void> {
    this.stopRoomProgressPoll();
    this.stopStream();
    if (this.apiClient !== undefined) {
      this.apiClient.dispose();
      this.apiClient = undefined;
    }
    if (this.cache !== undefined) {
      await this.cache.clear(this.context());
      this.cache = undefined;
    }
    await ProfileStore.clear(this.context());
    this.profile = undefined;
    this.paired = false;
    this.online = false;
    this.team = EMPTY_TEAM;
    this.conversations = [];
    this.messages = [];
    this.selectedId = '';
    this.deviceName = 'HarmonyOS 设备';
    this.error = reason;
  }

  private isAuthFailure(error: Object): boolean {
    return isAuthFailureOf(error);
  }

  /** 事件流状态的用户可读文案。 */
  private streamLabel(): string {
    if (this.streamStatus === 'connected') return this.queue.length > 0 ? `实时已连接 · 排队 ${this.queue.length}` : '实时已连接';
    if (this.streamStatus === 'connecting') return '正在连接实时通道…';
    if (this.streamStatus === 'reconnecting') return '实时通道重连中…';
    if (this.streamStatus === 'unauthorized') return '会话已失效';
    if (this.streamStatus === 'closed') return '实时通道已断开';
    return this.online ? '已连接主机' : '未连接';
  }

  /** 清空本机消息与草稿缓存（设置 → 维护）。只动本机数据，不碰主机。 */
  private async clearLocalCache(): Promise<void> {
    if (this.cache === undefined) {
      this.toast('当前没有可清理的缓存');
      return;
    }
    // 清缓存会丢掉本机已缓存的消息与草稿（不可恢复），同样先确认
    const confirmed = await this.confirmDestructive(
      '清空本机缓存', '将删除本机保存的消息与草稿。主机上的数据不受影响，但本机历史需要重新加载。', '清空');
    if (!confirmed) return;
    await this.cache.clear(this.context());
    this.messages = [];
    this.conversationPreviews = {};
    this.draft = '';
    this.toast('本机缓存已清空');
  }

  private async cacheDraft(conversationId: string, text: string): Promise<void> {
    if (this.cache === undefined) return;
    await this.cache.saveDraft(this.context(), conversationId, text);
  }

  /** 输入框只显示正文；引用在草稿头部持久化并以芯片呈现。 */
  private composerText(): string {
    return referenceDraft(this.draft).text;
  }

  private composerReferences(): ChatReference[] {
    return referenceDraft(this.draft).references;
  }

  private composerMaxLength(): number {
    const visible = this.composerText();
    return Math.max(0, 100000 - (this.draft.length - visible.length));
  }

  private setComposerText(value: string): void {
    this.draft = composeReferenceDraft(value, this.composerReferences());
    void this.cacheDraft(this.selectedId, this.draft);
  }

  private selectedBot(): Bot | undefined {
    const conversation = this.selectedConversation();
    return conversation === undefined ? undefined : this.botOf(conversation);
  }

  private selectedRoom(): Room | undefined {
    const conversation = this.selectedConversation();
    if (conversation === undefined || conversation.kind !== 'room') return undefined;
    return this.team.rooms.find((room: Room) =>
      room.id === conversation.id || `room:${room.id}` === conversation.id);
  }

  private roomProgressMemberIds(): string[] {
    const room = this.selectedRoom();
    if (room === undefined) return [];
    if (this.busy && this.roomRounds.length > 0) {
      return room.members.filter((id: string) => this.botById(id) !== undefined);
    }
    return busyMemberIds(room.members, room.id, this.team.work)
      .filter((id: string) => this.botById(id) !== undefined);
  }

  private progressOf(room: Room, botId: string): MemberProgress {
    return memberProgress(botId, room.id, this.roomRounds, this.team.work);
  }

  private async stopMemberWork(roomId: string, botId: string): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.stoppingMemberId.length > 0 || !this.online || this.team.readOnly !== undefined) return;
    this.stoppingMemberId = botId;
    this.roomProgressError = '';
    try {
      const payload: StopMemberWorkPayload = { roomId: roomId, botId: botId };
      await api.action<object>('stop-member-work', payload);
      await this.loadQuestionState();
      if (this.busy) await this.loadRoomProgress(roomId);
    } catch (error) {
      this.roomProgressError = `无法停止成员任务：${(error as Error).message}`;
    } finally {
      this.stoppingMemberId = '';
    }
  }

  private composerMentionRows(): MentionCandidate[] {
    if (!this.composerFocused || this.busy || !this.online) return [];
    const query = mentionQuery(this.composerText(), {
      start: this.composerSelectionStart,
      end: this.composerSelectionEnd
    });
    if (query === undefined) return [];
    const rows = mentionCandidates(this.team.bots, this.selectedBot()?.id, this.selectedRoom(), query.query, '所有人');
    return rows.slice(0, 8);
  }

  private pickMention(name: string): void {
    const text = this.composerText();
    const query = mentionQuery(text, {
      start: this.composerSelectionStart,
      end: this.composerSelectionEnd
    });
    if (query === undefined) return;
    const insert = `@${name} `;
    const next = `${text.slice(0, query.start)}${insert}${text.slice(query.end)}`;
    const caret = query.start + insert.length;
    this.setComposerText(next);
    this.composerSelectionStart = caret;
    this.composerSelectionEnd = caret;
    setTimeout((): void => this.composerController.caretPosition(caret), 0);
  }

  private filteredReferenceChats(): ReferenceChat[] {
    const query = this.referenceQuery.trim().toLowerCase();
    if (query.length === 0) return this.referenceChats;
    return this.referenceChats.filter((chat: ReferenceChat) => chat.label.toLowerCase().includes(query));
  }

  private async openReferencePicker(): Promise<void> {
    const api = this.apiClient;
    const conversationId = this.selectedId;
    if (api === undefined || conversationId.length === 0 || !this.online || this.busy) return;
    if (this.composerReferences().length >= 3) {
      this.toast('每条消息最多引用 3 个会话');
      return;
    }
    this.referencePickerVisible = true;
    this.referenceLoading = true;
    this.referenceAvailable = false;
    this.referenceQuery = '';
    this.referenceChats = [];
    try {
      const payload: ReferenceChatsPayload = { conversationId: conversationId };
      const result = await api.action<ReferenceChatsResult>('reference-chats', payload);
      if (this.selectedId !== conversationId) return;
      this.referenceAvailable = result.available;
      this.referenceChats = result.chats;
    } catch (error) {
      this.error = `读取可引用会话失败：${(error as Error).message}`;
    } finally {
      this.referenceLoading = false;
    }
  }

  private pickReference(chat: ReferenceChat): void {
    const parts = referenceDraft(this.draft);
    if (parts.references.some((item: ChatReference) => item.sessionId === chat.sessionId)) {
      this.referencePickerVisible = false;
      return;
    }
    if (parts.references.length >= 3) {
      this.toast('每条消息最多引用 3 个会话');
      return;
    }
    const added: ChatReference = {
      sessionId: chat.sessionId,
      label: chat.label,
      mention: sessionMention(chat.sessionId, chat.label)
    };
    this.draft = composeReferenceDraft(parts.text, [...parts.references, added]);
    void this.cacheDraft(this.selectedId, this.draft);
    this.referencePickerVisible = false;
  }

  private removeReference(sessionId: string): void {
    const parts = referenceDraft(this.draft);
    this.draft = composeReferenceDraft(parts.text,
      parts.references.filter((item: ChatReference) => item.sessionId !== sessionId));
    void this.cacheDraft(this.selectedId, this.draft);
  }

  private composerMenu(): MenuElement[] {
    return [
      {
        value: '引用会话',
        enabled: this.online && !this.busy,
        action: (): void => { void this.openReferencePicker(); }
      },
      {
        value: '图片与文件（后续支持）',
        enabled: false,
        action: (): void => {}
      }
    ];
  }

  private effortSelectOptions(): SelectOption[] {
    const options: SelectOption[] = [{ value: '默认思考档位' }];
    for (const effort of this.effortOptions) options.push({ value: effort.name });
    return options;
  }

  private effortSelectedIndex(): number {
    if (this.selectedEffort.length === 0) return 0;
    const index = this.effortOptions.findIndex((effort: EffortOption) => effort.id === this.selectedEffort);
    return index < 0 ? 0 : index + 1;
  }

  private async loadEfforts(): Promise<void> {
    const api = this.apiClient;
    const bot = this.selectedBot();
    const conversationId = this.selectedId;
    this.effortOptions = [];
    this.selectedEffort = bot?.effort ?? '';
    if (api === undefined || bot === undefined || bot.model === undefined || bot.model.length === 0) return;
    this.effortLoading = true;
    try {
      const payload: EffortsPayload = { ref: bot.model };
      const result = await api.action<EffortResult>('efforts', payload);
      if (this.selectedId !== conversationId) return;
      // 必须走投影：主机应答可能不含 `efforts` 字段，直接赋值会把 @State 写成 undefined，
      // 下一次渲染读 `this.effortOptions.length` 就会崩溃（2026-10-16 真机/模拟器复现，
      // 故障日志指向本文件 2272 行）。见 logic/Efforts.ets 的说明与 efforts.test.ets。
      this.effortOptions = toEffortOptions(result);
      const fallback = toDefaultEffort(result);
      if (this.selectedEffort.length === 0 && fallback.length > 0) this.selectedEffort = fallback;
    } catch (_error) {
      // 模型不支持推理档位时不占用输入区；主机错误仍可在 Bot 详情里处理。
      this.effortOptions = [];
    } finally {
      this.effortLoading = false;
    }
  }

  private async setEffort(index: number): Promise<void> {
    const api = this.apiClient;
    const bot = this.selectedBot();
    if (api === undefined || bot === undefined || this.busy) return;
    const value = index <= 0 ? '' : (this.effortOptions[index - 1]?.id ?? '');
    const previous = this.selectedEffort;
    this.selectedEffort = value;
    try {
      const payload: UpdateBotEffortPayload = { id: bot.id, effort: value.length === 0 ? null : value };
      await api.action<object>('update-bot', payload);
      await this.refreshAll();
      this.toast(value.length === 0 ? '已使用模型默认思考档位' : '思考档位已更新');
    } catch (error) {
      this.selectedEffort = previous;
      this.error = `更新思考档位失败：${(error as Error).message}`;
    }
  }

  /**
   * 事件流不可用时的兜底轮询。
   *
   * 背景：P0 时主机 Origin 白名单曾阻塞鸿蒙 WebSocket；P1 已通过主机
   * `mobile.allowedOrigins` 配置解决。这里仍保留「每 5 秒拉一次当前会话」作为网络故障、
   * 配置回退或 WebSocket 暂时断开时的容错；事件流一旦连上就不执行请求。
   */
  private scheduleFallbackPoll(): void {
    if (this.fallbackTimer >= 0) return;
    this.fallbackTimer = setInterval((): void => {
      if (this.streamStatus === 'connected') return;
      if (this.selectedId.length === 0) return;
      void this.loadMessages();
    }, 5000);
  }

  /**
   * 审批轮询（P1-6）。
   *
   * 主机不会主动推送「有新审批 / 问题」的事件，所以聊天打开期间按 10 秒轮询一次
   * `/actions approvals` 与 `/state`。后者只更新 questions/团队轻量状态，不重拉消息历史。
   */
  private startApprovalPoll(): void {
    if (this.approvalTimer >= 0) return;
    this.approvalTimer = setInterval((): void => {
      if (this.selectedId.length === 0) return;
      void this.loadAdminData();
      void this.loadQuestionState();
    }, 10000);
  }

  private stopApprovalPoll(): void {
    if (this.approvalTimer >= 0) {
      clearInterval(this.approvalTimer);
      this.approvalTimer = -1;
    }
  }

  /** 上游只在群聊运行时轮询轮次；非群聊、离线或执行结束立即释放定时器。 */
  private refreshRoomProgressPoll(): void {
    const room = this.selectedRoom();
    if (room === undefined || !this.online || !this.busy) {
      this.stopRoomProgressPoll();
      return;
    }
    if (this.roomProgressTimer >= 0) return;
    void this.loadRoomProgress(room.id);
    this.roomProgressTimer = setInterval((): void => {
      const current = this.selectedRoom();
      if (current === undefined || current.id !== room.id || !this.online || !this.busy) {
        this.stopRoomProgressPoll();
        return;
      }
      void this.loadRoomProgress(room.id);
    }, 1000);
  }

  private stopRoomProgressPoll(): void {
    this.roomProgressGeneration += 1;
    if (this.roomProgressTimer >= 0) {
      clearInterval(this.roomProgressTimer);
      this.roomProgressTimer = -1;
    }
    this.roomProgressLoading = false;
    this.roomRounds = [];
    this.roomProgressUnavailable = false;
  }

  private async loadRoomProgress(roomId: string): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.roomProgressLoading) return;
    const generation = this.roomProgressGeneration;
    this.roomProgressLoading = true;
    try {
      const payload: RoomProgressPayload = { roomId: roomId };
      const result: Object = await api.action<Object>('room-progress', payload);
      if (generation !== this.roomProgressGeneration || this.selectedRoom()?.id !== roomId || !this.busy) return;
      this.roomRounds = toRoomRounds(result);
      this.roomProgressUnavailable = false;
    } catch (_error) {
      if (generation === this.roomProgressGeneration && this.selectedRoom()?.id === roomId && this.busy) {
        this.roomRounds = [];
        this.roomProgressUnavailable = true;
      }
    } finally {
      if (generation === this.roomProgressGeneration) this.roomProgressLoading = false;
    }
  }

  private stopFallbackPoll(): void {
    if (this.fallbackTimer >= 0) {
      clearInterval(this.fallbackTimer);
      this.fallbackTimer = -1;
    }
  }

  /**
   * 判断某条本地乐观消息是否已被主机确认。
   * 本机占位气泡的 `id` 以 `local-` 开头并带 `requestId`；主机回来的同 `requestId` 消息
   * 使用真实 id（`<sessionId>:<seq>`），因此只要出现同 requestId 的正式消息就丢弃占位。
   */
  private isConfirmedLocally(item: Message, loaded: Message[]): boolean {
    return isConfirmedLocallyOf(item, loaded);
  }

  private async persistMessages(conversationId: string): Promise<void> {
    if (this.cache === undefined) return;
    await this.cache.saveMessages(this.context(), conversationId, this.messages);
  }

  private async loadConversationPreviews(items: Conversation[]): Promise<void> {
    const api = this.apiClient;
    if (api === undefined) return;
    const previews: Record<string, string> = {};
    const count = Math.min(items.length, 24);
    for (let index = 0; index < count; index++) {
      const item = items[index];
      try {
        const page = await api.messages(item.id, '', 8);
        for (let messageIndex = page.messages.length - 1; messageIndex >= 0; messageIndex--) {
          const text = page.messages[messageIndex].text.trim().replace(/\s+/gu, ' ');
          if (text.length > 0) {
            previews[item.id] = text;
            break;
          }
        }
      } catch (_error) {}
    }
    this.conversationPreviews = previews;
  }

  /** 拉取最新一页消息（90 条），并把最新 seq 报给主机作为已读位置。 */
  private async loadMessages(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.selectedId.length === 0) return;
    const conversationId = this.selectedId;
    try {
      const page = await api.messages(conversationId, '', 90);
      const loaded = mergeMessages(this.messages, page.messages);
      if (this.selectedId !== conversationId) return;
      // 乐观回执对账：主机回来的消息里若已包含同一个 requestId，就丢掉本地占位气泡。
      // 事件流不可用时（见 scheduleFallbackPoll 的说明）这是唯一能清掉「发送中…」的路径。
      this.messages = loaded.filter((item: Message) => !this.isConfirmedLocally(item, loaded));
      if (!this.historyInitialized) {
        this.historyCursor = page.cursor ?? '';
        this.hasEarlier = this.historyCursor.length > 0;
        this.historyInitialized = true;
      }
      this.online = true;
      // 已连接事件流时，运行态以 status 帧为准；历史页没有 pending 不代表群任务已经结束。
      if (this.streamStatus !== 'connected') {
        this.busy = loaded.some((item: Message) => item.pending === true);
      }
      this.refreshRoomProgressPoll();
      if (page.messages.length > 0) {
        const latest = page.messages[page.messages.length - 1];
        if (Number.isSafeInteger(latest.seq) && latest.seq >= 0) {
          try {
            await api.markRead(conversationId, latest.seq);
          } catch (_error) {}
        }
      }
      void this.persistMessages(conversationId);
      this.scrollToBottom(40);
    } catch (error) {
      this.online = false;
      this.refreshRoomProgressPoll();
      this.error = (error as Error).message;
    }
  }

  /** 用主机游标向前翻页；合并后不滚到底，用户会停留在历史区域继续阅读。 */
  private async loadEarlierMessages(): Promise<void> {
    const api = this.apiClient;
    const conversationId = this.selectedId;
    const cursor = this.historyCursor;
    if (api === undefined || conversationId.length === 0 || cursor.length === 0 || this.loadingEarlier || !this.online) return;
    this.loadingEarlier = true;
    try {
      const page = await api.messages(conversationId, cursor, 90);
      if (this.selectedId !== conversationId || this.historyCursor !== cursor) return;
      this.messages = mergeMessages(this.messages, page.messages);
      this.historyCursor = page.cursor ?? '';
      this.hasEarlier = this.historyCursor.length > 0;
      void this.persistMessages(conversationId);
    } catch (error) {
      if (this.selectedId === conversationId) this.error = `加载更早消息失败：${(error as Error).message}`;
    } finally {
      if (this.selectedId === conversationId) this.loadingEarlier = false;
    }
  }

  /**
   * 发送消息。
   *
   * 与旧实现的关键差别：
   * - **删除 30×1200ms 轮询循环**：回复由事件流推送（`handleStreamEvent`）；
   * - `requestId` 先生成一次并在重试中保持不变，提交后用 `/submissions/{requestId}` 查询回执，
   *   避免「结果未知却重新发送」造成重复提问；
   * - 失败时把草稿还原并要求用户手动重发（不静默重试）。
   */
  private async send(): Promise<void> {
    const api = this.apiClient;
    const text = this.draft.trim();
    if (api === undefined || text.length === 0 || this.selectedId.length === 0 || this.busy) return;
    const conversationId = this.selectedId;
    this.busy = true;
    this.refreshRoomProgressPoll();
    this.error = '';
    this.draft = '';
    const requestId = `harmony-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
    const optimistic: Message = {
      id: `local-${requestId}`,
      sessionId: '',
      seq: Number.MAX_SAFE_INTEGER,
      role: 'user',
      text: text,
      createdAt: Date.now(),
      pending: true,
      requestId: requestId
    };
    this.messages = mergeMessages(this.messages, [optimistic]);
    this.scrollToBottom(30);
    try {
      const target: RawTarget = await api.target(conversationId);
      const submission: SubmissionRequest = {
        conversationId: target.conversationId,
        sessionId: target.sessionId,
        requestId: requestId,
        text: text
      };
      try {
        await api.submit(submission);
      } catch (error) {
        // 提交失败可能是「结果未知」：先查回执再决定是否报错。
        const failure = error as Error;
        const receipt = await api.submission(requestId);
        if (receipt.status !== 'accepted' && receipt.status !== 'pending') throw failure;
      }
      await this.cacheDraft(conversationId, '');
      this.busy = false;
      this.refreshRoomProgressPoll();
      this.scrollToBottom(30);
      // 立刻拉一次真实消息，把本地乐观气泡换成主机版本（含真实 seq 与 userName）。
      // 事件流不可用时这一步也保证消息顺序正确。
      setTimeout((): void => {
        if (this.selectedId === conversationId) void this.loadMessages();
      }, 800);
    } catch (error) {
      this.messages = this.messages.filter((item: Message) => item.id !== optimistic.id);
      this.draft = text;
      this.busy = false;
      this.refreshRoomProgressPoll();
      this.error = `发送失败：${(error as Error).message}`;
    }
  }

  /**
   * 停止生成。只请求主机取消，执行状态随后由 `status` 帧回落，
   * 不再手动清 `busy`（旧实现清掉 busy 后轮询循环仍在写 messages，见缺陷 B1）。
   */
  private async stop(): Promise<void> {
    if (this.apiClient === undefined || this.selectedId.length === 0) return;
    try {
      await this.apiClient.cancel(this.selectedId);
    } catch (error) {
      this.error = (error as Error).message;
    }
  }

  private async createBot(): Promise<void> {
    const name = this.newBotName.trim();
    if (this.apiClient === undefined || name.length === 0 || this.busy) return;
    this.busy = true;
    try {
      const avatar: Avatar = { shape: this.newBotShape };
      const payload: CreateBotPayload = {
        name: name,
        role: '',
        instructions: '',
        color: this.newBotColor,
        avatar: avatar
      };
      if (this.team.models.length > 0) payload.model = this.team.models[0].ref;
      const bot = await this.apiClient.action<Bot>('create-bot', payload);
      this.newBotName = '';
      await this.refreshAll();
      const found = this.conversations.find((item: Conversation) => item.id === bot.id || item.id === `bot:${bot.id}`);
      if (found !== undefined) {
        this.mobileOverlay = '';
        this.section = 'chat';
        await this.selectConversation(found);
      }
    } catch (error) {
      this.error = (error as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private toggleMember(id: string): void {
    this.selectedMembers = this.selectedMembers.includes(id) ?
      this.selectedMembers.filter((value: string) => value !== id) : [...this.selectedMembers, id];
  }

  private async createGroup(): Promise<void> {
    const name = this.newGroupName.trim();
    if (this.apiClient === undefined || name.length === 0 || this.selectedMembers.length < 2 || this.busy) return;
    this.busy = true;
    try {
      const payload: CreateRoomPayload = {
        name: name,
        members: this.selectedMembers,
        admin: this.selectedMembers[0],
        greet: true
      };
      await this.apiClient.action<Room>('create-room', payload);
      this.newGroupName = '';
      this.selectedMembers = [];
      await this.refreshAll();
    } catch (error) {
      this.error = (error as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async loadAdminData(): Promise<void> {
    if (this.apiClient === undefined) return;
    try {
      const approvalResult: RawApprovalList = await this.apiClient.approvals();
      const deviceResult: RawDeviceList = await this.apiClient.devices();
      this.approvals = toApprovals(approvalResult);
      this.devices = toDeviceList(deviceResult);
    } catch (error) {
      this.error = (error as Error).message;
    }
  }

  /**
   * 单独刷新 `/state.questions`。
   * 问题不走消息 WebSocket；没有这一步，Bot 已在主机等待时手机端要到手动刷新后才看得到卡片。
   */
  private async loadQuestionState(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.selectedId.length === 0) return;
    try {
      const rawState: RawState = await api.state();
      this.team = toTeamState(rawState);
    } catch (error) {
      if (this.isAuthFailure(error)) void this.handleSessionLost('设备会话已失效，请重新与电脑配对。');
    }
  }

  private async resolveApproval(id: string, decision: string): Promise<void> {
    if (this.apiClient === undefined) return;
    try {
      const payload: ApprovalDecisionPayload = { id: id, decision: decision };
      await this.apiClient.action<object>('approval-resolve', payload);
      await this.loadAdminData();
    } catch (error) {
      this.error = (error as Error).message;
    }
  }

  private async setConversationFlag(item: Conversation, pinned?: boolean, hidden?: boolean): Promise<void> {
    if (this.apiClient === undefined || this.busy) return;
    this.busy = true;
    this.error = '';
    try {
      const payload: ConversationFlagPayload = { id: item.id };
      if (pinned !== undefined) payload.pinned = pinned;
      if (hidden !== undefined) payload.hidden = hidden;
      await this.apiClient.action<object>('set-flags', payload);
      if (hidden === true && !this.showHidden) {
        this.selectedId = '';
        this.messages = [];
      }
      await this.refreshAll();
    } catch (error) {
      this.error = (error as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async revokeDevice(device: DeviceListItem): Promise<void> {
    if (this.apiClient === undefined || this.busy) return;
    // 撤销设备是不可逆操作，用原生 `showDialog` 做确认，而不是「同一按钮点两次」。
    // 原生对话框自带标题/正文/按钮布局、焦点与返回键处理，比自造确认态更清楚。
    const confirmed = await this.confirmDestructive('移除设备', `将撤销「${device.name ?? device.deviceName ?? device.id}」的访问权限，该设备需要重新配对才能再次连接。`, '移除');
    if (!confirmed) return;
    this.busy = true;
    this.error = '';
    try {
      await this.apiClient.revokeDevice(device.id);
      await this.loadAdminData();
    } catch (error) {
      this.error = (error as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async logout(): Promise<void> {
    // 破坏性操作要先确认：登出会清空凭据并回到连接页，需要重新配对才能再用。
    // 之前这里没有确认，误触一次就断连（2026-10-16 设备实测发现）。
    const confirmed = await this.confirmDestructive(
      '断开此设备', '将清除本机的会话凭据并返回连接页，需要重新配对才能再次连接。', '断开');
    if (!confirmed) return;
    this.stopRoomProgressPoll();
    this.stopApprovalPoll();
    this.stopFallbackPoll();
    this.stopStream();
    await ProfileStore.clear(this.context());
    this.apiClient = undefined;
    this.profile = undefined;
    this.paired = false;
    this.online = false;
    this.team = EMPTY_TEAM;
    this.conversations = [];
    this.messages = [];
    this.selectedId = '';
    this.section = 'chat';
  }

  private selectedConversation(): Conversation | undefined {
    return this.conversations.find((item: Conversation) => item.id === this.selectedId);
  }

  private filteredConversations(): Conversation[] {
    const query = this.searchText.trim().toLowerCase();
    const visible = this.conversations.filter((item: Conversation) => this.showHidden || !item.hidden);
    const matched = query.length === 0 ? visible : visible.filter((item: Conversation) =>
      `${item.name} ${item.role ?? ''}`.toLowerCase().includes(query));
    return matched.sort((left: Conversation, right: Conversation) =>
      left.pinned === right.pinned ? 0 : left.pinned ? -1 : 1);
  }

  private isMainConversation(item: Conversation): boolean {
    return isMainConversationIn(this.team, item);
  }

  private mainConversation(): Conversation | undefined {
    return this.conversations.find((item: Conversation) => this.isMainConversation(item));
  }

  private conversationTime(item: Conversation): string {
    // 只传所需字段：ArkTS 不支持结构类型，不能把 Conversation 当 TimestampedItem 传
    return conversationTimeOf(item.updatedAt);
  }

  /** 可选的形状清单（来自 rawfile 目录，20 种）。 */
  private avatarShapes(): string[] {
    const catalog = avatarShapeList();
    return catalog.length > 0 ? catalog : ['whale', 'star', 'moon', 'wave', 'squircle', 'zed', 'hex', 'gumdrop', 'peanut', 'saucer', 'bunny', 'kitty', 'beacon'];
  }

  /** 可选的颜色清单（来自 rawfile 目录，12 种，含 aurora）。 */
  private avatarColors(): string[] {
    const colors = avatarPalette();
    return colors.length > 0 ? colors : ['black', 'brown', 'red', 'orange', 'yellow', 'green', 'cyan', 'blue', 'violet', 'magenta', 'gray', 'aurora'];
  }

  /** 首页顶部展示的主 Bot（取第一个主 Bot）。 */
  private mainBotOf(): Bot | undefined {
    const ids = this.mainBotIds();
    if (ids.length > 0) {
      const found = this.team.bots.find((bot: Bot) => bot.id === ids[0]);
      if (found !== undefined) return found;
    }
    return this.team.bots.find((bot: Bot) => this.isMainConversation({
      id: bot.id,
      kind: 'bot',
      name: bot.name,
      sessionId: bot.sessionId ?? ''
    }));
  }

  /** 团队里的主 Bot id 列表（`mainBotIds` 优先，回退单个 `mainBotId`）。 */
  private mainBotIds(): string[] {
    return mainBotIdsOf(this.team);
  }

  /** 按 id 找 Bot（群聊作者标识用）。 */
  private botById(id?: string): Bot | undefined {
    if (id === undefined || id.length === 0) return undefined;
    return this.team.bots.find((bot: Bot) => bot.id === id);
  }

  /** 会话对应的 Bot（用于取头像形状与颜色）。 */
  private botOf(item: Conversation): Bot | undefined {
    return botOfIn(this.team, item);
  }

  private isMainBotId(id: string): boolean {
    return isMainBotIdOf(this.team, id);
  }

  /**
   * Bot 头像（矢量化，P1-1 集成）。
   * 颜色优先级：`avatar.color` → `bot.color` → 空（组件回退默认色）。
   */
  @Builder
  private botAvatar(bot: Bot | undefined, fallbackName: string, size: number, main: boolean, live: boolean) {
    // 组合逻辑已抽到 view/BotAvatar.ets（星标/活跃点只能有一处实现）
    BotAvatar({
      spec: {
        shape: bot?.avatar?.shape ?? '',
        color: bot?.avatar?.color ?? bot?.color ?? '',
        image: '',
        main: main,
        live: live
      } as AvatarSpec,
      avatarSize: size,
      dark: this.dark
    });
  }


  /** 群聊头像：最多 4 个成员头像叠放（对齐上游 RoomAvatar 的排布思路）。 */
  @Builder
  @Builder
  private roomAvatar(item: Conversation, size: number) {
    // 保留旧名以兼容既有调用点，实际渲染统一交给 ConversationAvatar
    ConversationAvatar({ item: item, team: this.team, avatarSize: size, dark: this.dark });
  }

  private roomMembers(item: Conversation): Bot[] {
    return roomMembersOf(this.team, item);
  }

  private roomMemberCount(item: Conversation): number {
    return memberSlotCount(this.team, item);
  }

  private roomMemberSize(item: Conversation, size: number): number {
    return memberSlotSize(this.team, item, size);
  }

  private roomMemberPosition(item: Conversation, index: number, size: number): Position {
    // 返回类型沿用 ArkUI 的 Position（字段同名，可直接赋值）
    const offset = memberSlotOffset(this.team, item, index, size);
    return { x: offset.x, y: offset.y };
  }

  /**
   * 会话头像分发。
   * 注意：`@Builder` 内不能写局部变量声明等普通语句，所以判断逻辑放在辅助方法里。
   */
  @Builder
  @Builder
  private conversationAvatar(item: Conversation, size: number = 50) {
    // 头像组合已抽到 view/ConversationAvatarView.ets（叠加算法在 logic/ConversationAvatar.ets）
    ConversationAvatar({ item: item, team: this.team, avatarSize: size, dark: this.dark });
  }

  /** 会话头像是否显示主 Bot 星标。 */
  private isMainAvatar(item: Conversation): boolean {
    return isMainAvatarIn(this.team, item);
  }

  @Builder
  private mobileHome() {
    Column() {
      Row({ space: 10 }) {
        Button() {
          Image($r('app.media.ic_settings')).width(23).height(23);
        }
        .width(48).height(48).borderRadius(24).backgroundColor(this.surface())
        .border({ width: 1, color: this.line() })
        .onClick(() => {
          this.section = 'settings';
          void this.loadAdminData();
        });
        Blank();
        Button() {
          Image($r('app.media.ic_search')).width(22).height(22);
        }
        .width(48).height(48).borderRadius(24).backgroundColor(this.surface())
        .border({ width: 1, color: this.line() })
        .onClick(() => {
          this.searching = !this.searching;
          if (!this.searching) this.searchText = '';
        });
        Button() {
          Image($r('app.media.ic_plus')).width(27).height(27);
        }
        .width(48).height(48).borderRadius(24).backgroundColor(this.surface())
        .border({ width: 1, color: this.line() })
        .onClick(() => this.mobileOverlay = 'create-bot');
      }.width('100%').height(72).padding({ left: 20, right: 20, top: 12, bottom: 12 });
      if (this.searching) {
        TextInput({ placeholder: '搜索会话', text: this.searchText })
          .height(50).margin({ left: 20, right: 20, bottom: 8 }).padding({ left: 18, right: 18 })
          .fontSize(17).fontColor(this.ink()).backgroundColor(this.dark ? '#202022' : '#F1F1F1')
          .borderRadius(25).onChange((value: string) => this.searchText = value);
      }
      Scroll() {
        Column() {
          if (!this.searching && this.mainConversation() !== undefined) {
            Column({ space: 10 }) {
              this.botAvatar(this.mainBotOf(), this.mainConversation()?.name ?? 'Chief', 100,
                this.mainBotOf() !== undefined && this.isMainBotId(this.mainBotOf()!.id), false);
              Text(this.mainConversation()?.name ?? 'Chief').fontSize(16).fontColor(this.muted());
            }
            .width('100%').padding({ top: 4, bottom: 22 })
            .onClick(() => {
              const item = this.mainConversation();
              if (item !== undefined) void this.selectConversation(item);
            })
            // 长按首页主 Bot 头像打开诊断页；页内可切换「事件流诊断 / 头像诊断」。
            .gesture(LongPressGesture().onAction(() => this.showProbe = true));
          }
          ForEach(this.filteredConversations(), (item: Conversation) => {
            Row({ space: 18 }) {
              this.conversationAvatar(item, 50);
              Column({ space: 5 }) {
                Text(item.name).fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.ink())
                  .maxLines(1).width('100%');
                Text(this.conversationPreviews[item.id] ?? item.role ?? (item.kind === 'room' ? '群聊' : 'Bot'))
                  .fontSize(16).fontColor(this.muted()).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);
              Column() {
                Text(this.conversationTime(item)).fontSize(13).fontColor(this.muted());
                Blank();
                if (item.waiting !== undefined && item.waiting.length > 0) {
                  Circle({ width: 10, height: 10 }).fill('#4D6BFE');
                }
              }.height(52).alignItems(HorizontalAlign.End);
            }
            .width('100%').height(92).padding({ left: 8, right: 8 })
            .onClick(() => void this.selectConversation(item));
          }, (item: Conversation) => item.id);
          if (this.filteredConversations().length === 0) {
            Text('没有找到会话').fontSize(16).fontColor(this.muted())
              .width('100%').padding(32).textAlign(TextAlign.Center);
          }
        }
        .width('100%').constraintSize({ minHeight: '100%' }).justifyContent(FlexAlign.Start)
        .padding({ left: 16, right: 16, bottom: 24 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(this.dark ? '#121212' : '#FFFFFF');
  }

  @Builder
  private appMark(size: number = 42) {
    Stack() {
      Rect().width(size).height(size).radius(size * 0.3).fill('#665CF6');
      Text('✦').fontSize(size * 0.52).fontColor('#FFFFFF').fontWeight(FontWeight.Bold);
    }.width(size).height(size);
  }

  @Builder


  @Builder
  private pairingPage() {
    Scroll() {
      Column({ space: 16 }) {
        this.appMark(76);
        Text('DS Bot').fontSize(32).fontWeight(FontWeight.Bold).fontColor(this.ink());
        Text('把你的 Bot 团队带到鸿蒙设备上')
          .fontSize(16).fontColor(this.muted()).textAlign(TextAlign.Center);
        Column({ space: 14 }) {
          Text('连接主机').fontSize(21).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%');
          Text('在电脑端打开 DS Bot 设置 → 移动设备，启用手机连接，然后粘贴完整配对 JSON 并在电脑端批准。')
            .fontSize(14).lineHeight(21).fontColor(this.muted());
          TextArea({ placeholder: '{"url":"https://…","code":"…","serverId":"…"}', text: this.pairingJson })
            .height(120).fontSize(14).fontColor(this.ink()).backgroundColor(this.pageBg())
            .borderRadius(14).padding(12).onChange((value: string) => this.pairingJson = value);
          TextInput({ placeholder: '设备名称', text: this.deviceName })
            .height(48).fontSize(15).fontColor(this.ink()).backgroundColor(this.pageBg())
            .borderRadius(14).padding({ left: 14, right: 14 })
            .onChange((value: string) => this.deviceName = value);
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor('#D94343').width('100%');
          }
          Button(this.busy ? '等待电脑批准…' : '连接我的主机')
            .width('100%').height(50).borderRadius(25).backgroundColor('#665CF6')
            .fontSize(17).enabled(!this.busy && this.pairingJson.trim().length > 0 && this.deviceName.trim().length > 0)
            .onClick(() => void this.pair());
        }
        .width('100%').constraintSize({ maxWidth: 560 }).padding(22)
        .backgroundColor(this.surface()).borderRadius(24);
        Text('连接信息和会话凭据仅保存在本机应用沙箱中。')
          .fontSize(12).fontColor(this.muted()).textAlign(TextAlign.Center);
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
      .padding({ left: 20, right: 20, top: 40, bottom: 40 });
    }.width('100%').height('100%');
  }

  /** 宽屏左栏的配色与数据（抽到 view/DesktopSidebar.ets）。 */
  private sidebarTheme(): SidebarTheme {
    return {
      surface: this.surface(), ink: this.ink(), muted: this.muted(), line: this.line(),
      pageBg: this.pageBg(),
      selectedBg: this.dark ? '#2B2946' : '#EFEDFF',
      chipBg: this.dark ? '#252833' : '#F0F2F7',
      brand: '#665CF6', waitingDot: '#F29D49', online: this.online
    };
  }

  /** 会话行视图模型：父组件算好，组件只渲染。 */
  private conversationEntries(): ConversationEntry[] {
    const entries: ConversationEntry[] = [];
    for (const item of this.filteredConversations()) {
      const entry: ConversationEntry = {
        id: item.id,
        conversation: item,
        name: item.name,
        preview: this.conversationPreviews[item.id] ?? item.role ?? (item.kind === 'room' ? '群聊' : 'Bot'),
        pinned: item.pinned === true,
        hidden: item.hidden === true,
        waiting: item.waiting !== undefined && item.waiting.length > 0,
        selected: this.selectedId === item.id
      };
      entries.push(entry);
    }
    return entries;
  }

  @Builder
  private statusPill() {
    Row({ space: 6 }) {
      Circle({ width: 8, height: 8 }).fill(this.online ? '#24B47E' : '#A4A9BB');
      Text(this.online ? '已连接' : '离线').fontSize(12).fontColor(this.muted());
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(this.dark ? '#242732' : '#F0F2F7')
    .borderRadius(16);
  }

  /** 宽屏右侧内容区（聊天 / 团队 / 设置）。 */
  @Builder
  private desktopPane() {
    Column() {
      if (this.section === 'chat') {
        this.chatPanel();
      } else if (this.section === 'team') {
        this.teamPage();
      } else {
        this.settingsPage();
      }
    }.width('100%').height('100%');
  }

  @Builder
  private desktopSidebar() {
    DesktopSidebar({
      tokens: this.sidebarTheme(),
      // 宽度由 SideBarContainer 决定（用户可拖拽），这里传入避免子组件再算一次
      forcedWidth: this.sideBarWidth,
      windowWidth: this.windowWidth,
      section: this.section,
      railItems: [
        {
          icon: $r('app.media.ic_nav_chat'), selectedIcon: $r('app.media.ic_nav_chat_selected'),
          label: '对话', section: 'chat'
        },
        {
          icon: $r('app.media.ic_nav_team'), selectedIcon: $r('app.media.ic_nav_team_selected'),
          label: '团队', section: 'team'
        },
        {
          icon: $r('app.media.ic_nav_settings'), selectedIcon: $r('app.media.ic_nav_settings_selected'),
          label: '设置', section: 'settings'
        }
      ] as RailItem[],
      serverName: this.serverName,
      entries: this.conversationEntries(),
      team: this.team,
      searchText: this.searchText,
      showHidden: this.showHidden,
      onSelectSection: (target: string): void => {
        this.section = target as AppSection;
        if (target === 'settings') void this.loadAdminData();
      },
      onRefresh: (): void => void this.refreshAll(),
      onSearch: (value: string): void => { this.searchText = value; },
      onToggleHidden: (value: boolean): void => { this.showHidden = value; },
      onSelectConversation: (item: Conversation): void => void this.selectConversation(item)
    });
  }



  @Builder


  @Builder


  @Builder
  private messageBubble(message: Message) {
    // 对齐用 Row 的 justifyContent，**不要用 `Blank()`**：
    // Blank 会贪婪占位，与气泡的 `constraintSize({ maxWidth })` 叠加后
    // 总数超过行宽，用户气泡会被推到屏幕右边缘（2026-07-16 实测 bounds 右边界 = 屏宽）。
    Row() {
      Column({ space: 6 }) {
        // 作者标识：群聊里每条回复显示是谁在说话（P1-7）；单聊沿用「你 / Bot」。
        if (message.role === 'assistant' && message.author !== undefined &&
          message.author.name !== undefined && message.author.name.length > 0) {
          Row({ space: 6 }) {
            BotAvatarView({
              shape: this.botById(message.author.id)?.avatar?.shape ?? '',
              color: this.botById(message.author.id)?.avatar?.color ?? this.botById(message.author.id)?.color ?? '',
              avatarSize: 18,
              image: ''
            });
            Text(message.author.name)
              .fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.muted()).maxLines(1);
          }.alignItems(VerticalAlign.Center)
        } else if (this.windowWidth >= 600) {
          Text(message.role === 'user' ? '你' : message.role === 'assistant' ? 'Bot' : message.role)
            .fontSize(11).fontColor(message.role === 'user' ? '#5B6B99' : this.muted());
        }
        if (message.reasoning !== undefined && message.reasoning.length > 0) {
          this.reasoningBlock(message);
        }
        if (message.tool !== undefined) {
          this.toolCard(message.tool);
        } else if (message.text.length > 0) {
          MarkdownView({
            text: message.text,
            theme: {
              ink: this.ink(),
              muted: this.muted(),
              surface: this.surface(),
              line: this.line(),
              code: this.dark ? '#242732' : '#F0F2F7',
              link: this.dark ? '#8FA8FF' : '#3A5BD9'
            },
            fontSize: this.windowWidth < 600 ? 16 : 15,
            ownBubble: message.role === 'user',
            maxContentWidth: this.bubbleContentWidth()
          });
        }
        if (message.pending) {
          Text(message.role === 'user' ? '发送中…' : '正在输出…')
            .fontSize(11).fontColor(message.role === 'user' ? '#5B6B99' : this.muted());
        }
      }
      .alignItems(HorizontalAlign.Start)
      // 气泡宽度必须用**显式 vp 数值**：`constraintSize({ maxWidth: '90%' })` 在嵌套
      // Row → Blank → Column 里百分比会相对内容而非父容器解析，长文本会溢出气泡边界
      // （2026-10-16 用户报告 + 截图确认）。留出两侧 padding(16*2) 与气泡内边距。
      .constraintSize({ maxWidth: this.bubbleMaxWidth() })
      .padding({
        left: this.bubblePadding(), right: this.bubblePadding(),
        top: this.windowWidth < 600 ? 13 : 13, bottom: this.windowWidth < 600 ? 13 : 13
      })
      .borderRadius(this.windowWidth < 600 ? 26 : 17)
      .backgroundColor(this.windowWidth < 600 ?
        (this.dark ? '#333333' : message.role === 'user' ? '#EDF3FF' : '#F0F0F0') :
        message.role === 'user' ? '#665CF6' : this.surface())
      .gesture(LongPressGesture().onAction(() => this.openMessageActions(message)));
    }
    .width('100%')
    .justifyContent(message.role === 'user' ? FlexAlign.End : FlexAlign.Start)
    .padding({ left: 16, right: 16, top: this.windowWidth < 600 ? 8 : 6, bottom: this.windowWidth < 600 ? 8 : 6 });
  }

  /**
   * 思考过程：默认折叠成一行，点一下展开。
   * 旧实现是固定 maxLines 截断，长推理看不到全文（P1-4）。
   */
  @Builder
  private reasoningBlock(message: Message) {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(this.expandedReasoning.includes(message.id) ? '⌃ 思考过程' : '⌄ 思考过程')
          .fontSize(12).fontColor(this.muted());
        if (message.pending === true) {
          Text('进行中').fontSize(11).fontColor('#C77A28');
        }
        Blank();
      }
      .width('100%')
      .onClick(() => this.toggleReasoning(message.id))
      if (this.expandedReasoning.includes(message.id)) {
        Text(message.reasoning ?? '')
          .fontSize(this.windowWidth < 600 ? 14 : 12)
          .lineHeight(this.windowWidth < 600 ? 21 : 18)
          .fontColor(this.muted())
          .padding(this.windowWidth < 600 ? 0 : { left: 10 })
          .border(this.windowWidth < 600 ? { width: 0 } : { width: { left: 2 }, color: '#9D96FF' })
          .copyOption(CopyOptions.LocalDevice)
          .width('100%')
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }

  private toggleReasoning(id: string): void {
    this.expandedReasoning = this.expandedReasoning.includes(id) ?
      this.expandedReasoning.filter((value: string) => value !== id) : [...this.expandedReasoning, id];
  }

  private conversationQuestions(): ConversationQuestion[] {
    return questionsForConversation(this.team, this.selectedConversation());
  }

  private questionKey(entry: ConversationQuestion): string {
    return questionKeyOf(entry.sessionId, entry.question.id);
  }

  private async submitQuestion(entry: ConversationQuestion, selected: string[], custom: string, dismiss: boolean): Promise<void> {
    const api = this.apiClient;
    const key = this.questionKey(entry);
    if (api === undefined || this.questionBusyKey.length > 0 || this.team.readOnly !== undefined || !this.online) return;
    this.questionBusyKey = key;
    this.questionErrorKey = '';
    this.questionError = '';
    try {
      if (dismiss) {
        const payload: DismissQuestionPayload = { sessionId: entry.sessionId };
        await api.action<object>('dismiss-question', payload);
      } else {
        const answer: QuestionAnswer = { selected: selected };
        // 自定义回答由卡片传入，不再从父组件的草稿 map 里取
        if (entry.question.allowCustom === true && custom.trim().length > 0) {
          answer.custom = custom.trim();
        }
        const payload: AnswerQuestionPayload = {
          sessionId: entry.sessionId,
          questionId: entry.question.id,
          answer: answer
        };
        await api.action<object>('answer-question', payload);
      }
      await this.refreshAll();
    } catch (error) {
      this.questionErrorKey = key;
      this.questionError = (error as Error).message;
    } finally {
      this.questionBusyKey = '';
    }
  }

  @Builder
  private earlierMessagesButton() {
    if (this.historyInitialized && this.hasEarlier) {
      Row() {
        Button(this.loadingEarlier ? '正在加载更早消息…' : '加载更早消息')
          .height(40).borderRadius(20).fontSize(13)
          .backgroundColor(this.surface()).fontColor(this.muted())
          .border({ width: 1, color: this.line() })
          .enabled(!this.loadingEarlier && this.online)
          .onClick(() => void this.loadEarlierMessages());
      }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 10, bottom: 4 });
    }
  }

  /**
   * 群聊执行进度：ArkUI 横向 Scroll 承载成员状态胶囊，避免窄屏挤压输入区。
   * 「停止」直接使用原生 Button，并只对有主机 work 证据的成员显示。
   */
  @Builder
  private groupProgress() {
    if (this.selectedRoom() !== undefined && this.online &&
      (this.roomProgressMemberIds().length > 0 || this.roomProgressUnavailable || this.roomProgressError.length > 0)) {
      // 数据在父组件算好，组件只渲染（见 view/GroupProgressBar.ets 的设计说明）
      GroupProgressBar({
        chips: this.roomProgressChips(),
        tokens: {
          ink: this.ink(), muted: this.muted(), surface: this.surface(), line: this.line(),
          danger: '#C93C3C',
          dangerBg: this.dark ? '#3B2930' : '#FDECEC',
          activeBg: this.dark ? '#252D47' : '#F0F4FF',
          brand: '#4D6BFE'
        },
        errorText: this.roomProgressError,
        unavailable: this.roomProgressUnavailable,
        onStop: (botId: string): void => {
          const room = this.selectedRoom();
          if (room !== undefined) void this.stopMemberWork(room.id, botId);
        }
      });
    }
  }

  /** 把群进度所需的显示数据算成视图模型（组件不再接触业务状态）。 */
  private roomProgressChips(): MemberChip[] {
    const room = this.selectedRoom();
    const chips: MemberChip[] = [];
    if (room === undefined) return chips;
    for (const botId of this.roomProgressMemberIds()) {
      const bot = this.botById(botId);
      if (bot === undefined) continue;
      const progress = this.progressOf(room, botId);
      chips.push({
        botId: botId,
        name: bot.name ?? botId,
        avatar: {
          shape: bot.avatar?.shape ?? '',
          color: bot.avatar?.color ?? bot.color ?? '',
          image: '',
          main: this.isMainBotId(botId),
          live: progress.speaking
        },
        status: progress.status,
        failed: progress.failed,
        working: progress.working,
        speaking: progress.speaking,
        stopping: this.stoppingMemberId === botId,
        canStop: this.stoppingMemberId.length === 0 && this.team.readOnly === undefined
      });
    }
    return chips;
  }


  /** 聊天内提问卡：Radio/Checkbox/TextArea 均使用 ArkUI 原生组件。 */
  @Builder
  private chatQuestions() {
    // 卡片本体与草稿状态已移到 view/QuestionCard.ets（每张卡自己持草稿）
    Column({ space: 10 }) {
      ForEach(this.conversationQuestions(), (entry: ConversationQuestion) => {
        QuestionCard({
          entry: entry,
          tokens: {
            ink: this.ink(), muted: this.muted(),
            cardBg: this.dark ? '#202839' : '#F4F7FF',
            cardLine: this.dark ? '#33415C' : '#D9E2FF',
            fieldBg: this.surface(), line: this.line(),
            brand: '#4D6BFE', danger: '#C93C3C'
          },
          busy: this.questionBusyKey.length > 0,
          readOnly: this.team.readOnly !== undefined,
          submitting: this.questionBusyKey === this.questionKey(entry),
          errorText: this.questionErrorKey === this.questionKey(entry) ? this.questionError : '',
          onSubmit: (selected: string[], custom: string, dismiss: boolean): void =>
            void this.submitQuestion(entry, selected, custom, dismiss)
        });
      }, (entry: ConversationQuestion) => this.questionKey(entry));
    }.width('100%').padding({ left: 12, right: 12, top: 8 });
  }


  /**
   * 聊天内审批卡（P1-6）。
   *
   * 主机在执行需要授权的工具操作时会挂起并等待批准；旧实现只在设置页显示这些请求，
   * 用户在聊天里既看不到也处理不了。这里把「本会话相关的待批准操作」直接贴在消息流上方。
   */
  @Builder
  private chatApprovals() {
    // 卡片本体已抽到 view/ChatApprovals.ets；决定通过回调交回，组件不接触 API
    ChatApprovals({
      items: this.conversationApprovals(),
      tokens: this.dark ? DARK_NOTICE_THEME : LIGHT_NOTICE_THEME,
      disabled: this.busy,
      onResolve: (approvalId: string, decision: string): void =>
        void this.resolveApproval(approvalId, decision)
    });
  }


  /**
   * 移除一条排队中的消息（`queue-remove`）。
   *
   * 主机在上一轮还在跑的时候会把新消息排进队列；用户需要能撤掉它。
   * 需要 `sessionId`，取自会话当前的 target。
   */
  private async removeQueued(item: QueueItem): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.selectedId.length === 0) return;
    try {
      const target = await api.target(this.selectedId);
      await api.action<object>('queue-remove', new QueueRemoveRequest(this.selectedId, target.sessionId, item.id));
      this.queue = this.queue.filter((value: QueueItem) => value.id !== item.id);
      this.toast('已移除排队消息');
    } catch (error) {
      this.error = `移除失败：${(error as Error).message}`;
    }
  }

  /** 排队消息卡片（贴在输入栏上方）。 */
  @Builder
  private queuePanel() {
    // 面板本体已抽到 view/QueuePanel.ets（展开状态内聚在组件内）
    QueuePanel({
      items: this.queue,
      tokens: {
        ink: this.ink(), muted: this.muted(), warning: '#C77A28',
        itemBg: this.dark ? '#26231A' : '#FFFBF3',
        itemLine: this.dark ? '#3A2E18' : '#F3E2C7',
        dangerBg: this.dark ? '#3A2226' : '#FDECEC',
        danger: '#C93C3C'
      },
      initiallyExpanded: this.showQueue,
      onRemove: (item: QueueItem): void => void this.removeQueued(item)
    });
  }


  /** 只显示属于当前会话的待批准操作（没有会话时显示全部）。 */
  private conversationApprovals(): Approval[] {
    const conversationId = this.selectedId;
    const sessionId = this.selectedConversation()?.sessionId ?? '';
    if (conversationId.length === 0 && sessionId.length === 0) return this.approvals;
    return this.approvals.filter((item: Approval) =>
      item.conversationId === conversationId || (sessionId.length > 0 && item.sessionId === sessionId));
  }

  /** 长按消息：复制 / 引用 / 查看思考过程。 */
  private openMessageActions(message: Message): void {
    const actions: MessageAction[] = [];
    actions.push({ label: '复制消息', run: () => this.copyToClipboard(message.text, '消息已复制') });
    if (message.reasoning !== undefined && message.reasoning.length > 0) {
      actions.push({ label: '复制思考过程', run: () => this.copyToClipboard(message.reasoning ?? '', '思考过程已复制') });
    }
    if (message.text.length > 0) {
      actions.push({ label: '引用到输入框', run: () => this.quoteIntoDraft(message.text) });
    }
    this.messageActions = actions;
    this.actionTargetId = message.id;
    this.messageActionsVisible = actions.length > 0;
  }

  private copyToClipboard(value: string, toast: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.toast(toast);
    } catch (_error) {
      this.toast('复制失败');
    }
  }

  /** 把消息引用进输入框（上游的「引用」是对整条消息做 Markdown 引用）。 */
  private quoteIntoDraft(text: string): void {
    const quoted = text.split('\n').map((line: string) => `> ${line}`).join('\n');
    const parts = referenceDraft(this.draft);
    const body = parts.text.length > 0 ? `${quoted}\n\n${parts.text}` : `${quoted}\n\n`;
    this.draft = composeReferenceDraft(body, parts.references);
    void this.cacheDraft(this.selectedId, this.draft);
    this.toast('已引用到输入框');
  }

  /**
   * 消息操作面板的薄封装：把 Index 的状态与回调接到抽出的 `MessageActionSheet` 上。
   * 面板本体已移到 `view/MessageActionSheet.ets`。
   */
  @Builder
  private messageSheetBuilder() {
    MessageActionSheet({
      actions: this.messageActions,
      tokens: this.tokens(),
      onClose: (): void => this.closeMessageActions(),
      onAction: (action: MessageAction): void => {
        const run = action.run;
        this.closeMessageActions();
        run();
      }
    })
  }

  /**
   * 消息气泡最大宽度（vp）。
   * 宽屏上限 720vp（与上游一致），窄屏用「窗口宽 - 两侧留白 - 气泡内边距」，
   * 且至少 160vp，避免极窄窗口下算出非正值。
   */
  /** 气泡水平内边距（vp），窄屏与宽屏不同。**宽度计算的唯一来源**。 */
  private bubblePadding(): number {
    return this.windowWidth < 600 ? 18 : 13;
  }

  /**
   * 气泡最大宽度（vp）。
   *
   * 口径只在这里定义一次：`窗口宽 - 消息行两侧 padding(16*2) - 气泡两侧内边距`。
   * 之前 `bubbleMaxWidth()` 与 `bubbleContentWidth()` 各自扣一次内边距，
   * 两处算法分叉导致文字顶到卡片边缘（2026-10-16 反复出现）。
   */
  private bubbleMaxWidth(): number {
    if (this.windowWidth >= 840) return 720;
    const available = this.windowWidth - 16 * 2 - this.bubblePadding() * 2;
    return available > 160 ? available : 160;
  }

  /**
   * 气泡**内容区**宽度（vp）= 气泡最大宽度 − 两侧内边距。
   *
   * Markdown 内容（根容器、行内 Text、列表、代码块/表格 Scroll）都用它作为确定宽度：
   * 用 `width('100%')` 时，在「只有 constraintSize(maxWidth)」的父容器里会按内容解析，
   * 长文本会把容器算成内容宽并越出气泡。
   */
  private bubbleContentWidth(): number {
    const width = this.bubbleMaxWidth() - this.bubblePadding() * 2;
    return width > 120 ? width : 120;
  }

  /** 当前深浅色对应的语义令牌（视图拆分后与子组件共用同一来源）。 */
  private tokens(): ThemeTokens {
    return themeOf(this.dark);
  }

  /** 关闭消息操作面板（同时清掉待执行动作，避免残留）。 */
  private closeMessageActions(): void {
    this.messageActions = [];
    this.actionTargetId = '';
    this.messageActionsVisible = false;
  }

  /**
   * 破坏性操作的确认框（原生 `showDialog`）。
   * 返回 true 表示用户确认。
   */
  private async confirmDestructive(title: string, message: string, confirmText: string): Promise<boolean> {
    try {
      const result = await this.getUIContext().getPromptAction().showDialog({
        title: title,
        message: message,
        buttons: [
          { text: '取消', color: '#6F758B' },
          { text: confirmText, color: '#C93C3C' }
        ]
      });
      return result.index === 1;
    } catch (_error) {
      return false;
    }
  }

  private toast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1600 });
  }

  @Builder
  private toolCard(tool: ToolActivity) {
    // 卡片本体与展开状态已移到 view/ToolCard.ets
    ToolCard({
      tool: tool,
      tokens: {
        ink: this.ink(), muted: this.muted(),
        cardBg: this.pageBg(), line: this.line(),
        link: this.dark ? '#8FA8FF' : '#3A5BD9'
      },
      onCopy: (text: string, toast: string): void => this.copyToClipboard(text, toast),
      // 必须传确定宽度：否则卡片按气泡全宽排版并越出气泡内边界
      maxWidth: this.bubbleContentWidth()
    });
  }






  /** @ 候选直接贴在输入框上方，使用原生列表语义并保留输入焦点/光标位置。 */
  @Builder
  private mentionMenu() {
    if (this.composerMentionRows().length > 0) {
      Column() {
        Row() {
          Text('提及 Bot').fontSize(12).fontColor(this.muted()).layoutWeight(1);
          Text('输入名称筛选').fontSize(11).fontColor(this.muted());
        }.width('100%').padding({ left: 14, right: 14, top: 9, bottom: 5 });
        ForEach(this.composerMentionRows(), (candidate: MentionCandidate) => {
          Row({ space: 10 }) {
            if (candidate.bot !== undefined) {
              this.botAvatar(candidate.bot, candidate.name, 30, this.isMainBotId(candidate.bot.id), false);
            } else {
              Stack() {
                Circle({ width: 30, height: 30 }).fill('#E8EDFF');
                Text('@').fontSize(16).fontWeight(FontWeight.Bold).fontColor('#4D6BFE');
              }.width(30).height(30);
            }
            Text(candidate.name).fontSize(15).fontColor(this.ink()).layoutWeight(1).maxLines(1);
          }
          .width('100%').height(48).padding({ left: 14, right: 14 })
          .onClick(() => this.pickMention(candidate.name));
        }, (candidate: MentionCandidate) => `mention:${candidate.bot?.id ?? 'all'}:${candidate.name}`);
      }
      .width('100%').constraintSize({ maxHeight: 280 })
      .backgroundColor(this.surface()).borderRadius(16)
      .border({ width: 1, color: this.line() })
      .shadow({ radius: 10, color: '#18000000' });
    }
  }

  /** 引用芯片与原生 Select 思考档位，两套宽度布局共同复用。 */
  @Builder
  private composerAccessories() {
    if (this.composerReferences().length > 0 || this.effortOptions.length > 0 || this.effortLoading) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        ForEach(this.composerReferences(), (reference: ChatReference) => {
          Row({ space: 6 }) {
            Text('◫').fontSize(14).fontColor('#4D6BFE');
            Text(reference.label).fontSize(13).fontColor(this.ink()).maxLines(1)
              .constraintSize({ maxWidth: 180 });
            Button('×').width(30).height(30).borderRadius(15).fontSize(16)
              .backgroundColor(Color.Transparent).fontColor(this.muted())
              .enabled(!this.busy)
              .onClick(() => this.removeReference(reference.sessionId));
          }
          .height(36).padding({ left: 12, right: 4 }).margin({ right: 8, bottom: 6 })
          .backgroundColor(this.surface()).borderRadius(18)
          .border({ width: 1, color: this.line() });
        }, (reference: ChatReference) => `reference:${reference.sessionId}`);
        if (this.effortLoading) {
          Row({ space: 6 }) {
            LoadingProgress().width(16).height(16).color('#4D6BFE');
            Text('读取思考档位…').fontSize(12).fontColor(this.muted());
          }.height(36).margin({ right: 8, bottom: 6 });
        } else if (this.effortOptions.length > 0) {
          Select(this.effortSelectOptions())
            .selected(this.effortSelectedIndex())
            .value(this.effortSelectOptions()[this.effortSelectedIndex()].value)
            .height(36).margin({ right: 8, bottom: 6 })
            .font({ size: 13 }).fontColor(this.ink())
            .selectedOptionBgColor(this.dark ? '#2B2E39' : '#E8EDFF')
            .onSelect((index: number, _value: string) => void this.setEffort(index));
        }
      }.width('100%').padding({ left: 2, right: 2 });
    }
  }

  /** ArkUI 原生 Sheet：手机为底部抽屉，平板/折叠屏/PC 自动采用大屏样式。 */
  @Builder
  private referencePickerSheet() {
    Column({ space: 12 }) {
      Text('引用会话').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.ink()).width('100%');
      Text('所选会话会作为只读上下文随下一条消息发送，最多可选 3 个。')
        .fontSize(13).fontColor(this.muted()).width('100%');
      Search({ placeholder: '搜索会话', value: this.referenceQuery })
        .width('100%').height(48).backgroundColor(this.pageBg()).borderRadius(16)
        .onChange((value: string) => this.referenceQuery = value);
      if (this.referenceLoading) {
        Row({ space: 10 }) {
          LoadingProgress().width(22).height(22).color('#4D6BFE');
          Text('正在读取可引用会话…').fontSize(14).fontColor(this.muted());
        }.width('100%').padding(16);
      } else if (!this.referenceAvailable) {
        Text('当前主机不支持会话引用，请先更新电脑端 DSH。')
          .fontSize(14).fontColor(this.muted()).width('100%').padding(16);
      } else {
        Scroll() {
          Column() {
            ForEach(this.filteredReferenceChats(), (chat: ReferenceChat) => {
              Row({ space: 12 }) {
                if (chat.botId !== undefined && this.botById(chat.botId) !== undefined) {
                  this.botAvatar(this.botById(chat.botId), chat.label, 36, this.isMainBotId(chat.botId), false);
                } else {
                  Stack() {
                    Circle({ width: 36, height: 36 }).fill(this.dark ? '#2B2E39' : '#EEF0F6');
                    Text('◫').fontSize(17).fontColor(this.muted());
                  }.width(36).height(36);
                }
                Column({ space: 2 }) {
                  Text(chat.label).fontSize(16).fontColor(this.ink()).maxLines(1).width('100%');
                  Text(chat.kind === 'bot' ? 'Bot 会话' : '最近会话').fontSize(11).fontColor(this.muted()).width('100%');
                }.layoutWeight(1).alignItems(HorizontalAlign.Start);
                Text('添加').fontSize(13).fontColor('#4D6BFE');
              }
              .width('100%').height(62).padding({ left: 8, right: 8 })
              .onClick(() => this.pickReference(chat));
              Divider().color(this.line()).margin({ left: 56 });
            }, (chat: ReferenceChat) => `ref-chat:${chat.sessionId}`);
            if (this.filteredReferenceChats().length === 0) {
              Text('没有找到会话').fontSize(14).fontColor(this.muted())
                .width('100%').padding(24).textAlign(TextAlign.Center);
            }
          }.width('100%');
        }.layoutWeight(1).width('100%').scrollBar(BarState.Auto);
      }
    }
    .width('100%').height('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 16 })
    .backgroundColor(this.surface());
  }

  @Builder
  private chatPanel() {
    Column() {
      Row({ space: 12 }) {
        if (this.windowWidth < 600) {
          Button('‹').width(40).height(40).borderRadius(20).fontSize(26)
            .backgroundColor(this.pageBg()).fontColor(this.ink())
            .onClick(() => {
              this.stopRoomProgressPoll();
              this.selectedId = '';
            });
        }
        Column({ space: 2 }) {
          Text(this.selectedConversation()?.name ?? '选择一个会话')
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.ink()).maxLines(1);
          Text(this.streamLabel()).fontSize(11)
            .fontColor(this.streamStatus === 'connected' ? '#24B47E' : this.muted());
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        if (this.busy) {
          Button('停止').height(36).borderRadius(18).backgroundColor('#FDECEC').fontColor('#C93C3C')
            .onClick(() => void this.stop());
        } else if (this.selectedConversation() !== undefined) {
          Button(this.selectedConversation()?.pinned ? '取消置顶' : '置顶')
            .height(34).borderRadius(17).fontSize(12).backgroundColor(this.pageBg()).fontColor(this.ink())
            .onClick(() => {
              const item = this.selectedConversation();
              if (item !== undefined) void this.setConversationFlag(item, !item.pinned, undefined);
            });
          Button(this.selectedConversation()?.hidden ? '恢复' : '隐藏')
            .height(34).borderRadius(17).fontSize(12).backgroundColor(this.pageBg()).fontColor(this.ink())
            .onClick(() => {
              const item = this.selectedConversation();
              if (item !== undefined) void this.setConversationFlag(item, undefined, !item.hidden);
            });
        }
      }
      .height(68).width('100%').padding({ left: 16, right: 16 })
      .backgroundColor(this.surface()).border({ width: { bottom: 1 }, color: this.line() });
      if (this.conversationApprovals().length > 0) {
        this.chatApprovals();
      }
      if (this.selectedId.length === 0) {
        Column({ space: 12 }) {
          this.appMark(64);
          Text('选择一个 Bot 开始对话').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.ink());
          Text('所有模型、工具和工作目录仍在你的 DSH 主机上运行。')
            .fontSize(13).fontColor(this.muted()).textAlign(TextAlign.Center);
        }.layoutWeight(1).justifyContent(FlexAlign.Center).padding(30);
      } else {
        Scroll(this.scroller) {
          Column() {
            this.earlierMessagesButton();
            if (this.conversationQuestions().length > 0) {
              this.chatQuestions();
            }
            if (this.messages.length === 0) {
              Text('还没有消息，向这个 Bot 打个招呼吧。')
                .fontSize(14).fontColor(this.muted()).padding(30).width('100%').textAlign(TextAlign.Center);
            }
            ForEach(this.messages, (message: Message) => {
              this.messageBubble(message);
            }, (message: Message) => message.id);
            if (this.busy) {
              Row({ space: 10 }) {
                LoadingProgress().width(22).height(22).color('#665CF6');
                Text('Bot 正在主机上工作…').fontSize(13).fontColor(this.muted());
              }.padding(18).width('100%');
            }
          }.width('100%').constraintSize({ maxWidth: 920 }).alignSelf(ItemAlign.Center);
        }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
        this.groupProgress();
        Column({ space: 6 }) {
          this.mentionMenu();
          this.composerAccessories();
        }.width('100%').padding({ left: 14, right: 14 });
        Row({ space: 10 }) {
          Button('+').width(48).height(48).borderRadius(24).fontSize(24)
            .backgroundColor(this.pageBg()).fontColor(this.ink())
            .bindMenu(this.composerMenu());
          TextArea({ placeholder: '发送消息…', text: this.composerText(), controller: this.composerController })
            .layoutWeight(1).height(56).maxLength(this.composerMaxLength()).fontSize(15).fontColor(this.ink())
            .backgroundColor(this.pageBg()).borderRadius(16)
            .onChange((value: string) => {
              this.setComposerText(value);
            })
            .onEditChange((editing: boolean) => this.composerFocused = editing)
            .onTextSelectionChange((start: number, end: number) => {
              this.composerSelectionStart = start;
              this.composerSelectionEnd = end;
            });
          Button(this.busy ? '…' : '发送').height(48).width(72).borderRadius(24)
            .backgroundColor('#665CF6')
            .enabled(!this.busy && this.draft.trim().length > 0 && this.online)
            .onClick(() => void this.send());
        }
        .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 14 })
        .backgroundColor(this.surface()).border({ width: { top: 1 }, color: this.line() });
      }
    }.layoutWeight(1).height('100%').backgroundColor(this.pageBg());
  }

  @Builder
  private mobileChatPanel() {
    Column() {
      Row({ space: 10 }) {
        Button() {
          Image(this.dark ? $r('app.media.ic_back_light') : $r('app.media.ic_back')).width(22).height(22);
        }
        .width(48).height(48).borderRadius(24).backgroundColor(this.dark ? '#242424' : '#FFFFFF')
        .border({ width: 1, color: this.line() }).onClick(() => {
          this.stopRoomProgressPoll();
          this.selectedId = '';
        });
        Row({ space: 8 }) {
          if (this.selectedConversation() !== undefined) {
            this.conversationAvatar(this.selectedConversation()!, 30);
          }
          Column({ space: 1 }) {
            Text(this.selectedConversation()?.name ?? 'DS Bot')
              .fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).maxLines(1);
            Text(this.streamLabel()).fontSize(11)
              .fontColor(this.streamStatus === 'connected' ? '#24B47E' : this.muted()).maxLines(1);
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        }
        .height(48).padding({ left: 12, right: 16 }).borderRadius(24)
        .backgroundColor(this.dark ? '#242424' : '#FFFFFF').border({ width: 1, color: this.line() })
        .layoutWeight(1);
        Button() {
          Image(this.dark ? $r('app.media.ic_more_light') : $r('app.media.ic_more')).width(22).height(22);
        }
        .width(48).height(48).borderRadius(24).backgroundColor(this.dark ? '#242424' : '#FFFFFF')
        .border({ width: 1, color: this.line() })
        .onClick(() => this.getUIContext().getPromptAction().showToast({ message: '长按会话可在设置中管理置顶与隐藏', duration: 1800 }));
      }.width('100%').height(72).padding({ left: 20, right: 20, top: 12, bottom: 12 });
      if (this.conversationApprovals().length > 0) {
        this.chatApprovals();
      }
      Scroll(this.scroller) {
        Column() {
          this.earlierMessagesButton();
          if (this.conversationQuestions().length > 0) {
            this.chatQuestions();
          }
          if (this.messages.length === 0) {
            Text('还没有消息，向这个 Bot 打个招呼吧。')
              .fontSize(14).fontColor(this.muted()).padding(30).width('100%').textAlign(TextAlign.Center);
          }
          ForEach(this.messages, (message: Message) => {
            this.messageBubble(message);
          }, (message: Message) => message.id);
          if (this.busy) {
            Row({ space: 10 }) {
              LoadingProgress().width(22).height(22).color('#4D6BFE');
              Text('Bot 正在主机上工作…').fontSize(13).fontColor(this.muted());
            }.padding(18).width('100%');
          }
        }.width('100%').padding({ top: 8, bottom: 8 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
      this.groupProgress();
      if (this.queue.length > 0) {
        this.queuePanel();
      }
      Column({ space: 6 }) {
        this.mentionMenu();
        this.composerAccessories();
      }.width('100%').padding({ left: 20, right: 20 });
      Row({ space: 10 }) {
        Button() {
          Image(this.dark ? $r('app.media.ic_plus_light') : $r('app.media.ic_plus')).width(24).height(24);
        }
        .width(48).height(48).borderRadius(24).backgroundColor(this.dark ? '#242424' : '#FFFFFF')
        .border({ width: 1, color: this.line() })
        .bindMenu(this.composerMenu());
        TextArea({
          placeholder: `向 ${this.selectedConversation()?.name ?? 'Bot'} 提问`,
          text: this.composerText(),
          controller: this.composerController
        })
          .layoutWeight(1).height(48).maxLength(this.composerMaxLength()).fontSize(16).fontColor(this.ink())
          .backgroundColor(this.dark ? '#202022' : '#FFFFFF').borderRadius(24)
          .border({ width: 1, color: this.line() }).padding({ left: 14, right: 14, top: 10, bottom: 8 })
          .onChange((value: string) => {
            this.setComposerText(value);
          })
          .onEditChange((editing: boolean) => this.composerFocused = editing)
          .onTextSelectionChange((start: number, end: number) => {
            this.composerSelectionStart = start;
            this.composerSelectionEnd = end;
          });
        Button() {
          Image($r('app.media.ic_send')).width(22).height(22);
        }
        .width(48).height(48).borderRadius(24).backgroundColor('#4D6BFE')
        .opacity(!this.busy && this.draft.trim().length > 0 && this.online ? 1 : 0.38)
        .enabled(!this.busy && this.draft.trim().length > 0 && this.online)
        .onClick(() => void this.send());
      }
      .width('100%').padding({ left: 20, right: 20, top: 10, bottom: 10 })
      .backgroundColor(this.dark ? '#121212' : '#FFFFFF');
    }.width('100%').height('100%').backgroundColor(this.dark ? '#121212' : '#FFFFFF');
  }

  @Builder
  private teamPage() {
    Scroll() {
      Column({ space: 18 }) {
        Row() {
          if (this.windowWidth < 600) {
            Button() {
              Image($r('app.media.ic_close')).width(22).height(22);
            }
            .width(48).height(48).margin({ right: 14 }).borderRadius(24).backgroundColor('#FFFFFF')
            .border({ width: 1, color: '#E5E5E5' }).onClick(() => this.section = 'chat');
          }
          Column({ space: 3 }) {
            Text(this.windowWidth < 600 ? 'Bot 与群聊' : 'Bot 团队')
              .fontSize(this.windowWidth < 600 ? 22 : 28).fontWeight(FontWeight.Bold).fontColor(this.ink());
            Text(`${this.team.bots.length} 个 Bot · ${this.team.rooms.length} 个群聊`)
              .fontSize(13).fontColor(this.muted());
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          this.statusPill();
        }.width('100%');
        if (this.team.readOnly !== undefined) {
          Text(this.team.readOnly).fontSize(13).fontColor('#C77A28').width('100%')
            .padding(12).backgroundColor('#FFF4E5').borderRadius(12);
        }
        Grid() {
          ForEach(this.team.bots, (bot: Bot) => {
            GridItem() {
              Column({ space: 10 }) {
                // 团队页 Bot 卡片：同样改用矢量头像（曾经是 `Circle` + 首字母占位）
                this.botAvatar(bot, bot.name, 54, this.isMainBotId(bot.id), bot.waiting === true);
                Text(bot.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.ink()).maxLines(1);
                Text(bot.role ?? 'Bot').fontSize(12).fontColor(this.muted()).maxLines(2);
                if (bot.waiting) Text('等待中').fontSize(11).fontColor('#C77A28');
              }
              .width('100%').height(150).justifyContent(FlexAlign.Center)
              .padding(14).backgroundColor(this.surface()).borderRadius(18)
              .onClick(() => {
                const item = this.conversations.find((value: Conversation) =>
                  value.id === bot.id || value.id === `bot:${bot.id}` || value.sessionId === bot.sessionId);
                if (item !== undefined) {
                  this.section = 'chat';
                  void this.selectConversation(item);
                }
              });
            }
          }, (bot: Bot) => bot.id);
        }
        .columnsTemplate(this.windowWidth >= 1200 ? '1fr 1fr 1fr 1fr' : this.windowWidth >= 700 ? '1fr 1fr 1fr' : '1fr 1fr')
        .columnsGap(12).rowsGap(12).width('100%');
        Column({ space: 12 }) {
          Text('创建 Bot').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%');
          Row({ space: 10 }) {
            TextInput({ placeholder: 'Bot 名称', text: this.newBotName })
              .layoutWeight(1).height(46).backgroundColor(this.pageBg()).borderRadius(14)
              .fontColor(this.ink()).onChange((value: string) => this.newBotName = value);
            Button('创建').height(44).borderRadius(22).backgroundColor('#665CF6')
              .enabled(!this.busy && this.online && this.newBotName.trim().length > 0)
              .onClick(() => void this.createBot());
          }.width('100%');
        }.width('100%').padding(18).backgroundColor(this.surface()).borderRadius(18);
        Column({ space: 12 }) {
          Text('创建群聊').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%');
          Text('选择至少两个 Bot，第一个成员将成为管理员。').fontSize(12).fontColor(this.muted()).width('100%');
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.team.bots, (bot: Bot) => {
              Button(bot.name).height(36).margin({ right: 8, bottom: 8 }).borderRadius(18)
                .backgroundColor(this.selectedMembers.includes(bot.id) ? '#665CF6' : this.pageBg())
                .fontColor(this.selectedMembers.includes(bot.id) ? '#FFFFFF' : this.ink())
                .onClick(() => this.toggleMember(bot.id));
            }, (bot: Bot) => bot.id);
          }.width('100%');
          Row({ space: 10 }) {
            TextInput({ placeholder: '群聊名称', text: this.newGroupName })
              .layoutWeight(1).height(46).backgroundColor(this.pageBg()).borderRadius(14)
              .fontColor(this.ink()).onChange((value: string) => this.newGroupName = value);
            Button('创建').height(44).borderRadius(22).backgroundColor('#665CF6')
              .enabled(!this.busy && this.online && this.newGroupName.trim().length > 0 && this.selectedMembers.length >= 2)
              .onClick(() => void this.createGroup());
          }.width('100%');
        }.width('100%').padding(18).backgroundColor(this.surface()).borderRadius(18);
      }
      .width('100%').constraintSize({ maxWidth: 1100 }).padding(22).alignSelf(ItemAlign.Center);
    }.layoutWeight(1).height('100%').backgroundColor(this.pageBg());
  }

  @Builder
  private settingsPage() {
    Scroll() {
      Column({ space: 16 }) {
        Text('设置').fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.ink()).width('100%');
        Column({ space: 12 }) {
          Row() {
            Column({ space: 4 }) {
              Text(this.serverName).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink());
              Text(this.profile?.serverUrl ?? '').fontSize(12).fontColor(this.muted()).maxLines(1);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            this.statusPill();
          }.width('100%');
          Button('立即刷新').width('100%').height(44).borderRadius(22).backgroundColor('#665CF6')
            .onClick(() => void this.refreshAll());
        }.width('100%').padding(18).backgroundColor(this.surface()).borderRadius(18);
        Column({ space: 12 }) {
          Text('外观').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%');
          Row() {
            Text('深色模式').fontSize(15).fontColor(this.ink()).layoutWeight(1);
            Toggle({ type: ToggleType.Switch, isOn: this.dark }).onChange((value: boolean) => this.dark = value);
          }.width('100%');
        }.width('100%').padding(18).backgroundColor(this.surface()).borderRadius(18);
        Column({ space: 12 }) {
          Row() {
            Text('待批准操作').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).layoutWeight(1);
            Text(`${this.approvals.length}`).fontSize(13).fontColor(this.muted());
          }.width('100%');
          ForEach(this.approvals, (approval: Approval) => {
            Column({ space: 8 }) {
              Text(approval.toolName).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%');
              Text(approval.reason ?? '主机请求批准此工具操作').fontSize(12).fontColor(this.muted()).width('100%');
              Row({ space: 8 }) {
                Button('允许一次').height(36).borderRadius(18).backgroundColor('#665CF6')
                  .onClick(() => void this.resolveApproval(approval.id, 'allowed-once'));
                Button('拒绝').height(36).borderRadius(18).backgroundColor('#FDECEC').fontColor('#C93C3C')
                  .onClick(() => void this.resolveApproval(approval.id, 'rejected'));
              }.width('100%');
            }.width('100%').padding(12).backgroundColor(this.pageBg()).borderRadius(12);
          }, (approval: Approval) => approval.id);
          if (this.approvals.length === 0) {
            Text('暂无待批准操作').fontSize(13).fontColor(this.muted()).width('100%');
          }
        }.width('100%').padding(18).backgroundColor(this.surface()).borderRadius(18);
        Column({ space: 10 }) {
          Text('已配对设备').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%');
          ForEach(this.devices, (device: DeviceListItem) => {
            Row({ space: 10 }) {
              Text(device.deviceName ?? device.name ?? device.id).fontSize(14).fontColor(this.ink()).layoutWeight(1);
              if (device.id === this.profile?.session.deviceId) {
                Text('本机').fontSize(12).fontColor('#665CF6');
              } else {
                // 确认交给原生 showDialog（见 confirmDestructive），按钮不再承担确认态
                Button('移除')
                  .height(32).borderRadius(16).fontSize(12)
                  .backgroundColor(this.pageBg()).fontColor(this.ink())
                  .enabled(!this.busy)
                  .onClick(() => void this.revokeDevice(device));
              }
            }.width('100%').padding({ top: 8, bottom: 8 });
          }, (device: DeviceListItem) => device.id);
        }.width('100%').padding(18).backgroundColor(this.surface()).borderRadius(18);
        Button('断开并清除本机凭据').width('100%').height(46).borderRadius(23)
          .backgroundColor('#FDECEC').fontColor('#C93C3C').onClick(() => void this.logout());
        Text('DS Bot Harmony 0.1.0 · HarmonyOS 6.0+').fontSize(12).fontColor(this.muted());
      }
      .width('100%').constraintSize({ maxWidth: 760 }).padding(22).alignSelf(ItemAlign.Center);
    }.layoutWeight(1).height('100%').backgroundColor(this.pageBg());
  }

  @Builder
  private mobileSettingsPage() {
    // 整页已抽到 view/SettingsPage.ets（纯展示组件，交互通过回调发出意图）
    SettingsPage({
      view: {
        serverName: this.serverName,
        serverUrl: this.profile?.serverUrl ?? '',
        dark: this.dark,
        approvals: this.approvals
      } as SettingsView,
      tokens: {
        pageBg: this.dark ? '#121212' : '#FFFFFF',
        rowBg: this.dark ? '#202022' : '#F1F1F1',
        ink: this.ink(), muted: this.muted(), line: this.tokens().line,
        dangerBg: '#FDECEC', danger: '#C93C3C', brand: '#4D6BFE'
      } as SettingsTheme,
      onClose: (): void => { this.section = 'chat'; },
      onToggleDark: (value: boolean): void => { this.dark = value; },
      onOpenTools: (): void => { this.mobileOverlay = 'tools'; },
      onOpenTeam: (): void => { this.section = 'team'; },
      onOpenProbe: (): void => { this.showProbe = true; },
      onRefresh: (): void => void this.refreshAll(),
      onClearCache: (): void => void this.clearLocalCache(),
      onLogout: (): void => void this.logout(),
      onResolveApproval: (approvalId: string, decision: string): void =>
        void this.resolveApproval(approvalId, decision)
    });
  }


  /**
   * 创建页的头像预览。
   *
   * 旧实现是「14 张 PNG + 手绘几何占位」，颜色对预览无效、形状也只有 13 种。
   * 现在直接用矢量组件：20 形状 × 12 颜色都是真实渲染结果，所见即所得。
   */
  @Builder
  private botAvatarPreview(size: number) {
    Column({ space: 6 }) {
      BotAvatarView({
        shape: this.newBotShape,
        color: this.newBotColor,
        avatarSize: size,
        image: ''
      });
      Text(`${this.newBotShape} · ${this.newBotColor}`)
        .fontSize(12).fontColor(this.muted());
    }
    .width(size + 40).alignItems(HorizontalAlign.Center)
  }

  @Builder
  private mobileCreateBotPage() {
    Column() {
      Row() {
        Button() {
          Image($r('app.media.ic_close')).width(22).height(22);
        }
        .width(48).height(48).borderRadius(24).backgroundColor('#FFFFFF')
        .border({ width: 1, color: '#E5E5E5' }).onClick(() => this.mobileOverlay = '');
        Text('创建新 Bot').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).layoutWeight(1)
          .textAlign(TextAlign.Center);
        Blank().width(48);
      }.width('100%').height(76).padding({ left: 20, right: 20, top: 12, bottom: 16 });

      Scroll() {
        Column({ space: 28 }) {
          this.botAvatarPreview(126);
          TextInput({ placeholder: '为 Bot 取个名字', text: this.newBotName })
            .width('100%').height(64).fontSize(20).fontWeight(FontWeight.Medium).textAlign(TextAlign.Center)
            .fontColor(this.ink()).backgroundColor(this.dark ? '#202022' : '#EFEFEF').borderRadius(18)
            .onChange((value: string) => this.newBotName = value);

          Text('选择形状').fontSize(14).fontColor(this.muted()).width('100%');
          // 形状网格：直接渲染矢量预览，颜色随当前选择实时变化（旧版是 13 张固定配色 PNG）。
          Grid() {
            ForEach(this.avatarShapes(), (shape: string) => {
              GridItem() {
                Stack() {
                  BotAvatarView({
                    shape: shape,
                    color: this.newBotColor,
                    avatarSize: 40,
                    image: ''
                  });
                }
                .width(56).height(52)
                .borderRadius(12)
                .border({ width: this.newBotShape === shape ? 2 : 0, color: '#4D6BFE' })
                .onClick(() => this.newBotShape = shape);
              }
            }, (shape: string) => shape)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr')
          .columnsGap(6).rowsGap(6).width('100%').height(240);

          Text('选择颜色').fontSize(14).fontColor(this.muted()).width('100%');
          // 色板：颜色取自矢量头像的 inks 表（12 色，含上游的 aurora）。
          Grid() {
            ForEach(this.avatarColors(), (color: string) => {
              GridItem() {
                Column({ space: 2 }) {
                  Stack() {
                    BotAvatarView({ shape: this.newBotShape, color: color, avatarSize: 34, image: '' });
                  }
                  .width(48).height(40)
                  .borderRadius(10)
                  .border({ width: this.newBotColor === color ? 2 : 0, color: '#4D6BFE' });
                  Text(color).fontSize(9).fontColor(this.muted()).maxLines(1);
                }
                .onClick(() => this.newBotColor = color);
              }
            }, (color: string) => color)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
          .columnsGap(4).rowsGap(6).width('100%').height(150);

          Button(this.busy ? '正在创建…' : '创建 Bot').width('100%').height(54).borderRadius(27)
            .margin({ top: 12, bottom: 18 }).backgroundColor('#4D6BFE').fontSize(17)
            .enabled(!this.busy && this.online && this.newBotName.trim().length > 0)
            .onClick(() => void this.createBot());
        }.width('100%').padding({ left: 24, right: 24, top: 32, bottom: 30 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(this.dark ? '#121212' : '#FAFAFA');
  }

  private secondaryTokens(): SecondaryPageTheme {
    return {
      pageBg: this.dark ? '#121212' : '#FFFFFF',
      rowBg: this.dark ? '#202022' : '#F1F1F1',
      chipBg: this.dark ? '#202022' : '#FFFFFF',
      chipLine: this.dark ? '#2B2B2D' : '#E5E5E5',
      ink: this.ink(), muted: this.muted(), line: this.line(),
      brand: '#4D6BFE', brandSoft: this.dark ? '#25304F' : '#E8EDFF'
    };
  }

  @Builder
  private mobileToolsPage() {
    // 页面本体已抽到 view/SecondaryPages.ets
    ToolsPage({
      tokens: this.secondaryTokens(),
      onClose: (): void => { this.mobileOverlay = ''; },
      onOpenCapabilities: (): void => { this.mobileOverlay = 'capabilities'; }
    });
  }



  @Builder
  @Builder
  private mobileCapabilitiesPage() {
    CapabilitiesPage({
      tokens: this.secondaryTokens(),
      bots: this.team.bots,
      onBack: (): void => { this.mobileOverlay = 'tools'; }
    });
  }


  @Builder
  private mainContent() {
    if (this.windowWidth >= 600) {
      // **宽屏用原生 `SideBarContainer`**：分隔条由系统提供，用户可拖拽调整会话区/聊天区比例。
      // 之前是手写 `Row` + 固定 320vp，用户无法调节（2026-10-16 用户反馈会话区太宽/聊天区太窄）。
      // - `autoHide(false)`：拖到最小也不自动隐藏（默认 true 会把侧栏吞掉）
      // - `showControlButton(false)`：隐藏系统默认的折叠按钮（我们的导航栏已有一级入口）
      // - 宽度范围 240~520vp：240 是 SDK 默认下限；上限 520 避免聊天区被压得过窄
      //   （折叠屏实测 706vp 窗口下，侧栏 419vp 时聊天区只剩 285vp，太窄）
      SideBarContainer(SideBarContainerType.Embed) {
        this.desktopSidebar();
        this.desktopPane();
      }
      .showSideBar(true)
      .showControlButton(false)
      .autoHide(false)
      .sideBarWidth(this.sideBarWidth)
      .minSideBarWidth(240)
      .maxSideBarWidth(520)
      .onChange((visible: boolean) => { this.sideBarShown = visible; })
      .width('100%').height('100%');
    } else {
      if (this.mobileOverlay === 'create-bot') {
        this.mobileCreateBotPage();
      } else if (this.mobileOverlay === 'tools') {
        this.mobileToolsPage();
      } else if (this.mobileOverlay === 'capabilities') {
        this.mobileCapabilitiesPage();
      } else if (this.section === 'chat') {
        if (this.selectedId.length === 0) this.mobileHome();
        else this.mobileChatPanel();
      } else if (this.section === 'team') {
        this.teamPage();
      } else {
        this.mobileSettingsPage();
      }
    }
  }

  build() {
    Stack() {
      if (!this.ready) {
        Column({ space: 14 }) {
          this.appMark(64);
          LoadingProgress().width(28).height(28).color('#665CF6');
          Text('正在准备 DS Bot…').fontSize(14).fontColor(this.muted());
        }.width('100%').height('100%').justifyContent(FlexAlign.Center);
      } else if (!this.paired) {
        this.pairingPage();
      } else {
        this.mainContent();
      }

      if (this.showProbe) {
        Column() {
          Row({ space: 10 }) {
            Text('事件流验证').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.ink()).layoutWeight(1);
            Button('关闭').height(34).borderRadius(17).fontSize(13)
              .backgroundColor(this.pageBg()).fontColor(this.ink())
              .onClick(() => this.showProbe = false);
          }.width('100%').padding({ left: 16, right: 16, top: 12, bottom: 8 });
          StreamProbe().layoutWeight(1);
        }
        .width('100%').height('100%').backgroundColor(this.dark ? '#101116' : '#FFFFFF');
      }
    }
    .width('100%').height('100%').backgroundColor(this.pageBg())
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateWindowWidth(newArea.width);
    })
    // 错误提示改用原生 `bindPopup`：定位、点击外部关闭、无障碍都由系统处理，
    // 替代之前自绘的「绝对定位浮动横幅 + 手写关闭按钮」。
    .bindPopup(this.error.length > 0, {
      message: this.error,
      placement: Placement.Bottom,
      onStateChange: (event: PopupStateChangeParam): void => {
        if (!event.isVisible) this.error = '';
      }
    })
    .bindSheet(this.messageActionsVisible, this.messageSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: this.surface(),
      onDisappear: (): void => this.closeMessageActions()
    })
    .bindSheet(this.referencePickerVisible, this.referencePickerSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: true,
      backgroundColor: this.surface(),
      onDisappear: (): void => { this.referencePickerVisible = false; }
    });
  }
}
