import { ToolActivity } from '../model/Models';

/**
 * 消息里的工具调用卡（抽自 `Index.ets`，P1 视图拆分）。
 *
 * 设计：**展开状态完全内聚在组件内**。
 * 原实现把 `expandedTools: string[]` 放在 `Index` 上，但那个字段只被工具卡使用，
 * 属于展示细节；搬进来后 `Index` 少一个状态，也不再需要 `toggleTool()` / `toolGlyph()`。
 */
export interface ToolCardTheme {
  ink: string;
  muted: string;
  /** 卡片底色 */
  cardBg: string;
  /** 卡片描边 */
  line: string;
  /** 链接色（复制输出） */
  link: string;
}

@Component
export struct ToolCard {
  @Prop tool: ToolActivity = {
    callId: '', name: '', state: 'done'
  };
  @Prop tokens: ToolCardTheme = {
    ink: '#202336', muted: '#6F758B', cardBg: '#F6F7FB', line: '#E7E9F1', link: '#3A5BD9'
  };
  /** 复制文本（由父组件提供剪贴板能力与提示文案）。 */
  onCopy: (text: string, toast: string) => void = (): void => {};
  /**
   * 卡片可用宽度（vp）。**必须由父组件传入确定值**：
   * `width('100%')` 在「父容器只有 constraintSize(maxWidth)」时按内容解析，
   * 卡片会按气泡全宽排版并越出气泡内边界（2026-10-16 用户报告：工具卡超出气泡）。
   */
  @Prop maxWidth: number = 0;

  @State expandedCallId: string = '';

  private glyph(tool: ToolActivity): string {
    if (tool.state === 'running') return '◌';
    return tool.isError === true ? '!' : '✓';
  }

  private glyphColor(tool: ToolActivity): string {
    if (tool.isError === true) return '#E35252';
    return tool.state === 'running' ? '#F29D49' : '#24B47E';
  }

  private stateLabel(tool: ToolActivity): string {
    if (tool.state === 'running') return '执行中';
    return tool.isError === true ? '失败' : '已完成';
  }

  build() {
    Column({ space: 7 }) {
      Row({ space: 8 }) {
        Text(this.glyph(this.tool)).fontColor(this.glyphColor(this.tool));
        Text(this.tool.name.length > 0 ? this.tool.name : '工具')
          .fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.tokens.ink).layoutWeight(1).maxLines(1)
          .wordBreak(WordBreak.BREAK_WORD);
        if (this.tool.durationMs !== undefined && this.tool.durationMs > 0) {
          Text(`${Math.round(this.tool.durationMs)} ms`).fontSize(11).fontColor(this.tokens.muted);
        }
        Text(this.stateLabel(this.tool)).fontSize(11).fontColor(this.tokens.muted);
      }
      .width(this.innerWidth())
      .onClick(() => {
        if (this.tool.callId.length === 0) return;
        this.expandedCallId = this.expandedCallId === this.tool.callId ? '' : this.tool.callId;
      });
      if (this.expandedCallId === this.tool.callId) {
        this.detail();
      } else {
        if (this.tool.input !== undefined && this.tool.input.length > 0) {
          Text(this.tool.input).fontSize(12).fontColor(this.tokens.muted).maxLines(2)
            .wordBreak(WordBreak.BREAK_WORD)
            .copyOption(CopyOptions.LocalDevice).width(this.innerWidth());
        }
        Text('点击查看详情').fontSize(11).fontColor(this.tokens.muted).width(this.innerWidth());
      }
    }
    .width(this.cardWidth()).padding(12).backgroundColor(this.tokens.cardBg).borderRadius(12)
    .border({ width: 1, color: this.tokens.line });
  }

  /** 卡片宽度：给了确定值就用它，否则填满父容器（气泡已有确定宽度）。 */
  private cardWidth(): Length {
    return this.maxWidth > 0 ? this.maxWidth : '100%';
  }

  /** 卡片内文本可用宽度：未指定时同样填满父容器。 */
  private innerWidth(): Length {
    if (this.maxWidth <= 0) return '100%';
    const width = this.maxWidth - 24;
    return width > 60 ? width : 60;
  }

  @Builder
  private detail() {
    // 窄屏也必须能断行：工具输入/输出常是长 JSON 或 URL
    if (this.tool.input !== undefined && this.tool.input.length > 0) {
      Text('输入').fontSize(11).fontColor(this.tokens.muted).width(this.innerWidth());
      Text(this.tool.input).fontSize(12).fontColor(this.tokens.ink).width(this.innerWidth())
        .wordBreak(WordBreak.BREAK_WORD)
        .copyOption(CopyOptions.LocalDevice);
    }
    if (this.tool.output !== undefined && this.tool.output.length > 0) {
      Text('输出').fontSize(11).fontColor(this.tokens.muted).width(this.innerWidth());
      Text(this.tool.output).fontSize(12).fontColor(this.tokens.ink).width(this.innerWidth())
        .wordBreak(WordBreak.BREAK_WORD)
        .copyOption(CopyOptions.LocalDevice);
    }
    if (this.tool.truncated === true) {
      Text('（主机已截断输出）').fontSize(11).fontColor(this.tokens.muted).width(this.innerWidth());
    }
    if (this.tool.callId.length > 0) {
      Row() {
        Text('复制输出').fontSize(12).fontColor(this.tokens.link)
          .onClick(() => this.onCopy(this.tool.output ?? '', '工具输出已复制'));
      }.width(this.innerWidth()).justifyContent(FlexAlign.End);
    }
  }
}
