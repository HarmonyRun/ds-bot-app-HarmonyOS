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
  @State selectedId: string = '';
  @State messages: Message[] = [];
  @State draft: string = '';
  @State searchText: string = '';
  @State newBotName: string = '';
  @State newGroupName: string = '';
  @State selectedMembers: string[] = [];
  @State approvals: Approval[] = [];
  @State devices: DeviceListItem[] = [];
  @State dark: boolean = false;
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
      this.conversations = result.conversations.filter((item: Conversation) => !item.hidden);
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

  private async loadMessages(): Promise<void> {
    if (this.apiClient === undefined || this.selectedId.length === 0) return;
    try {
      const page = await this.apiClient.messages(this.selectedId, 100);
      this.messages = page.messages;
      this.online = true;
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
      const avatar: Avatar = { shape: 'gumdrop' };
      const payload: CreateBotPayload = {
        name: name,
        role: '',
        instructions: '',
        color: 'blue',
        avatar: avatar
      };
      if (this.team.models.length > 0) payload.model = this.team.models[0].ref;
      const bot = await this.apiClient.action<Bot>('create-bot', payload);
      this.newBotName = '';
      await this.refreshAll();
      const found = this.conversations.find((item: Conversation) => item.id === bot.id || item.id === `bot:${bot.id}`);
      if (found !== undefined) {
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
    if (query.length === 0) return this.conversations;
    return this.conversations.filter((item: Conversation) => `${item.name} ${item.role ?? ''}`.toLowerCase().includes(query));
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
                  if (item.waiting !== undefined) Circle({ width: 8, height: 8 }).fill('#F29D49');
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
        Text(message.role === 'user' ? '你' : message.role === 'assistant' ? 'Bot' : message.role)
          .fontSize(11).fontColor(message.role === 'user' ? '#DCD8FF' : this.muted());
        if (message.reasoning !== undefined && message.reasoning.length > 0) {
          Text(message.reasoning).fontSize(12).fontColor(this.muted()).maxLines(4)
            .padding({ left: 10 }).border({ width: { left: 2 }, color: '#9D96FF' });
        }
        if (message.tool !== undefined) {
          this.toolCard(message.tool);
        } else {
          Text(message.text).fontSize(15).lineHeight(23)
            .fontColor(message.role === 'user' ? '#FFFFFF' : this.ink())
            .copyOption(CopyOptions.LocalDevice);
        }
        if (message.pending) {
          Text('发送中…').fontSize(11).fontColor(message.role === 'user' ? '#DCD8FF' : this.muted());
        }
      }
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ maxWidth: this.windowWidth >= 840 ? 720 : '88%' })
      .padding(13).borderRadius(17)
      .backgroundColor(message.role === 'user' ? '#665CF6' : this.surface());
      if (message.role !== 'user') Blank();
    }.width('100%').padding({ left: 16, right: 16, top: 6, bottom: 6 });
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
  private teamPage() {
    Scroll() {
      Column({ space: 18 }) {
        Row() {
          Column({ space: 3 }) {
            Text('Bot 团队').fontSize(28).fontWeight(FontWeight.Bold).fontColor(this.ink());
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
            Row() {
              Text(device.deviceName ?? device.name ?? device.id).fontSize(14).fontColor(this.ink()).layoutWeight(1);
              Text(device.id === this.profile?.session.deviceId ? '本机' : '').fontSize(12).fontColor('#665CF6');
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
      Column() {
        if (this.section === 'chat') {
          if (this.selectedId.length === 0) this.conversationList();
          else this.chatPanel();
        } else if (this.section === 'team') {
          this.teamPage();
        } else {
          this.settingsPage();
        }
        this.bottomBar();
      }.width('100%').height('100%');
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
