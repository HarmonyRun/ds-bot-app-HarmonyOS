import { Question, QuestionOption } from '../model/Models';
import { ConversationQuestion } from '../logic/Questions';

/**
 * 聊天内提问卡（抽自 `Index.ets`，P1 视图拆分）。
 *
 * 设计：**草稿状态内聚在每张卡里**。
 * 原实现把草稿存在 `Index` 的一个 `questionDrafts: QuestionDraftState[]` 数组里
 * （按 `sessionId:questionId` 查找），每个渲染回调都要 `find()` 一次，还要在
 * 父组件维护增删。搬进组件后：
 * - 选中项与自定义回答是本卡的展示状态，天然属于本卡；
 * - `Index` 少一整套 map 与 `questionKey/toggleQuestionOption/setQuestionCustom` 辅助方法；
 * - 提交与关闭仍通过回调交回父组件，组件不接触 API，也无法绕过只读/在线判断。
 */

/**
 * 卡片入参：只需要「哪个 session」和「问题本体」。
 * 不直接用 `ConversationQuestion`，是为了让组件对上层投影结构的变化不敏感。
 */
export interface QuestionCardEntry {
  sessionId: string;
  question: Question;
}

/** 空问题：`@Prop` 必须有默认值，且 ArkTS 禁止 `as` 断言字面量。 */
const EMPTY_QUESTION: Question = {
  id: '', options: []
};

export interface QuestionCardTheme {
  ink: string;
  muted: string;
  /** 卡片底色 */
  cardBg: string;
  /** 卡片描边 */
  cardLine: string;
  /** 选项/输入框底色 */
  fieldBg: string;
  /** 描边 */
  line: string;
  /** 强调色（单选、选中边框、提交按钮） */
  brand: string;
  danger: string;
}

@Component
export struct QuestionCard {
  @Prop entry: QuestionCardEntry = {
    sessionId: '', question: EMPTY_QUESTION
  };
  @Prop tokens: QuestionCardTheme = {
    ink: '#202336', muted: '#6F758B', cardBg: '#F4F7FF', cardLine: '#D9E2FF',
    fieldBg: '#FFFFFF', line: '#E7E9F1', brand: '#4D6BFE', danger: '#C93C3C'
  };
  /** 是否有其它提问正在提交（全局只能有一个进行中）。 */
  @Prop busy: boolean = false;
  /** 团队是否只读。 */
  @Prop readOnly: boolean = false;
  /** 该卡自己的错误文案（由父组件在提交失败时写入）。 */
  @Prop errorText: string = '';
  /** 该卡是否正在提交。 */
  @Prop submitting: boolean = false;

  /** 跳过/关闭：`dismiss` 为 true 时表示不回答。 */
  onSubmit: (selected: string[], custom: string, dismiss: boolean) => void = (): void => {};

  /** 选中的选项 label。 */
  @State selected: string[] = [];
  /** 自定义回答文本。 */
  @State custom: string = '';

  private locked(): boolean {
    return this.busy || this.readOnly;
  }

  private canSubmit(): boolean {
    return this.selected.length > 0 ||
      (this.entry.question.allowCustom === true && this.custom.trim().length > 0);
  }

  private title(): string {
    const question = this.entry.question;
    const body = question.question ?? question.prompt ?? question.text ?? 'Bot 正在等待你的回答';
    return question.header === undefined || question.header.length === 0 ? body : `${question.header} · ${body}`;
  }

  private toggleOption(label: string, checked: boolean): void {
    if (checked) {
      if (!this.selected.includes(label)) this.selected = [...this.selected, label];
    } else {
      this.selected = this.selected.filter((value: string) => value !== label);
    }
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(this.title()).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(this.tokens.ink).width('100%')
            .wordBreak(WordBreak.BREAK_WORD);
          if (this.entry.question.detail !== undefined && this.entry.question.detail.length > 0) {
            Text(this.entry.question.detail).fontSize(13).fontColor(this.tokens.muted).width('100%')
              .wordBreak(WordBreak.BREAK_WORD);
          }
          if (this.entry.question.multiSelect === true) {
            Text('可选择多项').fontSize(11).fontColor(this.tokens.muted).width('100%');
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Button('×').width(42).height(42).borderRadius(21).fontSize(22)
          .backgroundColor(Color.Transparent).fontColor(this.tokens.muted)
          .enabled(!this.locked())
          .onClick(() => this.onSubmit([], '', true));
      }.width('100%').alignItems(VerticalAlign.Top);

      ForEach(this.entry.question.options, (option: QuestionOption, index: number) => {
        this.optionRow(option, index);
      }, (option: QuestionOption, index: number) => `${index}:${option.label}`);

      if (this.entry.question.allowCustom === true) {
        Column({ space: 5 }) {
          Text('自定义回答').fontSize(12).fontColor(this.tokens.muted).width('100%');
          TextArea({ placeholder: '输入你的回答', text: this.custom })
            .width('100%').height(76).fontSize(14).fontColor(this.tokens.ink).maxLength(4000)
            .backgroundColor(this.tokens.fieldBg).borderRadius(12)
            .border({ width: 1, color: this.tokens.line })
            .enabled(!this.locked())
            .onChange((value: string) => this.custom = value);
        }.width('100%').alignItems(HorizontalAlign.Start);
      }
      if (this.errorText.length > 0) {
        Text(this.errorText).fontSize(12).fontColor(this.tokens.danger).width('100%');
      }
      if (this.entry.question.multiSelect === true || this.entry.question.allowCustom === true) {
        Row({ space: 10 }) {
          if (this.entry.question.multiSelect === true) {
            Button('跳过').height(38).borderRadius(19).fontSize(13)
              .backgroundColor(this.tokens.fieldBg).fontColor(this.tokens.muted)
              .enabled(!this.locked())
              .onClick(() => this.onSubmit([], '', true));
          }
          Button(this.submitting ? '提交中…' : '提交')
            .height(38).borderRadius(19).fontSize(13).backgroundColor(this.tokens.brand)
            .enabled(!this.locked() && this.canSubmit())
            .onClick(() => this.onSubmit(this.selected, this.custom, false));
        }.width('100%').justifyContent(FlexAlign.End);
      }
    }
    .width('100%').padding(14)
    .backgroundColor(this.tokens.cardBg)
    .borderRadius(16)
    .border({ width: 1, color: this.tokens.cardLine });
  }

  @Builder
  private optionRow(option: QuestionOption, index: number) {
    Row({ space: 10 }) {
      if (this.entry.question.multiSelect === true) {
        Checkbox({ name: `${index}:${option.label}`, group: this.entry.question.id })
          .select(this.selected.includes(option.label))
          .selectedColor(this.tokens.brand)
          .enabled(!this.locked())
          .onChange((checked: boolean) => this.toggleOption(option.label, checked));
      } else {
        // 单选遵循上游行为：点选即提交
        Radio({ value: option.label, group: this.entry.question.id })
          .checked(this.selected.includes(option.label))
          .enabled(!this.locked())
          .onChange((checked: boolean) => {
            if (checked) {
              this.selected = [option.label];
              this.onSubmit([option.label], '', false);
            }
          });
      }
      Text(String.fromCharCode(65 + index)).fontSize(12).fontColor(this.tokens.brand)
        .width(24).textAlign(TextAlign.Center);
      Column({ space: 2 }) {
        Text(option.label).fontSize(14).fontColor(this.tokens.ink).width('100%')
          .wordBreak(WordBreak.BREAK_WORD);
        if (option.description !== undefined && option.description.length > 0) {
          Text(option.description).fontSize(12).fontColor(this.tokens.muted).width('100%')
            .wordBreak(WordBreak.BREAK_WORD);
        }
      }.layoutWeight(1).alignItems(HorizontalAlign.Start);
    }
    .width('100%').constraintSize({ minHeight: 48 }).padding({ left: 10, right: 10, top: 7, bottom: 7 })
    .backgroundColor(this.tokens.fieldBg).borderRadius(12)
    .border({ width: 1, color: this.selected.includes(option.label) ? this.tokens.brand : this.tokens.line });
  }
}
