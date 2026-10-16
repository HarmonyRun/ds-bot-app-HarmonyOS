import { QueueItem } from '../model/Models';

/**
 * 排队消息面板（抽自 `Index.ets`，P1 视图拆分）。
 *
 * 设计：**父组件给数据、子组件管自己的展开状态**。
 * 「展开/收起」纯粹是展示状态，留在组件内部即可，不必让 `Index` 多背一个字段；
 * 业务动作（移除）通过回调交给父组件，组件不接触任何 API。
 */
export interface QueuePanelTheme {
  ink: string;
  muted: string;
  /** 警示色（「排队中」标题） */
  warning: string;
  /** 条目底色 */
  itemBg: string;
  /** 条目描边 */
  itemLine: string;
  /** 移除按钮底色 */
  dangerBg: string;
  /** 移除按钮文字色 */
  danger: string;
}

@Component
export struct QueuePanel {
  /** 待展示的排队消息（已由父组件按会话过滤）。 */
  @Prop items: QueueItem[] = [];
  /** 配色。 */
  @Prop tokens: QueuePanelTheme = {
    ink: '#202336', muted: '#6F758B', warning: '#C77A28',
    itemBg: '#FFFBF3', itemLine: '#F3E2C7', dangerBg: '#FDECEC', danger: '#C93C3C'
  };
  /** 点击「移除」时回调该条目。 */
  onRemove: (item: QueueItem) => void = (): void => {};
  /** 初始是否展开（组件自己维护后续展开状态）。 */
  @Prop initiallyExpanded: boolean = true;

  /** 展开状态属于展示细节，内聚在组件内。 */
  @State expanded: boolean = true;

  aboutToAppear(): void {
    this.expanded = this.initiallyExpanded;
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('排队中').fontSize(12).fontColor(this.tokens.warning);
        Text(`${this.items.length}`).fontSize(12).fontColor(this.tokens.muted);
        Blank();
        Text(this.expanded ? '收起' : '展开').fontSize(12).fontColor(this.tokens.muted)
          .onClick(() => this.expanded = !this.expanded);
      }.width('100%');
      if (this.expanded) {
        ForEach(this.items, (item: QueueItem) => {
          this.queueItem(item);
        }, (item: QueueItem) => item.id);
      }
    }
    .width('100%').padding({ left: 12, right: 12, top: 8 });
  }

  @Builder
  private queueItem(item: QueueItem) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(item.text.length > 0 ? item.text : '（附件消息）')
          .fontSize(14).fontColor(this.tokens.ink).maxLines(2).width('100%')
          // 长 URL / 无空格串要能断行，否则会顶出条目卡片
          .wordBreak(WordBreak.BREAK_WORD);
        Text(item.target === 'next-step' ? '下一步执行' : '下一轮对话')
          .fontSize(11).fontColor(this.tokens.muted).width('100%');
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
      Button('移除').height(34).borderRadius(17).fontSize(13)
        .backgroundColor(this.tokens.dangerBg).fontColor(this.tokens.danger)
        .onClick(() => this.onRemove(item));
    }
    .width('100%').padding(12)
    .backgroundColor(this.tokens.itemBg)
    .borderRadius(14)
    .border({ width: 1, color: this.tokens.itemLine });
  }
}
