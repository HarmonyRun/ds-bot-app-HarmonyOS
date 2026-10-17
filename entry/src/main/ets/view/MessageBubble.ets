import { Message } from '../model/Models';
import { MarkdownView, MarkdownTheme } from './MarkdownView';
import { ReasoningBlock } from './ReasoningBlock';
import { ToolCard, ToolCardTheme } from './ToolCard';
import { AvatarSpec, BotAvatar } from './BotAvatar';
import { themeOf } from './Theme';

/**
 * 单条消息气泡（抽自 `Index.ets` 的 `messageBubble()`）。
 *
 * 这一步把消息渲染整条链路都变成了组件：
 * `MessageBubble` → `ReasoningBlock` / `ToolCard` / `MarkdownView` / `BotAvatar`，
 * 页面里不再有消息渲染逻辑。
 *
 * 设计：**父组件算好宽度与作者头像**。
 * - 气泡宽度与 Markdown 内容宽度由父组件传入（口径在 `Index.bubbleMaxWidth()` /
 *   `bubbleContentWidth()`，那里是唯一来源；组件不重复推导，避免两处算法分叉——
 *   这个坑在 2026-10-16 的溢出问题里踩过）
 * - 作者头像的 `AvatarSpec` 由父组件解析（需要 `team` 查找），组件只画
 * - 长按通过 `onLongPress` 交回父组件（动作面板仍由父组件持有）
 */
export interface BubbleMetrics {
  /** 气泡最大宽度（vp） */
  maxWidth: number;
  /** Markdown 内容可用宽度（vp） */
  contentWidth: number;
  /** 气泡内边距（vp） */
  padding: number;
  /** 窗口宽（判断宽/窄屏形态） */
  windowWidth: number;
}

@Component
export struct MessageBubble {
  @Prop message: Message = {
    id: '', sessionId: '', seq: 0, role: 'user', text: '', createdAt: 0
  };
  @Prop metrics: BubbleMetrics = { maxWidth: 320, contentWidth: 280, padding: 13, windowWidth: 440 };
  @Prop dark: boolean = false;
  /** 群聊作者头像（为空则不显示头像行） */
  @Prop authorAvatar: AvatarSpec | undefined = undefined;
  /** 作者显示名（群聊作者） */
  @Prop authorName: string = '';

  onLongPress: (message: Message) => void = (): void => {};
  onCopy: (text: string, toast: string) => void = (): void => {};

  private narrow(): boolean {
    return this.metrics.windowWidth < 600;
  }

  private isUser(): boolean {
    return this.message.role === 'user';
  }

  private markdownTheme(): MarkdownTheme {
    const tokens = themeOf(this.dark);
    return {
      ink: tokens.ink, muted: tokens.muted, surface: tokens.surface, line: tokens.line,
      code: tokens.code, link: tokens.link
    };
  }

  private toolTheme(): ToolCardTheme {
    const tokens = themeOf(this.dark);
    return {
      ink: tokens.ink, muted: tokens.muted, cardBg: tokens.pageBg,
      line: tokens.line, link: tokens.link
    };
  }

  /**
   * 气泡内容（作者行 / 思考过程 / 工具卡 / Markdown / 发送态）。
   *
   * 装在**定宽的内层 Column** 里——这是修「表格/代码块/列表溢出气泡」的结构性做法：
   * 外层气泡用 `constraintSize({ maxWidth })` + `padding`，其子项的 `width('100%')`
   * 会按**外层盒子全宽**（不含 padding）解析，比内边距边界多出「两侧 padding」，
   * 于是右对齐内容（列表、标题、代码块）一路顶到气泡背景边缘
   * （2026-10-16 反复出现：文字到 x=1108，而内边距边界应为 x=1084）。
   */
  @Builder
  private bubbleContent() {
    Column({ space: 6 }) {
      this.authorRow();
      if (this.message.reasoning !== undefined && this.message.reasoning.length > 0) {
        ReasoningBlock({
          reasoning: this.message.reasoning,
          pending: this.message.pending === true,
          compact: this.narrow(),
          tokens: { muted: themeOf(this.dark).muted, pending: '#B86A16', accent: themeOf(this.dark).brand }
        });
      }
      if (this.message.tool !== undefined) {
        ToolCard({
          tool: this.message.tool,
          tokens: this.toolTheme(),
          maxWidth: this.metrics.contentWidth,
          onCopy: (text: string, toast: string): void => this.onCopy(text, toast)
        });
      } else if (this.message.text.length > 0) {
        MarkdownView({
          text: this.message.text,
          theme: this.markdownTheme(),
          fontSize: this.narrow() ? 16 : 15,
          ownBubble: this.isUser(),
          // 块级容器铺满内层定宽 Column；行内文字（列表/引用）用数值扣缩进与符号位
          maxContentWidth: -1,
          measureWidth: this.metrics.contentWidth
        });
      }
      if (this.message.pending === true) {
        Text(this.isUser() ? '发送中…' : '正在输出…')
          .fontSize(11).fontColor(this.isUser() ? '#5B6B99' : themeOf(this.dark).muted);
      }
    }
    .width(this.metrics.contentWidth)
    .alignItems(HorizontalAlign.Start);
  }

  build() {
    // 对齐用 `justifyContent`，**不要用 `Blank()`**：
    // Blank 会贪婪占位，与气泡的 `constraintSize({ maxWidth })` 叠加后总数超过行宽，
    // 用户气泡会被推到屏幕右边缘（2026-10-16 实测 bounds 右边界 = 屏宽）。
    Row() {
      // 外层只负责内边距与背景；内容宽度由内层定宽 Column 决定
      this.bubbleContentFrame();
    }
    .width('100%')
    .justifyContent(this.isUser() ? FlexAlign.End : FlexAlign.Start)
    .padding({
      left: this.narrow() ? 14 : 20, right: this.narrow() ? 14 : 20,
      top: this.narrow() ? 7 : 6, bottom: this.narrow() ? 7 : 6
    });
  }

  /** 气泡外框：内边距 + 圆角 + 底色 + 长按手势。 */
  @Builder
  private bubbleContentFrame() {
    Column() {
      this.bubbleContent();
    }
    .alignItems(HorizontalAlign.Start)
    .constraintSize({ maxWidth: this.metrics.maxWidth })
    .padding({
      left: this.metrics.padding, right: this.metrics.padding, top: 13, bottom: 13
    })
    .borderRadius(this.narrow() ? 18 : 14)
    .backgroundColor(this.bubbleColor())
    .border({ width: this.isUser() ? 0 : 1, color: themeOf(this.dark).line })
    .gesture(LongPressGesture().onAction(() => this.onLongPress(this.message)));
  }

  /** 气泡底色：窄屏用浅灰/浅蓝，宽屏用户气泡用品牌紫、其余用卡片底色。 */
  private bubbleColor(): string {
    const tokens = themeOf(this.dark);
    if (this.dark) return this.isUser() ? '#26385F' : tokens.surface;
    return this.isUser() ? '#EAF0FF' : tokens.surface;
  }

  @Builder
  private authorRow() {
    // 作者标识：群聊里每条回复显示是谁在说话（P1-7）；单聊沿用「你 / Bot」。
    if (this.message.role === 'assistant' && this.authorName.length > 0) {
      Row({ space: 6 }) {
        BotAvatar({
          spec: this.authorAvatar ?? { shape: '', color: '', image: '', main: false, live: false },
          avatarSize: 18,
          dark: this.dark
        });
        Text(this.authorName).fontSize(12).fontWeight(FontWeight.Medium)
          .fontColor(themeOf(this.dark).ink).maxLines(1);
      }.alignItems(VerticalAlign.Center);
    } else if (this.metrics.windowWidth >= 600) {
      Text(this.isUser() ? '你' : this.message.role === 'assistant' ? 'Bot' : this.message.role)
        .fontSize(11)
        .fontColor(this.isUser() ? '#52668F' : themeOf(this.dark).muted);
    }
  }
}
