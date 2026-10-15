import { common } from '@kit.AbilityKit';
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
  Room,
  Session,
  TeamState,
  ToolActivity
} from '../model/Models';
import { MobileApi } from '../service/MobileApi';
import { ProfileStore } from '../service/ProfileStore';

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
  @State pendingRevokeId: string = '';
  private apiClient?: MobileApi;
  private profile?: ClientProfile;
  private messageScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    void this.restore();
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

  private botColor(): string {
    if (this.newBotColor === 'black') return '#000000';
    if (this.newBotColor === 'brown') return '#A27952';
    if (this.newBotColor === 'red') return '#F15152';
    if (this.newBotColor === 'orange') return '#FF781C';
    if (this.newBotColor === 'yellow') return '#FFAF38';
    if (this.newBotColor === 'green') return '#00C972';
    if (this.newBotColor === 'cyan') return '#1CC3B0';
    if (this.newBotColor === 'violet') return '#A97EFE';
    if (this.newBotColor === 'magenta') return '#FF5EB1';
    if (this.newBotColor === 'gray') return '#959595';
    return '#4D6BFE';
  }

  private async restore(): Promise<void> {
    try {
      const saved = await ProfileStore.load(this.context());
      if (saved !== undefined) {
        this.profile = saved;
        this.serverName = saved.serverName;
        this.apiClient = new MobileApi(saved.serverUrl, saved.tlsPin, saved.session);
        this.paired = true;
        await this.refreshAll();
      }
    } catch (error) {
      this.error = `恢复连接失败：${(error as Error).message}`;
    } finally {
      this.ready = true;
    }
  }

  private async pair(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.error = '';
    try {
      const value = JSON.parse(this.pairingJson.trim()) as PairingCode;
      if (typeof value.url !== 'string' || value.url.trim().length === 0 ||
        typeof value.code !== 'string' || value.code.trim().length === 0 ||
        typeof value.serverId !== 'string' || value.serverId.trim().length === 0) {
        throw new Error('请粘贴电脑端显示的完整配对 JSON。');
      }
      const api = new MobileApi(value.url, value.tlsPin ?? '');
      const info = await api.info();
      if (info.serverId !== value.serverId) throw new Error('服务器身份与配对码不一致，请重新生成配对码。');
      const pairing = await api.pair(value.code, this.deviceName.trim());
      this.getUIContext().getPromptAction().showToast({ message: '请在电脑端批准此设备', duration: 2500 });
      let session: Session | undefined = undefined;
      for (let attempt = 0; attempt < 80 && session === undefined; attempt++) {
        session = await api.completePairing(pairing.claimToken);
        if (session === undefined) await new Promise<void>((resolve) => setTimeout(resolve, 1500));
      }
      if (session === undefined) throw new Error('配对已超时，请重新生成配对码。');
      const profile: ClientProfile = {
        serverUrl: value.url.replace(/\/+$/u, '').replace(/\/mobile\/v1$/u, ''),
        serverName: info.name ?? 'DSH 主机',
        tlsPin: value.tlsPin ?? '',
        session: session
      };
      await ProfileStore.save(this.context(), profile);
      this.profile = profile;
      this.apiClient = api;
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
      const state = await api.state();
      const result = await api.conversations();
      this.team = state;
      this.conversations = result.conversations;
      void this.loadConversationPreviews(result.conversations);
      this.online = true;
      if (this.selectedId.length === 0 && this.conversations.length > 0 && this.windowWidth >= 600) {
        await this.selectConversation(this.conversations[0]);
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
      this.error = (error as Error).message;
    } finally {
      this.refreshing = false;
    }
  }

  private async selectConversation(item: Conversation): Promise<void> {
    this.selectedId = item.id;
    this.messages = [];
    await this.loadMessages();
  }

  private async loadConversationPreviews(items: Conversation[]): Promise<void> {
    const api = this.apiClient;
    if (api === undefined) return;
    const previews: Record<string, string> = {};
    const count = Math.min(items.length, 24);
    for (let index = 0; index < count; index++) {
      const item = items[index];
      try {
        const page = await api.messages(item.id, 8);
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

  private async loadMessages(): Promise<void> {
    if (this.apiClient === undefined || this.selectedId.length === 0) return;
    try {
      const page = await this.apiClient.messages(this.selectedId, 100);
      this.messages = page.messages;
      this.online = true;
      if (page.messages.length > 0) {
        const latest = page.messages[page.messages.length - 1];
        if (Number.isSafeInteger(latest.seq) && latest.seq >= 0) {
          try {
            await this.apiClient.markRead(this.selectedId, latest.seq);
          } catch (_error) {}
        }
      }
      setTimeout((): void => this.messageScroller.scrollEdge(Edge.Bottom), 40);
    } catch (error) {
      this.online = false;
      this.error = (error as Error).message;
    }
  }

  private async send(): Promise<void> {
    const api = this.apiClient;
    const text = this.draft.trim();
    if (api === undefined || text.length === 0 || this.selectedId.length === 0 || this.busy) return;
    this.busy = true;
    this.error = '';
    this.draft = '';
    const optimistic: Message = {
      id: `local-${Date.now()}`,
      sessionId: '',
      seq: Number.MAX_SAFE_INTEGER,
      role: 'user',
      text: text,
      createdAt: Date.now(),
      pending: true
    };
    this.messages = [...this.messages, optimistic];
    setTimeout((): void => this.messageScroller.scrollEdge(Edge.Bottom), 30);
    try {
      const target = await api.target(this.selectedId);
      await api.submit({
        conversationId: target.conversationId,
        sessionId: target.sessionId,
        requestId: `harmony-${Date.now()}-${Math.floor(Math.random() * 100000)}`,
        text: text
      });
      for (let attempt = 0; attempt < 30; attempt++) {
        await new Promise<void>((resolve) => setTimeout(resolve, 1200));
        const page = await api.messages(this.selectedId, 100);
        this.messages = page.messages;
        const last = page.messages.length > 0 ? page.messages[page.messages.length - 1] : undefined;
        if (last !== undefined && last.role === 'assistant' && !last.pending) break;
      }
      await this.refreshAll();
    } catch (error) {
      this.messages = this.messages.filter((item: Message) => item.id !== optimistic.id);
      this.draft = text;
      this.error = (error as Error).message;
    } finally {
      this.busy = false;
      setTimeout((): void => this.messageScroller.scrollEdge(Edge.Bottom), 30);
    }
  }

  private async stop(): Promise<void> {
    if (this.apiClient === undefined || this.selectedId.length === 0) return;
    try {
      await this.apiClient.cancel(this.selectedId);
      this.busy = false;
      await this.loadMessages();
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
      const approvalResult = await this.apiClient.approvals();
      const deviceResult = await this.apiClient.devices();
      this.approvals = approvalResult.requests;
      this.devices = deviceResult.devices;
    } catch (error) {
      this.error = (error as Error).message;
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
    if (this.pendingRevokeId !== device.id) {
      this.pendingRevokeId = device.id;
      this.getUIContext().getPromptAction().showToast({ message: '再次点击“确认移除”以撤销该设备', duration: 2200 });
      return;
    }
    this.busy = true;
    this.error = '';
    try {
      await this.apiClient.revokeDevice(device.id);
      this.pendingRevokeId = '';
      await this.loadAdminData();
    } catch (error) {
      this.error = (error as Error).message;
    } finally {
      this.busy = false;
    }
  }

  private async logout(): Promise<void> {
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
    const ids = this.team.mainBotIds ?? (this.team.mainBotId === undefined ? [] : [this.team.mainBotId]);
    return ids.includes(item.id) || ids.some((id: string) => item.id === `bot:${id}`);
  }

  private mainConversation(): Conversation | undefined {
    return this.conversations.find((item: Conversation) => this.isMainConversation(item));
  }

  private conversationTime(item: Conversation): string {
    if (item.updatedAt === undefined) return '';
    const date = new Date(item.updatedAt);
    if (!Number.isFinite(date.getTime())) return '';
    return `${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  @Builder
  private conversationAvatar(item: Conversation, size: number = 50) {
    Stack() {
      if (item.kind === 'bot' && this.isMainConversation(item)) {
        Image($r('app.media.ds_whale')).width(size).height(size).objectFit(ImageFit.Contain);
      } else if (item.kind === 'room') {
        Circle({ width: size, height: size }).fill('#F0F1F4');
        Text('群').fontSize(size * 0.34).fontWeight(FontWeight.Medium).fontColor('#4D6BFE');
      } else {
        Circle({ width: size, height: size }).fill('#4D6BFE');
        Text(item.name.length > 0 ? item.name.slice(0, 1) : 'B')
          .fontSize(size * 0.34).fontWeight(FontWeight.Bold).fontColor('#FFFFFF');
      }
    }.width(size).height(size);
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
              Image($r('app.media.ds_whale')).width(100).height(100).objectFit(ImageFit.Contain);
              Text(this.mainConversation()?.name ?? 'Chief').fontSize(16).fontColor(this.muted());
            }
            .width('100%').padding({ top: 4, bottom: 22 })
            .onClick(() => {
              const item = this.mainConversation();
              if (item !== undefined) void this.selectConversation(item);
            });
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
  private statusPill() {
    Row({ space: 6 }) {
      Circle({ width: 8, height: 8 }).fill(this.online ? '#24B47E' : '#A4A9BB');
      Text(this.online ? '已连接' : '离线').fontSize(12).fontColor(this.muted());
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(this.dark ? '#242732' : '#F0F2F7')
    .borderRadius(16);
  }

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

  @Builder
  private navigationRail() {
    Column() {
      Row({ space: 12 }) {
        this.appMark(40);
        if (this.windowWidth >= 1040) {
          Column() {
            Text('DS Bot').fontSize(19).fontWeight(FontWeight.Bold).fontColor(this.ink());
            Text(this.serverName).fontSize(11).fontColor(this.muted()).maxLines(1);
          }.alignItems(HorizontalAlign.Start);
        }
      }.width('100%').padding({ left: 12, right: 12, top: 16, bottom: 20 });
      this.railButton('✦', '对话', 'chat');
      this.railButton('◎', '团队', 'team');
      this.railButton('⚙', '设置', 'settings');
      Blank();
      this.statusPill();
    }
    .width(this.windowWidth >= 1040 ? 180 : 76).height('100%')
    .padding({ left: 8, right: 8, bottom: 18 })
    .backgroundColor(this.surface())
    .border({ width: { right: 1 }, color: this.line() });
  }

  @Builder
  private railButton(icon: string, label: string, target: AppSection) {
    Button() {
      Row({ space: 12 }) {
        Text(icon).fontSize(21).fontColor(this.section === target ? '#665CF6' : this.muted());
        if (this.windowWidth >= 1040) {
          Text(label).fontSize(15).fontColor(this.section === target ? '#665CF6' : this.ink());
        }
      }.width('100%');
    }
    .height(48).width('100%').margin({ bottom: 6 })
    .backgroundColor(this.section === target ? (this.dark ? '#2B2946' : '#EFEDFF') : Color.Transparent)
    .borderRadius(14)
    .onClick(() => {
      this.section = target;
      if (target === 'settings') void this.loadAdminData();
    });
  }

  @Builder
  private conversationList() {
    Column() {
      Row() {
        Text('会话').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.ink()).layoutWeight(1);
        Button('↻').width(40).height(40).borderRadius(20).fontSize(19)
          .backgroundColor(this.dark ? '#252833' : '#F0F2F7').fontColor(this.ink())
          .onClick(() => void this.refreshAll());
      }.width('100%').padding({ left: 18, right: 14, top: 18, bottom: 12 });
      TextInput({ placeholder: '搜索会话', text: this.searchText })
        .height(42).margin({ left: 14, right: 14, bottom: 10 }).borderRadius(14)
        .backgroundColor(this.pageBg()).fontColor(this.ink())
        .onChange((value: string) => this.searchText = value);
      Row() {
        Text('显示已隐藏会话').fontSize(12).fontColor(this.muted()).layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.showHidden })
          .onChange((value: boolean) => this.showHidden = value);
      }.width('100%').padding({ left: 16, right: 14, bottom: 8 });
      List({ space: 4 }) {
        ForEach(this.filteredConversations(), (item: Conversation) => {
          ListItem() {
            Row({ space: 12 }) {
              Stack() {
                Circle({ width: 42, height: 42 }).fill(item.kind === 'room' ? '#F3B64B' : '#665CF6');
                Text(item.kind === 'room' ? '群' : (item.name.length > 0 ? item.name.slice(0, 1) : 'B'))
                  .fontSize(16).fontWeight(FontWeight.Bold).fontColor('#FFFFFF');
              }.width(42).height(42);
              Column({ space: 4 }) {
                Row() {
                  Text(item.name).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.ink()).maxLines(1).layoutWeight(1);
                  if (item.pinned) Text('置顶').fontSize(10).fontColor('#665CF6');
                  if (item.hidden) Text('隐藏').fontSize(10).fontColor(this.muted());
                  if (item.waiting !== undefined && item.waiting.length > 0) {
                    Circle({ width: 8, height: 8 }).fill('#F29D49');
                  }
                }.width('100%');
                Text(item.role ?? (item.kind === 'room' ? '群聊' : 'Bot'))
                  .fontSize(12).fontColor(this.muted()).maxLines(1).width('100%');
              }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            }
            .width('100%').padding(12)
            .backgroundColor(this.selectedId === item.id ? (this.dark ? '#2B2946' : '#EFEDFF') : Color.Transparent)
            .borderRadius(14);
          }.onClick(() => void this.selectConversation(item));
        }, (item: Conversation) => item.id);
      }
      .layoutWeight(1).width('100%').height('100%').padding({ left: 8, right: 8 })
      .scrollBar(BarState.Off);
    }
    .width(this.windowWidth >= 840 ? 320 : '100%').height('100%')
    .backgroundColor(this.surface())
    .border({ width: { right: this.windowWidth >= 840 ? 1 : 0 }, color: this.line() });
  }

  @Builder
  private messageBubble(message: Message) {
    Row() {
      if (message.role === 'user') Blank();
      Column({ space: 6 }) {
        if (this.windowWidth >= 600) {
          Text(message.role === 'user' ? '你' : message.role === 'assistant' ? 'Bot' : message.role)
            .fontSize(11).fontColor(message.role === 'user' ? '#DCD8FF' : this.muted());
        }
        if (message.reasoning !== undefined && message.reasoning.length > 0) {
          if (this.windowWidth < 600) {
            Text('⌄ 思考过程').fontSize(12).fontColor(this.muted()).width('100%');
          }
          Text(message.reasoning).fontSize(this.windowWidth < 600 ? 16 : 12)
            .lineHeight(this.windowWidth < 600 ? 23 : 18).fontColor(this.windowWidth < 600 ? this.ink() : this.muted())
            .maxLines(this.windowWidth < 600 ? 8 : 4)
            .padding(this.windowWidth < 600 ? 0 : { left: 10 })
            .border(this.windowWidth < 600 ? { width: 0 } : { width: { left: 2 }, color: '#9D96FF' });
        }
        if (message.tool !== undefined) {
          this.toolCard(message.tool);
        } else {
          Text(message.text).fontSize(15).lineHeight(23)
            .fontColor(this.windowWidth < 600 ? this.ink() : message.role === 'user' ? '#FFFFFF' : this.ink())
            .copyOption(CopyOptions.LocalDevice);
        }
        if (message.pending) {
          Text('发送中…').fontSize(11).fontColor(message.role === 'user' ? '#DCD8FF' : this.muted());
        }
      }
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ maxWidth: this.windowWidth >= 840 ? 720 : '90%' })
      .padding(this.windowWidth < 600 ? { left: 18, right: 18, top: 13, bottom: 13 } : 13)
      .borderRadius(this.windowWidth < 600 ? 26 : 17)
      .backgroundColor(this.windowWidth < 600 ?
        (this.dark ? '#333333' : message.role === 'user' ? '#EDF3FF' : '#F0F0F0') :
        message.role === 'user' ? '#665CF6' : this.surface());
      if (message.role !== 'user') Blank();
    }.width('100%').padding({ left: 16, right: 16, top: this.windowWidth < 600 ? 8 : 6, bottom: this.windowWidth < 600 ? 8 : 6 });
  }

  @Builder
  private toolCard(tool: ToolActivity) {
    Column({ space: 7 }) {
      Row({ space: 8 }) {
        Text(tool.state === 'running' ? '◌' : tool.isError ? '!' : '✓')
          .fontColor(tool.isError ? '#E35252' : tool.state === 'running' ? '#F29D49' : '#24B47E');
        Text(tool.name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.ink()).layoutWeight(1);
        Text(tool.state).fontSize(11).fontColor(this.muted());
      }.width('100%');
      if (tool.input !== undefined && tool.input.length > 0) {
        Text(tool.input).fontSize(12).fontColor(this.muted()).maxLines(5).copyOption(CopyOptions.LocalDevice);
      }
      if (tool.output !== undefined && tool.output.length > 0) {
        Text(tool.output).fontSize(12).fontColor(this.ink()).maxLines(10).copyOption(CopyOptions.LocalDevice);
      }
    }
    .width('100%').padding(12).backgroundColor(this.pageBg()).borderRadius(12)
    .border({ width: 1, color: this.line() });
  }

  @Builder
  private chatPanel() {
    Column() {
      Row({ space: 12 }) {
        if (this.windowWidth < 600) {
          Button('‹').width(40).height(40).borderRadius(20).fontSize(26)
            .backgroundColor(this.pageBg()).fontColor(this.ink())
            .onClick(() => this.selectedId = '');
        }
        Column({ space: 2 }) {
          Text(this.selectedConversation()?.name ?? '选择一个会话')
            .fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.ink()).maxLines(1);
          Text(this.online ? '主机在线' : '正在等待主机').fontSize(11).fontColor(this.muted());
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
      if (this.selectedId.length === 0) {
        Column({ space: 12 }) {
          this.appMark(64);
          Text('选择一个 Bot 开始对话').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.ink());
          Text('所有模型、工具和工作目录仍在你的 DSH 主机上运行。')
            .fontSize(13).fontColor(this.muted()).textAlign(TextAlign.Center);
        }.layoutWeight(1).justifyContent(FlexAlign.Center).padding(30);
      } else {
        Scroll(this.messageScroller) {
          Column() {
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
        Row({ space: 10 }) {
          TextArea({ placeholder: '发送消息…', text: this.draft })
            .layoutWeight(1).height(56).maxLength(32000).fontSize(15).fontColor(this.ink())
            .backgroundColor(this.pageBg()).borderRadius(16)
            .onChange((value: string) => this.draft = value);
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
        .border({ width: 1, color: this.line() }).onClick(() => this.selectedId = '');
        Row({ space: 8 }) {
          if (this.selectedConversation() !== undefined) {
            this.conversationAvatar(this.selectedConversation()!, 30);
          }
          Text(this.selectedConversation()?.name ?? 'DS Bot')
            .fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()).maxLines(1);
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
      Scroll(this.messageScroller) {
        Column() {
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
      Row({ space: 10 }) {
        Button() {
          Image(this.dark ? $r('app.media.ic_plus_light') : $r('app.media.ic_plus')).width(24).height(24);
        }
        .width(48).height(48).borderRadius(24).backgroundColor(this.dark ? '#242424' : '#FFFFFF')
        .border({ width: 1, color: this.line() })
        .onClick(() => this.getUIContext().getPromptAction().showToast({ message: '图片与文件附件正在转译中', duration: 1800 }));
        TextArea({ placeholder: `向 ${this.selectedConversation()?.name ?? 'Bot'} 提问`, text: this.draft })
          .layoutWeight(1).height(48).maxLength(32000).fontSize(16).fontColor(this.ink())
          .backgroundColor(this.dark ? '#202022' : '#FFFFFF').borderRadius(24)
          .border({ width: 1, color: this.line() }).padding({ left: 14, right: 14, top: 10, bottom: 8 })
          .onChange((value: string) => this.draft = value);
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
                Stack() {
                  Circle({ width: 54, height: 54 }).fill('#665CF6');
                  Text(bot.name.length > 0 ? bot.name.slice(0, 1) : 'B')
                    .fontSize(21).fontWeight(FontWeight.Bold).fontColor('#FFFFFF');
                }.width(54).height(54);
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
                Button(this.pendingRevokeId === device.id ? '确认移除' : '移除')
                  .height(32).borderRadius(16).fontSize(12)
                  .backgroundColor(this.pendingRevokeId === device.id ? '#FDECEC' : this.pageBg())
                  .fontColor(this.pendingRevokeId === device.id ? '#C93C3C' : this.ink())
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
    Scroll() {
      Column({ space: 0 }) {
        Row() {
          Button() {
            Image($r('app.media.ic_close')).width(22).height(22);
          }
          .width(48).height(48).borderRadius(24).backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#E5E5E5' }).onClick(() => this.section = 'chat');
          Blank();
        }.width('100%').height(76).padding({ left: 20, right: 20, top: 12, bottom: 16 });

        Column() {
          Row({ space: 14 }) {
            Stack() {
              Circle({ width: 46, height: 46 }).fill('#E0E0E0');
              Text('DS').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#777777');
            }.width(46).height(46);
            Column({ space: 3 }) {
              Text(this.serverName.length > 0 ? this.serverName : 'DS Bot')
                .fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink());
              Text(this.profile?.serverUrl ?? '').fontSize(14).fontColor(this.muted()).maxLines(1);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Image($r('app.media.ic_chevron')).width(18).height(18);
          }.height(76).width('100%').padding({ left: 20, right: 18 });
          Divider().color(this.line()).margin({ left: 20 });
          Row() {
            Text('用量').fontSize(18).fontColor(this.ink()).layoutWeight(1);
            Image($r('app.media.ic_chevron')).width(18).height(18);
          }.height(58).padding({ left: 20, right: 18 });
        }
        .width('100%').backgroundColor(this.dark ? '#202022' : '#F1F1F1').borderRadius(22);

        Column() {
          Row() {
            Column({ space: 3 }) {
              Text('工具与技能').fontSize(18).fontColor(this.ink());
              Text('DS Bot 的工具、技能与插件').fontSize(13).fontColor(this.muted());
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Image($r('app.media.ic_chevron')).width(18).height(18);
          }.height(78).padding({ left: 20, right: 18 });
        }
        .width('100%').margin({ top: 32 }).backgroundColor(this.dark ? '#202022' : '#F1F1F1').borderRadius(22)
        .onClick(() => this.mobileOverlay = 'tools');

        Text('Bot').fontSize(14).fontColor(this.muted()).width('100%').margin({ top: 32, bottom: 10, left: 20 });
        Column() {
          Row() {
            Text('Bot 与群聊').fontSize(18).fontColor(this.ink()).layoutWeight(1);
            Image($r('app.media.ic_chevron')).width(18).height(18);
          }.height(64).padding({ left: 20, right: 18 }).onClick(() => this.section = 'team');
          Divider().color(this.line()).margin({ left: 20 });
          Row() {
            Text('定时任务').fontSize(18).fontColor(this.ink()).layoutWeight(1);
            Image($r('app.media.ic_chevron')).width(18).height(18);
          }.height(64).padding({ left: 20, right: 18 });
          Divider().color(this.line()).margin({ left: 20 });
          Row() {
            Column({ space: 3 }) {
              Text('经典 Agent 模式').fontSize(18).fontColor(this.ink());
              Text('在主页显示 DSH Agent 会话。').fontSize(13).fontColor(this.muted());
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Toggle({ type: ToggleType.Switch, isOn: false });
          }.height(80).padding({ left: 20, right: 18 });
          Divider().color(this.line()).margin({ left: 20 });
          Row() {
            Text('Bot 电脑').fontSize(18).fontColor(this.ink()).layoutWeight(1);
            Image($r('app.media.ic_chevron')).width(18).height(18);
          }.height(64).padding({ left: 20, right: 18 });
        }
        .width('100%').backgroundColor(this.dark ? '#202022' : '#F1F1F1').borderRadius(22);

        Text('偏好设置').fontSize(14).fontColor(this.muted()).width('100%').margin({ top: 32, bottom: 10, left: 20 });
        Column() {
          Row() {
            Text('通知中心').fontSize(18).fontColor(this.ink()).layoutWeight(1);
            Image($r('app.media.ic_chevron')).width(18).height(18);
          }.height(64).padding({ left: 20, right: 18 });
          Divider().color(this.line()).margin({ left: 20 });
          Row() {
            Text('夜间模式').fontSize(18).fontColor(this.ink()).layoutWeight(1);
            Toggle({ type: ToggleType.Switch, isOn: this.dark })
              .onChange((value: boolean) => this.dark = value);
          }.height(64).padding({ left: 20, right: 18 });
        }.width('100%').backgroundColor(this.dark ? '#202022' : '#F1F1F1').borderRadius(22);

        if (this.approvals.length > 0) {
          Text('待批准操作').fontSize(14).fontColor(this.muted()).width('100%').margin({ top: 32, bottom: 10, left: 20 });
          Column({ space: 10 }) {
            ForEach(this.approvals, (approval: Approval) => {
              Column({ space: 8 }) {
                Text(approval.toolName).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%');
                Text(approval.reason ?? '主机请求批准此工具操作').fontSize(13).fontColor(this.muted()).width('100%');
                Row({ space: 8 }) {
                  Button('允许一次').height(36).borderRadius(18).backgroundColor('#4D6BFE')
                    .onClick(() => void this.resolveApproval(approval.id, 'allowed-once'));
                  Button('拒绝').height(36).borderRadius(18).backgroundColor('#FDECEC').fontColor('#C93C3C')
                    .onClick(() => void this.resolveApproval(approval.id, 'rejected'));
                }
              }.padding(14).backgroundColor(this.dark ? '#202022' : '#F1F1F1').borderRadius(18);
            }, (approval: Approval) => approval.id);
          }.width('100%');
        }

        Button('断开此设备').width('100%').height(50).margin({ top: 32, bottom: 20 }).borderRadius(25)
          .backgroundColor('#FDECEC').fontColor('#C93C3C').onClick(() => void this.logout());
      }
      .width('100%').padding({ left: 18, right: 18, bottom: 24 });
    }.width('100%').height('100%').backgroundColor(this.dark ? '#121212' : '#FFFFFF');
  }

  @Builder
  private botAvatarPreview(size: number) {
    Stack() {
      if (this.newBotShape === 'gumdrop' && this.newBotColor === 'blue') {
        Image($r('app.media.avatar_gumdrop_large')).width(size).height(size * 1.36).objectFit(ImageFit.Contain);
      } else if (this.newBotShape === 'circle') {
        Circle({ width: size, height: size }).fill(this.botColor());
      } else if (this.newBotShape === 'square') {
        Rect().width(size).height(size).radius(size * 0.2).fill(this.botColor());
      } else if (this.newBotShape === 'diamond') {
        Rect().width(size * 0.72).height(size * 0.72).radius(size * 0.16).fill(this.botColor()).rotate({ angle: 45 });
      } else {
        Rect().width(size).height(size * 0.9).radius(size * 0.46).fill(this.botColor());
      }
      if (!(this.newBotShape === 'gumdrop' && this.newBotColor === 'blue')) {
        Row({ space: size * 0.08 }) {
          Rect().width(size * 0.1).height(size * 0.29).radius(size * 0.05).fill('#FFFFFF');
          Rect().width(size * 0.1).height(size * 0.29).radius(size * 0.05).fill('#FFFFFF');
        }
      }
    }.width(size).height(size * 1.36);
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
          Column({ space: 4 }) {
            Row() {
            Button() { Image($r('app.media.avatar_whale')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'whale' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'whale');
            Button() { Image($r('app.media.avatar_star')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'star' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'star');
            Button() { Image($r('app.media.avatar_moon')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'moon' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'moon');
            Button() { Image($r('app.media.avatar_wave')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'wave' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'wave');
            Button() { Image($r('app.media.avatar_squircle')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'squircle' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'squircle');
            }.width('100%');
            Row() {
            Button() { Image($r('app.media.avatar_zed')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'zed' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'zed');
            Button() { Image($r('app.media.avatar_hex')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'hex' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'hex');
            Button() { Image($r('app.media.avatar_gumdrop')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).onClick(() => this.newBotShape = 'gumdrop');
            Button() { Image($r('app.media.avatar_peanut')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'peanut' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'peanut');
            Button() { Image($r('app.media.avatar_saucer')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'saucer' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'saucer');
            }.width('100%');
            Row() {
            Button() { Image($r('app.media.avatar_bunny')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'bunny' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'bunny');
            Button() { Image($r('app.media.avatar_kitty')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'kitty' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'kitty');
            Button() { Image($r('app.media.avatar_beacon')).width(42).height(42); }.layoutWeight(1).height(50).borderRadius(25).backgroundColor(Color.Transparent).border({ width: this.newBotShape === 'beacon' ? 2 : 0, color: this.line() }).onClick(() => this.newBotShape = 'beacon');
            Blank().layoutWeight(2);
            }.width('100%');
          }.width('100%');

          Text('选择颜色').fontSize(14).fontColor(this.muted()).width('100%');
          Column({ space: 2 }) {
            Row() {
            Button() { Circle({ width: 32, height: 32 }).fill('#000000'); }.layoutWeight(1).height(46).backgroundColor(Color.Transparent).onClick(() => this.newBotColor = 'black');
            Button() { Circle({ width: 32, height: 32 }).fill('#A27952'); }.layoutWeight(1).height(46).backgroundColor(Color.Transparent).onClick(() => this.newBotColor = 'brown');
            Button() { Circle({ width: 32, height: 32 }).fill('#FF3E51'); }.layoutWeight(1).height(46).backgroundColor(Color.Transparent).onClick(() => this.newBotColor = 'red');
            Button() { Circle({ width: 32, height: 32 }).fill('#FF781C'); }.layoutWeight(1).height(46).backgroundColor(Color.Transparent).onClick(() => this.newBotColor = 'orange');
            Button() { Circle({ width: 32, height: 32 }).fill('#FFAF38'); }.layoutWeight(1).height(46).backgroundColor(Color.Transparent).onClick(() => this.newBotColor = 'yellow');
            Button() { Circle({ width: 32, height: 32 }).fill('#00C972'); }.layoutWeight(1).height(46).backgroundColor(Color.Transparent).onClick(() => this.newBotColor = 'green');
            }.width('100%');
            Row() {
            Button() { Circle({ width: 32, height: 32 }).fill('#1CC3B0'); }.layoutWeight(1).height(46).backgroundColor(Color.Transparent).onClick(() => this.newBotColor = 'cyan');
            Button() { Circle({ width: 32, height: 32 }).fill('#4D6BFE'); }.layoutWeight(1).height(46).backgroundColor(Color.Transparent).border({ width: this.newBotColor === 'blue' ? 2 : 0, color: this.line() }).borderRadius(23).onClick(() => this.newBotColor = 'blue');
            Button() { Circle({ width: 32, height: 32 }).fill('#A97EFE'); }.layoutWeight(1).height(46).backgroundColor(Color.Transparent).onClick(() => this.newBotColor = 'violet');
            Button() { Circle({ width: 32, height: 32 }).fill('#FF5EB1'); }.layoutWeight(1).height(46).backgroundColor(Color.Transparent).onClick(() => this.newBotColor = 'magenta');
            Button() { Circle({ width: 32, height: 32 }).fill('#959595'); }.layoutWeight(1).height(46).backgroundColor(Color.Transparent).onClick(() => this.newBotColor = 'gray');
            Blank().layoutWeight(1);
            }.width('100%');
          }.width('100%');
          Button(this.busy ? '正在创建…' : '创建 Bot').width('100%').height(54).borderRadius(27)
            .margin({ top: 12, bottom: 18 }).backgroundColor('#4D6BFE').fontSize(17)
            .enabled(!this.busy && this.online && this.newBotName.trim().length > 0)
            .onClick(() => void this.createBot());
        }.width('100%').padding({ left: 24, right: 24, top: 32, bottom: 30 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(this.dark ? '#121212' : '#FAFAFA');
  }

  @Builder
  private mobileToolsPage() {
    Column() {
      Row({ space: 10 }) {
        Button() { Image($r('app.media.ic_close')).width(22).height(22); }
          .width(48).height(48).borderRadius(24).backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#E5E5E5' }).onClick(() => this.mobileOverlay = '');
        Row() {
          Text('工具与技能').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink());
        }.height(48).padding({ left: 18, right: 18 }).borderRadius(24).backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#E5E5E5' });
      }.width('100%').height(76).padding({ left: 20, right: 20, top: 12, bottom: 16 });
      Scroll() {
        Column({ space: 8 }) {
          Text('工具与技能').fontSize(14).fontColor(this.muted()).width('100%').padding({ left: 20 });
          Column() {
            Row() {
              Text('技能').fontSize(18).fontColor(this.ink()).layoutWeight(1);
              Image($r('app.media.ic_chevron')).width(18).height(18);
            }.height(64).padding({ left: 20, right: 18 });
            Divider().color(this.line()).margin({ left: 20 });
            Row() {
              Text('插件').fontSize(18).fontColor(this.ink()).layoutWeight(1);
              Image($r('app.media.ic_chevron')).width(18).height(18);
            }.height(64).padding({ left: 20, right: 18 });
            Divider().color(this.line()).margin({ left: 20 });
            Row() {
              Text('连接器').fontSize(18).fontColor(this.ink()).layoutWeight(1);
              Image($r('app.media.ic_chevron')).width(18).height(18);
            }.height(64).padding({ left: 20, right: 18 });
            Divider().color(this.line()).margin({ left: 20 });
            Row() {
              Text('能力库').fontSize(18).fontColor(this.ink()).layoutWeight(1);
              Image($r('app.media.ic_chevron')).width(18).height(18);
            }.height(64).padding({ left: 20, right: 18 }).onClick(() => this.mobileOverlay = 'capabilities');
          }.width('100%').backgroundColor(this.dark ? '#202022' : '#F1F1F1').borderRadius(22);
        }
        .width('100%').constraintSize({ minHeight: '100%' }).justifyContent(FlexAlign.Start)
        .padding({ left: 18, right: 18, top: 12 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(this.dark ? '#121212' : '#FFFFFF');
  }

  @Builder
  private mobileCapabilitiesPage() {
    Column() {
      Row({ space: 10 }) {
        Button() { Image($r('app.media.ic_back')).width(22).height(22); }
          .width(48).height(48).borderRadius(24).backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#E5E5E5' }).onClick(() => this.mobileOverlay = 'tools');
        Row() { Text('能力库').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.ink()); }
          .height(48).padding({ left: 18, right: 18 }).borderRadius(24).backgroundColor('#FFFFFF')
          .border({ width: 1, color: '#E5E5E5' });
      }.width('100%').height(76).padding({ left: 20, right: 20, top: 12, bottom: 16 });
      Scroll() {
        Column({ space: 18 }) {
          Text('为 Bot 添加可复用能力').fontSize(14).fontColor(this.muted()).width('100%');
          if (this.team.bots.length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.team.bots, (bot: Bot) => {
                Button(bot.name).height(38).margin({ right: 8, bottom: 8 }).borderRadius(19)
                  .backgroundColor('#E8EDFF').fontColor('#4D6BFE');
              }, (bot: Bot) => bot.id);
            }.width('100%');
          }
          Column({ space: 10 }) {
            Text('网页浏览').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%');
            Text('允许 Bot 打开网页、搜索资料并提取内容。').fontSize(14).fontColor(this.muted()).width('100%');
            Button('＋ 添加能力').height(38).borderRadius(19).backgroundColor('#E8EDFF').fontColor('#4D6BFE').alignSelf(ItemAlign.End);
          }.padding(20).width('100%').backgroundColor(this.dark ? '#202022' : '#F1F1F1').borderRadius(22);
          Column({ space: 10 }) {
            Text('文件与工作区').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%');
            Text('读取、整理和编辑主机工作目录里的文件。').fontSize(14).fontColor(this.muted()).width('100%');
            Button('＋ 添加能力').height(38).borderRadius(19).backgroundColor('#E8EDFF').fontColor('#4D6BFE').alignSelf(ItemAlign.End);
          }.padding(20).width('100%').backgroundColor(this.dark ? '#202022' : '#F1F1F1').borderRadius(22);
          Column({ space: 10 }) {
            Text('定时执行').fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.ink()).width('100%');
            Text('让 Bot 按计划运行任务并发送结果通知。').fontSize(14).fontColor(this.muted()).width('100%');
            Button('＋ 添加能力').height(38).borderRadius(19).backgroundColor('#E8EDFF').fontColor('#4D6BFE').alignSelf(ItemAlign.End);
          }.padding(20).width('100%').backgroundColor(this.dark ? '#202022' : '#F1F1F1').borderRadius(22);
        }.width('100%').padding({ left: 18, right: 18, top: 12, bottom: 24 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(this.dark ? '#121212' : '#FFFFFF');
  }

  @Builder
  private bottomBar() {
    Row() {
      this.bottomButton('✦', '对话', 'chat');
      this.bottomButton('◎', '团队', 'team');
      this.bottomButton('⚙', '设置', 'settings');
    }
    .height(68).width('100%').padding({ left: 24, right: 24, top: 6, bottom: 6 })
    .backgroundColor(this.surface()).border({ width: { top: 1 }, color: this.line() });
  }

  @Builder
  private bottomButton(icon: string, label: string, target: AppSection) {
    Button() {
      Column({ space: 2 }) {
        Text(icon).fontSize(20).fontColor(this.section === target ? '#665CF6' : this.muted());
        Text(label).fontSize(11).fontColor(this.section === target ? '#665CF6' : this.muted());
      }
    }
    .layoutWeight(1).height(56).backgroundColor(Color.Transparent)
    .onClick(() => {
      this.section = target;
      if (target === 'settings') void this.loadAdminData();
    });
  }

  @Builder
  private mainContent() {
    if (this.windowWidth >= 600) {
      Row() {
        this.navigationRail();
        if (this.section === 'chat') {
          this.conversationList();
          this.chatPanel();
        } else if (this.section === 'team') {
          this.teamPage();
        } else {
          this.settingsPage();
        }
      }.width('100%').height('100%');
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
      if (this.error.length > 0 && this.paired) {
        Row({ space: 10 }) {
          Text(this.error).fontSize(12).fontColor('#C93C3C').maxLines(2).layoutWeight(1);
          Button('×').width(32).height(32).borderRadius(16).backgroundColor(Color.Transparent)
            .fontColor('#C93C3C').onClick(() => this.error = '');
        }
        .position({ x: 16, y: 12 }).constraintSize({ maxWidth: 520 }).padding(10)
        .backgroundColor('#FFF0F0').borderRadius(12).shadow({ radius: 12, color: '#33000000' });
      }
    }
    .width('100%').height('100%').backgroundColor(this.pageBg())
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateWindowWidth(newArea.width);
    });
  }
}
