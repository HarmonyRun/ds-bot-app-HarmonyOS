import { Approval } from '../model/Models';

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
}

@Component
export struct SettingsPage {
  @Prop view: SettingsView = { serverName: '', serverUrl: '', dark: false, approvals: [] };
  @Prop tokens: SettingsTheme = {
    pageBg: '#FFFFFF', rowBg: '#F1F1F1', ink: '#202336', muted: '#6F758B', line: '#E5E5E5',
    dangerBg: '#FDECEC', danger: '#C93C3C', brand: '#4D6BFE'
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
      .width(48).height(48).borderRadius(24).backgroundColor('#FFFFFF')
      .border({ width: 1, color: this.tokens.line })
      .onClick(() => this.onClose());
      Blank();
    }.width('100%').height(76).padding({ left: 20, right: 20, top: 12, bottom: 16 });
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
        Stack() {
          Circle({ width: 46, height: 46 }).fill('#E0E0E0');
          Text('DS').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#777777');
        }.width(46).height(46);
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
      }.height(58).padding({ left: 20, right: 18 });
    }
    .width('100%').backgroundColor(this.tokens.rowBg).borderRadius(22);
  }

  @Builder
  private toolsCard() {
    Column() {
      Row() {
        this.rowLabel('工具与技能', 'DS Bot 的工具、技能与插件');
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(78).padding({ left: 20, right: 18 });
    }
    .width('100%').margin({ top: 32 }).backgroundColor(this.tokens.rowBg).borderRadius(22)
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
      }.height(64).padding({ left: 20, right: 18 });
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
    .width('100%').backgroundColor(this.tokens.rowBg).borderRadius(22);
  }

  @Builder
  private preferenceGroup() {
    this.groupTitle('偏好设置');
    Column() {
      Row() {
        Text('通知中心').fontSize(18).fontColor(this.tokens.ink).layoutWeight(1);
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }.height(64).padding({ left: 20, right: 18 });
      Divider().color(this.tokens.line).margin({ left: 20 });
      Row() {
        Text('夜间模式').fontSize(18).fontColor(this.tokens.ink).layoutWeight(1);
        Toggle({ type: ToggleType.Switch, isOn: this.view.dark })
          .onChange((value: boolean) => this.onToggleDark(value));
      }.height(64).padding({ left: 20, right: 18 });
    }.width('100%').backgroundColor(this.tokens.rowBg).borderRadius(22);
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
        }.padding(14).backgroundColor(this.tokens.rowBg).borderRadius(18);
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
    .width('100%').backgroundColor(this.tokens.rowBg).borderRadius(22);
  }

  @Builder
  private logoutButton() {
    Button('断开此设备').width('100%').height(50).margin({ top: 32, bottom: 20 }).borderRadius(25)
      .backgroundColor(this.tokens.dangerBg).fontColor(this.tokens.danger)
      .onClick(() => this.onLogout());
  }
}
