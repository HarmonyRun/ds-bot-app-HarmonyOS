import { Conversation } from '../model/Models';
import { addAgentBlockedReason, canAddAgent, groupAgentConversations } from '../logic/Agents';
import { SecondaryPageTheme } from './SecondaryPages';

/**
 * DSH Agent 管理（P2-9）。
 *
 * DSH Agent 与 Bot 的区别：**每个团队最多一个**，但它可以有多个会话。
 * 宿主把每个 Agent 会话当作一条 `kind: 'agent'` 的会话下发，
 * 所以这里不需要单独的 state 字段，直接用本地会话过滤。
 *
 * 能力：创建 / 移除 Agent、重命名会话、归档会话。
 */
@Component
export struct AgentPanel {
  @Prop theme: SecondaryPageTheme = {
    pageBg: '#F5F7FA', rowBg: '#FFFFFF', chipBg: '#FFFFFF', chipLine: '#E3E8F0',
    ink: '#172033', muted: '#657086', line: '#E3E8F0', brand: '#3F5EF5', brandSoft: '#EEF2FF', danger: '#C93F49', dangerBg: '#FFF0F1'
  };
  /** 全部会话（组件内部按 kind 过滤） */
  @Prop conversations: Conversation[] = [];
  /** 正在重命名的会话 id（空串表示未编辑） */
  @Prop editingId: string = '';
  @Prop titleDraft: string = '';
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop notice: string = '';

  onClose: () => void = (): void => {};
  onRefresh: () => void = (): void => {};
  onAddAgent: () => void = (): void => {};
  onRemoveAgent: (agentId: string) => void = (): void => {};
  onStartRename: (conversation: Conversation) => void = (): void => {};
  onTitleChange: (value: string) => void = (): void => {};
  onConfirmRename: (conversation: Conversation) => void = (): void => {};
  onCancelRename: () => void = (): void => {};
  onArchive: (conversation: Conversation) => void = (): void => {};

  private agentIds(): string[] {
    return groupAgentConversations(this.conversations).agentIds;
  }

  private agentSessions(): Conversation[] {
    return groupAgentConversations(this.conversations).conversations;
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Button('‹').width(40).height(40).borderRadius(20).fontSize(24)
          .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
          .onClick(() => this.onClose());
        Text('DSH Agent').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.ink)
          .layoutWeight(1);
        Button('刷新').height(34).borderRadius(17).fontSize(13)
          .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
          .enabled(!this.busy)
          .onClick(() => this.onRefresh());
      }
      .width('100%').height(64).padding({ left: 16, right: 16 });

      Scroll() {
        Column({ space: 14 }) {
          this.statusCard();
          this.sessionsCard();
          if (this.notice.length > 0) {
            Text(this.notice).fontSize(13).fontColor(this.theme.brand).width('100%')
              .padding(14).backgroundColor(this.theme.brandSoft).borderRadius(12);
          }
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor('#C93F49').width('100%')
              .padding(14).backgroundColor(this.theme.rowBg).borderRadius(12);
          }
        }.width('100%').padding({ left: 18, right: 18, top: 4, bottom: 28 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }
    .width('100%').height('100%').backgroundColor(this.theme.pageBg);
  }

  /** Agent 本体：有没有 / 能不能建 / 能不能删。 */
  @Builder
  private statusCard() {
    Column({ space: 10 }) {
      Text(this.agentIds().length > 0 ? '团队已有一个 DSH Agent' : '团队还没有 DSH Agent')
        .fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.theme.ink).width('100%');
      Text('DSH Agent 是团队里唯一的通用智能体，可以有多个会话；与 Bot 不同，它不参与群聊。')
        .fontSize(12).fontColor(this.theme.muted).width('100%').wordBreak(WordBreak.BREAK_WORD);
      if (canAddAgent(this.agentIds())) {
        Button(this.busy ? '创建中…' : '创建 DSH Agent')
          .width('100%').height(44).borderRadius(12).fontSize(15)
          .backgroundColor(this.theme.brand).fontColor('#FFFFFF')
          .enabled(!this.busy)
          .onClick(() => this.onAddAgent());
      } else {
        Text(addAgentBlockedReason(this.agentIds())).fontSize(12).fontColor(this.theme.muted)
          .width('100%');
        Button('移除 DSH Agent')
          .width('100%').height(44).borderRadius(12).fontSize(15)
          .backgroundColor(this.theme.chipBg).fontColor('#C93F49')
          .enabled(!this.busy)
          .onClick(() => this.onRemoveAgent(this.agentIds()[0]));
      }
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }

  /** Agent 的会话列表：改名 / 归档。 */
  @Builder
  private sessionsCard() {
    Column({ space: 10 }) {
      Text(`已归档以外的会话（${this.agentSessions().length}）`)
        .fontSize(15).fontColor(this.theme.muted).width('100%');
      if (this.agentSessions().length === 0) {
        Text('还没有会话。创建 Agent 时会自动建一个。')
          .fontSize(13).fontColor(this.theme.muted).width('100%');
      } else {
        ForEach(this.agentSessions(), (item: Conversation) => {
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Text(item.name).fontSize(15).fontColor(this.theme.ink).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              Text('改名').fontSize(12).fontColor(this.theme.brand)
                .onClick(() => this.onStartRename(item));
              Text('归档').fontSize(12).fontColor(this.theme.muted)
                .onClick(() => this.onArchive(item));
            }.width('100%');
            if (this.editingId === item.id) {
              TextInput({ text: this.titleDraft })
                .height(40).width('100%').backgroundColor(this.theme.chipBg).borderRadius(10)
                .fontColor(this.theme.ink).fontSize(14)
                .onChange((value: string) => this.onTitleChange(value));
              Row({ space: 8 }) {
                Button('取消').layoutWeight(1).height(36).borderRadius(10).fontSize(13)
                  .backgroundColor(this.theme.chipBg).fontColor(this.theme.ink)
                  .onClick(() => this.onCancelRename());
                Button('保存').layoutWeight(1).height(36).borderRadius(10).fontSize(13)
                  .backgroundColor(this.theme.brand).fontColor('#FFFFFF')
                  .enabled(!this.busy)
                  .onClick(() => this.onConfirmRename(item));
              }.width('100%');
            }
          }
          .width('100%').padding({ top: 10, bottom: 10 });
          Divider().color(this.theme.line);
        }, (item: Conversation) => `${item.id}#${item.name}#${this.editingId === item.id}#${this.titleDraft}`);
      }
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }
}
