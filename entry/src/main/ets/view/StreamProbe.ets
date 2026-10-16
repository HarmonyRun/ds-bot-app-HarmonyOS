import { webSocket } from '@kit.NetworkKit';
import { MobileClient, RawConversationList, RawPairingStart, RawServerInfo, RawTarget, SubmissionRequest } from '../service/MobileClient';
import { AvatarProbe } from './AvatarProbe';
import { MessageAction, MessageActionSheet } from './MessageActionSheet';
import { Session } from '../model/Models';
import { MobileEvent, StreamStatus } from '../service/Wire';

/** 配对码 JSON 的形状。 */
interface ProbePairingCode {
  url: string;
  code: string;
  serverId: string;
  tlsPin?: string;
}

/** 从会话列表里取第一个会话所需的最小投影。 */
interface ProbeConversation {
  id: string;
  name?: string;
}

/**
 * P0-1 可行性验证页：在不依赖业务界面的情况下验证
 * 「HTTP（SPKI 钉住）+ WebSocket 事件流」在真机/模拟器上是否可用。
 *
 * 用法：
 * 1. 在主机（DSH）里开启手机连接，复制完整配对 JSON；
 * 2. 粘贴到本页，点「1 验证配对码」；
 * 3. 在电脑端批准后点「2 批准并订阅」；
 * 4. 观察帧日志：应依次出现 `HTTP ok` → `ws connecting` → `ws connected` → `ready/reset/status` 帧。
 *
 * 本页不写入任何业务数据（不置顶、不隐藏、不改设置），只做连接与订阅验证。
 */
@Component
export struct StreamProbe {
  /** 诊断模式：`stream` 事件流 / `avatar` 头像渲染。 */
  @State mode: string = 'stream';
  /**
   * 自检用的动作面板状态。
   *
   * 为什么要在这里放一个入口：消息操作面板用的是原生 `bindSheet`，正常入口是
   * 「长按消息」，但 `uitest uiInput longClick` 在本工程的手势上触发不了
   * （换过 3 个按压点与时长），所以留一个按钮入口做真机实证。
   */
  @State demoSheetVisible: boolean = false;
  @State demoSheetResult: string = '（未点击）';
  @State pairingJson: string = '';
  @State deviceName: string = 'HarmonyOS Probe';
  @State stateLine: string = '未开始';
  @State frames: string[] = [];
  @State busy: boolean = false;
  @State eventCount: number = 0;
  @State deltaCount: number = 0;
  @State connected: boolean = false;
  @State errorCode: string = '';
  private client?: MobileClient;
  private claimToken: string = '';
  private conversationId: string = '';
  private paired: boolean = false;
  /** 原始 WebSocket 直连地址（诊断用，默认指向本机诱捕服务端）。 */
  @State wsUrl: string = 'wss://192.168.1.100:9443/mobile/v1/events';
  private probeSocket?: webSocket.WebSocket;
  private scroller: Scroller = new Scroller();

  aboutToDisappear(): void {
    this.stop();
  }

  private log(line: string): void {
    const stamp = new Date().toISOString().slice(11, 23);
    this.frames = [...this.frames, `${stamp}  ${line}`].slice(-200);
    setTimeout((): void => this.scroller.scrollEdge(Edge.Bottom), 30);
  }

  private stop(): void {
    if (this.probeSocket !== undefined) {
      try {
        this.probeSocket.close();
      } catch (_error) {}
      this.probeSocket = undefined;
    }
    if (this.client !== undefined) {
      this.client.dispose();
      this.client = undefined;
    }
    this.connected = false;
    this.busy = false;
    this.paired = false;
    this.stateLine = '已断开';
  }

  /** 第一步：解析配对 JSON、握手、发起配对请求。 */
  private async startPairing(): Promise<void> {
    this.stop();
    this.frames = [];
    this.eventCount = 0;
    this.deltaCount = 0;
    this.errorCode = '';
    this.busy = true;
    this.stateLine = '握手中…';
    try {
      const value = JSON.parse(this.pairingJson.trim()) as ProbePairingCode;
      if (value.url === undefined || value.code === undefined || value.serverId === undefined) {
        throw new Error('配对 JSON 缺少 url / code / serverId。');
      }
      const pin = value.tlsPin ?? '';
      this.log(`配对码 url=${value.url} 指纹=${pin.length > 0 ? '有' : '无'}`);
      const client = new MobileClient(value.url, pin);
      const info: RawServerInfo = await client.info();
      this.log(`HTTP ok  protocolVersion=${info.protocolVersion} serverId=${info.serverId.slice(0, 8)}…`);
      if (info.serverId !== value.serverId) throw new Error('服务器身份与配对码不一致。');
      this.log('服务器身份与配对码一致 ✓');
      const pairing: RawPairingStart = await client.pair(value.code, this.deviceName.trim());
      this.claimToken = pairing.claimToken;
      this.client = client;
      this.stateLine = '等待电脑端批准';
      this.log('配对请求已提交，请在电脑端批准…');
    } catch (error) {
      const failure = error as Error;
      this.stateLine = `失败：${failure.message}`;
      this.log(`失败：${failure.message}`);
    } finally {
      this.busy = false;
    }
  }

  /** 第二步：轮询完成配对（需要在电脑端点批准），然后订阅事件流。 */
  private async completePairing(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.claimToken.length === 0) {
      this.log('请先点「1 验证配对码」发起配对请求。');
      return;
    }
    this.busy = true;
    this.stateLine = '等待批准…';
    try {
      let session: Session | undefined = undefined;
      for (let attempt = 0; attempt < 60 && session === undefined; attempt++) {
        session = await client.completePairing(this.claimToken);
        if (session === undefined) await new Promise<void>((resolve) => setTimeout(resolve, 1500));
      }
      if (session === undefined) throw new Error('等待批准超时。');
      this.paired = true;
      this.log(`配对完成 deviceId=${session.deviceId.slice(0, 8)}…`);
      this.stateLine = '已配对，订阅事件流…';
      await this.openStream();
    } catch (error) {
      const failure = error as Error;
      this.stateLine = `失败：${failure.message}`;
      this.log(`失败：${failure.message}`);
    } finally {
      this.busy = false;
    }
  }

  /** 第三步：取一个会话并打开事件流。 */
  private async openStream(): Promise<void> {
    const client = this.client;
    if (client === undefined) return;
    const result: RawConversationList = await client.conversations();
    if (result.conversations.length === 0) {
      this.log('主机没有可订阅的会话。');
      return;
    }
    const first = result.conversations[0] as ProbeConversation;
    this.conversationId = first.id;
    this.log(`选用会话 ${first.name ?? '(未命名)'}（${this.conversationId.slice(0, 12)}…）`);
    this.log('ws connecting…');
    client.openStream(this.conversationId, 0, {
      onEvent: (event: MobileEvent): void => this.handleEvent(event),
      onStatus: (value: StreamStatus): void => {
        this.log(`ws ${value}`);
        this.connected = value === 'connected';
        this.stateLine = `事件流：${value}`;
      },
      onError: (message: string, code: string): void => this.log(`ws 错误 [${code}] ${message}`)
    });
  }

  private handleEvent(event: MobileEvent): void {
    this.eventCount++;
    if (event.type === 'delta') this.deltaCount++;
    if (event.type === 'error' && event.error !== undefined) this.errorCode = event.error.code;
    const parts: string[] = [event.type];
    if (event.eventSeq !== undefined) parts.push(`eventSeq=${event.eventSeq}`);
    if (event.attemptId !== undefined) parts.push(`attempt=…${event.attemptId.slice(-4)}`);
    if (event.index !== undefined) parts.push(`index=${event.index}`);
    if (event.text !== undefined) parts.push(`text=${event.text.length}字`);
    if (event.reasoning !== undefined) parts.push(`reasoning=${event.reasoning.length}字`);
    if (event.messages !== undefined) parts.push(`messages=${event.messages.length}`);
    if (event.queue !== undefined) parts.push(`queue=${event.queue.length}`);
    if (event.running !== undefined) parts.push(`running=${event.running}`);
    if (event.phase !== undefined) parts.push(`phase=${event.phase}`);
    if (event.error !== undefined) parts.push(`code=${event.error.code}`);
    this.log(`帧 ${parts.join(' ')}`);
  }

  /** 主动发送一条消息，用于观察 delta / message 帧。 */
  private async probeSend(): Promise<void> {
    const client = this.client;
    if (client === undefined || this.conversationId.length === 0) {
      this.log('事件流尚未就绪。');
      return;
    }
    try {
      const target: RawTarget = await client.target(this.conversationId);
      const submission: SubmissionRequest = {
        conversationId: this.conversationId,
        sessionId: target.sessionId,
        requestId: `probe-${Date.now()}`,
        text: '只回复两个字：收到'
      };
      await client.submit(submission);
      this.log('已提交探针消息，观察 delta / message 帧…');
    } catch (error) {
      const failure = error as Error;
      this.log(`发送失败：${failure.message}`);
    }
  }

  /**
   * 原始 WebSocket 诊断：不走业务逻辑，直接把 NetStack 的 open/error/close 回调打出来。
   * 用来区分「鸿蒙侧握手失败」与「主机侧拒绝升级」。
   */
  /**
   * 对照实验：同一地址分别用三种 header 配置连接，判断 `header` 选项是否真的生效。
   * 结论用于确定修复方式（是否需要在客户端显式覆盖 Origin）。
   */
  private async headerExperiment(): Promise<void> {
    await this.rawSocketTest(undefined, 'A 不传 header');
    await new Promise<void>((resolve) => setTimeout(resolve, 2500));
    await this.rawSocketTest({ 'Origin': 'https://192.168.1.100:9443' }, 'B Origin 带端口');
    await new Promise<void>((resolve) => setTimeout(resolve, 2500));
    await this.rawSocketTest({ 'Origin': 'https://192.168.1.100' }, 'C Origin 无端口');
    await new Promise<void>((resolve) => setTimeout(resolve, 2500));
    await this.rawSocketTest({ 'Origin': 'https://example.invalid', 'X-Probe': 'yes' }, 'D 自定义头');
  }

  private async rawSocketTest(headers: Record<string, string> | undefined, label: string): Promise<void> {
    this.log(`raw ws [${label}] → ${this.wsUrl}`);
    try {
      const socket = webSocket.createWebSocket();
      this.probeSocket = socket;
      socket.on('open', () => this.log('raw ws open ✓（TCP+TLS+升级握手全部成功）'));
      socket.on('message', (error: Error, value: string | ArrayBuffer) => {
        if (error !== undefined) {
          this.log(`raw ws message 回调错误：${error.message}`);
          return;
        }
        const text = typeof value === 'string' ? value : '(binary)';
        this.log(`raw ws 收到：${text.slice(0, 120)}`);
      });
      socket.on('close', (error: Error, value: webSocket.CloseResult) => {
        this.log(`raw ws close code=${value === undefined ? 0 : value.code} reason=${value === undefined ? '' : value.reason}`);
      });
      socket.on('error', (error: Error) => this.log(`raw ws error：${error === undefined ? '(空)' : error.message}`));
      const options: webSocket.WebSocketRequestOptions = { skipServerCertVerification: true };
      if (headers !== undefined) options.header = headers;
      await socket.connect(this.wsUrl, options);
      this.log('raw ws connect() 已返回');
    } catch (error) {
      const failure = error as Error;
      this.log(`raw ws 异常：${failure.message}`);
    }
  }

  @Builder
  private infoRow(label: string, value: string) {
    Row({ space: 8 }) {
      Text(label).fontSize(12).fontColor('#6F758B').width(96);
      Text(value).fontSize(12).fontColor('#202336').layoutWeight(1);
    }.width('100%')
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button('原生动作面板自检').layoutWeight(1).height(38).fontSize(13)
          .backgroundColor('#EEF1FF').fontColor('#3A46C8')
          .onClick(() => this.demoSheetVisible = true)
      }.width('100%')
      if (this.demoSheetResult !== '（未点击）') {
        Text(`面板回调：${this.demoSheetResult}`).fontSize(12).fontColor('#24B47E').width('100%')
      }
      Row({ space: 8 }) {
        Button('事件流诊断').layoutWeight(1).height(38).fontSize(14)
          .backgroundColor(this.mode === 'stream' ? '#4D6BFE' : '#EEF1FF')
          .fontColor(this.mode === 'stream' ? '#FFFFFF' : '#3A46C8')
          .onClick(() => this.mode = 'stream')
        Button('头像诊断').layoutWeight(1).height(38).fontSize(14)
          .backgroundColor(this.mode === 'avatar' ? '#4D6BFE' : '#EEF1FF')
          .fontColor(this.mode === 'avatar' ? '#FFFFFF' : '#3A46C8')
          .onClick(() => this.mode = 'avatar')
      }.width('100%')
      if (this.mode === 'avatar') {
        AvatarProbe().layoutWeight(1)
      } else {
        this.streamPanel()
      }
    }
    .width('100%').height('100%').padding(16).backgroundColor('#FFFFFF')
    .bindSheet(this.demoSheetVisible, this.demoSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      onDisappear: (): void => { this.demoSheetVisible = false; }
    })
  }

  /** 自检面板内容：验证原生 bindSheet 通路。 */
  @Builder
  private demoSheet() {
    MessageActionSheet({
      actions: [
        { label: '复制消息', run: (): void => { this.demoSheetResult = '复制消息'; } },
        { label: '复制思考过程', run: (): void => { this.demoSheetResult = '复制思考过程'; } },
        { label: '引用到输入框', run: (): void => { this.demoSheetResult = '引用到输入框'; } }
      ] as MessageAction[],
      onClose: (): void => { this.demoSheetVisible = false; },
      onAction: (action: MessageAction): void => {
        this.demoSheetResult = action.label;
        this.demoSheetVisible = false;
        action.run();
      }
    })
  }

  @Builder
  private streamPanel() {
    Column({ space: 10 }) {
      Text('事件流可行性验证').fontSize(20).fontWeight(FontWeight.Bold).width('100%')
      Text('验证 HTTP 证书锁定与 /mobile/v1/events 事件流。此页不写入任何业务数据，只做连接与订阅。')
        .fontSize(12).fontColor('#6F758B').width('100%')
      TextArea({ placeholder: '粘贴电脑端的完整配对 JSON', text: this.pairingJson })
        .width('100%').height(84).fontSize(12)
        .onChange((value: string) => this.pairingJson = value)
      TextInput({ placeholder: '设备名', text: this.deviceName })
        .width('100%').height(42).fontSize(13)
        .onChange((value: string) => this.deviceName = value)
      Row({ space: 8 }) {
        Button('1 验证配对码').layoutWeight(1).height(40).fontSize(13)
          .enabled(!this.busy && this.pairingJson.trim().length > 0)
          .onClick(() => void this.startPairing())
        Button('2 批准并订阅').layoutWeight(1).height(40).fontSize(13)
          .enabled(!this.busy && this.client !== undefined)
          .onClick(() => void this.completePairing())
      }.width('100%')
      TextInput({ placeholder: '诊断用 WebSocket 地址', text: this.wsUrl })
        .width('100%').height(40).fontSize(12)
        .onChange((value: string) => this.wsUrl = value)
      Button('原始 WebSocket 直连诊断').width('100%').height(38).fontSize(13)
        .backgroundColor('#EEF1FF').fontColor('#3A46C8')
        .onClick(() => void this.rawSocketTest(undefined, 'A 不传 header'))
      Button('Origin 对照实验 A/B/C/D').width('100%').height(38).fontSize(13)
        .backgroundColor('#FFF4E5').fontColor('#C77A28')
        .onClick(() => void this.headerExperiment())
      Row({ space: 8 }) {
        Button('发送探针消息').layoutWeight(1).height(38).fontSize(13)
          .enabled(this.connected)
          .onClick(() => void this.probeSend())
        Button('断开').layoutWeight(1).height(38).fontSize(13)
          .backgroundColor('#FDECEC').fontColor('#C93C3C')
          .onClick(() => {
            this.log('手动断开');
            this.stop();
          })
      }.width('100%')
      Column({ space: 4 }) {
        this.infoRow('状态', this.stateLine)
        this.infoRow('已配对', this.paired ? '是' : '否')
        this.infoRow('已连接', this.connected ? '是' : '否')
        this.infoRow('事件总数', `${this.eventCount}（delta ${this.deltaCount}）`)
        this.infoRow('错误码', this.errorCode.length > 0 ? this.errorCode : '无')
      }.width('100%').padding(10).backgroundColor('#F6F7FB').borderRadius(10)
      Text('帧日志').fontSize(13).fontWeight(FontWeight.Medium).width('100%')
      Scroll(this.scroller) {
        Column({ space: 2 }) {
          ForEach(this.frames, (line: string) => {
            Text(line).fontSize(11).fontColor('#202336').width('100%')
              .fontFamily('monospace').copyOption(CopyOptions.LocalDevice)
          }, (line: string, index: number) => `${index}-${line}`)
        }.width('100%')
      }
      .layoutWeight(1).width('100%').padding(8)
      .backgroundColor('#F6F7FB').borderRadius(10).scrollBar(BarState.Auto)
    }
    .width('100%').height('100%').alignItems(HorizontalAlign.Start)
  }
}
