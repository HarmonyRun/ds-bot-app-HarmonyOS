import { Message } from '../model/Models';

/**
 * 消息滚动区（抽自 `Index.ets` 的 `chatPanel` 与 `mobileChatPanel`）。
 *
 * 两个面板里这段**几乎逐行相同**（各 22 行），差异只有加载点颜色与底部 padding：
 *
 * ```
 * Scroll(this.scroller) {
 *   Column() {
 *     earlierMessagesButton();                      // 加载更早
 *     if (questions > 0) chatQuestions();            // 提问卡
 *     if (messages.length === 0) 空态;              // 空态
 *     ForEach(messages, messageBubble);             // 消息
 *     if (busy) 加载行;                              // 工作指示
 *   }...
 * }
 * ```
 *
 * 设计：**列表骨架在这里，内容片段由父组件注入**。
 * `earlierButton` / `questions` / `emptyState` / `messageItem` 用 `@BuilderParam` 承接——
 * 它们依赖父组件大量状态（提问卡要草稿与提交动作、消息要头像与长按动作），
 * 搬进来会让组件变成「Index 的镜像」；用 BuilderParam 注入能让骨架与内容各自独立。
 */
@Component
export struct ChatMessageList {
  /** 滚动控制器（父组件持有，用于「发送后滚到底」等）。 */
  scroller: Scroller = new Scroller();
  /** 要渲染的消息（父组件已按会话整理并去重）。 */
  @Prop messages: Message[] = [];
  /** 是否显示「正在工作」指示。 */
  @Prop busy: boolean = false;
  /** 窄屏形态（字号/间距更大）。 */
  @Prop compact: boolean = false;
  /** 加载点颜色（手机 #4D6BFE / 宽屏 #665CF6）。 */
  @Prop spinnerColor: string = '#4D6BFE';
  @Prop muted: string = '#6F758B';
  /** 桌面端给内容列一个最大宽度并居中，手机上铺满。 */
  @Prop desktopInset: boolean = false;

  /** 「加载更早消息」按钮；无 cursor 时应自行不渲染。 */
  @BuilderParam earlierButton: () => void;
  /** 提问卡区（无提问时应自行不渲染）。 */
  @BuilderParam questions: () => void;
  /** 空态内容。 */
  @BuilderParam emptyState: () => void;
  /** 单条消息的渲染（父组件负责传参）。 */
  @BuilderParam messageItem: (message: Message) => void;

  build() {
    Scroll(this.scroller) {
      Column() {
        this.earlierButton();
        this.questions();
        if (this.messages.length === 0) {
          this.emptyState();
        }
        ForEach(this.messages, (message: Message) => {
          this.messageItem(message);
        }, (message: Message) => message.id);
        if (this.busy) {
          Row({ space: 10 }) {
            LoadingProgress().width(22).height(22).color(this.spinnerColor);
            Text('Bot 正在主机上工作…').fontSize(13).fontColor(this.muted);
          }.padding(18).width('100%');
        }
      }
      .width('100%')
      .constraintSize(this.desktopInset ? { maxWidth: 920 } : {})
      .alignSelf(this.desktopInset ? ItemAlign.Center : ItemAlign.Auto)
      .padding(this.desktopInset ? {} : { top: 8, bottom: 8 });
    }
    .layoutWeight(1).width('100%').scrollBar(BarState.Off);
  }
}
