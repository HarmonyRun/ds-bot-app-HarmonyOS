import { pasteboard } from '@kit.BasicServicesKit';
import { Block, Span, TableRow, ListBlock, ListItem, parseMarkdown, safeMarkdownLink } from '../logic/Markdown';

/** 渲染 Markdown 片段所需的主题色（由父组件传入，避免这里依赖 Index 的主题实现）。 */
export interface MarkdownTheme {
  ink: string;
  muted: string;
  surface: string;
  line: string;
  code: string;
  link: string;
}

/**
 * 把 Markdown 文本渲染成 ArkUI 组件（P1-3）。
 *
 * 与上游 `MarkdownText.tsx` 对齐的能力：
 * - 标题（`#`…`######`，字号随层级递减）
 * - 围栏代码块：语言标签 + 复制按钮 + 等宽字体
 * - 无序 / 有序列表（含一层嵌套）
 * - 引用（左侧竖线）
 * - 分隔线、GFM 管道表格（可横向滚动）
 * - 行内：粗体、斜体、删除线、行内代码、链接、提及、软换行
 *
 * 已知差异（不吹）：
 * - 不解析 HTML 原文（上游同样 `html: false`，行为一致）
 * - 表格列宽固定，不做自适应
 * - 链接点击：只复制到剪贴板并提示，不做系统跳转（跳转需要 `Want` + 用户确认，留到 P3）
 * - 不支持引用式链接、脚注、任务列表复选框
 */
@Component
export struct MarkdownView {
  @Prop text: string = '';
  @Prop theme: MarkdownTheme = {
    ink: '#202336',
    muted: '#6F758B',
    surface: '#FFFFFF',
    line: '#E7E9F1',
    code: '#F0F2F7',
    link: '#4D6BFE'
  };
  @Prop fontSize: number = 15;
  /**
   * 是否为自己发送的气泡。
   * 注意：主题化只影响**背景**（用户气泡在深色模式下仍是浅底 `#EDF3FF`），
   * 所以用户气泡的正文必须用深色，不能用白色——否则文字会看不见。
   */
  @Prop ownBubble: boolean = false;
  /** 气泡内可用宽度（vp）。由调用方按窗口宽度算好传入，见 bubbleContentWidth()。 */
  @Prop maxContentWidth: number = 0;
  @State blocks: Block[] = [];
  @State copiedCode: number = -1;

  aboutToAppear(): void {
    this.blocks = parseMarkdown(this.text);
  }

  /** 文本变化时重新解析（流式输出会不断更新同一个消息体）。 */
  onTextChanged(): void {
    this.blocks = parseMarkdown(this.text);
  }

  private ink(): string {
    return this.ownBubble ? '#1B1F35' : this.theme.ink;
  }

  private muted(): string {
    return this.ownBubble ? '#5B6B99' : this.theme.muted;
  }

  /**
   * 内容可用宽度（vp）——气泡内宽。
   *
   * 为什么必须是确定值：`Scroll`（代码块/表格）与 `Flex`（行内片段）在
   * 「父容器只给了 `constraintSize({ maxWidth })`」时会退化为按**内容**测量，
   * 长代码行会把气泡整个撑开，之后所有内容溢出气泡边界。
   * 2026-10-16 已用构造用例复现（见 P1 报告 §9.6）。
   */
  private blockWidth(): number {
    return this.maxContentWidth > 0 ? this.maxContentWidth : 320;
  }

  /**
   * 列表某一层可用的内容宽度。
   *
   * **为什么要按层递减**：ArkUI 的 `padding` 按 border-box 计入宽度内部，
   * 所以 `Row().width('100%').padding({ left: depth * 12 })` 的**内容区**只有
   * `100% - depth * 12`。若子项仍按满宽布局，每层缩进都会把文字往右推，
   * 深层嵌套必然越出气泡背景（2026-10-16 实测：背景右边界 1132px，列表文字到 1141px，
   * 且层级越深超出越多）。
   */
  private listWidth(depth: number): number {
    const indent = depth * 12;
    const width = this.blockWidth() - indent;
    return width > 60 ? width : 60;
  }

  /** 引用块内文字的可用宽度（引用块自身有左侧竖线与内边距）。 */
  private quoteTextWidth(): number {
    const width = this.blockWidth() - 40;
    return width > 40 ? width : 40;
  }

  /** 列表某一层里**文字**的可用宽度：再扣掉项目符号(minWidth 14) 与 Row space(7)。 */
  private listTextWidth(depth: number): number {
    // 逐层扣减：项目符号(minWidth 14) + Row space(7) + 余量。
    // 余量取 16vp 是按**紧邻父容器**实测收敛的：只留 4vp 时深层列表仍超出父 Column 约 35px
    // （约 12vp）——之前只与「气泡」比对了右边界，漏掉了这一层（2026-10-16）。
    const width = this.listWidth(depth) - 37;
    return width > 40 ? width : 40;
  }

  private copy(value: string, codeIndex: number): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, value);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.copiedCode = codeIndex;
    } catch (_error) {
      this.copiedCode = -2;
    }
  }

  /**
   * 是否加粗。样式有两个来源，都要看：
   * - `kind`：顶层或递归得到的片段类型（`strong` / `em` / `strike`）
   * - `extra`：组合样式（`**_加粗斜体_**` 这类嵌套时把外层类型记在 extra）
   */
  private bold(kind: string, extra: string | undefined): boolean {
    return kind === 'strong' || this.hasMark(extra, 'strong');
  }

  private italic(kind: string, extra: string | undefined): boolean {
    return kind === 'em' || this.hasMark(extra, 'em');
  }

  private strike(kind: string, extra: string | undefined): boolean {
    return kind === 'strike' || this.hasMark(extra, 'strike');
  }

  /** `extra` 里是否含某个样式标记（空格分隔，如 `strong em`）。 */
  private hasMark(extra: string | undefined, mark: string): boolean {
    if (extra === undefined || extra.length === 0) return false;
    return extra.split(' ').includes(mark);
  }

  /**
   * 行内片段 → 一个 `Text` + 多个 `Span`。
   *
   * **这是本文件最重要的布局约束之一**：行内混排必须用 `Text` 承载 `Span`，
   * 不能用 `Flex({ wrap: Wrap })` 装一串独立 `Text`。原因：`Flex` 是通用容器，
   * 测量时把每个子 `Text` 当**不可分割的盒子**，`wordBreak` 只作用于文本自身的换行、
   * 无法让 `Flex` 在字符间断开——于是长 URL / 无空格串会整体溢出气泡
   * （2026-10-16 用户报告，先误判为气泡宽度问题，实际是这里）。
   * `Text` 才是文本容器，换行/断词由它统一计算，才能正确折行。
   *
   * 样式映射：
   * - code：等宽 + 底色（行内代码）
   * - link/image：链接色 + 下划线，点击复制（P1 只复制，系统跳转留 P3）
   * - mention：链接色 + 中等字重
   * - 其余：正文色，按 extra 叠加粗体/斜体/删除线
   */
  @Builder
  private inlineSpans(spans: Span[], baseSize: number, availWidth: number) {
    Text() {
      ForEach(spans, (item: Span, index: number) => {
        if (item.kind === 'softbreak') {
          Span('\n').fontSize(baseSize)
        } else if (item.kind === 'code') {
          Span(item.text)
            .fontSize(baseSize - 1)
            .fontFamily('monospace')
            .fontColor(this.ink())
            .textBackgroundStyle({ color: this.ownBubble ? '#D8E4FA' : this.theme.code, radius: 4 })
        } else if (item.kind === 'link' || item.kind === 'image') {
          Span(item.text.length > 0 ? item.text : (item.href ?? ''))
            .fontSize(baseSize)
            .fontColor(this.ownBubble ? '#2A4BB8' : this.theme.link)
            .decoration({
              type: TextDecorationType.Underline,
              color: this.ownBubble ? '#2A4BB8' : this.theme.link
            })
            .onClick(() => {
              const safe = safeMarkdownLink(item.href ?? '');
              if (safe === undefined) {
                this.copy(item.href ?? '', -2);
                return;
              }
              // P1 只复制链接；系统跳转留到 P3（需要 Want + 用户确认）
              this.copy(safe, -1);
            })
        } else if (item.kind === 'mention') {
          Span(item.text)
            .fontSize(baseSize)
            .fontColor(this.ownBubble ? '#2A4BB8' : this.theme.link)
            .fontWeight(FontWeight.Medium)
        } else {
          Span(item.text)
            .fontSize(baseSize)
            .fontColor(this.ink())
            .fontWeight(this.bold(item.kind, item.extra) ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(this.italic(item.kind, item.extra) ? FontStyle.Italic : FontStyle.Normal)
            .decoration(this.strike(item.kind, item.extra) ?
              { type: TextDecorationType.LineThrough, color: this.ink() } :
              { type: TextDecorationType.None, color: this.ink() })
        }
      }, (item: Span, index: number) => `${index}:${item.kind}:${item.text.length}`)
    }
    // 断行发生在 Text 上；BREAK_WORD 让长 URL / 无空格串在字符间折行
    .wordBreak(WordBreak.BREAK_WORD)
    // 必须用**调用方传入的可用宽度**，不能固定用 blockWidth()（气泡全宽）：
    // 列表/引用会通过 padding 把内容推右，若文字仍按全宽排版，起点+宽度就会越出气泡
    // （2026-10-16 铁证：Text x0=323 宽=956 → 右边界 1279，而气泡右边界仅 1075）。
    .width(availWidth > 40 ? availWidth : 40)
  }


  @Builder
  private codeBlock(item: Block, index: number) {
    Column() {
      Row() {
        Text(item.info.length > 0 ? item.info : '代码')
          .fontSize(11).fontColor(this.muted()).layoutWeight(1)
        Text(this.copiedCode === index ? '已复制' : this.copiedCode === -2 ? '复制失败' : '复制')
          .fontSize(12)
          .fontColor(this.copiedCode === -2 ? '#C93C3C' : this.muted())
          .padding({ left: 12, right: 4, top: 6, bottom: 6 })
          .onClick(() => this.copy(item.code, index))
      }
      .width('100%').padding({ left: 12, right: 8 })
      .border({ width: { bottom: 1 }, color: this.theme.line })
      Scroll() {
        Text(item.code)
          .fontSize(13).lineHeight(20).fontFamily('monospace').fontColor(this.ink())
          .copyOption(CopyOptions.LocalDevice)
          .wordBreak(WordBreak.BREAK_ALL)
          .padding(12)
      }
      .scrollable(ScrollDirection.Horizontal)
      // **关键**：横向 Scroll 在「父容器只有 maxWidth」时会按内容宽度测量，把气泡撑开。
      // 在 Scroll 自身加 maxWidth 约束，它才会被压缩并在内部横向滚动。
      .constraintSize({ maxWidth: this.blockWidth() })
      .width('100%').scrollBar(BarState.Off)
    }
    .width('100%').constraintSize({ maxWidth: this.blockWidth() })
    .backgroundColor(this.theme.surface)
    .borderRadius(10)
    .border({ width: 1, color: this.theme.line })
  }

  @Builder
  private listBlock(list: ListBlock, depth: number) {
    Column({ space: 5 }) {
      ForEach(list.items, (entry: ListItem, index: number) => {
        Row({ space: 7 }) {
          Text(list.ordered ? `${entry.marker}.` : '•')
            .fontSize(this.fontSize).fontColor(this.ink())
            .constraintSize({ minWidth: 14 })
          Column({ space: 5 }) {
            // 剩余宽度 = 本层宽度 - 本层缩进 - 项目符号 - 间距
            this.inlineSpans(entry.spans, this.fontSize, this.listTextWidth(depth));
            if (entry.child !== undefined) {
              this.listBlock(entry.child, depth + 1);
            }
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        }
        // 宽度按层递减：缩进已占用宽度，子行必须用剩余宽度，否则文字被推出气泡
        .width(this.listWidth(depth)).alignItems(VerticalAlign.Top)
        .padding({ left: depth * 12 })
      }, (entry: ListItem, index: number) => `${depth}:${index}:${entry.marker}`)
    }
    // **确定宽度**，不用 `width('100%')`：本组件挂在「只有 constraintSize({maxWidth})」
    // 的气泡里时，百分比会按内容解析，长文本会把宽度算成内容宽并溢出气泡
    // （2026-10-16 实测：用户气泡内层 1075px 伸到屏宽 1320px）。
    .width(this.blockWidth()).alignItems(HorizontalAlign.Start)
  }

  @Builder
  private tableBlock(rows: TableRow[]) {
    Scroll() {
      Column() {
        ForEach(rows, (row: TableRow, rowIndex: number) => {
          // 用 Flex 而非 Row：`Row.alignItems` 只接受 VerticalAlign(Top/Center/Bottom)，
          // **无法把单元格拉伸到行高**；`Flex` + `ItemAlign.Stretch` 才能让同排单元格等高，
          // 从而背景色与底边框覆盖整行（2026-10-16 用户报告「左右单元格高度值不统一」）。
          Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
            ForEach(row.cells, (cell: TableCellView, colIndex: number) => {
              Column() {
                // 单元格内可用宽度 = 列宽 148 - 内边距(10*2)
                this.inlineSpans(cell.spans, this.fontSize - 1, 128);
              }
              .width(148).padding(10).alignItems(HorizontalAlign.Start)
              .backgroundColor(cell.header ? this.theme.line : this.theme.surface)
              .border({ width: { left: colIndex > 0 ? 1 : 0, bottom: 1 }, color: this.theme.line })
            }, (cell: TableCellView, colIndex: number) => `${rowIndex}:${colIndex}`)
          }
          .width('100%')
        }, (row: TableRow, rowIndex: number) => `row:${rowIndex}`)
      }
      .border({ width: 1, color: this.theme.line })
      .borderRadius(7)
    }
    .scrollable(ScrollDirection.Horizontal)
    .constraintSize({ maxWidth: this.blockWidth() })
    .width('100%').scrollBar(BarState.Off)
  }

  @Builder
  private blockView(item: Block, index: number) {
    if (item.kind === 'heading') {
      Text(this.plainOf(item.spans))
        .fontSize(Math.max(this.fontSize + 1, 25 - item.level * 2))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.ink())
        .wordBreak(WordBreak.BREAK_WORD)
        .width('100%').margin({ top: 4 })
    } else if (item.kind === 'code') {
      this.codeBlock(item, index);
    } else if (item.kind === 'rule') {
      Divider().color(this.theme.line).margin({ top: 5, bottom: 5 });
    } else if (item.kind === 'list' && item.list !== undefined) {
      this.listBlock(item.list, 0);
    } else if (item.kind === 'quote') {
      Column({ space: 7 }) {
        ForEach(item.blocks, (inner: Block, innerIndex: number) => {
          this.blockView(inner, innerIndex);
        }, (inner: Block, innerIndex: number) => `quote:${innerIndex}`)
      }
      .width('100%').padding({ left: 11 })
      .border({ width: { left: 3 }, color: this.muted() })
      .alignItems(HorizontalAlign.Start)
    } else if (item.kind === 'table') {
      this.tableBlock(item.rows);
    } else {
      this.inlineSpans(item.spans, this.fontSize, this.quoteTextWidth());
    }
  }

  /** 标题按纯文本渲染（标题内部的行内样式在 P1 不单独着色）。 */
  private plainOf(spans: Span[]): string {
    const parts: string[] = [];
    for (const item of spans) {
      if (item.kind === 'softbreak') {
        parts.push(' ');
        continue;
      }
      parts.push(item.text);
    }
    return parts.join('');
  }

  build() {
    Column({ space: 8 }) {
      ForEach(this.blocks, (item: Block, index: number) => {
        this.blockView(item, index);
      }, (item: Block, index: number) => `${index}:${item.kind}`)
    }
    .width('100%').alignItems(HorizontalAlign.Start)
  }
}

/**
 * 表格单元格在 ForEach 里的视图类型。
 * ArkTS 的 ForEach 回调参数需要显式类型，这里用别名避免直接依赖 Markdown.ets 的 TableCell。
 */
interface TableCellView {
  header: boolean;
  spans: Span[];
}
