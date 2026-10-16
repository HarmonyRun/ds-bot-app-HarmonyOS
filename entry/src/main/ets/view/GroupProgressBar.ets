/**
 * 群成员工作进度条（抽自 `Index.ets`，P1 视图拆分）。
 *
 * 设计：**父组件算数据，子组件只渲染**。
 * 原实现直接依赖 `Index` 的 12 个成员（`botById()` / `progressOf()` / `botAvatar()` /
 * `stopMemberWork()` / `selectedRoom()` …）。若照搬成 12 个 `@Prop`，组件会变成
 * 「Index 的镜像」，既难复用也难测。因此这里用 `MemberChip` 视图模型承载全部显示数据，
 * 组件只负责布局与回调，不再触碰业务状态。
 */
import { BotAvatar } from './BotAvatar';

/** 成员头像所需的最小数据（避免子组件依赖 Bot 模型）。 */
export interface MemberAvatar {
  shape: string;
  color: string;
  image: string;
  main: boolean;
  live: boolean;
}

/** 进度条上单个成员的全部显示数据。 */
export interface MemberChip {
  botId: string;
  name: string;
  avatar: MemberAvatar;
  /** 状态文案（已回复 / 正在输入 / 等待审批 …）。 */
  status: string;
  /** 状态是否表示失败（决定文案颜色）。 */
  failed: boolean;
  /** 该成员是否正在工作（决定是否显示「停止」）。 */
  working: boolean;
  /** 是否正在发言（高亮边框）。 */
  speaking: boolean;
  /** 是否正在执行停止请求（按钮文案与禁用态）。 */
  stopping: boolean;
  /** 是否允许停止（只读团队 / 已有其它停止请求时为 false）。 */
  canStop: boolean;
}

export interface GroupProgressTheme {
  ink: string;
  muted: string;
  surface: string;
  line: string;
  danger: string;
  dangerBg: string;
  activeBg: string;
  brand: string;
}

@Component
export struct GroupProgressBar {
  /** 要展示的成员（已由父组件算好，可直接渲染）。 */
  @Prop chips: MemberChip[] = [];
  /** 配色。 */
  @Prop tokens: GroupProgressTheme = {
    ink: '#202336', muted: '#6F758B', surface: '#FFFFFF', line: '#E7E9F1',
    danger: '#C93C3C', dangerBg: '#FDECEC', activeBg: '#F0F4FF', brand: '#4D6BFE'
  };
  /** 错误文案（空串表示无错误）。 */
  @Prop errorText: string = '';
  /** 群聊活动是否暂时不可用。 */
  @Prop unavailable: boolean = false;

  /** 点击「停止」时回调该成员 id。 */
  onStop: (botId: string) => void = (): void => {};

  build() {
    Column({ space: 5 }) {
      if (this.errorText.length > 0) {
        Text(this.errorText).fontSize(11).fontColor(this.tokens.danger)
          .width('100%').padding({ left: 12, right: 12 });
      }
      if (this.unavailable && this.chips.length === 0) {
        Text('群聊活动暂时不可用').fontSize(11).fontColor(this.tokens.muted)
          .width('100%').padding({ left: 12, right: 12, bottom: 4 });
      } else {
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.chips, (chip: MemberChip) => {
              this.memberChip(chip);
            }, (chip: MemberChip) => `progress:${chip.botId}`);
          }.padding({ left: 12, right: 12, bottom: 4 });
        }
        .scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%');
      }
    }.width('100%').padding({ top: 4 });
  }

  @Builder
  private memberChip(chip: MemberChip) {
    Row({ space: 7 }) {
      // 头像：复用矢量头像组件（父组件把图形/颜色/是否主 Bot 都算进 MemberChip）
      BotAvatar({ spec: chip.avatar, avatarSize: 24 });
      Column({ space: 1 }) {
        Text(chip.name).fontSize(11).fontColor(this.tokens.ink).maxLines(1);
        if (chip.status.length > 0) {
          Text(chip.status).fontSize(10)
            .fontColor(chip.failed ? this.tokens.danger : this.tokens.muted)
            .maxLines(1);
        }
      }.alignItems(HorizontalAlign.Start);
      if (chip.working) {
        Button(chip.stopping ? '停止中…' : '停止')
          .height(32).borderRadius(16).fontSize(11)
          .backgroundColor(this.tokens.dangerBg).fontColor(this.tokens.danger)
          .enabled(chip.canStop)
          .onClick(() => this.onStop(chip.botId));
      }
    }
    .constraintSize({ minHeight: 44 }).padding({ left: 10, right: 8, top: 6, bottom: 6 })
    .borderRadius(22).backgroundColor(chip.speaking ? this.tokens.activeBg : this.tokens.surface)
    .border({ width: 1, color: chip.speaking ? this.tokens.brand : this.tokens.line });
  }
}
