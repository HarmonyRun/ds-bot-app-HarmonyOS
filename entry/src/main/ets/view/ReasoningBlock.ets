/**
 * 可展开的「思考过程」区块（抽自 `Index.ets` 的 `reasoningBlock()`）。
 *
 * 设计：**展开状态内聚在组件内**。原实现把 `expandedReasoning: string[]` 放在 `Index` 上，
 * 但它只服务于这个区块（按 message id 记忆展开项），属于展示细节；
 * 搬进来后 `Index` 少一个状态与 `toggleReasoning()`，且每个气泡各自管自己的展开。
 */
export interface ReasoningTheme {
  muted: string;
  /** 「进行中」标记色 */
  pending: string;
  /** 展开内容的左侧竖线色 */
  accent: string;
}

@Component
export struct ReasoningBlock {
  /** 思考文本（空则不渲染展开内容）。 */
  @Prop reasoning: string = '';
  /** 消息是否仍在流式输出（显示「进行中」）。 */
  @Prop pending: boolean = false;
  /** 窄屏用更大的字号与行高，且不画左侧竖线。 */
  @Prop compact: boolean = false;
  @Prop tokens: ReasoningTheme = { muted: '#6F758B', pending: '#C77A28', accent: '#9D96FF' };

  @State expanded: boolean = false;

  build() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Text(this.expanded ? '⌃ 思考过程' : '⌄ 思考过程')
          .fontSize(12).fontColor(this.tokens.muted);
        if (this.pending) {
          Text('进行中').fontSize(11).fontColor(this.tokens.pending);
        }
        Blank();
      }
      .width('100%')
      .onClick(() => this.expanded = !this.expanded);
      if (this.expanded) {
        Text(this.reasoning)
          .fontSize(this.compact ? 14 : 12)
          .lineHeight(this.compact ? 21 : 18)
          .fontColor(this.tokens.muted)
          .padding(this.compact ? 0 : { left: 10 })
          .border(this.compact ? { width: 0 } : { width: { left: 2 }, color: this.tokens.accent })
          .wordBreak(WordBreak.BREAK_WORD)
          .copyOption(CopyOptions.LocalDevice)
          .width('100%');
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start);
  }
}
