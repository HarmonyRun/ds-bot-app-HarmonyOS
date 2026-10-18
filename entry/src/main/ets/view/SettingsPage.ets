import { Approval, DeviceListItem } from '../model/Models';
import { AppMark } from './AppMark';

/**
 * 手机设置页（抽自 `Index.ets` 的 `mobileSettingsPage`，P1 视图拆分第五步）。
 *
 * 设计：**纯展示组件**。它自己不改任何业务状态，所有交互都通过回调发出意图：
 * 关页 / 切深色 / 进工具页 / 进团队页 / 进诊断页 / 刷新 / 清缓存 / 断开 / 审批决定。
 * 因此本组件可以直接用固定 props 渲染（例如诊断页或截图回归），不依赖真实会话。
 *
 * P2 会往这里加 9 个设置面板，所以先把「分组标题 + 卡片 + 行」的结构固定下来：
 * - 行统一 64/78 高度、左 20 右 18 内边距、`chevron` 图标；
 * - 卡片统一圆角 22、`rowBg` 底色；
 * - 新增面板只需追加一段「标题 + 卡片」，不要另起一套样式。
 */

export interface SettingsTheme {
  /** 页面底色 */
  pageBg: string;
  /** 卡片底色 */
  rowBg: string;
  ink: string;
  muted: string;
  line: string;
  /** 危险操作底色/文字色 */
  dangerBg: string;
  danger: string;
  /** 主色（审批「允许一次」） */
  brand: string;
}

/** 设置页需要展示的数据（由父组件算好）。 */
export interface SettingsView {
  /** 主机名（空则显示 DS Bot） */
  serverName: string;
  /** 主机地址 */
  serverUrl: string;
  /** 是否深色（夜间模式开关的当前值） */
  dark: boolean;
  /** 待批准操作（空数组则不显示该分组） */
  approvals: Approval[];
  /**
   * 已配对设备（P2-10）。
   *
   * 宽屏设置页早已显示设备列表并可移除，**手机端设置页此前没有**——
   * 同一功能两种形态表现不一致，这里补齐。
   */
  devices: DeviceListItem[];
  /** 本机设备 id：用于标记「本机」并禁止移除自己 */
  currentDeviceId: string;
}

@Component
export struct SettingsPage {
  @Prop view: SettingsView = {
    serverName: '', serverUrl: '', dark: false, approvals: [], devices: [], currentDeviceId: ''
  };
  @Prop tokens: SettingsTheme = {
    pageBg: '#F5F7FA', rowBg: '#FFFFFF', ink: '#172033', muted: '#657086', line: '#E3E8F0',
    dangerBg: '#FFF0F1', danger: '#C93F49', brand: '#3F5EF5'
  };

  /** 关闭设置页（回到聊天）。 */
  onClose: () => void = (): void => {};
  /** 切换夜间模式。 */
  onToggleDark: (value: boolean) => void = (): void => {};
  /** 打开工具与技能页。 */
  onOpenTools: () => void = (): void => {};
  /** 打开 Bot 与群聊页。 */
  onOpenTeam: () => void = (): void => {};
  /** 打开诊断页。 */
  onOpenProbe: () => void = (): void => {};
  /** 刷新主机信息。 */
  onRefresh: () => void = (): void => {};
  /** 清空本机缓存。 */
  onClearCache: () => void = (): void => {};
  /** 断开此设备（父组件负责二次确认）。 */
  onLogout: () => void = (): void => {};
  /** 审批决定：`allowed-once` / `rejected`。 */
  onResolveApproval: (approvalId: string, decision: string) => void = (): void => {};
  /** 打开用量面板（P2-2） */
  onOpenUsage: () => void = (): void => {};
  /** 打开定时任务面板（P2-3） */
  onOpenSchedules: () => void = (): void => {};
  /** 打开记忆面板（P2-4） */
  onOpenMemory: () => void = (): void => {};
  /** 打开群聊管理（P2-6） */
  onOpenRooms: () => void = (): void => {};
  /** 打开 Bot 管理（P2-5） */
  onOpenBots: () => void = (): void => {};
  /** 打开 DSH Agent（P2-9） */
  onOpenAgent: () => void = (): void => {};
  /** 打开通知中心（P3-4） */
  onOpenNotifications: () => void = (): void => {};
  /** 未读通知数（显示红点角标） */
  @Prop notificationUnread: number = 0;
  /** 移除某台已配对设备（父组件负责原生确认对话框） */
  onRevokeDevice: (device: DeviceListItem) => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: 0 }) {
        this.header();
        this.hostCard();
        this.toolsCard();
        this.botGroup();
        this.preferenceGroup();
        if (this.view.approvals.length > 0) {
          this.approvalsGroup();
        }
        this.devicesGroup();
        this.maintenanceGroup();
        this.logoutButton();
      }
      .width('100%').padding({ left: 18, right: 18, bottom: 24 });
    }
    .width('100%').height('100%').backgroundColor(this.tokens.pageBg);
  }

  @Builder
  private header() {
    Row() {
      Button() {
        Image($r('app.media.ic_close')).width(22).height(22);
      }
      .width(44).height(44).borderRadius(12).backgroundColor(this.tokens.rowBg)
      .border({ width: 1, color: this.tokens.line })
      .onClick(() => this.onClose());
      Text('设置').fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.tokens.ink)
        .layoutWeight(1).margin({ left: 12 });
    }.width('100%').height(68).padding({ left: 20, right: 20, top: 10, bottom: 12 });
  }

  /** 分组标题（P2 新增面板复用）。 */
  @Builder
  private groupTitle(text: string) {
    Text(text).fontSize(14).fontColor(this.tokens.muted)
      .width('100%').margin({ top: 32, bottom: 10, left: 20 });
  }

  /** 普通设置行（P2 新增面板复用）。 */
  @Builder
  private rowLabel(title: string, subtitle: string) {
    Column({ space: 3 }) {
      Text(title).fontSize(18).fontColor(this.tokens.ink);
      if (subtitle.length > 0) {
        Text(subtitle).fontSize(13).fontColor(this.tokens.muted);
      }
    }.alignItems(HorizontalAlign.Start).layoutWeight(1);
  }

  @Builder
  private hostCard() {
    Column() {
      Row({ space: 14 }) {
        AppMark({ markSize: 46 });
        Column({ space: 3 }) {
          Text(this.view.serverName.length > 0 ? this.view.serverName : 'DS Bot')
            .fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.tokens.ink);
          Text(this.view.serverUrl).fontSize(14).fontColor(this.tokens.muted).maxLines(1);
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(76).width('100%').padding({ left: 20, right: 18 });
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        Text('用量').fontSize(18).fontColor(this.tokens.ink).layoutWeight(1);
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(58).padding({ left: 20, right: 18 })
      .onClick(() => this.onOpenUsage());
    }
    .width('100%').backgroundColor(this.tokens.rowBg).borderRadius(14)
    .border({ width: 1, color: this.tokens.line });
  }

  @Builder
  private toolsCard() {
    Column() {
      Row() {
        this.rowLabel('工具与技能', 'DS Bot 的工具、技能与插件');
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(78).padding({ left: 20, right: 18 })
      .onClick(() => this.onOpenTools());
    }
    .width('100%').margin({ top: 24 }).backgroundColor(this.tokens.rowBg).borderRadius(14)
    .border({ width: 1, color: this.tokens.line })
    .onClick(() => this.onOpenTools());
  }

  @Builder
  private botGroup() {
    this.groupTitle('Bot');
    Column() {
      Row() {
        Text('Bot 与群聊').fontSize(18).fontColor(this.tokens.ink).layoutWeight(1);
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(64).padding({ left: 20, right: 18 }).onClick(() => this.onOpenTeam());
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        Text('定时任务').fontSize(18).fontColor(this.tokens.ink).layoutWeight(1);
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(64).padding({ left: 20, right: 18 })
      .onClick(() => this.onOpenSchedules());
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        this.rowLabel('DSH Agent', '团队的通用智能体与它的会话');
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(72).padding({ left: 20, right: 18 })
      .onClick(() => this.onOpenAgent());
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        this.rowLabel('Bot 管理', '名字、角色、指令、模型与思考档位');
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(72).padding({ left: 20, right: 18 })
      .onClick(() => this.onOpenBots());
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        this.rowLabel('群聊管理', '改名、公告、管理员与成员');
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(72).padding({ left: 20, right: 18 })
      .onClick(() => this.onOpenRooms());
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        this.rowLabel('记忆', 'Bot 私有记忆与团队共享记忆');
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(72).padding({ left: 20, right: 18 })
      .onClick(() => this.onOpenMemory());
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        this.rowLabel('经典 Agent 模式', '在主页显示 DSH Agent 会话。');
        Toggle({ type: ToggleType.Switch, isOn: false });
      }.height(80).padding({ left: 20, right: 18 });
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        Text('Bot 电脑').fontSize(18).fontColor(this.tokens.ink).layoutWeight(1);
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(64).padding({ left: 20, right: 18 });
    }
    .width('100%').backgroundColor(this.tokens.rowBg).borderRadius(14)
    .border({ width: 1, color: this.tokens.line });
  }

  @Builder
  private preferenceGroup() {
    this.groupTitle('偏好设置');
    Column() {
      Row() {
        Text('通知中心').fontSize(18).fontColor(this.tokens.ink).layoutWeight(1);
        if (this.notificationUnread > 0) {
          Text(`${this.notificationUnread}`).fontSize(11).fontColor('#FFFFFF')
            .padding({ left: 7, right: 7, top: 2, bottom: 2 })
            .backgroundColor('#C93F49').borderRadius(9).margin({ right: 6 });
        }
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(64).padding({ left: 20, right: 18 })
      .onClick(() => this.onOpenNotifications());
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        Text('夜间模式').fontSize(18).fontColor(this.tokens.ink).layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.view.dark })
          .onChange((value: boolean) => this.onToggleDark(value));
      }.height(64).padding({ left: 20, right: 18 });
    }.width('100%').backgroundColor(this.tokens.rowBg).borderRadius(14)
      .border({ width: 1, color: this.tokens.line });
  }

  @Builder
  private approvalsGroup() {
    this.groupTitle('待批准操作');
    Column({ space: 10 }) {
      ForEach(this.view.approvals, (approval: Approval) => {
        Column({ space: 8 }) {
          Text(approval.toolName).fontSize(16).fontWeight(FontWeight.Medium)
            .fontColor(this.tokens.ink).width('100%');
          Text(approval.reason ?? '主机请求批准此工具操作')
            .fontSize(13).fontColor(this.tokens.muted).width('100%');
          Row({ space: 8 }) {
            Button('允许一次').height(36).borderRadius(18).backgroundColor(this.tokens.brand)
              .onClick(() => this.onResolveApproval(approval.id, 'allowed-once'));
            Button('拒绝').height(36).borderRadius(18)
              .backgroundColor(this.tokens.dangerBg).fontColor(this.tokens.danger)
              .onClick(() => this.onResolveApproval(approval.id, 'rejected'));
          }
        }.padding(14).backgroundColor(this.tokens.rowBg).borderRadius(12)
          .border({ width: 1, color: this.tokens.line });
      }, (approval: Approval) => approval.id);
    }.width('100%');
  }

  @Builder
  private maintenanceGroup() {
    this.groupTitle('维护');
    Column() {
      Row() {
        this.rowLabel('诊断页', '事件流连接测试与头像渲染对照');
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }
      .height(78).padding({ left: 20, right: 18 })
      .onClick(() => this.onOpenProbe());
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        this.rowLabel('刷新主机信息', '重新读取团队、会话与待批准操作');
      }
      .height(78).padding({ left: 20, right: 18 })
      .onClick(() => this.onRefresh());
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        this.rowLabel('清空本机缓存', '删除本机保存的消息与草稿（不影响主机）');
      }
      .height(78).padding({ left: 20, right: 18 })
      .onClick(() => this.onClearCache());
    }
    .width('100%').backgroundColor(this.tokens.rowBg).borderRadius(14)
    .border({ width: 1, color: this.tokens.line });
  }

  /**
   * 已配对设备（P2-10）。
   *
   * 撤销设备是**不可逆**操作，确认交给父组件的原生 `showDialog`；
   * 这里只发出意图，本机自己不给「移除」入口（避免把自己踢下线）。
   */
  @Builder
  private devicesGroup() {
    this.groupTitle('已配对设备');
    Column() {
      if (this.view.devices.length === 0) {
        Text('暂无已配对设备').fontSize(14).fontColor(this.tokens.muted).width('100%')
          .padding({ left: 20, right: 20, top: 16, bottom: 16 });
      } else {
        ForEach(this.view.devices, (device: DeviceListItem) => {
          Row({ space: 10 }) {
            Text(device.deviceName ?? device.name ?? device.id)
              .fontSize(15).fontColor(this.tokens.ink).layoutWeight(1).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis });
            if (device.id === this.view.currentDeviceId) {
              Text('本机').fontSize(12).fontColor(this.tokens.brand);
            } else {
              Button('移除')
                .height(32).borderRadius(16).fontSize(12)
                .backgroundColor(this.tokens.pageBg).fontColor(this.tokens.ink)
                .onClick(() => this.onRevokeDevice(device));
            }
          }
          .width('100%').height(64).padding({ left: 20, right: 18 });
          Divider().color(this.tokens.line).margin({ left: 20 });
        }, (device: DeviceListItem) => device.id);
      }
    }
    .width('100%').backgroundColor(this.tokens.rowBg).borderRadius(14)
    .border({ width: 1, color: this.tokens.line });
  }

  @Builder
  private logoutButton() {
    Button('断开此设备').width('100%').height(48).margin({ top: 28, bottom: 20 }).borderRadius(12)
      .backgroundColor(this.tokens.dangerBg).fontColor(this.tokens.danger)
      .onClick(() => this.onLogout());
  }
}
