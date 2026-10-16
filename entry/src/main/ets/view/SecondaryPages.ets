import { Bot } from '../model/Models';

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
  brandSoft: string;
}

@Component
export struct ToolsPage {
  @Prop tokens: SecondaryPageTheme = {
    pageBg: '#FFFFFF', rowBg: '#F1F1F1', chipBg: '#FFFFFF', chipLine: '#E5E5E5',
    ink: '#202336', muted: '#6F758B', line: '#E7E9F1', brand: '#4D6BFE', brandSoft: '#E8EDFF'
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

@Component
export struct CapabilitiesPage {
  @Prop tokens: SecondaryPageTheme = {
    pageBg: '#FFFFFF', rowBg: '#F1F1F1', chipBg: '#FFFFFF', chipLine: '#E5E5E5',
    ink: '#202336', muted: '#6F758B', line: '#E7E9F1', brand: '#4D6BFE', brandSoft: '#E8EDFF'
  };
  /** 可用于添加能力的 Bot（由父组件传入）。 */
  @Prop bots: Bot[] = [];
  onBack: () => void = (): void => {};

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
        Column({ space: 18 }) {
          Text('为 Bot 添加可复用能力').fontSize(14).fontColor(this.tokens.muted).width('100%');
          if (this.bots.length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.bots, (bot: Bot) => {
                Button(bot.name).height(38).margin({ right: 8, bottom: 8 }).borderRadius(19)
                  .backgroundColor(this.tokens.brandSoft).fontColor(this.tokens.brand);
              }, (bot: Bot) => bot.id);
            }.width('100%');
          }
          this.abilityCard('网页浏览', '允许 Bot 打开网页、搜索资料并提取内容。');
          this.abilityCard('文件与工作区', '读取、整理和编辑主机工作目录里的文件。');
          this.abilityCard('定时执行', '让 Bot 按计划运行任务并发送结果通知。');
        }.width('100%').padding({ left: 18, right: 18, top: 12, bottom: 24 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(this.tokens.pageBg);
  }

  @Builder
  private abilityCard(title: string, description: string) {
    Column({ space: 10 }) {
      Text(title).fontSize(20).fontWeight(FontWeight.Medium).fontColor(this.tokens.ink).width('100%');
      Text(description).fontSize(14).fontColor(this.tokens.muted).width('100%')
        .wordBreak(WordBreak.BREAK_WORD);
      Button('＋ 添加能力').height(38).borderRadius(19)
        .backgroundColor(this.tokens.brandSoft).fontColor(this.tokens.brand)
        .alignSelf(ItemAlign.End);
    }.padding(20).width('100%').backgroundColor(this.tokens.rowBg).borderRadius(22);
  }
}
