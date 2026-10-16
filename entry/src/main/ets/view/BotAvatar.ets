import { BotAvatarView } from './BotAvatarView';

/**
 * 角色头像（矢量底图 + 主 Bot 星标 + 活跃点）。抽自 `Index.ets` 的 `botAvatar()`。
 *
 * 为什么必须抽成一个共享组件：真机实测曾经踩过「同一界面有两份头像实现，
 * 只改了一份」的坑（桌面版会话列表与团队页仍是旧的「圆底 + 首字母」占位，
 * 见 P1 报告 §8.3）。因此星标与活跃点只能有**一处**实现，所有列表/卡片/进度条复用。
 *
 * 组合规则（与上游一致）：
 * - 主 Bot：右下角白底金星徽标
 * - 活跃（等待/流式）：左下角橙色圆点
 */
export interface AvatarSpec {
  /** 矢量头像形状名（上游 `characters.json` 的 key）。 */
  shape: string;
  /** 矢量头像颜色名。 */
  color: string;
  /** 位图头像地址（为空则用矢量）。 */
  image: string;
  /** 是否主 Bot（画星标）。 */
  main: boolean;
  /** 是否活跃（画橙点）。 */
  live: boolean;
}

@Component
export struct BotAvatar {
  @Prop spec: AvatarSpec = { shape: '', color: '', image: '', main: false, live: false };
  /** 头像边长（vp）。 */
  @Prop avatarSize: number = 42;
  /** 是否深色（影响星标描边）。 */
  @Prop dark: boolean = false;

  build() {
    Stack() {
      if (this.spec.image.length > 0) {
        Image(this.spec.image)
          .width(this.avatarSize).height(this.avatarSize)
          .borderRadius(this.avatarSize / 2)
          .objectFit(ImageFit.Cover);
      } else {
        BotAvatarView({
          shape: this.spec.shape,
          color: this.spec.color,
          avatarSize: this.avatarSize,
          image: ''
        });
      }
      if (this.spec.main) {
        // 主 Bot 星标：右下角小圆底 + 金星（对齐上游 `main` 徽标）。
        Column() {
          Text('★').fontSize(this.avatarSize * 0.22).fontColor('#E2A227')
        }
        .width(this.avatarSize * 0.36).height(this.avatarSize * 0.36)
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#FFFFFF')
        .borderRadius(this.avatarSize * 0.18)
        .border({ width: 1, color: this.dark ? '#2B2E39' : '#EDEFF5' })
        .position({ x: this.avatarSize * 0.64, y: this.avatarSize * 0.62 })
      }
      if (this.spec.live) {
        Circle({ width: 8, height: 8 }).fill('#F29D49')
          .border({ width: 1.5, color: '#FFFFFF' })
          .position({ x: 0, y: this.avatarSize - 8 });
      }
    }
    .width(this.avatarSize).height(this.avatarSize);
  }
}
