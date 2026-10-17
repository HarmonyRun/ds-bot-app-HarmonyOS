import { AvatarSpec, BotAvatar } from './BotAvatar';

/**
 * Bot 团队页（抽自 `Index.ets` 的 `teamPage`）。
 *
 * 设计：**父组件把数据算成视图模型，页面只渲染 + 发意图**。
 * - `BotCard` 由父组件解析（含头像 spec、是否主 Bot、是否等待中），
 *   避免页面对 `TeamState` 做查找，也让头像只有 `BotAvatar` 一处实现；
 * - 动作（创建 Bot / 创建群聊 / 选中成员 / 打开会话）通过回调交回父组件。
 */

/** 团队页主题令牌。 */
export interface TeamTheme {
  pageBg: string;
  surface: string;
  ink: string;
  muted: string;
  /** 输入框/未选中标签底色 */
  fieldBg: string;
  brand: string;
  onBrand: string;
  /** 只读提示 */
  warning: string;
  warningBg: string;
  /** 顶部胶囊描边 */
  chipBorder: string;
}

/** Bot 卡片（父组件已算好所有显示数据）。 */
export interface BotCard {
  id: string;
  name: string;
  role: string;
  /** 头像参数（`BotAvatar` 直接消费） */
  avatar: AvatarSpec;
  /** 是否主 Bot（画星标） */
  main: boolean;
  waiting: boolean;
}

@Component
export struct TeamPage {
  @Prop theme: TeamTheme = {
    pageBg: '#F5F7FA', surface: '#FFFFFF', ink: '#172033', muted: '#657086', fieldBg: '#F3F5F9',
    brand: '#3F5EF5', onBrand: '#FFFFFF', warning: '#B86A16', warningBg: '#FFF6E8', chipBorder: '#E3E8F0'
  };
  /** 是否窄屏形态（决定标题字号与是否显示关闭按钮） */
  @Prop compact: boolean = false;
  /** 栅格列模板（由窗口宽度决定） */
  @Prop columnsTemplate: string = '1fr 1fr';
  @Prop bots: BotCard[] = [];
  @Prop roomCount: number = 0;
  /** 只读说明（为空表示可写） */
  @Prop readOnlyNotice: string = '';
  @Prop newBotName: string = '';
  @Prop newGroupName: string = '';
  @Prop selectedMemberIds: string[] = [];
  @Prop busy: boolean = false;
  @Prop online: boolean = false;
  /** 顶部连接状态胶囊文案与颜色 */
  @Prop statusLabel: string = '';
  @Prop statusOnline: boolean = false;

  onClose: () => void = (): void => {};
  onOpenBot: (botCard: BotCard) => void = (): void => {};
  onBotNameChange: (value: string) => void = (): void => {};
  onCreateBot: () => void = (): void => {};
  onToggleMember: (botId: string) => void = (): void => {};
  onGroupNameChange: (value: string) => void = (): void => {};
  onCreateGroup: () => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: 16 }) {
        this.header();
        if (this.readOnlyNotice.length > 0) {
          Text(this.readOnlyNotice).fontSize(13).fontColor(this.theme.warning).width('100%')
            .padding(12).backgroundColor(this.theme.warningBg).borderRadius(12);
        }
        this.botGrid();
        this.createBotCard();
        this.createGroupCard();
      }
      .width('100%').constraintSize({ maxWidth: 1120 }).padding({ left: 24, right: 24, top: 22, bottom: 28 })
      .alignSelf(ItemAlign.Center);
    }.id('team-page').layoutWeight(1).height('100%').backgroundColor(this.theme.pageBg);
  }

  @Builder
  private header() {
    Row() {
      if (this.compact) {
        Button() {
          Image($r('app.media.ic_close')).width(22).height(22);
        }
        .width(48).height(48).margin({ right: 14 }).borderRadius(24).backgroundColor('#FFFFFF')
        .border({ width: 1, color: this.theme.chipBorder })
        .onClick(() => this.onClose());
      }
      Column({ space: 3 }) {
        Text(this.compact ? 'Bot 与群聊' : 'Bot 团队')
          .fontSize(this.compact ? 22 : 28).fontWeight(FontWeight.Bold).fontColor(this.theme.ink);
        Text(`${this.bots.length} 个 Bot · ${this.roomCount} 个群聊`)
          .fontSize(13).fontColor(this.theme.muted);
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      this.statusPill();
    }.width('100%');
  }

  @Builder
  private statusPill() {
    Row({ space: 6 }) {
      Circle({ width: 7, height: 7 }).fill(this.statusOnline ? '#159A72' : '#A4A9BB');
      Text(this.statusLabel).fontSize(12).fontColor(this.theme.muted);
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .backgroundColor(this.theme.fieldBg)
    .borderRadius(16);
  }

  @Builder
  private botGrid() {
    Grid() {
      ForEach(this.bots, (card: BotCard) => {
        GridItem() {
          Row({ space: 12 }) {
            // 头像复用 `BotAvatar`（星标/活跃点只有那一处实现）
            BotAvatar({ spec: card.avatar, avatarSize: 48 });
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                Text(card.name).fontSize(16).fontWeight(FontWeight.Medium)
                  .fontColor(this.theme.ink).maxLines(1);
                if (card.main) Text('主 Bot').fontSize(10).fontColor(this.theme.brand);
              }
              Text(card.role).fontSize(12).fontColor(this.theme.muted).maxLines(2);
              if (card.waiting) Text('等待中').fontSize(11).fontColor(this.theme.warning);
            }.alignItems(HorizontalAlign.Start).layoutWeight(1);
            Image($r('app.media.ic_chevron')).width(16).height(16);
          }
          .width('100%').height(104).alignItems(VerticalAlign.Center)
          .padding({ left: 14, right: 12 }).backgroundColor(this.theme.surface).borderRadius(14)
          .border({ width: 1, color: this.theme.chipBorder })
          .onClick(() => this.onOpenBot(card));
        }
      }, (card: BotCard) => card.id);
    }
    .columnsTemplate(this.columnsTemplate)
    .columnsGap(12).rowsGap(12).width('100%');
  }

  @Builder
  private createBotCard() {
    Column({ space: 12 }) {
      Text('创建 Bot').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.theme.ink).width('100%');
      Row({ space: 10 }) {
        TextInput({ placeholder: 'Bot 名称', text: this.newBotName })
          .layoutWeight(1).height(44).backgroundColor(this.theme.fieldBg).borderRadius(10)
          .border({ width: 1, color: this.theme.chipBorder })
          .fontColor(this.theme.ink)
          .onChange((value: string) => this.onBotNameChange(value));
        Button('创建').height(42).borderRadius(10).backgroundColor(this.theme.brand)
          .fontColor(this.theme.onBrand)
          .enabled(!this.busy && this.online && this.newBotName.trim().length > 0)
          .onClick(() => this.onCreateBot());
      }.width('100%');
    }.width('100%').padding(18).backgroundColor(this.theme.surface).borderRadius(14)
      .border({ width: 1, color: this.theme.chipBorder });
  }

  @Builder
  private createGroupCard() {
    Column({ space: 12 }) {
      Text('创建群聊').fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.theme.ink).width('100%');
      Text('选择至少两个 Bot，第一个成员将成为管理员。').fontSize(12)
        .fontColor(this.theme.muted).width('100%');
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.bots, (card: BotCard) => {
          Button(card.name).height(34).margin({ right: 8, bottom: 8 }).borderRadius(9)
            .backgroundColor(this.selectedMemberIds.includes(card.id) ? this.theme.brand : this.theme.fieldBg)
            .fontColor(this.selectedMemberIds.includes(card.id) ? this.theme.onBrand : this.theme.ink)
            .onClick(() => this.onToggleMember(card.id));
        }, (card: BotCard) => card.id);
      }.width('100%');
      Row({ space: 10 }) {
        TextInput({ placeholder: '群聊名称', text: this.newGroupName })
          .layoutWeight(1).height(44).backgroundColor(this.theme.fieldBg).borderRadius(10)
          .border({ width: 1, color: this.theme.chipBorder })
          .fontColor(this.theme.ink)
          .onChange((value: string) => this.onGroupNameChange(value));
        Button('创建').height(42).borderRadius(10).backgroundColor(this.theme.brand)
          .fontColor(this.theme.onBrand)
          .enabled(!this.busy && this.online && this.newGroupName.trim().length > 0 &&
            this.selectedMemberIds.length >= 2)
          .onClick(() => this.onCreateGroup());
      }.width('100%');
    }.width('100%').padding(18).backgroundColor(this.theme.surface).borderRadius(14)
      .border({ width: 1, color: this.theme.chipBorder });
  }
}
