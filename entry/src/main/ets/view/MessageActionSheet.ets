import { ThemeTokens } from './Theme';

/**
 * 长按消息后的动作面板（抽自 `Index.ets`，P1 视图拆分第一步）。
 *
 * 用原生 `bindSheet` 承载，而不是自绘「遮罩 + 底部卡片」：
 * 系统负责遮罩、点击外部关闭、拖拽条、圆角与转场动画，也自动处理安全区，
 * 与「引用会话」选择器保持同一种交互。
 *
 * 抽出来的目的有两个：
 * 1. 让 `Index.ets` 不再承载这块 UI；
 * 2. 让面板能被独立触发（诊断页按钮），从而在不依赖长按手势的情况下做真机实证
 *    —— `uitest uiInput longClick` 在本工程的手势上触发不了。
 */

/** 一个可选动作。`run` 由调用方提供，面板只负责展示与回调。 */
export interface MessageAction {
  label: string;
  run: () => void;
}

@Component
export struct MessageActionSheet {
  /** 待展示的动作列表。 */
  @Prop actions: MessageAction[] = [];
  /** 配色令牌。 */
  @Prop tokens: ThemeTokens = {
    pageBg: '#F6F7FB', surface: '#FFFFFF', ink: '#202336', muted: '#6F758B', line: '#E7E9F1',
    brand: '#4D6BFE', danger: '#C93C3C', dangerBg: '#FDECEC', warning: '#C77A28',
    warningBg: '#FFF4E5', success: '#24B47E', code: '#F0F2F7', link: '#3A5BD9'
  };
  /** 点击某项或系统关闭时回调。 */
  onClose: () => void = (): void => {};
  /** 动作回调。 */
  onAction: (action: MessageAction) => void = (): void => {};

  build() {
    Column({ space: 0 }) {
      ForEach(this.actions, (action: MessageAction, index: number) => {
        Row() {
          Text(action.label).fontSize(16).fontColor(this.tokens.ink).layoutWeight(1);
        }
        .width('100%').height(56).padding({ left: 20, right: 20 })
        .onClick(() => this.onAction(action))
        if (index < this.actions.length - 1) {
          Divider().color(this.tokens.line).margin({ left: 20 });
        }
      }, (action: MessageAction, index: number) => `${index}:${action.label}`)
    }
    .width('100%').padding({ top: 8, bottom: 16 })
    .alignItems(HorizontalAlign.Start)
  }
}
