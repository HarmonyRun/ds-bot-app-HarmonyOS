import { Approval } from '../model/Models';

/**
 * 聊天内审批卡（抽自 `Index.ets`，P1 视图拆分）。
 *
 * 设计：**父组件给数据、子组件只渲染 + 回调**。
 * 决定（允许一次 / 拒绝）通过回调交回父组件，组件本身不接触 API，
 * 因此无法绕过父组件的 busy/只读判断。
 */

/** 审批卡与排队面板共用的「警示面板」配色。 */
export interface NoticePanelTheme {
  ink: string;
  muted: string;
  /** 警示色（「待批准」标签文字） */
  warning: string;
  /** 警示底色（标签背景） */
  warningBg: string;
  /** 卡片底色 */
  cardBg: string;
  /** 卡片描边 */
  cardLine: string;
  /** 主按钮底色 */
  primary: string;
  /** 危险按钮底色 */
  dangerBg: string;
  /** 危险按钮文字色 */
  danger: string;
}

export const LIGHT_NOTICE_THEME: NoticePanelTheme = {
  ink: '#202336', muted: '#6F758B', warning: '#C77A28', warningBg: '#FFF4E5',
  cardBg: '#FFFBF3', cardLine: '#F3E2C7', primary: '#4D6BFE',
  dangerBg: '#FDECEC', danger: '#C93C3C'
};

export const DARK_NOTICE_THEME: NoticePanelTheme = {
  ink: '#F4F5FA', muted: '#A4A9BB', warning: '#F0B45E', warningBg: '#3A2E18',
  cardBg: '#26231A', cardLine: '#3A2E18', primary: '#8FA8FF',
  dangerBg: '#3A2226', danger: '#FF8A8A'
};

@Component
export struct ChatApprovals {
  /** 待批准的操作（已由父组件按会话过滤）。 */
  @Prop items: Approval[] = [];
  /** 配色。 */
  @Prop tokens: NoticePanelTheme = LIGHT_NOTICE_THEME;
  /** 是否禁用按钮（父组件 busy 时）。 */
  @Prop disabled: boolean = false;

  /** 用户做出决定：`allowed-once` 或 `rejected`。 */
  onResolve: (approvalId: string, decision: string) => void = (): void => {};

  build() {
    Column({ space: 8 }) {
      ForEach(this.items, (approval: Approval) => {
        this.approvalCard(approval);
      }, (approval: Approval) => approval.id);
    }
    .width('100%').padding({ left: 12, right: 12, top: 8 });
  }

  @Builder
  private approvalCard(approval: Approval) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('待批准')
          .fontSize(11).fontColor(this.tokens.warning)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .backgroundColor(this.tokens.warningBg).borderRadius(8);
        Text(approval.toolName).fontSize(15).fontWeight(FontWeight.Medium)
          .fontColor(this.tokens.ink).layoutWeight(1).maxLines(2)
          .wordBreak(WordBreak.BREAK_WORD);
      }.width('100%');
      Text(approval.reason ?? '主机请求批准此工具操作')
        .fontSize(13).fontColor(this.tokens.muted).width('100%').maxLines(4)
        .wordBreak(WordBreak.BREAK_WORD);
      Row({ space: 10 }) {
        Button('允许一次').layoutWeight(1).height(40).borderRadius(20).fontSize(14)
          .backgroundColor(this.tokens.primary)
          .enabled(!this.disabled)
          .onClick(() => this.onResolve(approval.id, 'allowed-once'));
        Button('拒绝').layoutWeight(1).height(40).borderRadius(20).fontSize(14)
          .backgroundColor(this.tokens.dangerBg).fontColor(this.tokens.danger)
          .enabled(!this.disabled)
          .onClick(() => this.onResolve(approval.id, 'rejected'));
      }.width('100%');
    }
    .width('100%').padding(14)
    .backgroundColor(this.tokens.cardBg)
    .borderRadius(16)
    .border({ width: 1, color: this.tokens.cardLine });
  }
}
