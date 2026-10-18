import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
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
import { ConnectorList, MobileApiError, MobileClient, RawApprovalList, RawConversationList, RawDeviceList, RawServerInfo, RawState, RawTarget, SubmissionRequest } from '../service/MobileClient';
import { MessageCache } from '../service/MessageCache';
import { serverNameOf, toApprovals, toConnectors, toConversations, toDeviceList, toTeamState } from '../service/Projection';
import { ProfileStore } from '../service/ProfileStore';
import { AppPreferences, defaultPreferences, loadPreferences, savePreferences } from '../service/AppPreferences';
import { selfTestCredentialCipher } from '../service/CredentialCipher';
import { MobileEvent, StreamStatus } from '../service/Wire';
import { EffortOption } from '../service/Wire';
import { applyConversationEvent, mergeMessages } from '../logic/Merge';
import { ConversationQuestion, questionsForConversation } from '../logic/Questions';
import { ConversationPart, HistoryPage, PartsPage, UsagePage } from '../model/Models';
import { UsagePanel } from '../view/UsagePanel';
import { ScheduleTarget, SchedulesPanel } from '../view/SchedulesPanel';
import { MemoryBotOption, MemoryPanel } from '../view/MemoryPanel';
import { RoomManagePanel } from '../view/RoomManagePanel';
import { BotManagePanel } from '../view/BotManagePanel';
import { ToolsSkillsPanel } from '../view/ToolsSkillsPanel';
import { AgentPanel } from '../view/AgentPanel';
import { UsageWindow } from '../logic/Usage';
import { ScheduleForm, ScheduleValidation } from '../logic/Schedules';
import { describeChanges, MemoryRow, validateAsk } from '../logic/Memory';
import { buildRoomPatch, formOfRoom, RoomForm, translateChanges } from '../logic/Rooms';
import { AVATAR_DATA_URL_MAX, avatarDataUrl, BotForm, buildBotPatch, formOfBot } from '../logic/Bots';
import { readOnlyNotice } from '../logic/Capabilities2';
import { needsToken, tokenProblem } from '../logic/Connectors';
import {
  filterByPreferences, kindLabel, readThroughCursor, shouldNotify, unreadCount
} from '../logic/Notifications';
import { NotificationsPanel } from '../view/NotificationsPanel';
import { LocalNotify } from '../service/LocalNotify';
import { NotificationItem, NotificationPreferences } from '../model/Models';
import { Connector } from '../model/Models';
import { exportConversation, exportFileName } from '../logic/Export';
import {
  addBlockedReason, allUploaded, baseName, canAddMore, MAX_ATTACHMENTS, PendingAttachment,
  formatSize, uploadingCount
} from '../logic/Attachments';
import { AttachmentPicker } from '../service/AttachmentPicker';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImageLoader } from '../service/ImageLoader';
import { Attachment } from '../model/Models';
import { image } from '@kit.ImageKit';
import { archivePrompt, groupAgentConversations, removePrompt, titleProblem } from '../logic/Agents';
import {
  CapabilityStatus, MemoryEntry, MemoryView, PluginBundle, PluginEntry, ScheduleTask,
  SkillDetail, SkillItem
} from '../model/Models';
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
import { AppMark } from '../view/AppMark';
import { ChatComposer, ComposerTheme } from '../view/ChatComposer';
import { ReasoningBlock } from '../view/ReasoningBlock';
import { BubbleMetrics, MessageBubble } from '../view/MessageBubble';
import { ChatMessageList } from '../view/ChatMessageList';
import { BotCard, TeamPage } from '../view/TeamPage';
import { MobileHome, MobileHomeEntry } from '../view/MobileHome';
import { MobileCreateBotPage } from '../view/MobileCreateBotPage';
import { PairingPage } from '../view/PairingPage';
import { ConversationEntry, DesktopSidebar, RailItem, SidebarTheme } from '../view/DesktopSidebar';
import { AvatarSpec, BotAvatar } from '../view/BotAvatar';
import { ThemeTokens, themeOf } from '../view/Theme';
import { WorkspaceInspector } from '../view/WorkspaceInspector';
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
  /**
   * **接管系统返回**：鸿蒙的边缘侧滑手势与返回键走同一事件，因此这一处同时覆盖两者。
   *
   * 本应用是「单页 + 内部状态导航」（`section` / `mobileOverlay` / `selectedId`），
   * 没有使用 `Navigation` 路由栈，系统无从得知"上一级"是什么。
   * 所以必须按内部层级手动回退，否则一按返回就直接退出应用
   * （2026-10-17 真机发现：会话页返回会退回系统桌面）。
   *
   * 回退优先级（从最内层到最外层）：
   * 1. 浮层（创建 Bot / 工具 / 能力库）→ 关闭浮层；
   * 2. 手机端会话页 → 回到会话列表；
   * 3. 非「对话」分区（团队 / 设置）→ 回到对话；
   * 4. 其余情况交还系统（允许退出应用）。
   */
  onBackPress(): boolean {
    // 0. 原生 bindSheet 弹层优先：只关弹层，不再往下退一层
    if (this.messageActionsVisible) {
      this.closeMessageActions();
      return true;
    }
    if (this.referencePickerVisible) {
      this.referencePickerVisible = false;
      return true;
    }
    if (this.partsVisible) {
      this.partsVisible = false;
      return true;
    }
    if (this.usageVisible) {
      this.usageVisible = false;
      return true;
    }
    if (this.schedulesVisible) {
      this.schedulesVisible = false;
      return true;
    }
    if (this.memoryVisible) {
      this.memoryVisible = false;
      return true;
    }
    if (this.agentVisible) {
      this.agentVisible = false;
      return true;
    }
    if (this.notificationsVisible) {
      this.notificationsVisible = false;
      return true;
    }
    if (this.capabilitiesVisible) {
      this.capabilitiesVisible = false;
      return true;
    }
    if (this.toolsVisible) {
      if (this.skillDetail !== null) {
        this.skillDetail = null;
      } else {
        this.toolsVisible = false;
      }
      return true;
    }
    if (this.botsVisible) {
      if (this.botEditingId.length > 0) {
        this.botEditingId = '';
      } else {
        this.botsVisible = false;
      }
      return true;
    }
    if (this.roomsVisible) {
      if (this.roomEditingId.length > 0) {
        this.roomEditingId = '';
      } else {
        this.roomsVisible = false;
      }
      return true;
    }
    // 正在看历史分段 → 先回到当前分段（不要直接退出会话）
    if (this.viewingPartSessionId.length > 0) {
      this.returnToCurrentPart();
      return true;
    }
    // 1. 关闭最内层浮层
    if (this.mobileOverlay.length > 0) {
      this.mobileOverlay = '';
      return true;
    }
    // 2. 手机端：会话页 → 会话列表（与顶栏返回按钮行为完全一致）
    if (this.windowWidth < 600 && this.section === 'chat' && this.selectedId.length > 0) {
      this.stopRoomProgressPoll();
      this.selectedId = '';
      return true;
    }
    // 3. 团队 / 设置 → 对话
    if (this.section !== 'chat') {
      this.section = 'chat';
      return true;
    }
    // 4. 已在最外层：让系统处理（退回桌面 / 后台）
    return false;
  }

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
  /** 历史分段（P0-6）：主机把一个长会话切成多个 part，每个 part 有自己的 sessionId 与 cursor。 */
  @State parts: ConversationPart[] = [];
  /** parts 是为哪个会话拉的（避免重复请求 / 切换会话后误用旧数据）。 */
  private partsLoadedFor: string = '';
  /** 分段选择器（原生 bindSheet）是否展开。 */
  @State partsVisible: boolean = false;
  /** 用量面板（P2-2） */
  @State usageVisible: boolean = false;
  @State usageData: UsagePage = {};
  @State usageWindow: UsageWindow = '24h';
  @State usageLoading: boolean = false;
  @State usageError: string = '';
  /** 定时任务面板（P2-3） */
  @State schedulesVisible: boolean = false;
  @State scheduleTasks: ScheduleTask[] = [];
  @State schedulesAvailable: boolean = true;
  @State schedulesLoading: boolean = false;
  @State schedulesError: string = '';
  @State scheduleCreating: boolean = false;
  @State scheduleFormError: string = '';
  /** 待发送附件（P3-1）：上传成功后带 receiptId */
  @State attachments: PendingAttachment[] = [];
  @State attachmentBusy: boolean = false;
  /** 全屏查看的图片（P3-1） */
  @State previewPixel: image.PixelMap | undefined = undefined;
  @State previewVisible: boolean = false;
  @State attachmentError: string = '';
  /** DSH Agent（P2-9） */
  @State agentVisible: boolean = false;
  @State agentEditingId: string = '';
  @State agentTitleDraft: string = '';
  @State agentBusy: boolean = false;
  @State agentError: string = '';
  @State agentNotice: string = '';
  /** 工具与技能（P2-8） */
  @State toolsVisible: boolean = false;
  @State skills: SkillItem[] = [];
  @State skillsAvailable: boolean = true;
  @State plugins: PluginEntry[] = [];
  @State bundles: PluginBundle[] = [];
  @State toolsWritable: boolean = true;
  /** 连接器 token 输入（工具与技能） */
  @State connectorTokenFor: string = '';
  @State connectorTokenDraft: string = '';
  @State connectorBusy: boolean = false;
  /** 能力库整页（从工具与技能进入；宽屏也要能进，所以不依赖 mobileOverlay） */
  @State capabilitiesVisible: boolean = false;
  /** 通知中心（P3-4） */
  @State notificationsVisible: boolean = false;
  @State notificationItems: NotificationItem[] = [];
  @State notificationPrefs: NotificationPreferences = { enabled: true, categories: [] };
  @State notificationCursor: number = 0;
  @State notificationLoading: boolean = false;
  @State notificationBusy: boolean = false;
  @State notificationError: string = '';
  /** 已经弹过系统通知的 id（避免重复弹） */
  private notifiedIds: number[] = [];
  @State toolsLoading: boolean = false;
  @State toolsError: string = '';
  @State toolsBusy: boolean = false;
  @State skillDetail: SkillDetail | null = null;
  @State skillDetailLoading: boolean = false;
  /** Bot 管理（P2-5） */
  @State botsVisible: boolean = false;
  @State botEditingId: string = '';
  @State botForm: BotForm = { id: '', name: '', role: '', instructions: '', model: '', effort: '', avatarImage: '' };
  @State botBusy: boolean = false;
  @State botError: string = '';
  @State botNotice: string = '';
  /** 档位 id → 显示名（列表里显示「高/低」而不是原始 id） */
  @State botEffortNames: Record<string, string> = {};
  /** 群聊管理（P2-6） */
  @State roomsVisible: boolean = false;
  @State roomEditingId: string = '';
  @State roomForm: RoomForm = { id: '', name: '', notice: '', mode: 'admin', admin: '', members: [] };
  @State roomBusy: boolean = false;
  @State roomError: string = '';
  @State roomChanges: string[] = [];
  /** 能力库选中的 Bot（P2-7） */
  @State capabilityBotId: string = '';
  @State capabilityBusy: boolean = false;
  @State capabilityError: string = '';
  /** 记忆面板（P2-4） */
  @State memoryVisible: boolean = false;
  @State memoryView: MemoryView = {};
  @State memoryBotId: string = '';
  @State memoryLoading: boolean = false;
  @State memoryError: string = '';
  @State memoryAskText: string = '';
  @State memoryAsking: boolean = false;
  @State memoryAskError: string = '';
  @State memoryAskLines: string[] = [];
  @State scheduleForm: ScheduleForm = {
    target: '', title: '', prompt: '', kind: 'daily',
    atLocal: '', time: '09:00', weekdays: [], minutes: 60, timeZone: 'UTC'
  };
  /**
   * 正在查看的历史分段 sessionId；空串表示当前分段。
   * 非空时消息来自 `earlier(sessionId, cursor)`，**不应混入实时事件流**，
   * 也不应允许发送（发送属于当前分段）。
   */
  @State viewingPartSessionId: string = '';
  /** 查看历史分段时的分段序号（用于横幅文案）。 */
  @State viewingPartNumber: number = 0;
  /** 历史分段是否还有更早（该 part 内部的 cursor）。 */
  @State partHasEarlier: boolean = false;
  @State partCursor: string = '';
  @State loadingPart: boolean = false;
  /** 本地是否还有更早的历史（翻到最早时为 false）。 */
  @State hasEarlier: boolean = true;
  @State historyCursor: string = '';
  /**
   * 是否已完成首次历史加载（决定「加载更早消息」按钮是否可显示）。
   *
   * **必须是 `@State`**：它在 `loadMessages()` 返回后被置为 true，
   * 而 `earlierMessagesButton()` 的渲染条件依赖它。此前写成普通私有字段，
   * 赋值不触发重渲染，按钮因此**从不出现**（2026-10-16 检查消息区插槽时发现）。
   */
  @State historyInitialized: boolean = false;
  /** 已展开思考过程的消息 id（P1-4）。 */
  /** 长按消息弹出的动作列表。 */
  @State messageActions: MessageAction[] = [];
  @State actionTargetId: string = '';
  /** 是否展示消息操作面板（驱动原生 bindSheet）。 */
  @State messageActionsVisible: boolean = false;
  /** 宽屏分栏宽度（vp）：由 SideBarContainer 决定，用户可拖拽。 */
  @State sideBarWidth: number = 340;
  /**
   * **实测**的聊天内容区宽度（vp），由 `onAreaChange` 写入。
   *
   * 为什么不再用「窗口宽 − 侧栏宽 − 上下文栏」推算：侧栏宽度由原生
   * `SideBarContainer` 管理，用户拖拽后 `sideBarWidth` 状态不会同步，
   * 推算值会比实际宽，气泡与工具卡因此越出内容区
   * （2026-10-17 PC 实测：工具卡 1100px 撑破 1087px 的气泡，超出 38px）。
   * 改为测量实际宽度，「算不如量」。
   */
  @State chatPaneMeasuredWidth: number = 0;
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
  /** 桌面设置页独立滚动位置，避免与聊天/团队页切换时复用偏移。 */
  private settingsScroller: Scroller = new Scroller();
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
    // HUKS 凭据加密自检：参数错误只有真机运行才暴露，这里把结果写进 hilog
    void selfTestCredentialCipher();
    // 偏好（深色模式等）需要跨重启保持（P2-11）
    void this.restorePreferences();
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

  /** 系统栏背景透明，由当前页面安全区背景着色；这里只同步图标明暗。 */
  private async updateSystemBars(dark: boolean): Promise<void> {
    try {
      const appWindow: window.Window = await window.getLastWindow(this.context());
      await appWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        statusBarContentColor: dark ? '#F3F6FC' : '#172033',
        isStatusBarLightIcon: dark,
        navigationBarColor: '#00000000',
        navigationBarContentColor: dark ? '#9DA9BC' : '#657086',
        isNavigationBarLightIcon: dark
      });
    } catch (error) {
      console.warn(`update system bars failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 启动时恢复偏好。
   *
   * 注意要**顺带同步系统栏**：只改 `dark` 而不调 `updateSystemBars`，
   * 会出现「页面是深色、状态栏还是浅色图标」的割裂。
   */
  private async restorePreferences(): Promise<void> {
    const prefs: AppPreferences = await loadPreferences(this.context());
    if (prefs.dark !== this.dark) {
      this.dark = prefs.dark;
      this.updateSystemBars(prefs.dark);
    }
  }

  private toggleDark(value: boolean): void {
    this.dark = value;
    this.updateSystemBars(value);
    // 落盘：用户显式切换过就应跨重启保持（P2-11）
    void savePreferences(this.context(), { dark: value });
  }

  private updateWindowWidth(width: Length): void {
    const parsed = typeof width === 'number' ? width : Number.parseFloat(width.toString());
    if (Number.isFinite(parsed) && parsed > 0) this.windowWidth = parsed;
  }

  private pageBg(): string {
    return this.tokens().pageBg;
  }

  private surface(): string {
    return this.tokens().surface;
  }

  /** 与系统栏相邻区域的语义底色：聊天衔接面板，其余页面衔接页面背景。 */
  private systemChromeBg(): string {
    // 宽屏由导航栏、会话栏、工作区各自延伸背景；这里仅提供缝隙回退色。
    if (this.windowWidth < 600 && this.paired && this.section === 'chat' && this.selectedId.length > 0) {
      return this.surface();
    }
    return this.pageBg();
  }

  private ink(): string {
    return this.tokens().ink;
  }

  private muted(): string {
    return this.tokens().muted;
  }

  private line(): string {
    return this.tokens().line;
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
  /**
   * 扫码连接主机：用**鸿蒙原生 ScanKit** 扫电脑端显示的配对二维码。
   *
   * 为什么用原生能力而不是自己接相机解码：
   * - `scanBarcode.startScanForResult()` 直接拉起系统扫码 UI，含手电/相册/对焦，
   *   不需要本应用申请相机权限，也不需要自行处理解码与权限申请；
   * - `enableAlbum: true` 允许从相册选图识别，用户可用截图完成配对。
   *
   * 扫码结果就是配对 JSON（与手动粘贴的内容完全相同），因此复用同一条 `pair()` 流程。
   */
  private async scanPairingCode(): Promise<void> {
    if (this.busy) return;
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.getUIContext().getPromptAction().showToast({ message: '当前页面无法启动扫码', duration: 2000 });
      return;
    }
    try {
      const result = await scanBarcode.startScanForResult(context, {
        scanTypes: [scanCore.ScanType.QR_CODE],
        enableAlbum: true
      });
      const value = (result.originalValue ?? '').trim();
      if (value.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '没有识别到二维码内容', duration: 2000 });
        return;
      }
      // 必须是配对 JSON：先校验字段，不合格时把原文留在输入框里方便用户核对
      this.pairingJson = value;
      if (!this.isPairingJson(value)) {
        this.getUIContext().getPromptAction().showToast({
          message: '扫到的不是配对二维码，已填入输入框，请确认内容', duration: 3000
        });
        return;
      }
      await this.pair();
    } catch (raw) {
      const error = raw as BusinessError;
      // 1000500002 = 用户主动取消扫码，属于正常操作，不提示错误
      if (error.code === scanCore.ScanErrorCode.SCAN_SERVICE_CANCELED) return;
      this.getUIContext().getPromptAction().showToast({
        message: `扫码失败：${error.message ?? '未知错误'}`, duration: 2500
      });
    }
  }

  /** 粗校验一段文本是否是配对 JSON（字段存在且非空）。 */
  private isPairingJson(text: string): boolean {
    try {
      const value = JSON.parse(text) as PairingCode;
      return typeof value.url === 'string' && value.url.trim().length > 0 &&
        typeof value.code === 'string' && value.code.trim().length > 0 &&
        typeof value.serverId === 'string' && value.serverId.trim().length > 0;
    } catch (_error) {
      return false;
    }
  }

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
      // 顺带刷新通知中心：没有推送通道，前台轮询是唯一能弹横幅的时机
      void this.loadNotifications(true);
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
    // 切换会话必须丢弃上一条会话的分段视图与缓存（否则会串会话）
    this.viewingPartSessionId = '';
    this.viewingPartNumber = 0;
    this.partCursor = '';
    this.partHasEarlier = false;
    this.parts = [];
    this.partsLoadedFor = '';
    this.partsVisible = false;
    // 分段列表用于顶部的「历史分段」入口；同一会话只请求一次
    void this.loadParts();
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
    // **历史分段视图隔离**：正在看旧分段时，当前分段的新事件不能写进消息列表，
    // 否则历史与实时会混在一条时间线上（P0-6）。
    // 但 status 仍要处理（连接状态/忙碌指示不该被冻结）。
    if (this.viewingPartSessionId.length > 0 && event.type !== 'status') return;
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
        value: '选择图片',
        enabled: this.online && !this.busy && !this.attachmentBusy && canAddMore(this.attachments),
        action: (): void => void this.pickAttachments(true)
      },
      {
        value: '选择文件',
        enabled: this.online && !this.busy && !this.attachmentBusy && canAddMore(this.attachments),
        action: (): void => void this.pickAttachments(false)
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
  /**
   * 分段的时间范围文案。
   *
   * 用 `MM-DD HH:mm` 而不是 `HH:mm`：分段常常跨天，只显示时刻会让人误以为
   * 三个分段都在同一天同一时刻（2026-10-17 实测三个分段都显示 `17:32 – 17:32`）。
   */
  private partTimeRange(part: ConversationPart): string {
    const start = this.partTimestamp(part.startedAt);
    const end = this.partTimestamp(part.endedAt);
    if (start.length > 0 && end.length > 0) return `${start} – ${end}`;
    return start.length > 0 ? start : end;
  }

  /** 把毫秒时间戳格式化成 `MM-DD HH:mm`；无效值返回空串。 */
  private partTimestamp(value: number | undefined): string {
    if (value === undefined) return '';
    const date = new Date(Number(value));
    const time = date.getTime();
    if (!Number.isFinite(time)) return '';
    const pad = (input: number): string => (input < 10 ? `0${input}` : `${input}`);
    return `${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }

  /** 已上传成功的附件 receiptId（发送时带上）。 */
  private readyAttachmentIds(): string[] {
    const ids: string[] = [];
    for (let i = 0; i < this.attachments.length; i++) {
      const receiptId = this.attachments[i].receiptId;
      if (receiptId !== undefined && receiptId.length > 0) ids.push(receiptId);
    }
    return ids;
  }

  /**
   * 选择附件并逐个上传（P3-1）。
   *
   * 选完立刻上传：主机的 receipt 有有效期（约 15 分钟），
   * 攒着不发会在发送时报「上传已过期」，用户还得重选。
   */
  private async pickAttachments(images: boolean): Promise<void> {
    const api = this.apiClient;
    const conversation = this.selectedConversation();
    if (api === undefined || conversation === undefined || this.attachmentBusy) return;
    if (!canAddMore(this.attachments)) {
      this.toast(addBlockedReason(this.attachments));
      return;
    }
    this.attachmentError = '';
    const room = MAX_ATTACHMENTS - this.attachments.length;
    try {
      const picked = images
        ? await AttachmentPicker.pickImages(room)
        : await AttachmentPicker.pickFiles(room);
      if (picked.length === 0) return;
      this.attachments = this.attachments.concat(picked);
      await this.uploadPendingAttachments();
    } catch (error) {
      // 用户取消选择时系统会抛错，不当成失败提示
      const message = (error as Error).message;
      if (message.length > 0 && !message.toLowerCase().includes('cancel')) {
        this.attachmentError = `选择文件失败：${message}`;
      }
    }
  }

  /** 把还没有 receiptId 的附件逐个上传。 */
  private async uploadPendingAttachments(): Promise<void> {
    const api = this.apiClient;
    const conversation = this.selectedConversation();
    if (api === undefined || conversation === undefined) return;
    this.attachmentBusy = true;
    const next: PendingAttachment[] = [];
    for (let i = 0; i < this.attachments.length; i++) {
      const item = this.attachments[i];
      if (item.receiptId !== undefined && item.receiptId !== '') {
        next.push(item);
        continue;
      }
      if (item.error !== undefined && item.error !== '') {
        next.push(item);
        continue;
      }
      if (item.preview === undefined) {
        next.push(item);
        continue;
      }
      try {
        const receipt = await api.upload(conversation.id, conversation.sessionId,
          item.name, item.mediaType, item.preview);
        const uploading: PendingAttachment = {
          key: item.key, name: item.name, mediaType: item.mediaType, size: item.size,
          receiptId: receipt.receiptId ?? receipt.id ?? ''
        };
        next.push(uploading);
      } catch (error) {
        const failed: PendingAttachment = {
          key: item.key, name: item.name, mediaType: item.mediaType, size: item.size,
          error: `上传失败：${(error as Error).message}`
        };
        next.push(failed);
      }
    }
    this.attachments = next;
    this.attachmentBusy = false;
  }

  /** 移除一个待发附件。 */
  private removeAttachment(key: string): void {
    const next: PendingAttachment[] = [];
    for (let i = 0; i < this.attachments.length; i++) {
      if (this.attachments[i].key !== key) next.push(this.attachments[i]);
    }
    this.attachments = next;
  }

  /** 打开 DSH Agent 页（P2-9）。 */
  private openAgent(): void {
    this.agentVisible = true;
    this.agentEditingId = '';
    this.agentError = '';
    this.agentNotice = '';
    void this.refreshAll();
  }

  /** 创建 Agent（每个团队只能一个）。 */
  private async addAgent(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.agentBusy) return;
    this.agentBusy = true;
    this.agentError = '';
    try {
      await api.addAgent();
      await this.refreshAll();
      this.agentNotice = '已创建 DSH Agent';
    } catch (error) {
      this.agentError = `创建失败：${(error as Error).message}`;
    } finally {
      this.agentBusy = false;
    }
  }

  /** 移除 Agent（原生确认）。 */
  private async removeAgent(agentId: string): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.agentBusy) return;
    const confirmed = await this.confirmDestructive('移除 DSH Agent', removePrompt([agentId]), '移除');
    if (!confirmed) return;
    this.agentBusy = true;
    this.agentError = '';
    try {
      const state = await api.removeAgent(agentId);
      this.team = toTeamState(state);
      await this.refreshAll();
      this.agentNotice = '已移除 DSH Agent';
    } catch (error) {
      this.agentError = `移除失败：${(error as Error).message}`;
    } finally {
      this.agentBusy = false;
    }
  }

  /** 开始重命名某个 Agent 会话。 */
  private startAgentRename(conversation: Conversation): void {
    this.agentEditingId = conversation.id;
    this.agentTitleDraft = conversation.name;
    this.agentError = '';
  }

  /** 提交重命名。 */
  private async confirmAgentRename(conversation: Conversation): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.agentBusy) return;
    const problem = titleProblem(this.agentTitleDraft);
    if (problem.length > 0) {
      this.agentError = problem;
      return;
    }
    const agentId = conversation.agentId ?? '';
    if (agentId.length === 0) {
      this.agentError = '这个会话没有所属 Agent';
      return;
    }
    this.agentBusy = true;
    this.agentError = '';
    try {
      await api.agentRename(agentId, conversation.sessionId, this.agentTitleDraft.trim());
      await this.refreshAll();
      this.agentEditingId = '';
      this.agentNotice = '会话已改名';
    } catch (error) {
      this.agentError = `改名失败：${(error as Error).message}`;
    } finally {
      this.agentBusy = false;
    }
  }

  /** 归档某个 Agent 会话（原生确认）。 */
  private async archiveAgentSession(conversation: Conversation): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.agentBusy) return;
    const agentId = conversation.agentId ?? '';
    if (agentId.length === 0) {
      this.agentError = '这个会话没有所属 Agent';
      return;
    }
    const confirmed = await this.confirmDestructive('归档会话', archivePrompt(conversation), '归档');
    if (!confirmed) return;
    this.agentBusy = true;
    this.agentError = '';
    try {
      await api.agentArchive(agentId, conversation.sessionId);
      await this.refreshAll();
      this.agentNotice = `已归档「${conversation.name}」`;
    } catch (error) {
      this.agentError = `归档失败：${(error as Error).message}`;
    } finally {
      this.agentBusy = false;
    }
  }

  /**
   * 连接器主按钮：连接 / 重试 / 断开。
   *
   * 只有"未连接"需要先输入 token；已连接直接断开（原生确认），
   * error 状态走 `connector-retry`。
   */
  private async connectorAction(connector: Connector): Promise<void> {
    if (connector.state === 'ready') {
      const confirmed = await this.confirmDestructive('断开连接器',
        `将断开「${connector.name}」，主机上保存的访问令牌会被删除。`, '断开');
      if (!confirmed) return;
      await this.runConnector(() => this.requireApi().connectorDisconnect(connector.id));
      return;
    }
    if (connector.state === 'error') {
      await this.runConnector(() => this.requireApi().connectorRetry(connector.id));
      return;
    }
    // 未连接：展开 token 输入
    this.connectorTokenFor = connector.id;
    this.connectorTokenDraft = '';
  }

  /** 提交 token 建立连接。 */
  private async submitConnectorToken(connectorId: string): Promise<void> {
    const problem = tokenProblem(this.connectorTokenDraft);
    if (problem.length > 0) {
      this.toast(problem);
      return;
    }
    const ok = await this.runConnector(
      () => this.requireApi().connectorConnect(connectorId, this.connectorTokenDraft.trim()));
    if (ok) {
      this.connectorTokenFor = '';
      this.connectorTokenDraft = '';
      this.toast('连接请求已提交');
    }
  }

  /** 统一执行连接器动作：成功后用返回的列表局部更新，避免整页刷新。 */
  private async runConnector(run: () => Promise<ConnectorList>): Promise<boolean> {
    const api = this.apiClient;
    if (api === undefined || this.connectorBusy) return false;
    this.connectorBusy = true;
    this.toolsError = '';
    try {
      const result = await run();
      this.team.connectors = toConnectors(result.connectors);
      return true;
    } catch (error) {
      this.toolsError = `连接器操作失败：${(error as Error).message}`;
      return false;
    } finally {
      this.connectorBusy = false;
    }
  }

  /** 取客户端；未配对时给一个明确错误，避免各处重复判空。 */
  private requireApi(): MobileClient {
    const api = this.apiClient;
    if (api === undefined) throw new Error('设备尚未配对');
    return api;
  }

  /** 打开通知中心（P3-4）。 */
  private async openNotifications(): Promise<void> {
    this.notificationsVisible = true;
    this.notificationError = '';
    await this.loadNotifications(true);
  }

  /**
   * 读取通知中心。
   *
   * `ringLocal` 为 true 时，对**新出现的未读通知**弹一条本地系统通知：
   * 没有 HMS 推送，App 在前台轮询就是唯一能"提醒"的时机。
   */
  private async loadNotifications(ringLocal: boolean): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.notificationLoading) return;
    this.notificationLoading = true;
    this.notificationError = '';
    try {
      const page = await api.notifications();
      const items = page.items ?? [];
      this.notificationItems = items;
      this.notificationPrefs = page.preferences ?? { enabled: true, categories: [] };
      this.notificationCursor = readThroughCursor(page.cursor);
      if (ringLocal) await this.ringNewNotifications(items);
    } catch (error) {
      this.notificationError = `读取通知失败：${(error as Error).message}`;
    } finally {
      this.notificationLoading = false;
    }
  }

  /** 对新通知弹系统横幅（已弹过的不会重复）。 */
  private async ringNewNotifications(items: NotificationItem[]): Promise<void> {
    const fresh: NotificationItem[] = [];
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (this.notifiedIds.includes(item.id)) continue;
      if (!shouldNotify(item, this.notificationPrefs)) continue;
      fresh.push(item);
    }
    if (fresh.length === 0) return;
    const granted = await LocalNotify.requestPermission();
    if (!granted) return;
    for (let i = 0; i < fresh.length; i++) {
      await LocalNotify.publish(fresh[i]);
      this.notifiedIds.push(fresh[i].id);
    }
  }

  /** 全部标为已读（用主机游标，不能用条数）。 */
  private async markAllNotificationsRead(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.notificationBusy) return;
    if (this.notificationCursor <= 0) return;
    this.notificationBusy = true;
    this.notificationError = '';
    try {
      await api.markNotificationsRead([], this.notificationCursor);
      await this.loadNotifications(false);
    } catch (error) {
      this.notificationError = `标记已读失败：${(error as Error).message}`;
    } finally {
      this.notificationBusy = false;
    }
  }

  /** 点一条通知：标记已读 + 跳到对应会话。 */
  private async openNotification(item: NotificationItem): Promise<void> {
    const api = this.apiClient;
    if (api !== undefined && item.read !== true) {
      try {
        await api.markNotificationsRead([item.id], 0);
      } catch (_error) {
        // 标记失败不阻塞跳转
      }
      LocalNotify.cancel(item.id);
      await this.loadNotifications(false);
    }
    const conversation = this.conversationByAnyId(item.conversationId);
    if (conversation !== undefined) {
      this.notificationsVisible = false;
      this.section = 'chat';
      void this.selectConversation(conversation);
    }
  }

  /** 按会话 id / sessionId / `bot:` 前缀找会话。 */
  private conversationByAnyId(id: string): Conversation | undefined {
    for (let i = 0; i < this.conversations.length; i++) {
      const item = this.conversations[i];
      if (item.id === id || item.sessionId === id) return item;
    }
    const stripped = id.startsWith('bot:') ? id.substring(4) : '';
    if (stripped.length > 0) {
      for (let i = 0; i < this.conversations.length; i++) {
        if (this.conversations[i].id === stripped) return this.conversations[i];
      }
    }
    return undefined;
  }

  /** 保存通知偏好（总开关或类别变化）。 */
  private async saveNotificationPrefs(enabled: boolean, categories: string[]): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.notificationBusy) return;
    this.notificationBusy = true;
    try {
      await api.setNotificationPreferences(enabled, categories);
      this.notificationPrefs = { enabled: enabled, categories: categories };
    } catch (error) {
      this.notificationError = `保存偏好失败：${(error as Error).message}`;
    } finally {
      this.notificationBusy = false;
    }
  }

  private async toggleNotificationEnabled(enabled: boolean): Promise<void> {
    await this.saveNotificationPrefs(enabled, this.notificationPrefs.categories ?? []);
  }

  private async toggleNotificationCategory(kind: string): Promise<void> {
    const current = this.notificationPrefs.categories ?? [];
    const next: string[] = [];
    let removed = false;
    for (let i = 0; i < current.length; i++) {
      if (current[i] === kind) removed = true;
      else next.push(current[i]);
    }
    if (!removed) next.push(kind);
    await this.saveNotificationPrefs(this.notificationPrefs.enabled !== false, next);
  }

  /** 发一条测试通知：验证系统通知权限是否真的通了。 */
  private async testNotification(): Promise<void> {
    const granted = await LocalNotify.requestPermission();
    if (!granted) {
      this.notificationError = '系统通知权限未开启，请在系统设置里允许通知';
      return;
    }
    await LocalNotify.publish({
      id: Math.floor(Date.now() % 2000000000),
      conversationId: '',
      kind: 'test',
      title: 'DS Bot 通知测试',
      body: '看到这条说明本地通知可用'
    });
    this.toast('已发送测试通知');
  }

  /** 打开工具与技能（P2-8）。 */
  private async openTools(): Promise<void> {
    this.toolsVisible = true;
    this.skillDetail = null;
    this.toolsError = '';
    await this.loadTools();
  }

  /** 一次性拉技能 + 插件 + 插件包。 */
  private async loadTools(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.toolsLoading) return;
    this.toolsLoading = true;
    this.toolsError = '';
    try {
      // 技能按当前会话的 cwd 取（不同会话可能在不同目录，可见技能不同）
      const skillsPage = await api.skills(this.selectedId);
      this.skills = skillsPage.skills ?? [];
      this.skillsAvailable = skillsPage.available !== false;
      const pluginsPage = await api.plugins();
      this.plugins = pluginsPage.plugins ?? [];
      this.bundles = pluginsPage.bundles ?? [];
      this.toolsWritable = pluginsPage.writable !== false;
    } catch (error) {
      this.toolsError = `读取失败：${(error as Error).message}`;
    } finally {
      this.toolsLoading = false;
    }
  }

  /** 打开技能全文（宿主只允许 userInvocable 的技能）。 */
  private async openSkillDetail(name: string): Promise<void> {
    const api = this.apiClient;
    if (api === undefined) return;
    this.skillDetailLoading = true;
    this.skillDetail = { name: name };
    try {
      this.skillDetail = await api.skillDetail(name, this.selectedId);
    } catch (error) {
      this.toolsError = `读取技能失败：${(error as Error).message}`;
      this.skillDetail = null;
    } finally {
      this.skillDetailLoading = false;
    }
  }

  /** 切换插件开关。 */
  private async togglePlugin(id: string, enabled: boolean): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.toolsBusy) return;
    this.toolsBusy = true;
    this.toolsError = '';
    try {
      await api.setPluginEnabled(id, enabled);
      await this.loadTools();
    } catch (error) {
      this.toolsError = `操作失败：${(error as Error).message}`;
    } finally {
      this.toolsBusy = false;
    }
  }

  /** 切换插件包开关。 */
  private async toggleBundle(id: string, enabled: boolean): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.toolsBusy) return;
    this.toolsBusy = true;
    this.toolsError = '';
    try {
      await api.setBundleEnabled(id, enabled);
      await this.loadTools();
    } catch (error) {
      this.toolsError = `操作失败：${(error as Error).message}`;
    } finally {
      this.toolsBusy = false;
    }
  }

  /** 从相册选一张图作为 Bot 头像（转 data URL，宿主直接存）。 */
  private async pickBotAvatar(): Promise<void> {
    if (this.botBusy) return;
    this.botError = '';
    try {
      const picked = await AttachmentPicker.pickAvatar();
      hilog.info(0xD5B0, 'BotAvatar',
        'picked mediaType=%{public}s b64Len=%{public}d error=%{public}s',
        picked.mediaType, picked.base64.length, picked.error);
      if (picked.error.length > 0) {
        this.botError = picked.error;
        return;
      }
      if (picked.base64.length === 0) {
        this.toast('没有选择头像');
        return;
      }
      const dataUrl = avatarDataUrl(picked.mediaType, picked.base64);
      hilog.info(0xD5B0, 'BotAvatar', 'dataUrl len=%{public}d', dataUrl.length);
      if (dataUrl.length === 0) {
        this.botError = `头像太大或格式不支持（上限约 ${Math.round(AVATAR_DATA_URL_MAX / 1000)}KB 的 base64）`;
        return;
      }
      const next: BotForm = {
        id: this.botForm.id, name: this.botForm.name, role: this.botForm.role,
        instructions: this.botForm.instructions, model: this.botForm.model,
        effort: this.botForm.effort, avatarImage: dataUrl
      };
      this.botForm = next;
      this.toast('头像已选择，点保存生效');
    } catch (error) {
      const message = (error as Error).message;
      if (message.length > 0 && !message.toLowerCase().includes('cancel')) {
        this.botError = `选择头像失败：${message}`;
      }
    }
  }

  /** 清除 Bot 头像（回到矢量默认）。 */
  private clearBotAvatar(): void {
    this.botForm = {
      id: this.botForm.id, name: this.botForm.name, role: this.botForm.role,
      instructions: this.botForm.instructions, model: this.botForm.model,
      effort: this.botForm.effort, avatarImage: ''
    };
  }

  /** 打开 Bot 管理（P2-5）。 */
  private openBots(): void {
    this.botsVisible = true;
    this.botEditingId = '';
    this.botError = '';
    this.botNotice = '';
    void this.loadEffortNames();
  }

  /**
   * 把所有 Bot 用到的模型的思考档位名字都取一遍。
   *
   * 为什么需要：列表里要显示「高/低」而不是 `high`/`low`，
   * 但档位是按模型返回的，得先知道每个模型有哪些档位。
   * 模型数量很少（通常 1~3 个），一次并发取完即可。
   */
  private async loadEffortNames(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined) return;
    const refs: string[] = [];
    for (let i = 0; i < this.team.bots.length; i++) {
      const ref = this.team.bots[i].model ?? '';
      if (ref.length > 0 && !refs.includes(ref)) refs.push(ref);
    }
    const names: Record<string, string> = {};
    for (let i = 0; i < refs.length; i++) {
      try {
        const payload: EffortsPayload = { ref: refs[i] };
        const result = await api.action<EffortResult>('efforts', payload);
        const options = toEffortOptions(result);
        for (let j = 0; j < options.length; j++) {
          names[options[j].id] = options[j].name;
        }
      } catch (_error) {
        // 某个模型没有档位时忽略
      }
    }
    this.botEffortNames = names;
  }

  /** 进入某个 Bot 的编辑态；同时按它的模型拉一次思考档位。 */
  private async openBotEditor(botId: string): Promise<void> {
    const bot = this.teamBotOf(botId);
    if (bot === undefined) return;
    this.botForm = formOfBot(bot);
    this.botEditingId = botId;
    this.botError = '';
    this.botNotice = '';
    await this.loadBotEfforts(bot.model ?? '');
  }

  /** 按 id 找团队里的 Bot（与 `botOf(conversation)` 不同：那个是按会话找）。 */
  private teamBotOf(botId: string): Bot | undefined {
    for (let i = 0; i < this.team.bots.length; i++) {
      if (this.team.bots[i].id === botId) return this.team.bots[i];
    }
    return undefined;
  }

  /**
   * 按模型拉思考档位（宿主 `efforts {ref}`）。
   *
   * 为什么不复用 `loadEfforts`：那个方法绑定在「当前会话的 Bot」上，
   * 会顺带改输入区的状态；这里只需要一份候选列表，不能复用。
   */
  private async loadBotEfforts(modelRef: string): Promise<void> {
    const api = this.apiClient;
    this.effortOptions = [];
    if (api === undefined || modelRef.length === 0) return;
    this.effortLoading = true;
    try {
      const payload: EffortsPayload = { ref: modelRef };
      const result = await api.action<EffortResult>('efforts', payload);
      this.effortOptions = toEffortOptions(result);
    } catch (_error) {
      this.effortOptions = [];
    } finally {
      this.effortLoading = false;
    }
  }

  /** 切换模型时重新拉档位并清空档位选择（旧档位对新模型无意义）。 */
  private async changeBotForm(form: BotForm): Promise<void> {
    const modelChanged = form.model !== this.botForm.model;
    this.botForm = form;
    if (modelChanged) await this.loadBotEfforts(form.model);
  }

  /** 保存 Bot 修改。 */
  private async saveBot(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.botBusy) return;
    const before = this.teamBotOf(this.botForm.id);
    if (before === undefined) return;
    const patch = buildBotPatch(before, this.botForm);
    if (patch === undefined) {
      this.botNotice = '没有需要保存的修改';
      return;
    }
    this.botBusy = true;
    this.botError = '';
    this.botNotice = '';
    try {
      await api.updateBot(patch);
      await this.refreshAll();
      this.botEditingId = '';
      this.botNotice = '已保存';
    } catch (error) {
      this.botError = `保存失败：${(error as Error).message}`;
    } finally {
      this.botBusy = false;
    }
  }

  /** 复制 Bot。 */
  private async duplicateBot(botId: string): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.botBusy) return;
    this.botBusy = true;
    this.botError = '';
    try {
      await api.duplicateBot(botId);
      await this.refreshAll();
      this.botEditingId = '';
      this.botNotice = '已复制';
    } catch (error) {
      this.botError = `复制失败：${(error as Error).message}`;
    } finally {
      this.botBusy = false;
    }
  }

  /** 删除 Bot（原生确认）。 */
  private async deleteBot(bot: Bot): Promise<void> {
    const api = this.apiClient;
    if (api === undefined) return;
    const confirmed = await this.confirmDestructive('删除 Bot',
      `将删除「${bot.name}」。它与你的聊天记录会一起移除。`, '删除');
    if (!confirmed) return;
    this.botBusy = true;
    this.botError = '';
    try {
      const state = await api.deleteBot(bot.id);
      this.team = toTeamState(state);
      this.botEditingId = '';
      this.botNotice = `已删除「${bot.name}」`;
    } catch (error) {
      this.botError = `删除失败：${(error as Error).message}`;
    } finally {
      this.botBusy = false;
    }
  }

  /** 设置/取消主 Bot。 */
  private async toggleMainBot(botId: string, main: boolean): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.botBusy) return;
    this.botBusy = true;
    this.botError = '';
    try {
      const state = await api.setMain(botId, main, false, '');
      this.team = toTeamState(state);
      this.botNotice = main ? '已设为主 Bot' : '已取消主 Bot';
    } catch (error) {
      this.botError = `操作失败：${(error as Error).message}`;
    } finally {
      this.botBusy = false;
    }
  }

  /** 打开群聊管理（P2-6）。 */
  private openRooms(): void {
    this.roomsVisible = true;
    this.roomEditingId = '';
    this.roomError = '';
    this.roomChanges = [];
  }

  /** 进入某个群的编辑态。 */
  private openRoomEditor(roomId: string): void {
    const room = this.roomOf(roomId);
    if (room === undefined) return;
    this.roomForm = formOfRoom(room);
    this.roomEditingId = roomId;
    this.roomError = '';
  }

  private roomOf(roomId: string): Room | undefined {
    for (let i = 0; i < this.team.rooms.length; i++) {
      if (this.team.rooms[i].id === roomId) return this.team.rooms[i];
    }
    return undefined;
  }

  /**
   * 保存群聊修改（P2-6）。
   *
   * 先算 diff：**没有变化就不发请求**，避免产生无意义的变更记录。
   * 宿主返回 `{ room, changes }`，把 changes 展示给用户比"成功"更有信息量。
   */
  private async saveRoom(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.roomBusy) return;
    const before = this.roomOf(this.roomForm.id);
    if (before === undefined) return;
    const patch = buildRoomPatch(before, this.roomForm);
    if (patch === undefined) {
      this.roomChanges = ['没有需要保存的修改'];
      return;
    }
    this.roomBusy = true;
    this.roomError = '';
    try {
      const result = await api.updateRoom(patch);
      this.roomChanges = translateChanges(result.changes);
      // 宿主只回 { room, changes }，不回整份 state —— 拉一次全量以同步成员/管理员
      await this.refreshAll();
      this.roomEditingId = '';
    } catch (error) {
      this.roomError = `保存失败：${(error as Error).message}`;
    } finally {
      this.roomBusy = false;
    }
  }

  /** 删除群聊（原生确认）。 */
  private async deleteRoom(room: Room): Promise<void> {
    const api = this.apiClient;
    if (api === undefined) return;
    const confirmed = await this.confirmDestructive('删除群聊',
      `将删除「${room.name}」，聊天记录会一起移除。`, '删除');
    if (!confirmed) return;
    this.roomBusy = true;
    this.roomError = '';
    try {
      const state = await api.deleteRoom(room.id);
      this.team = toTeamState(state);
      this.roomEditingId = '';
      this.roomChanges = [`已删除「${room.name}」`];
    } catch (error) {
      this.roomError = `删除失败：${(error as Error).message}`;
    } finally {
      this.roomBusy = false;
    }
  }

  /** 某 Bot 已挂载的能力名（P2-7）。 */
  private attachedCapabilityNames(): string[] {
    for (let i = 0; i < this.team.bots.length; i++) {
      if (this.team.bots[i].id === this.capabilityBotId) {
        return this.team.bots[i].capabilities ?? [];
      }
    }
    return [];
  }

  /** 某 Bot 的能力运行状态。 */
  private capabilityStatusesOf(): Record<string, CapabilityStatus> {
    const all = this.team.capabilityStatuses;
    if (all === undefined) return {};
    const keys = Object.keys(all);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] === this.capabilityBotId) return all[keys[i]];
    }
    return {};
  }

  /** 打开能力库时默认选中第一个 Bot。 */
  private ensureCapabilityBot(): void {
    if (this.capabilityBotId.length === 0 && this.team.bots.length > 0) {
      this.capabilityBotId = this.team.bots[0].id;
    }
  }

  /**
   * 挂载/卸载能力（P2-7）。
   *
   * 宿主 `bot-capability` 直接返回最新 state，所以不需要额外刷新：
   * 用返回的 state 重新投影即可，避免"点了没反应"或列表闪烁。
   */
  private async toggleCapability(name: string, attached: boolean): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.capabilityBusy || this.capabilityBotId.length === 0) return;
    this.capabilityBusy = true;
    this.capabilityError = '';
    try {
      const state = await api.botCapability(this.capabilityBotId, name, attached);
      this.team = toTeamState(state);
    } catch (error) {
      this.capabilityError = `操作失败：${(error as Error).message}`;
    } finally {
      this.capabilityBusy = false;
    }
  }

  /** 打开记忆面板（P2-4）。 */
  private async openMemory(): Promise<void> {
    this.memoryVisible = true;
    this.memoryAskLines = [];
    this.memoryAskError = '';
    const bots = this.memoryBots();
    if (this.memoryBotId.length === 0 && bots.length > 0) this.memoryBotId = bots[0].id;
    await this.loadMemory();
  }

  /** Bot 候选（记忆按 Bot 私有 + 团队共享，所以必须先选 Bot）。 */
  private memoryBots(): MemoryBotOption[] {
    const options: MemoryBotOption[] = [];
    for (let i = 0; i < this.team.bots.length; i++) {
      options.push({ id: this.team.bots[i].id, name: this.team.bots[i].name });
    }
    return options;
  }

  /** 读取记忆（`summarize` 让主机在摘要过期时重新生成）。 */
  private async loadMemory(regenerate: boolean = false): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.memoryLoading || this.memoryBotId.length === 0) return;
    this.memoryLoading = true;
    this.memoryError = '';
    try {
      this.memoryView = await api.memoryView(this.memoryBotId, true, regenerate);
    } catch (error) {
      this.memoryError = `读取记忆失败：${(error as Error).message}`;
    } finally {
      this.memoryLoading = false;
    }
  }

  /** 切换 Bot 后重新读取。 */
  private async selectMemoryBot(botId: string): Promise<void> {
    if (this.memoryBotId === botId) return;
    this.memoryBotId = botId;
    this.memoryAskLines = [];
    this.memoryView = {};
    await this.loadMemory();
  }

  /** 删除一条记忆（原生确认）。 */
  private async forgetMemory(entry: MemoryEntry): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.memoryBotId.length === 0) return;
    const confirmed = await this.confirmDestructive('删除记忆', `将删除这条记忆：${entry.text}`, '删除');
    if (!confirmed) return;
    try {
      this.memoryView = await api.memoryForget(this.memoryBotId, entry.scope, entry.text);
      this.memoryAskLines = [];
    } catch (error) {
      this.memoryError = `删除失败：${(error as Error).message}`;
    }
  }

  /** 用自然语言让主机改记忆。 */
  private async askMemory(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.memoryAsking || this.memoryBotId.length === 0) return;
    const validation = validateAsk(this.memoryAskText);
    this.memoryAskError = validation.error;
    if (!validation.ok) return;
    this.memoryAsking = true;
    try {
      const result = await api.memoryAsk(this.memoryBotId, validation.text);
      if (result.view !== undefined) this.memoryView = result.view;
      const lines: string[] = [];
      if (result.reply.length > 0) lines.push(result.reply);
      const changes = describeChanges(result.changes);
      for (let i = 0; i < changes.length; i++) lines.push(changes[i]);
      this.memoryAskLines = lines;
      this.memoryAskText = '';
    } catch (error) {
      this.memoryAskError = `提交失败：${(error as Error).message}`;
    } finally {
      this.memoryAsking = false;
    }
  }

  /** 打开定时任务面板（P2-3）。 */
  private async openSchedules(): Promise<void> {
    this.schedulesVisible = true;
    // 表单默认值：时区跟设备、目标默认第一个 Bot
    const form: ScheduleForm = {
      target: this.scheduleTargets().length > 0 ? this.scheduleTargets()[0].id : '',
      title: '', prompt: '', kind: 'daily', atLocal: '', time: '09:00',
      weekdays: [], minutes: 60, timeZone: this.deviceTimeZone().length > 0 ? this.deviceTimeZone() : 'UTC'
    };
    this.scheduleForm = form;
    this.scheduleFormError = '';
    await this.loadSchedules();
  }

  /** 读取定时任务列表。 */
  private async loadSchedules(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.schedulesLoading) return;
    this.schedulesLoading = true;
    this.schedulesError = '';
    try {
      const page = await api.schedules();
      this.scheduleTasks = page.tasks ?? [];
      this.schedulesAvailable = page.available !== false;
    } catch (error) {
      this.schedulesError = `读取定时任务失败：${(error as Error).message}`;
    } finally {
      this.schedulesLoading = false;
    }
  }

  /** 目标候选：所有 Bot 与群聊。 */
  private scheduleTargets(): ScheduleTarget[] {
    const targets: ScheduleTarget[] = [];
    for (let i = 0; i < this.team.bots.length; i++) {
      const bot = this.team.bots[i];
      targets.push({ id: bot.id, name: bot.name });
    }
    for (let i = 0; i < this.team.rooms.length; i++) {
      const room = this.team.rooms[i];
      targets.push({ id: room.id, name: room.name });
    }
    return targets;
  }

  /** Bot / 群聊 id → 显示名（给列表用）。 */
  private scheduleBotNames(): Map<string, string> {
    const names = new Map<string, string>();
    for (let i = 0; i < this.team.bots.length; i++) {
      names.set(this.team.bots[i].id, this.team.bots[i].name);
    }
    return names;
  }

  private scheduleRoomNames(): Map<string, string> {
    const names = new Map<string, string>();
    for (let i = 0; i < this.team.rooms.length; i++) {
      names.set(this.team.rooms[i].id, this.team.rooms[i].name);
    }
    return names;
  }

  /** 创建任务：校验已在面板做过，这里只负责提交并刷新列表。 */
  private async createScheduleFromForm(validation: ScheduleValidation): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.scheduleCreating || !validation.ok || validation.when === undefined) return;
    this.scheduleCreating = true;
    this.scheduleFormError = '';
    try {
      const page = await api.createSchedule(
        this.scheduleForm.target, validation.title ?? '', validation.prompt ?? '', validation.when);
      this.scheduleTasks = page.tasks ?? [];
      this.schedulesAvailable = page.available !== false;
      // 创建成功后只清空名称与内容，保留目标/时间形态，便于连续创建
      this.scheduleForm = {
        target: this.scheduleForm.target, title: '', prompt: '',
        kind: this.scheduleForm.kind, atLocal: this.scheduleForm.atLocal,
        time: this.scheduleForm.time, weekdays: this.scheduleForm.weekdays,
        minutes: this.scheduleForm.minutes, timeZone: this.scheduleForm.timeZone
      };
      this.getUIContext().getPromptAction().showToast({ message: '任务已创建', duration: 1800 });
    } catch (error) {
      this.scheduleFormError = `创建失败：${(error as Error).message}`;
    } finally {
      this.scheduleCreating = false;
    }
  }

  /** 删除任务（原生确认）。 */
  private async deleteScheduleTask(task: ScheduleTask): Promise<void> {
    const api = this.apiClient;
    if (api === undefined) return;
    const confirmed = await this.confirmDestructive('删除任务', `将删除「${task.title}」。`, '删除');
    if (!confirmed) return;
    try {
      const page = await api.deleteSchedule(task.sessionId, task.id);
      this.scheduleTasks = page.tasks ?? [];
      this.schedulesAvailable = page.available !== false;
    } catch (error) {
      this.schedulesError = `删除失败：${(error as Error).message}`;
    }
  }

  /**
   * 打开用量面板（P2-2）并加载数据。
   *
   * `timeZone` 传设备时区：主机按该时区切小时桶，不传会按主机时区，
   * 跨时区时「今天的用量」会错位。
   */
  private async openUsage(): Promise<void> {
    this.usageVisible = true;
    await this.loadUsage();
  }

  /** 读取用量；`timeZone` 无法获取时传空串让主机用默认时区。 */
  private async loadUsage(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.usageLoading) return;
    this.usageLoading = true;
    this.usageError = '';
    try {
      this.usageData = await api.usage(this.deviceTimeZone());
    } catch (error) {
      this.usageError = `读取用量失败：${(error as Error).message}`;
    } finally {
      this.usageLoading = false;
    }
  }

  /** 设备时区（IANA 名）。取不到时返回空串，由主机决定。 */
  private deviceTimeZone(): string {
    try {
      return Intl.DateTimeFormat().resolvedOptions().timeZone ?? '';
    } catch (_error) {
      return '';
    }
  }

  /** 拉取历史分段列表（P0-6）。同一会话只拉一次，避免每次开面板都请求。 */
  private async loadParts(force: boolean = false): Promise<void> {
    const api = this.apiClient;
    const conversationId = this.selectedId;
    if (api === undefined || conversationId.length === 0) return;
    if (!force && this.partsLoadedFor === conversationId && this.parts.length > 0) return;
    try {
      const page: PartsPage = await api.parts(conversationId);
      if (this.selectedId !== conversationId) return;
      this.parts = page.parts ?? [];
      this.partsLoadedFor = conversationId;
    } catch (_error) {
      // 主机可能不支持 parts（旧版本）：保持空列表，不打扰用户
      this.parts = [];
      this.partsLoadedFor = conversationId;
    }
  }

  /** 打开分段选择器（原生 bindSheet）。 */
  private async openPartsSheet(): Promise<void> {
    // 只看在线：读取分段是**只读**操作，不该被「Bot 正在工作」挡住
    if (!this.online) return;
    await this.loadParts();
    this.partsVisible = true;
  }

  /**
   * 切到某个历史分段。
   *
   * 用 `earlier(sessionId, cursor)` 拉该分段的消息；同时把实时事件流隔离开——
   * 否则当前分段的新消息会混进历史视图（`applyingLiveEvent` 守卫）。
   */
  private async openPart(part: ConversationPart): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.loadingPart) return;
    if (part.current) {
      this.returnToCurrentPart();
      return;
    }
    this.loadingPart = true;
    this.partsVisible = false;
    try {
      const page: HistoryPage = await api.earlier(part.sessionId, part.cursor);
      this.messages = page.messages ?? [];
      this.viewingPartSessionId = part.sessionId;
      this.viewingPartNumber = part.number;
      this.partCursor = page.cursor ?? '';
      this.partHasEarlier = this.partCursor.length > 0;
      // 历史视图从顶部看：滚到顶
      this.scroller.scrollEdge(Edge.Top);
    } catch (error) {
      this.error = `加载历史分段失败：${(error as Error).message}`;
    } finally {
      this.loadingPart = false;
    }
  }

  /** 在历史分段内继续往前翻。 */
  private async loadEarlierInPart(): Promise<void> {
    const api = this.apiClient;
    if (api === undefined || this.loadingPart || this.partCursor.length === 0) return;
    const sessionId = this.viewingPartSessionId;
    const cursor = this.partCursor;
    if (sessionId.length === 0) return;
    this.loadingPart = true;
    try {
      const page: HistoryPage = await api.earlier(sessionId, cursor);
      if (this.viewingPartSessionId !== sessionId) return;
      this.messages = mergeMessages(this.messages, page.messages ?? []);
      this.partCursor = page.cursor ?? '';
      this.partHasEarlier = this.partCursor.length > 0;
    } catch (error) {
      this.error = `加载更早分段消息失败：${(error as Error).message}`;
    } finally {
      this.loadingPart = false;
    }
  }

  /** 回到当前分段：重新拉最新页并恢复实时流。 */
  private returnToCurrentPart(): void {
    if (this.viewingPartSessionId.length === 0) return;
    this.viewingPartSessionId = '';
    this.viewingPartNumber = 0;
    this.partCursor = '';
    this.partHasEarlier = false;
    this.partsVisible = false;
    // 清空后重新加载最新页（避免历史消息残留混在中间）
    this.messages = [];
    this.historyCursor = '';
    this.hasEarlier = true;
    this.historyInitialized = false;
    void this.loadMessages().then(() => this.scrollToBottom(0));
    void this.loadParts(true);
  }

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
    // P3-1：只有附件、没有文字也可以发（宿主允许 `text` 为空只要 attachments 非空）
    const attachmentIds = this.readyAttachmentIds();
    if (api === undefined || (text.length === 0 && attachmentIds.length === 0)
      || this.selectedId.length === 0 || this.busy) return;
    if (this.attachmentBusy || !allUploaded(this.attachments)) {
      this.toast('附件还在上传，稍等一下');
      return;
    }
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
        text: text,
        attachments: attachmentIds
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
      this.attachments = [];
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
  private conversationAvatar(item: Conversation, size: number = 50) {
    // 头像组合已抽到 view/ConversationAvatarView.ets（叠加算法在 logic/ConversationAvatar.ets）
    ConversationAvatar({ item: item, team: this.team, avatarSize: size, dark: this.dark });
  }

  /** 会话头像是否显示主 Bot 星标。 */
  private isMainAvatar(item: Conversation): boolean {
    return isMainAvatarIn(this.team, item);
  }

  /** 手机首页会话行视图模型。 */
  private mobileHomeEntries(): MobileHomeEntry[] {
    const entries: MobileHomeEntry[] = [];
    for (const item of this.filteredConversations()) {
      entries.push({
        id: item.id,
        conversation: item,
        name: item.name,
        preview: this.conversationPreviews[item.id] ?? item.role ?? (item.kind === 'room' ? '群聊' : 'Bot'),
        time: this.conversationTime(item),
        waiting: item.waiting !== undefined && item.waiting.length > 0
      });
    }
    return entries;
  }

  @Builder
  private mobileHome() {
    // 页面本体已抽到 view/MobileHome.ets
    MobileHome({
      theme: {
        pageBg: this.pageBg(),
        surface: this.surface(),
        ink: this.ink(), muted: this.muted(), line: this.line(),
        fieldBg: this.dark ? '#222C3A' : '#F3F5F9', waitingDot: this.tokens().brand
      },
      entries: this.mobileHomeEntries(),
      team: this.team,
      searchText: this.searchText,
      searching: this.searching,
      heroName: !this.searching && this.mainConversation() !== undefined
        ? (this.mainConversation()?.name ?? 'Chief') : '',
      heroAvatar: this.mainBotAvatarSpec(),
      onOpenSettings: (): void => {
        this.section = 'settings';
        void this.loadAdminData();
      },
      onToggleSearch: (): void => {
        this.searching = !this.searching;
        if (!this.searching) this.searchText = '';
      },
      onSearchChange: (value: string): void => { this.searchText = value; },
      onOpenCreate: (): void => { this.mobileOverlay = 'create-bot'; },
      onSelect: (entry: MobileHomeEntry): void => void this.selectConversation(entry.conversation),
      onOpenHero: (): void => {
        const item = this.mainConversation();
        if (item !== undefined) void this.selectConversation(item);
      },
      onLongPressHero: (): void => { this.showProbe = true; }
    });
  }

  /** 首页主 Bot 大头像参数。 */
  private mainBotAvatarSpec(): AvatarSpec | undefined {
    const bot = this.mainBotOf();
    if (bot === undefined) return undefined;
    return {
      shape: bot.avatar?.shape ?? '',
      color: bot.avatar?.color ?? bot.color ?? '',
      image: this.avatarImageOf(bot),
      main: this.isMainBotId(bot.id),
      live: false
    };
  }

  @Builder
  private appMark(size: number = 42) {
    // 品牌图只有一处实现（view/AppMark.ets）；此前这里仍是「紫底 ✦」旧标记，
    // 导致连接页/聊天空态/启动页与侧栏、桌面图标品牌不一致。
    AppMark({ markSize: size });
  }

  @Builder
  private pairingPage() {
    // 页面本体已抽到 view/PairingPage.ets（配对 JSON 与设备名自持，Index 少两个 @State）
    PairingPage({
      theme: {
        pageBg: this.pageBg(), surface: this.surface(), ink: this.ink(),
        muted: this.muted(), brand: this.tokens().brand, error: this.tokens().danger
      },
      outerBg: this.pageBg(),
      error: this.error,
      busy: this.busy,
      initialJson: this.pairingJson,
      initialDeviceName: this.deviceName,
      onSubmit: (json: string, deviceName: string): void => {
        this.pairingJson = json;
        this.deviceName = deviceName;
        void this.pair();
      },
      onScan: (): void => void this.scanPairingCode(),
      mark: (): void => { this.appMark(76); }
    });
  }
  /** 宽屏左栏的配色与数据（抽到 view/DesktopSidebar.ets）。 */
  private sidebarTheme(): SidebarTheme {
    return {
      surface: this.surface(), ink: this.ink(), muted: this.muted(), line: this.line(),
      pageBg: this.pageBg(),
      selectedBg: this.dark ? '#28344F' : '#EEF2FF',
      chipBg: this.dark ? '#222C3A' : '#F3F5F9',
      brand: this.tokens().brand, waitingDot: '#E89432', online: this.online
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
    Stack() {
      Column()
        .width('100%').height('100%')
        .backgroundColor(this.section === 'chat' ? this.surface() : this.pageBg())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
      if (this.section === 'chat' && this.windowWidth >= 1200) {
        Row() {
          // 测量聊天列的真实宽度（侧栏可拖拽，上下文栏占 286vp，推算不可靠）
          Column() {
            this.chatPanel();
          }
          .layoutWeight(1).height('100%')
          .onAreaChange((_old: Area, area: Area) => {
            this.chatPaneMeasuredWidth = Number(area.width);
          });
          this.workspaceInspector();
        }.width('100%').height('100%');
      } else {
        Column() {
          if (this.section === 'chat') {
            Column() {
              this.chatPanel();
            }
            .width('100%').height('100%')
            .onAreaChange((_old: Area, area: Area) => {
              this.chatPaneMeasuredWidth = Number(area.width);
            });
          } else if (this.section === 'team') {
            this.teamPage();
          } else {
            this.settingsPage();
          }
        }.width('100%').height('100%');
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
        if (target === 'settings') {
          void this.loadAdminData();
          const timer = setTimeout((): void => this.settingsScroller.scrollEdge(Edge.Top), 80);
          this.scrollTimers.push(timer);
        }
      },
      onRefresh: (): void => void this.refreshAll(),
      onSearch: (value: string): void => { this.searchText = value; },
      onToggleHidden: (value: boolean): void => { this.showHidden = value; },
      onSelectConversation: (item: Conversation): void => void this.selectConversation(item)
    });
  }

  /** PC 右侧栏只展示当前上下文，不改变协议层状态。 */
  @Builder
  private workspaceInspector() {
    WorkspaceInspector({
      tokens: this.tokens(),
      title: this.selectedConversation()?.name ?? '选择一个会话',
      bots: this.botCards(),
      busy: this.busy,
      queueCount: this.queue.length,
      activities: this.recentActivities(),
      onOpenBot: (card: BotCard): void => this.openBotCard(card)
    });
  }

  /** 右侧栏与团队页共用的打开 Bot 行为。 */
  /**
   * 点团队页的 Bot 卡片 → 进入**该 Bot 的设置**（P3-1 反馈）。
   *
   * 之前这里直接跳进聊天：用户想改人设/模型/头像时完全找不到入口。
   * 现在统一进 Bot 设置页（名字/角色/人设提示词/模型/思考档位/头像/删除）。
   * 想聊天时从会话列表点 Bot 会话即可。
   */
  private openBotCard(card: BotCard): void {
    this.openBots();
    void this.openBotEditor(card.id);
  }

  /** PC 活动栏使用的轻量投影，最多展示最近四条真实会话活动。 */
  private recentActivities(): string[] {
    const result: string[] = [];
    for (let index = this.messages.length - 1; index >= 0 && result.length < 4; index--) {
      const message = this.messages[index];
      if (message.tool !== undefined) {
        result.push(`${message.tool.name.length > 0 ? message.tool.name : '工具'} · ${message.tool.isError === true ? '执行失败' : message.tool.state === 'running' ? '执行中' : '已完成'}`);
      } else if (message.role === 'user') {
        result.push('你发送了一条消息');
      } else if (message.role === 'assistant') {
        result.push(`${message.author?.name ?? 'Bot'} 更新了回复`);
      }
    }
    return result;
  }



  /** 气泡几何口径（唯一来源，传给 view/MessageBubble.ets）。 */
  private bubbleMetrics(): BubbleMetrics {
    return {
      maxWidth: this.bubbleMaxWidth(),
      contentWidth: this.bubbleContentWidth(),
      padding: this.bubblePadding(),
      windowWidth: this.windowWidth
    };
  }

  @Builder
  private messageBubble(message: Message) {
    // 消息渲染整条链路已组件化（view/MessageBubble.ets → ReasoningBlock / ToolCard / MarkdownView / BotAvatar）
    MessageBubble({
      message: message,
      metrics: this.bubbleMetrics(),
      dark: this.dark,
      authorName: message.role === 'assistant' && message.author?.name !== undefined
        ? message.author.name : '',
      authorAvatar: this.authorSpec(message),
      onLongPress: (item: Message): void => this.openMessageActions(item),
      onCopy: (text: string, toast: string): void => this.copyToClipboard(text, toast),
      loadImage: (attachment: Attachment): Promise<image.PixelMap | undefined> =>
        this.loadMessageImage(attachment, message),
      onOpenAttachment: (attachment: Attachment): void => void this.openAttachmentPreview(attachment, message)
    });
  }

  /**
   * 加载消息内图片（P3-1）。
   *
   * 下载接口要 `conversationId + sessionId + seq` 三件套：
   * `seq` 必须是**该消息自己的序号**，用当前会话的其它值会被主机拒绝。
   * 分段视图（parts）下 sessionId 要取消息自身所属分段，而不是当前实时分段。
   */
  private async loadMessageImage(attachment: Attachment,
    message: Message): Promise<image.PixelMap | undefined> {
    const api = this.apiClient;
    if (api === undefined || this.selectedId.length === 0) return undefined;
    const sessionId = message.sessionId.length > 0
      ? message.sessionId
      : (this.selectedConversation()?.sessionId ?? '');
    // pending / 本地乐观消息没有真实 seq，无法下载
    if (!Number.isFinite(message.seq) || message.seq >= Number.MAX_SAFE_INTEGER) return undefined;
    return ImageLoader.load(api, this.selectedId, sessionId, attachment, message.seq);
  }

  /** 点开图片全屏查看。 */
  private async openAttachmentPreview(attachment: Attachment, message: Message): Promise<void> {
    const pixel = await this.loadMessageImage(attachment, message);
    if (pixel === undefined) {
      this.toast('图片还没有加载好');
      return;
    }
    this.previewPixel = pixel;
    this.previewVisible = true;
  }

  /** 群聊作者头像参数（需要 team 查找，因此在父组件解析）。 */
  private authorSpec(message: Message): AvatarSpec | undefined {
    if (message.author === undefined || message.author.id === undefined) return undefined;
    const bot = this.botById(message.author.id);
    if (bot === undefined) return undefined;
    return {
      shape: bot.avatar?.shape ?? '',
      color: bot.avatar?.color ?? bot.color ?? '',
      image: this.avatarImageOf(bot),
      main: this.isMainBotId(bot.id),
      live: false
    };
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

  /**
   * 空会话占位。
   *
   * **必须是 `@Builder` 方法，不能写成 `@BuilderParam` 里的内联 UI**：
   * `@BuilderParam` 收到内联 `Text(...)` 时，那部分不会被编译成 UI 创建代码，
   * 运行时 `Text()` 返回 undefined，接着 `.fontSize(...)` 抛
   * `TypeError: Cannot read property fontSize of undefined` 并**直接杀掉应用**。
   * 这个崩溃只在「消息为空」时触发——模拟器上消息来得快，未渲染空态，
   * 因此长期没被发现（2026-10-17 真机点会话必崩才暴露）。
   */
  @Builder
  private emptyChatState() {
    Text('还没有消息，向这个 Bot 打个招呼吧。')
      .fontSize(14).fontColor(this.muted()).padding(30).width('100%').textAlign(TextAlign.Center);
  }

  /** 历史分段：入口按钮（仅在主机返回多个 part 时出现）。 */
  @Builder
  private partsEntry() {
    if (this.parts.length > 1) {
      Row() {
        Button(this.loadingPart ? '正在读取分段…' : `历史分段（${this.parts.length}）`)
          .height(36).borderRadius(18).fontSize(12)
          .backgroundColor(this.surface()).fontColor(this.muted())
          .border({ width: 1, color: this.line() })
          .enabled(this.online)
          .onClick(() => void this.openPartsSheet());
      }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 8, bottom: 2 });
    }
  }

  /**
   * 正在查看历史分段时的横幅。
   *
   * 必须显眼：此时**收不到当前分段的新消息**（事件流被隔离），
   * 也不允许发送，用户需要知道自己在看历史、并能一键回到当前。
   */
  @Builder
  private viewingPartBanner() {
    if (this.viewingPartSessionId.length > 0) {
      Row({ space: 10 }) {
        Text(`正在查看历史分段 · 第 ${this.viewingPartNumber} 段`)
          .fontSize(13).fontColor(this.dark ? '#F0C27B' : '#8A5A00').layoutWeight(1);
        Button('回到当前')
          .height(32).borderRadius(16).fontSize(12)
          .backgroundColor(this.tokens().brand).fontColor('#FFFFFF')
          .onClick(() => this.returnToCurrentPart());
      }
      .width('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(this.dark ? '#3A2F1C' : '#FFF6E5');
    }
  }

  /** 分段选择器（原生 bindSheet）。 */
  @Builder
  private partsSheet() {
    Column({ space: 12 }) {
      Text('历史分段').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.ink()).width('100%');
      Text('长会话会被主机切成多个分段。选择较早的分段可查看历史，当前分段接收实时消息。')
        .fontSize(13).fontColor(this.muted()).width('100%');
      if (this.parts.length === 0) {
        Text('当前会话没有历史分段。').fontSize(14).fontColor(this.muted()).width('100%').padding(16);
      } else {
        Scroll() {
          Column() {
            ForEach(this.parts, (part: ConversationPart) => {
              Row({ space: 12 }) {
                Text(`第 ${part.number} 段`).fontSize(15).fontColor(this.ink());
                if (part.current) {
                  Text('当前').fontSize(11).fontColor(this.tokens().brand)
                    .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                    .backgroundColor(this.dark ? '#25304F' : '#EEF2FF').borderRadius(8);
                }
                Blank();
                Text(this.partTimeRange(part)).fontSize(12).fontColor(this.muted());
                if (part.sessionId === this.viewingPartSessionId) {
                  Text('· 查看中').fontSize(12).fontColor(this.tokens().brand);
                }
              }
              .width('100%').height(56).padding({ left: 8, right: 8 })
              .onClick(() => void this.openPart(part));
              Divider().color(this.line());
            }, (part: ConversationPart) => part.sessionId);
          }.width('100%');
        }
        // 不撑满整个 sheet：MEDIUM 高度下 `layoutWeight(1)` 会把 3 行内容
        // 挤到面板下半部分（2026-10-17 截图发现中间大片空白）
        .width('100%').constraintSize({ maxHeight: 420 }).scrollBar(BarState.Auto);
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 16 })
    .justifyContent(FlexAlign.Start)
    .backgroundColor(this.surface());
  }

  /**
   * 消息列表顶部的组合区：历史分段横幅 → 分段入口 → 加载更早。
   *
   * 作为 `ChatMessageList` 的 `earlierButton` 插槽注入（该插槽本就渲染在列表最上方）。
   */
  @Builder
  private chatListTop() {
    this.viewingPartBanner();
    this.partsEntry();
    this.earlierMessagesButton();
  }

  @Builder
  private earlierMessagesButton() {
    // 查看历史分段时，翻页走该分段自己的 cursor；否则走当前分段
    // 注意：`@Builder` 内不能写裸 `return;`，只能用 if/else 表达分支
    if (this.viewingPartSessionId.length > 0) {
      if (this.partHasEarlier) {
        Row() {
          Button(this.loadingPart ? '正在加载更早消息…' : '加载更早消息')
            .height(40).borderRadius(20).fontSize(13)
            .backgroundColor(this.surface()).fontColor(this.muted())
            .border({ width: 1, color: this.line() })
            .enabled(!this.loadingPart && this.online)
            .onClick(() => void this.loadEarlierInPart());
        }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 10, bottom: 4 });
      }
    } else {
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
          brand: this.tokens().brand
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
          image: this.avatarImageOf(bot),
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
            brand: this.tokens().brand, danger: this.tokens().danger
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
  /**
   * 会话级菜单（P2-9）：导出为 Markdown / JSON、置顶、隐藏。
   *
   * 原来这个 `⋯` 按钮只弹一句 toast 说明"去设置里管理"，等于没有功能。
   * 导出走剪贴板而不是写文件：手机上"复制走"比"存到某个目录再找不到"更实用，
   * 且不需要申请文件权限。
   */
  private openConversationActions(): void {
    const conversation = this.selectedConversation();
    if (conversation === undefined) return;
    const actions: MessageAction[] = [];
    const snapshot = this.messages;
    actions.push({
      label: '导出为 Markdown',
      run: () => this.exportCurrent('markdown', snapshot, conversation.name)
    });
    actions.push({
      label: '导出为 JSON',
      run: () => this.exportCurrent('json', snapshot, conversation.name)
    });
    actions.push({
      label: conversation.pinned === true ? '取消置顶' : '置顶会话',
      run: () => void this.setConversationFlag(conversation, !(conversation.pinned === true), undefined)
    });
    actions.push({
      label: '隐藏会话',
      run: () => void this.setConversationFlag(conversation, undefined, true)
    });
    // **复用消息操作面板**：同一个节点上挂多个 `bindSheet` 只有第一个生效
    //（之前已经踩过一次），所以会话级菜单也用这一套状态。
    this.messageActions = actions;
    this.actionTargetId = '';
    this.messageActionsVisible = actions.length > 0;
  }

  /** 导出并复制到剪贴板（附带文件名提示，方便用户知道存成什么名字）。 */
  private exportCurrent(format: string, messages: Message[], title: string): void {
    if (messages.length === 0) {
      this.toast('没有可导出的消息');
      return;
    }
    const now = Date.now();
    const text = exportConversation(messages, title, format, now);
    const fileName = exportFileName(title, format, now);
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.toast(`已复制 ${messages.length} 条消息（${fileName}）`);
    } catch (_error) {
      this.toast('导出失败');
    }
  }

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
    const available = this.chatPaneWidth() - 16 * 2 - this.bubblePadding() * 2;
    if (available <= 160) return 160;
    return this.windowWidth >= 840 && available > 720 ? 720 : available;
  }

  /**
   * 聊天内容区实际可用宽度（vp）。
   *
   * **必须扣掉宽屏侧栏**：侧栏由原生 `SideBarContainer` 决定（用户可拖拽），
   * 若仍按 `windowWidth` 推导，气泡会比聊天面板还宽。
   * 2026-10-16 折叠屏实测：气泡 1089px、面板仅 916px，右侧越出 44px 且贴着屏幕边。
   */
  private chatPaneWidth(): number {
    // 优先用**测量值**（见 `chatPaneMeasuredWidth` 的说明）
    if (this.chatPaneMeasuredWidth > 0) return this.chatPaneMeasuredWidth;
    if (this.windowWidth < 600) return this.windowWidth;
    const inspector = this.windowWidth >= 1200 ? 286 : 0;
    return this.windowWidth - this.sideBarWidth - inspector;
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
                Text('@').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.tokens().brand);
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
    if (this.composerReferences().length > 0 || this.effortOptions.length > 0 || this.effortLoading
      || this.attachments.length > 0 || this.attachmentError.length > 0) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        // P3-1：待发附件（名称 + 体积 + 状态 + 移除）
        ForEach(this.attachments, (item: PendingAttachment) => {
          Row({ space: 6 }) {
            if (item.error !== undefined && item.error !== '') {
              Text('!').fontSize(14).fontColor(this.tokens().danger);
            } else if (item.receiptId === undefined || item.receiptId === '') {
              LoadingProgress().width(14).height(14).color(this.tokens().brand);
            } else {
              Text(item.mediaType.startsWith('image/') ? '图' : '文').fontSize(13)
                .fontColor(this.tokens().brand);
            }
            Text(item.name).fontSize(13).fontColor(this.ink()).maxLines(1)
              .constraintSize({ maxWidth: 130 });
            Text(formatSize(item.size)).fontSize(11).fontColor(this.muted());
            Button('×').width(30).height(30).borderRadius(15).fontSize(16)
              .backgroundColor(Color.Transparent).fontColor(this.muted())
              .onClick(() => this.removeAttachment(item.key));
          }
          .height(36).padding({ left: 12, right: 4 }).margin({ right: 8, bottom: 6 })
          .backgroundColor(this.surface()).borderRadius(18)
          .border({ width: 1, color: this.line() });
        }, (item: PendingAttachment) => `${item.key}#${item.receiptId ?? ''}#${item.error ?? ''}`);
        if (this.attachmentError.length > 0) {
          Text(this.attachmentError).fontSize(12).fontColor(this.tokens().danger)
            .margin({ right: 8, bottom: 6 }).maxLines(2);
        }
        ForEach(this.composerReferences(), (reference: ChatReference) => {
          Row({ space: 6 }) {
            Text('◫').fontSize(14).fontColor(this.tokens().brand);
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
            LoadingProgress().width(16).height(16).color(this.tokens().brand);
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
          LoadingProgress().width(22).height(22).color(this.tokens().brand);
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
                Text('添加').fontSize(13).fontColor(this.tokens().brand);
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
        }
        // 不撑满整个 sheet：MEDIUM 高度下 `layoutWeight(1)` 会把 3 行内容
        // 挤到面板下半部分（2026-10-17 截图发现中间大片空白）
        .width('100%').constraintSize({ maxHeight: 420 }).scrollBar(BarState.Auto);
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 16 })
    .justifyContent(FlexAlign.Start)
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
            .fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.ink()).maxLines(1);
          Text(this.streamLabel()).fontSize(11)
            .fontColor(this.streamStatus === 'connected' ? '#24B47E' : this.muted());
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        if (this.busy) {
          Button('停止').height(34).borderRadius(10).backgroundColor(this.tokens().dangerBg).fontColor(this.tokens().danger)
            .onClick(() => void this.stop());
        } else if (this.selectedConversation() !== undefined) {
          Button(this.selectedConversation()?.pinned ? '取消置顶' : '置顶')
            .height(34).borderRadius(10).fontSize(12).backgroundColor(this.pageBg()).fontColor(this.ink())
            .onClick(() => {
              const item = this.selectedConversation();
              if (item !== undefined) void this.setConversationFlag(item, !item.pinned, undefined);
            });
          Button(this.selectedConversation()?.hidden ? '恢复' : '隐藏')
            .height(34).borderRadius(10).fontSize(12).backgroundColor(this.pageBg()).fontColor(this.ink())
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
        ChatMessageList({
          scroller: this.scroller,
          messages: this.messages,
          busy: this.busy,
          compact: false,
          spinnerColor: this.tokens().brand,
          muted: this.muted(),
          desktopInset: true,
          earlierButton: (): void => { this.chatListTop(); },
          questions: (): void => {
            if (this.conversationQuestions().length > 0) {
              this.chatQuestions();
            }
          },
          emptyState: (): void => { this.emptyChatState(); },
          messageItem: (message: Message): void => { this.messageBubble(message); }
        })
        this.groupProgress();
        Column({ space: 6 }) {
          this.mentionMenu();
          this.composerAccessories();
        }.width('100%').padding({ left: 14, right: 14 });
        ChatComposer({
          tokens: {
            fieldBg: this.pageBg(), ink: this.ink(), barBg: this.surface(),
            line: this.line(), sendBg: this.tokens().brand
          },
          placeholder: '发送消息…',
          text: this.composerText(),
          maxLength: this.composerMaxLength(),
          controller: this.composerController,
          // P3-1：只有附件没有文字也能发（宿主允许 text 为空）
          canSend: !this.busy && (this.draft.trim().length > 0 || this.readyAttachmentIds().length > 0)
            && this.online && this.viewingPartSessionId.length === 0,
          showAttach: true,
          mobileSendStyle: false,
          horizontalPadding: 14,
          showTopBorder: true,
          attachMenu: this.composerMenu(),
          onTextChange: (value: string): void => this.setComposerText(value),
          onEditChange: (editing: boolean): void => { this.composerFocused = editing; },
          onSelectionChange: (start: number, end: number): void => {
            this.composerSelectionStart = start;
            this.composerSelectionEnd = end;
          },
          onSend: (): void => void this.send()
        })
        .backgroundColor(this.surface()).border({ width: { top: 1 }, color: this.line() });
      }
    }
    .layoutWeight(1).height('100%').backgroundColor(this.pageBg())
    // 分段 sheet 挂在**聊天面板节点**上：与根节点的另两个 bindSheet 分开，
    // 否则同一节点多个 bindSheet 会互相覆盖（2026-10-17 实测：根节点三连只生效最后一个）
    .bindSheet(this.partsVisible, this.partsSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: true,
      backgroundColor: this.surface(),
      onDisappear: (): void => { this.partsVisible = false; }
    });
  }

  @Builder
  private mobileChatPanel() {
    Column() {
      Row({ space: 10 }) {
        Button() {
          Image(this.dark ? $r('app.media.ic_back_light') : $r('app.media.ic_back')).width(22).height(22);
        }
        .width(44).height(44).borderRadius(12).backgroundColor(this.surface())
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
        .height(44).padding({ left: 10, right: 14 }).borderRadius(12)
        .backgroundColor(this.surface()).border({ width: 1, color: this.line() })
        .layoutWeight(1);
        Button() {
          Image(this.dark ? $r('app.media.ic_more_light') : $r('app.media.ic_more')).width(22).height(22);
        }
        .width(44).height(44).borderRadius(12).backgroundColor(this.surface())
        .border({ width: 1, color: this.line() })
        .onClick(() => this.openConversationActions());
      }.width('100%').height(68).padding({ left: 16, right: 16, top: 12, bottom: 10 })
        .backgroundColor(this.surface()).border({ width: { bottom: 1 }, color: this.line() });
      if (this.conversationApprovals().length > 0) {
        this.chatApprovals();
      }
      ChatMessageList({
        scroller: this.scroller,
        messages: this.messages,
        busy: this.busy,
        compact: true,
        spinnerColor: this.tokens().brand,
        muted: this.muted(),
        desktopInset: false,
        earlierButton: (): void => { this.chatListTop(); },
        questions: (): void => {
          if (this.conversationQuestions().length > 0) {
            this.chatQuestions();
          }
        },
        emptyState: (): void => { this.emptyChatState(); },
        messageItem: (message: Message): void => { this.messageBubble(message); }
      })
      this.groupProgress();
      if (this.queue.length > 0) {
        this.queuePanel();
      }
      Column({ space: 6 }) {
        this.mentionMenu();
        this.composerAccessories();
      }.width('100%').padding({ left: 20, right: 20 });
      ChatComposer({
        tokens: {
          fieldBg: this.surface(), ink: this.ink(),
          barBg: this.surface(), line: this.line(), sendBg: this.tokens().brand
        },
        placeholder: `向 ${this.selectedConversation()?.name ?? 'Bot'} 提问`,
        text: this.composerText(),
        maxLength: this.composerMaxLength(),
        controller: this.composerController,
        // P3-1：只有附件没有文字也能发
        canSend: !this.busy && (this.draft.trim().length > 0 || this.readyAttachmentIds().length > 0)
          && this.online && this.viewingPartSessionId.length === 0,
        showAttach: true,
        attachIcon: this.dark ? $r('app.media.ic_plus_light') : $r('app.media.ic_plus'),
        attachBordered: true,
        attachBg: this.surface(),
        mobileSendStyle: true,
        horizontalPadding: 20,
        showTopBorder: false,
        attachMenu: this.composerMenu(),
        onTextChange: (value: string): void => this.setComposerText(value),
        onEditChange: (editing: boolean): void => { this.composerFocused = editing; },
        onSelectionChange: (start: number, end: number): void => {
          this.composerSelectionStart = start;
          this.composerSelectionEnd = end;
        },
        onSend: (): void => void this.send()
      })
      .width('100%').backgroundColor(this.surface());
    }
    .width('100%').height('100%').backgroundColor(this.pageBg())
    // 消息/会话操作面板挂在**聊天面板节点**上。
    // 根节点上已有 `bindPopup` + `referencePicker` 的 `bindSheet`，
    // ArkUI 同一个节点多个 `bindSheet` 只生效最后一个（2026-10-18 真机实测三连只剩最后一个），
    // 所以挂到这里的独立节点上。
    .bindSheet(this.messageActionsVisible, this.messageSheetBuilder(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: this.surface(),
      onDisappear: (): void => this.closeMessageActions()
    });
  }

  /** Bot 卡片视图模型（父组件解析，保证头像只有 BotAvatar 一处实现）。 */
  /**
   * 主机端 Bot 头像（P3-1 反馈）。
   *
   * 宿主把头像存成 **data URL 字符串**（`data:image/png;base64,…`，见 `cleanAvatar`），
   * ArkUI 的 `Image` 可以直接吃这种字符串。
   * 之前三处 `avatarSpec` 都硬编码 `image: ''`，等于**把主机头像丢掉了**，
   * 所有 Bot 都显示成默认矢量头像。
   */
  private avatarImageOf(bot: Bot | undefined): string {
    if (bot === undefined) return '';
    const image = bot.avatar?.image;
    return image === undefined ? '' : image;
  }

  private botCards(): BotCard[] {
    const cards: BotCard[] = [];
    for (const bot of this.team.bots) {
      cards.push({
        id: bot.id,
        name: bot.name,
        role: bot.role ?? 'Bot',
        avatar: {
          shape: bot.avatar?.shape ?? '',
          color: bot.avatar?.color ?? bot.color ?? '',
          image: this.avatarImageOf(bot),
          main: this.isMainBotId(bot.id),
          live: bot.waiting === true
        },
        main: this.isMainBotId(bot.id),
        waiting: bot.waiting === true
      });
    }
    return cards;
  }

  @Builder
  private teamPage() {
    // 页面本体已抽到 view/TeamPage.ets
    TeamPage({
      theme: {
        pageBg: this.pageBg(), surface: this.surface(), ink: this.ink(), muted: this.muted(),
        fieldBg: this.dark ? '#222C3A' : '#F3F5F9', brand: this.tokens().brand, onBrand: '#FFFFFF',
        warning: this.tokens().warning, warningBg: this.tokens().warningBg, chipBorder: this.line()
      },
      compact: this.windowWidth < 600,
      columnsTemplate: this.teamColumnsTemplate(),
      bots: this.botCards(),
      roomCount: this.team.rooms.length,
      readOnlyNotice: this.team.readOnly ?? '',
      newBotName: this.newBotName,
      newGroupName: this.newGroupName,
      selectedMemberIds: this.selectedMembers,
      busy: this.busy,
      online: this.online,
      statusLabel: this.online ? '已连接' : '离线',
      statusOnline: this.online,
      onClose: (): void => { this.section = 'chat'; },
      onOpenBot: (card: BotCard): void => this.openBotCard(card),
      onBotNameChange: (value: string): void => { this.newBotName = value; },
      onCreateBot: (): void => void this.createBot(),
      onToggleMember: (botId: string): void => this.toggleMember(botId),
      onGroupNameChange: (value: string): void => { this.newGroupName = value; },
      onCreateGroup: (): void => void this.createGroup()
    });
  }

  /** 团队卡片按实际内容区宽度分栏，不能用整窗宽度（折叠屏左栏会占掉近一半）。 */
  private teamColumnsTemplate(): string {
    if (this.windowWidth < 600) return '1fr 1fr';
    const contentWidth = this.windowWidth - this.sideBarWidth;
    if (contentWidth >= 900) return '1fr 1fr 1fr';
    if (contentWidth >= 560) return '1fr 1fr';
    return '1fr';
  }

  @Builder
  private settingsPage() {
    // 宽屏（平板/折叠屏展开）同样用 `settingsBody`：
    // 之前这里是独立实现，新增入口两边都要改，折叠屏实测出现"够不到"的问题。
    Column() {
      Column() {
        this.settingsBody();
      }
      .width('100%')
      // 内容区限宽并居中：1700vp 的窗口把设置项拉满会很难读
      .constraintSize({ maxWidth: 760 })
    }
    .width('100%').height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.pageBg());
  }

  /**
   * 设置页的**唯一实现**（P2-1 收尾）。
   *
   * 之前手机与宽屏各写一份：手机用 `view/SettingsPage.ets`，
   * 宽屏是 `Index.settingsPage()` 内联的一大段（只有连接/外观/审批/设备）。
   * 结果是**每次新增功能入口都要改两处**——2026-10-18 折叠屏实测时，
   * 用量/定时/记忆/群聊/Bot/Agent/工具 在宽屏全都够不到。
   *
   * 现在两边都调这一个 builder：手机直接铺满，宽屏套一层最大宽度居中。
   */
  @Builder
  private settingsBody() {
    SettingsPage({
      view: {
        serverName: this.serverName,
        serverUrl: this.profile?.serverUrl ?? '',
        dark: this.dark,
        approvals: this.approvals,
        devices: this.devices,
        currentDeviceId: this.profile?.session.deviceId ?? ''
      } as SettingsView,
      tokens: {
        pageBg: this.pageBg(),
        rowBg: this.surface(),
        ink: this.ink(), muted: this.muted(), line: this.tokens().line,
        dangerBg: this.tokens().dangerBg, danger: this.tokens().danger, brand: this.tokens().brand
      } as SettingsTheme,
      onClose: (): void => { this.section = 'chat'; },
      onToggleDark: (value: boolean): void => { this.toggleDark(value); },
      onOpenTools: (): void => void this.openTools(),
      onOpenTeam: (): void => { this.section = 'team'; },
      onOpenProbe: (): void => { this.showProbe = true; },
      onRefresh: (): void => void this.refreshAll(),
      onClearCache: (): void => void this.clearLocalCache(),
      onLogout: (): void => void this.logout(),
      onResolveApproval: (approvalId: string, decision: string): void =>
        void this.resolveApproval(approvalId, decision),
      onRevokeDevice: (device: DeviceListItem): void => void this.revokeDevice(device),
      onOpenUsage: (): void => { void this.openUsage(); },
      onOpenSchedules: (): void => { void this.openSchedules(); },
      onOpenMemory: (): void => { void this.openMemory(); },
      onOpenRooms: (): void => this.openRooms(),
      onOpenBots: (): void => this.openBots(),
      onOpenAgent: (): void => this.openAgent(),
      onOpenNotifications: (): void => void this.openNotifications(),
      notificationUnread: unreadCount(filterByPreferences(this.notificationItems, this.notificationPrefs))
    });
  }

  @Builder
  private mobileSettingsPage() {
    // 手机整页铺满（设置页本体已抽到 view/SettingsPage.ets）
    this.settingsBody();
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
    // 页面本体已抽到 view/MobileCreateBotPage.ets
    MobileCreateBotPage({
      ink: this.ink(), muted: this.muted(),
      pageBg: this.pageBg(),
      fieldBg: this.dark ? '#222C3A' : '#F3F5F9',
      cardBg: this.surface(), edgeColor: this.line(), brand: this.tokens().brand,
      title: '创建新 Bot',
      namePlaceholder: '为 Bot 取个名字',
      name: this.newBotName,
      shape: this.newBotShape,
      color: this.newBotColor,
      shapes: this.avatarShapes(),
      colors: this.avatarColors(),
      busy: this.busy,
      online: this.online,
      onClose: (): void => { this.mobileOverlay = ''; },
      onNameChange: (value: string): void => { this.newBotName = value; },
      onShapeChange: (value: string): void => { this.newBotShape = value; },
      onColorChange: (value: string): void => { this.newBotColor = value; },
      onSubmit: (): void => void this.createBot(),
      preview: (): void => { this.botAvatarPreview(126); }
    });
  }
  private secondaryTokens(): SecondaryPageTheme {
    return {
      pageBg: this.pageBg(),
      rowBg: this.surface(),
      chipBg: this.surface(),
      chipLine: this.line(),
      ink: this.ink(), muted: this.muted(), line: this.line(),
      brand: this.tokens().brand, brandSoft: this.dark ? '#25304F' : '#EEF2FF',
      danger: this.tokens().danger, dangerBg: this.tokens().dangerBg
    };
  }

  /** DSH Agent 整页（P2-9）。 */
  @Builder
  private agentPageView() {
    AgentPanel({
      theme: this.secondaryTokens(),
      conversations: this.conversations,
      editingId: this.agentEditingId,
      titleDraft: this.agentTitleDraft,
      busy: this.agentBusy,
      error: this.agentError,
      notice: this.agentNotice,
      onClose: (): void => { this.agentVisible = false; },
      onRefresh: (): void => void this.refreshAll(),
      onAddAgent: (): void => void this.addAgent(),
      onRemoveAgent: (agentId: string): void => void this.removeAgent(agentId),
      onStartRename: (conversation: Conversation): void => this.startAgentRename(conversation),
      onTitleChange: (value: string): void => { this.agentTitleDraft = value; },
      onConfirmRename: (conversation: Conversation): void => void this.confirmAgentRename(conversation),
      onCancelRename: (): void => { this.agentEditingId = ''; },
      onArchive: (conversation: Conversation): void => void this.archiveAgentSession(conversation)
    });
  }

  /** 通知中心整页（P3-4）。 */
  @Builder
  private notificationsPageView() {
    NotificationsPanel({
      theme: this.secondaryTokens(),
      items: filterByPreferences(this.notificationItems, this.notificationPrefs),
      preferences: this.notificationPrefs,
      loading: this.notificationLoading,
      busy: this.notificationBusy,
      error: this.notificationError,
      onClose: (): void => { this.notificationsVisible = false; },
      onRefresh: (): void => void this.loadNotifications(false),
      onMarkAllRead: (): void => void this.markAllNotificationsRead(),
      onOpenItem: (item: NotificationItem): void => void this.openNotification(item),
      onToggleEnabled: (enabled: boolean): void => void this.toggleNotificationEnabled(enabled),
      onToggleCategory: (kind: string): void => void this.toggleNotificationCategory(kind),
      onTestNotification: (): void => void this.testNotification()
    });
  }

  /** 工具与技能整页（P2-8）。 */
  @Builder
  private toolsPageView() {
    ToolsSkillsPanel({
      theme: this.secondaryTokens(),
      skills: this.skills,
      skillsAvailable: this.skillsAvailable,
      plugins: this.plugins,
      bundles: this.bundles,
      connectors: this.team.connectors ?? [],
      tokenFor: this.connectorTokenFor,
      tokenDraft: this.connectorTokenDraft,
      connectorBusy: this.connectorBusy,
      writable: this.toolsWritable,
      loading: this.toolsLoading,
      error: this.toolsError,
      detail: this.skillDetail,
      detailLoading: this.skillDetailLoading,
      busy: this.toolsBusy,
      onClose: (): void => { this.toolsVisible = false; },
      onRefresh: (): void => void this.loadTools(),
      onOpenSkill: (name: string): void => void this.openSkillDetail(name),
      onCloseDetail: (): void => { this.skillDetail = null; },
      onTogglePlugin: (id: string, enabled: boolean): void => void this.togglePlugin(id, enabled),
      onToggleBundle: (id: string, enabled: boolean): void => void this.toggleBundle(id, enabled),
      onOpenCapabilities: (): void => {
        this.ensureCapabilityBot();
        this.capabilitiesVisible = true;
      },
      onConnectorAction: (connector: Connector): void => void this.connectorAction(connector),
      onTokenChange: (value: string): void => { this.connectorTokenDraft = value; },
      onSubmitToken: (id: string): void => void this.submitConnectorToken(id),
      onCancelToken: (): void => { this.connectorTokenFor = ''; this.connectorTokenDraft = ''; }
    });
  }

  /** Bot 管理整页（P2-5）。 */
  @Builder
  private botsPageView() {
    BotManagePanel({
      theme: this.secondaryTokens(),
      bots: this.team.bots,
      mainBotIds: this.team.mainBotIds ?? [],
      models: this.team.models,
      efforts: this.effortOptions,
      effortNames: this.botEffortNames,
      effortLoading: this.effortLoading,
      editingId: this.botEditingId,
      form: this.botForm,
      busy: this.botBusy,
      error: this.botError,
      notice: this.botNotice,
      onClose: (): void => { this.botsVisible = false; },
      onRefresh: (): void => void this.refreshAll(),
      onOpenBot: (botId: string): void => void this.openBotEditor(botId),
      onBackToList: (): void => { this.botEditingId = ''; },
      onFormChange: (form: BotForm): void => void this.changeBotForm(form),
      onSave: (): void => void this.saveBot(),
      onDuplicate: (botId: string): void => void this.duplicateBot(botId),
      onDelete: (bot: Bot): void => void this.deleteBot(bot),
      onToggleMain: (botId: string, main: boolean): void => void this.toggleMainBot(botId, main),
      onPickAvatar: (): void => void this.pickBotAvatar(),
      onClearAvatar: (): void => this.clearBotAvatar()
    });
  }

  /** 群聊管理整页（P2-6）。 */
  @Builder
  private roomsPageView() {
    RoomManagePanel({
      theme: this.secondaryTokens(),
      rooms: this.team.rooms,
      bots: this.team.bots,
      editingId: this.roomEditingId,
      form: this.roomForm,
      busy: this.roomBusy,
      error: this.roomError,
      changes: this.roomChanges,
      readOnly: this.team.readOnly ?? '',
      onClose: (): void => { this.roomsVisible = false; },
      onRefresh: (): void => void this.refreshAll(),
      onOpenRoom: (roomId: string): void => this.openRoomEditor(roomId),
      onBackToList: (): void => { this.roomEditingId = ''; },
      onFormChange: (form: RoomForm): void => { this.roomForm = form; },
      onSave: (): void => void this.saveRoom(),
      onDelete: (room: Room): void => void this.deleteRoom(room)
    });
  }

  /** 记忆整页（P2-4）。 */
  @Builder
  private memoryPageView() {
    MemoryPanel({
      theme: this.secondaryTokens(),
      view: this.memoryView,
      botId: this.memoryBotId,
      bots: this.memoryBots(),
      loading: this.memoryLoading,
      error: this.memoryError,
      askText: this.memoryAskText,
      asking: this.memoryAsking,
      askError: this.memoryAskError,
      askResultLines: this.memoryAskLines,
      onClose: (): void => { this.memoryVisible = false; },
      onRefresh: (): void => void this.loadMemory(true),
      onSelectBot: (botId: string): void => void this.selectMemoryBot(botId),
      onForget: (entry: MemoryEntry): void => void this.forgetMemory(entry),
      onAskTextChange: (text: string): void => { this.memoryAskText = text; },
      onAsk: (): void => void this.askMemory()
    });
  }

  /** 定时任务整页（P2-3）。 */
  @Builder
  private schedulesPageView() {
    SchedulesPanel({
      theme: this.secondaryTokens(),
      tasks: this.scheduleTasks,
      available: this.schedulesAvailable,
      loading: this.schedulesLoading,
      error: this.schedulesError,
      targets: this.scheduleTargets(),
      botNames: this.scheduleBotNames(),
      roomNames: this.scheduleRoomNames(),
      form: this.scheduleForm,
      formError: this.scheduleFormError,
      creating: this.scheduleCreating,
      onClose: (): void => { this.schedulesVisible = false; },
      onRefresh: (): void => void this.loadSchedules(),
      onDelete: (task: ScheduleTask): void => void this.deleteScheduleTask(task),
      onFormChange: (form: ScheduleForm): void => { this.scheduleForm = form; },
      onCreate: (validation: ScheduleValidation): void => void this.createScheduleFromForm(validation)
    });
  }

  /** 用量面板整页（P2-2）。手机走 `mobileOverlay`，宽屏走同一条渲染。 */
  @Builder
  private usagePage() {
    UsagePanel({
      theme: this.secondaryTokens(),
      page: this.usageData,
      window: this.usageWindow,
      loading: this.usageLoading,
      error: this.usageError,
      onWindowChange: (value: UsageWindow): void => {
        this.usageWindow = value;
        // 切换窗口只是本地裁剪（数据一次拉全），不需要重新请求
      },
      onRefresh: (): void => void this.loadUsage(),
      onClose: (): void => {
        this.usageVisible = false;
        this.mobileOverlay = '';
      }
    });
  }

  @Builder
  private mobileToolsPage() {
    // 页面本体已抽到 view/SecondaryPages.ets
    ToolsPage({
      tokens: this.secondaryTokens(),
      onClose: (): void => { this.mobileOverlay = ''; },
      onOpenCapabilities: (): void => {
        this.ensureCapabilityBot();
        this.mobileOverlay = 'capabilities';
      }
    });
  }



  @Builder
  private mobileCapabilitiesPage() {
    CapabilitiesPage({
      tokens: this.secondaryTokens(),
      bots: this.team.bots,
      capabilities: this.team.capabilities ?? [],
      selectedBotId: this.capabilityBotId,
      attachedNames: this.attachedCapabilityNames(),
      statuses: this.capabilityStatusesOf(),
      busy: this.capabilityBusy,
      error: this.capabilityError,
      onBack: (): void => {
        this.capabilitiesVisible = false;
        this.toolsVisible = true;
      },
      onSelectBot: (botId: string): void => { this.capabilityBotId = botId; },
      onToggle: (name: string, attached: boolean): void => void this.toggleCapability(name, attached)
    });
  }


  @Builder
  private mainContent() {
    // 用量面板是整页覆盖：手机与宽屏都走这一条，避免「只在某一个 overlay 分支里渲染」而漏掉另一端
    if (this.usageVisible) {
      this.usagePage();
    } else if (this.schedulesVisible) {
      this.schedulesPageView();
    } else if (this.memoryVisible) {
      this.memoryPageView();
    } else if (this.roomsVisible) {
      this.roomsPageView();
    } else if (this.agentVisible) {
      this.agentPageView();
    } else if (this.notificationsVisible) {
      this.notificationsPageView();
    } else if (this.capabilitiesVisible) {
      this.mobileCapabilitiesPage();
    } else if (this.toolsVisible) {
      this.toolsPageView();
    } else if (this.botsVisible) {
      this.botsPageView();
    } else if (this.windowWidth >= 600) {
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
      } else if (this.mobileOverlay === 'usage') {
        this.usagePage();
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
      // 仅把当前页面的语义背景延伸进系统安全区，内容仍保持系统默认避让。
      // 聊天页衔接顶栏/输入栏，其余页面衔接页面底色。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.systemChromeBg())
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);

      if (!this.ready) {
        Column({ space: 14 }) {
          this.appMark(64);
          LoadingProgress().width(28).height(28).color(this.tokens().brand);
          Text('正在准备 DS Bot…').fontSize(14).fontColor(this.muted());
        }.width('100%').height('100%').justifyContent(FlexAlign.Center);
      } else if (!this.paired) {
        this.pairingPage();
      } else {
        this.mainContent();
      }

      // 图片全屏预览（P3-1）：点任意处关闭
      if (this.previewVisible && this.previewPixel !== undefined) {
        Column() {
          Image(this.previewPixel)
            .width('92%')
            .objectFit(ImageFit.Contain)
        }
        .width('100%').height('100%')
        .justifyContent(FlexAlign.Center)
        // ArkUI 颜色是 #AARRGGBB（透明度在前），写 #RRGGBBAA 不会生效
        .backgroundColor('#CC000000')
        .onClick(() => { this.previewVisible = false; });
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
    .bindSheet(this.referencePickerVisible, this.referencePickerSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: true,
      backgroundColor: this.surface(),
      onDisappear: (): void => { this.referencePickerVisible = false; }
    });
  }
}
