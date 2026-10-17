/**
 * 聊天输入栏（抽自 `Index.ets`）：`宽屏 chatPanel` 与 `手机 mobileChatPanel` 里各写了一遍。
 *
 * 两处的**结构完全相同**（可选附件按钮 + TextArea + 发送按钮 + 提示条），差异只有尺寸与配色，
 * 因此全部作为 props 暴露；`mentionMenu` / `composerAccessories`（引用芯片、思考档位）
 * 仍留在父组件，由父组件在组件**之前**渲染，保持原有纵向顺序。
 *
 * 设计取舍：
 * - 本组件**不持有业务状态**（草稿、引用、档位都在父组件），只做输入框；
 * - `canSend` 由父组件判定（需要 online / busy / 草稿非空），组件不猜；
 * - 手机端发送按钮是图标 + 透明度禁用态，宽屏是文字按钮，用 `mobileSendStyle` 区分。
 */
export interface ComposerTheme {
  /** 输入框底色 */
  fieldBg: string;
  /** 输入框文字色 */
  ink: string;
  /** 输入栏条底色（宽屏底部条 / 手机底色） */
  barBg: string;
  /** 分隔线（宽屏条上边框） */
  line: string;
  /** 发送按钮底色 */
  sendBg: string;
}

@Component
export struct ChatComposer {
  @Prop tokens: ComposerTheme = {
    fieldBg: '#F6F7FB', ink: '#202336', barBg: '#FFFFFF', line: '#E7E9F1', sendBg: '#4D6BFE'
  };
  /** 占位文案（手机端含会话名） */
  @Prop placeholder: string = '发送消息…';
  /** 当前文本（由父组件持有） */
  @Prop text: string = '';
  /** 输入上限（父组件扣除隐藏引用头后计算） */
  @Prop maxLength: number = 32000;
  /** TextArea 控制器（父组件持有，`@` 补全需要设置光标） */
  controller: TextAreaController = new TextAreaController();
  /** 是否可发送（父组件判定） */
  @Prop canSend: boolean = false;
  /** 是否显示附件「+」按钮 */
  @Prop showAttach: boolean = true;
  /** 手机端样式：圆角 24、图标发送按钮、透明度禁用态 */
  @Prop mobileSendStyle: boolean = false;
  /** 手机端边距 20，宽屏 14 */
  @Prop horizontalPadding: number = 14;
  /** 宽屏底部条带上边框 */
  @Prop showTopBorder: boolean = false;
  /** 附件按钮图标（手机端传 `ic_plus`，为空则用文字「+」） */
  @Prop attachIcon: Resource | undefined = undefined;
  /** 附件按钮是否描边（手机端样式） */
  @Prop attachBordered: boolean = false;
  /** 附件按钮底色 */
  @Prop attachBg: string = '';

  onTextChange: (value: string) => void = (): void => {};
  onEditChange: (editing: boolean) => void = (): void => {};
  onSelectionChange: (start: number, end: number) => void = (): void => {};
  onSend: () => void = (): void => {};
  /** 手机端：「+」取消态按钮内容（返回按钮）由父组件提供时用 onAttach；宽屏用 bindMenu。 */
  attachMenu: MenuElement[] = [];

  build() {
    Row({ space: 6 }) {
      if (this.showAttach) {
        Button() {
          if (this.attachIcon !== undefined) {
            Image(this.attachIcon)
              .width(this.mobileSendStyle ? 18 : 20)
              .height(this.mobileSendStyle ? 18 : 20);
          } else {
            Text('+').fontSize(21).fontColor(this.tokens.ink);
          }
        }
        .width(this.mobileSendStyle ? 38 : 36)
        .height(this.mobileSendStyle ? 38 : 36)
        .borderRadius(10)
        .backgroundColor(this.attachBg.length > 0 ? this.attachBg : Color.Transparent)
        .border(this.attachBordered ? { width: 1, color: this.tokens.line } : { width: 0 })
        .bindMenu(this.attachMenu);
      }
      TextArea({ placeholder: this.placeholder, text: this.text, controller: this.controller })
        .layoutWeight(1)
        .height(this.mobileSendStyle ? 46 : 50)
        .maxLength(this.maxLength)
        .fontSize(this.mobileSendStyle ? 16 : 15)
        .fontColor(this.tokens.ink)
        .backgroundColor(this.tokens.fieldBg)
        .borderRadius(this.mobileSendStyle ? 14 : 12)
        .border({ width: 1, color: this.tokens.line })
        .padding({ left: 14, right: 14, top: 10, bottom: 8 })
        .onChange((value: string) => this.onTextChange(value))
        .onEditChange((editing: boolean) => this.onEditChange(editing))
        .onTextSelectionChange((start: number, end: number) => this.onSelectionChange(start, end));
      if (this.mobileSendStyle) {
        Button() {
          Image($r('app.media.ic_send')).width(18).height(18);
        }
        .width(38).height(38).borderRadius(10).backgroundColor(this.tokens.sendBg)
        .opacity(this.canSend ? 1 : 0.38)
        .enabled(this.canSend)
        .onClick(() => this.onSend());
      } else {
        Button(this.canSend ? '发送' : '…').height(38).width(56).borderRadius(10)
          .backgroundColor(this.tokens.sendBg)
          .enabled(this.canSend)
          .onClick(() => this.onSend());
      }
    }
    .width('100%')
    .padding({ left: this.horizontalPadding, right: this.horizontalPadding, top: 10, bottom: 10 })
    .backgroundColor(this.tokens.barBg)
    .border(this.showTopBorder ? { width: { top: 1 }, color: this.tokens.line } : { width: 0 });
  }
}
