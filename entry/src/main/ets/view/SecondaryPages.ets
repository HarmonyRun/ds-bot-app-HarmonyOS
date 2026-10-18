import { Bot, Capability, CapabilityStatus } from '../model/Models';

/**
 * 「工具与技能」与「能力库」两个手机二级页（抽自 `Index.ets`，P1 视图拆分）。
 *
 * 两个页面结构同源（顶部返回/关闭栏 + 卡片列表），所以放在同一文件里共用：
 * - `ToolsPage`：技能 / 插件 / 连接器 / 能力库四个入口
 * - `CapabilitiesPage`：Bot 标签 + 三个能力卡
 *
 * 设计：纯展示组件。`mobileOverlay` 的路由状态仍由父组件持有，
 * 页面只通过 `onClose` / `onOpenCapabilities` 发出意图。
 */

export interface SecondaryPageTheme {
  pageBg: string;
  /** 卡片底色 */
  rowBg: string;
  /** 顶部胶囊底色 */
  chipBg: string;
  /** 胶囊描边 */
  chipLine: string;
  ink: string;
  muted: string;
  line: string;
  /** 强调色（能力标签、＋ 添加能力） */
  brand: string;
  /** 错误 / 危险操作色 */
  danger: string;
  /** 错误底色（危险按钮背景） */
  dangerBg: string;
  brandSoft: string;
}

@Component
export struct ToolsPage {
  @Prop tokens: SecondaryPageTheme = {
    pageBg: '#FFFFFF', rowBg: '#F1F1F1', chipBg: '#FFFFFF', chipLine: '#E5E5E5',
    ink: '#202336', muted: '#6F758B', line: '#E7E9F1', brand: '#4D6BFE', brandSoft: '#E8EDFF', danger: '#C93F49', dangerBg: '#FFF0F1'
  };
  onClose: () => void = (): void => {};
  onOpenCapabilities: () => void = (): void => {};

  build() {
    Column() {
      this.pageHeader('工具与技能', $r('app.media.ic_close'), (): void => this.onClose());
      Scroll() {
        Column({ space: 8 }) {
          Text('工具与技能').fontSize(14).fontColor(this.tokens.muted).width('100%').padding({ left: 20 });
          Column() {
            this.entryRow('技能');
            Divider().color(this.tokens.line).margin({ left: 20 });
            this.entryRow('插件');
            Divider().color(this.tokens.line).margin({ left: 20 });
            this.entryRow('连接器');
            Divider().color(this.tokens.line).margin({ left: 20 });
            this.entryRow('能力库', (): void => this.onOpenCapabilities());
          }.width('100%').backgroundColor(this.tokens.rowBg).borderRadius(22);
        }
        .width('100%').constraintSize({ minHeight: '100%' }).justifyContent(FlexAlign.Start)
        .padding({ left: 18, right: 18, top: 12 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(this.tokens.pageBg);
  }

  @Builder
  private pageHeader(title: string, icon: Resource, onBack: () => void) {
    Row({ space: 10 }) {
      Button() { Image(icon).width(22).height(22); }
        .width(48).height(48).borderRadius(24).backgroundColor(this.tokens.chipBg)
        .border({ width: 1, color: this.tokens.chipLine })
        .onClick(onBack);
      Row() {
        Text(title).fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.tokens.ink);
      }.height(48).padding({ left: 18, right: 18 }).borderRadius(24).backgroundColor(this.tokens.chipBg)
        .border({ width: 1, color: this.tokens.chipLine });
    }.width('100%').height(76).padding({ left: 20, right: 20, top: 12, bottom: 16 });
  }

  @Builder
  private entryRow(label: string, onOpen?: () => void) {
    Row() {
      Text(label).fontSize(18).fontColor(this.tokens.ink).layoutWeight(1);
      Image($r('app.media.ic_chevron')).width(18).height(18);
    }.height(64).padding({ left: 20, right: 18 })
      .onClick(() => { if (onOpen !== undefined) onOpen(); });
  }
}

/**
 * 能力库（P2-7）。
 *
 * **原来是 3 张硬编码占位卡**（网页浏览 / 文件与工作区 / 定时执行），
 * 「＋ 添加能力」也没有行为。现在改为真实数据：
 * 宿主 state 里的 `capabilities`（团队级清单）+ 每个 Bot 的挂载情况，
 * 点击即可挂载/卸载（`bot-capability`）。
 *
 * 设计取舍：**一次只对一个 Bot 操作**（顶部选 Bot），
 * 而不是矩阵表格——手机宽度放不下「能力 × Bot」矩阵，
 * 也没有真实的批量挂载需求。
 */
@Component
export struct CapabilitiesPage {
  @Prop tokens: SecondaryPageTheme = {
    pageBg: '#FFFFFF', rowBg: '#F1F1F7', chipBg: '#FFFFFF', chipLine: '#E5E5E5',
    ink: '#202336', muted: '#6F758B', line: '#E7E9F1', brand: '#4D6BFE', brandSoft: '#E8EDFF', danger: '#C93F49', dangerBg: '#FFF0F1'
  };
  /** 可选 Bot（由父组件传入） */
  @Prop bots: Bot[] = [];
  /** 能力库（团队级） */
  @Prop capabilities: Capability[] = [];
  /** 当前选中的 Bot（父组件持有） */
  @Prop selectedBotId: string = '';
  /** 该 Bot 已挂载的能力名 */
  @Prop attachedNames: string[] = [];
  /** 该 Bot 上各能力的运行状态 */
  @Prop statuses: Record<string, CapabilityStatus> = {};
  @Prop busy: boolean = false;
  @Prop error: string = '';
  onBack: () => void = (): void => {};
  onSelectBot: (botId: string) => void = (): void => {};
  onToggle: (name: string, attached: boolean) => void = (): void => {};

  /** 按 kind 过滤（返回能力名列表，供 ForEach 用）。 */
  private namesOf(kind: string): string[] {
    const names: string[] = [];
    for (let i = 0; i < this.capabilities.length; i++) {
      if (this.capabilities[i].kind === kind) names.push(this.capabilities[i].name);
    }
    return names;
  }

  private capabilityOf(name: string): Capability | undefined {
    for (let i = 0; i < this.capabilities.length; i++) {
      if (this.capabilities[i].name === name) return this.capabilities[i];
    }
    return undefined;
  }

  private isAttached(name: string): boolean {
    return this.attachedNames.includes(name);
  }

  /** 运行状态文案（未挂载时不显示）。 */
  /** 取某能力的运行状态（把 Record 索引访问收在这里，避免 @Builder 内出现 any）。 */
  private statusOf(name: string): CapabilityStatus | undefined {
    const keys = Object.keys(this.statuses);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] === name) return this.statuses[keys[i]];
    }
    return undefined;
  }

  private statusText(name: string): string {
    if (!this.isAttached(name)) return '';
    const status = this.statusOf(name);
    if (status === undefined) return '';
    if (status.state === 'ready') return '运行中';
    if (status.state === 'connecting') return '连接中';
    if (status.state === 'needs-approval') return '待批准';
    if (status.state === 'error') return status.error ?? '异常';
    return '';
  }

  private statusColor(name: string): string {
    const status = this.statusOf(name);
    if (status === undefined) return this.tokens.muted;
    if (status.state === 'ready') return '#24B47E';
    if (status.state === 'error') return '#C93F49';
    if (status.state === 'needs-approval') return '#C77A28';
    return this.tokens.muted;
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Button() { Image($r('app.media.ic_back')).width(22).height(22); }
          .width(48).height(48).borderRadius(24).backgroundColor(this.tokens.chipBg)
          .border({ width: 1, color: this.tokens.chipLine })
          .onClick(() => this.onBack());
        Row() { Text('能力库').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.tokens.ink); }
          .height(48).padding({ left: 18, right: 18 }).borderRadius(24).backgroundColor(this.tokens.chipBg)
          .border({ width: 1, color: this.tokens.chipLine });
      }.width('100%').height(76).padding({ left: 20, right: 20, top: 12, bottom: 16 });
      Scroll() {
        Column({ space: 16 }) {
          Text('选择一个 Bot，点能力即可挂载或卸载。').fontSize(13)
            .fontColor(this.tokens.muted).width('100%');
          // Bot 选择（无参之外的可变项用 ForEach + key 带选中态）
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.bots, (bot: Bot) => {
              Button(bot.name).height(38).margin({ right: 8, bottom: 8 }).borderRadius(19)
                .backgroundColor(this.selectedBotId === bot.id ? this.tokens.brand : this.tokens.brandSoft)
                .fontColor(this.selectedBotId === bot.id ? '#FFFFFF' : this.tokens.brand)
                .onClick(() => this.onSelectBot(bot.id));
            }, (bot: Bot) => `${bot.id}#${this.selectedBotId === bot.id}`);
          }.width('100%');
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor('#C93F49').width('100%');
          }
          if (this.capabilities.length === 0) {
            Text('团队还没有配置任何能力。').fontSize(14).fontColor(this.tokens.muted)
              .width('100%').padding(18).backgroundColor(this.tokens.rowBg).borderRadius(18);
          } else {
            this.skillSection();
            this.mcpSection();
            this.packSection();
          }
        }.width('100%').padding({ left: 18, right: 18, top: 4, bottom: 24 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(this.tokens.pageBg);
  }

  /**
   * 技能列表。
   *
   * 注意：这里用**三个独立无参 builder** 而不是 `kindSectionBody(kind)`。
   * ArkUI 的 `@Builder` 参数是按值传递的，带参 builder 在状态变化时不会重绘
   * （2026-10-17 在记忆面板已踩过一次，此处刻意避开）。
   */
  @Builder
  private skillSection() {
    if (this.namesOf('skill').length > 0) {
      this.sectionShell(`技能`);
      Column() {
        ForEach(this.namesOf('skill'), (name: string) => {
          this.capabilityRow(name);
          Divider().color(this.tokens.line).margin({ left: 18 });
        }, (name: string) => this.rowKey('skill', name));
      }.width('100%').backgroundColor(this.tokens.rowBg).borderRadius(18);
    }
  }

  @Builder
  private mcpSection() {
    if (this.namesOf('mcp').length > 0) {
      this.sectionShell(`外部服务（MCP）`);
      Column() {
        ForEach(this.namesOf('mcp'), (name: string) => {
          this.capabilityRow(name);
          Divider().color(this.tokens.line).margin({ left: 18 });
        }, (name: string) => this.rowKey('mcp', name));
      }.width('100%').backgroundColor(this.tokens.rowBg).borderRadius(18);
    }
  }

  @Builder
  private packSection() {
    if (this.namesOf('pack').length > 0) {
      this.sectionShell(`能力包`);
      Column() {
        ForEach(this.namesOf('pack'), (name: string) => {
          this.capabilityRow(name);
          Divider().color(this.tokens.line).margin({ left: 18 });
        }, (name: string) => this.rowKey('pack', name));
      }.width('100%').backgroundColor(this.tokens.rowBg).borderRadius(18);
    }
  }

  /** 分组标题（常量参数，仅用于文案，不承载可变数据）。 */
  @Builder
  private sectionShell(title: string) {
    Text(title).fontSize(14).fontColor(this.tokens.muted).width('100%');
  }

  /** 单行能力（无参：数据在内部读取）。 */
  @Builder
  private capabilityRow(name: string) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(name).fontSize(16).fontColor(this.tokens.ink).layoutWeight(1)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
        if (this.isAttached(name)) {
          Text(this.statusText(name)).fontSize(11).fontColor(this.statusColor(name));
        }
        Text(this.isAttached(name) ? '已挂载' : '挂载')
          .fontSize(12).fontColor(this.isAttached(name) ? this.tokens.brand : this.tokens.muted);
      }.width('100%');
      if (this.descriptionOf(name).length > 0) {
        Text(this.descriptionOf(name)).fontSize(12).fontColor(this.tokens.muted).width('100%')
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis });
      }
    }
    .width('100%').padding({ left: 18, right: 18, top: 12, bottom: 12 })
    .onClick(() => {
      if (!this.busy && this.selectedBotId.length > 0) {
        this.onToggle(name, !this.isAttached(name));
      }
    });
  }

  /** 行 key：把挂载态与状态一起编进去，保证变化时重建节点。 */
  private rowKey(kind: string, name: string): string {
    return `${kind}#${name}#${this.isAttached(name)}#${this.statusText(name)}`;
  }

  private descriptionOf(name: string): string {
    const capability = this.capabilityOf(name);
    const description = capability?.description;
    return description === undefined ? '' : description;
  }
}
