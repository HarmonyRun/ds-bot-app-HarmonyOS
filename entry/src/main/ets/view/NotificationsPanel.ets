import { NotificationItem, NotificationPreferences } from '../model/Models';
import {
  describeTime, kindGlyph, kindLabel, NOTIFICATION_KINDS, preferencesSummary, unreadCount
} from '../logic/Notifications';
import { SecondaryPageTheme } from './SecondaryPages';

/**
 * 通知中心（P3-4）。
 *
 * 主机把「需要你知道的事」聚合成 inbox：回复 / 提问 / 审批。
 * 这里展示列表、未读数、全部已读，以及按类别的订阅开关。
 *
 * 注意：**不做推送注册**（需要 HMS Push 与 AGC 配置）。
 * 新通知由 App 在前台轮询发现后**弹本地系统通知**（`service/LocalNotify.ets`）。
 */
@Component
export struct NotificationsPanel {
  @Prop theme: SecondaryPageTheme = {
    pageBg: '#F5F7FA', rowBg: '#FFFFFF', chipBg: '#FFFFFF', chipLine: '#E3E8F0',
    ink: '#172033', muted: '#657086', line: '#E3E8F0', brand: '#3F5EF5', brandSoft: '#EEF2FF',
    danger: '#C93F49', dangerBg: '#FFF0F1'
  };
  @Prop items: NotificationItem[] = [];
  @Prop preferences: NotificationPreferences = { enabled: true, categories: NOTIFICATION_KINDS };
  @Prop loading: boolean = false;
  @Prop busy: boolean = false;
  @Prop error: string = '';

  onClose: () => void = (): void => {};
  onRefresh: () => void = (): void => {};
  /** 全部标为已读 */
  onMarkAllRead: () => void = (): void => {};
  /** 点某条：标记该条已读并跳转到对应会话 */
  onOpenItem: (item: NotificationItem) => void = (): void => {};
  /** 总开关 */
  onToggleEnabled: (enabled: boolean) => void = (): void => {};
  /** 切换某个类别 */
  onToggleCategory: (kind: string) => void = (): void => {};
  /** 发一条测试通知（验证系统通知权限通了） */
  onTestNotification: () => void = (): void => {};

  private categoriesOf(): string[] {
    return this.preferences.categories ?? NOTIFICATION_KINDS;
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          this.preferencesCard();
          this.listCard();
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor(this.theme.danger).width('100%')
              .padding(14).backgroundColor(this.theme.dangerBg).borderRadius(12);
          }
        }.width('100%').padding({ left: 18, right: 18, top: 4, bottom: 28 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }
    .width('100%').height('100%').backgroundColor(this.theme.pageBg);
  }

  @Builder
  private header() {
    Row({ space: 12 }) {
      Button('‹').width(40).height(40).borderRadius(20).fontSize(24)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .onClick(() => this.onClose());
      Column({ space: 1 }) {
        Text('通知中心').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.ink);
        Text(unreadCount(this.items) > 0 ? `${unreadCount(this.items)} 条未读` : '全部已读')
          .fontSize(12).fontColor(this.theme.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Button(this.loading ? '读取中' : '刷新')
        .height(34).borderRadius(17).fontSize(13)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .enabled(!this.loading)
        .onClick(() => this.onRefresh());
    }
    .width('100%').height(64).padding({ left: 16, right: 16 });
  }

  /** 偏好：总开关 + 类别 + 测试。 */
  @Builder
  private preferencesCard() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('通知').fontSize(15).fontColor(this.theme.ink).width('100%');
          Text(preferencesSummary(this.preferences)).fontSize(11)
            .fontColor(this.theme.muted).width('100%');
        }.layoutWeight(1).alignItems(HorizontalAlign.Start);
        Toggle({ type: ToggleType.Switch, isOn: this.preferences.enabled !== false })
          .selectedColor(this.theme.brand)
          .enabled(!this.busy)
          .onChange((isOn: boolean) => this.onToggleEnabled(isOn));
      }.width('100%');

      if (this.preferences.enabled !== false) {
        Row({ space: 8 }) {
          ForEach(NOTIFICATION_KINDS, (kind: string) => {
            Button(`${kindGlyph(kind)} ${kindLabel(kind)}`)
              .layoutWeight(1).height(36).borderRadius(18).fontSize(12)
              .backgroundColor(this.categoriesOf().includes(kind) ? this.theme.brand : this.theme.chipBg)
              .fontColor(this.categoriesOf().includes(kind) ? '#FFFFFF' : this.theme.muted)
              .enabled(!this.busy)
              .onClick(() => this.onToggleCategory(kind));
          }, (kind: string) => `${kind}#${this.categoriesOf().includes(kind)}`);
        }.width('100%');
        Text('未装 HMS 推送，App 在前台时收到新通知会弹系统横幅')
          .fontSize(11).fontColor(this.theme.muted).width('100%');
        Button('发一条测试通知')
          .height(34).borderRadius(17).fontSize(12)
          .backgroundColor(this.theme.chipBg).fontColor(this.theme.brand)
          .enabled(!this.busy)
          .onClick(() => this.onTestNotification());
      }
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }

  /** 通知列表。 */
  @Builder
  private listCard() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Text(`通知（${this.items.length}）`).fontSize(15)
          .fontColor(this.theme.muted).layoutWeight(1);
        if (unreadCount(this.items) > 0) {
          Text('全部已读').fontSize(12).fontColor(this.theme.brand)
            .onClick(() => this.onMarkAllRead());
        }
      }.width('100%');
      if (this.items.length === 0) {
        Text('还没有通知。Bot 回复、向你提问或请求审批时，会出现在这里。')
          .fontSize(13).fontColor(this.theme.muted).width('100%');
      } else {
        ForEach(this.items, (item: NotificationItem) => {
          Row({ space: 10 }) {
            Text(kindGlyph(item.kind)).fontSize(16);
            Column({ space: 3 }) {
              Row({ space: 6 }) {
                Text(item.title).fontSize(14)
                  .fontColor(item.read === true ? this.theme.muted : this.theme.ink)
                  .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
                if (item.read !== true) {
                  Circle({ width: 7, height: 7 }).fill(this.theme.brand);
                }
              }.width('100%');
              Row({ space: 8 }) {
                Text(`${kindLabel(item.kind)} · ${describeTime(item.createdAt, Date.now())}`)
                  .fontSize(11).fontColor(this.theme.muted).layoutWeight(1);
              }.width('100%');
            }.layoutWeight(1).alignItems(HorizontalAlign.Start);
          }
          .width('100%').padding({ top: 10, bottom: 10 })
          .onClick(() => this.onOpenItem(item));
          Divider().color(this.theme.line);
        }, (item: NotificationItem) => `${item.id}#${item.read === true}#${item.title}`);
      }
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }
}
