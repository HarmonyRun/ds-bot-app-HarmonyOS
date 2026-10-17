import { AvatarSpec, BotAvatar } from './BotAvatar';
import { ConversationAvatar } from './ConversationAvatarView';
import { Conversation, TeamState } from '../model/Models';
import { AppMark } from './AppMark';

/**
 * 手机首页（抽自 `Index.ets` 的 `mobileHome`）。
 *
 * 结构：顶部三个圆形入口（设置/搜索/新建）+ 可选搜索框 + 主 Bot 大头像 + 会话列表。
 *
 * 设计：**父组件算好行数据与头像参数**。
 * - `MobileHomeEntry` 已含名称/摘要/时间/等待标记，页面不做 `team` 查找、不碰缓存；
 * - 头像统一交给 `ConversationAvatar` / `BotAvatar`（全工程只有那一处实现）；
 * - 动作走回调：设置 / 切换搜索 / 新建 / 打开会话 / 长按头像进诊断。
 */

/** 会话行（父组件已算好全部显示数据）。 */
export interface MobileHomeEntry {
  id: string;
  conversation: Conversation;
  name: string;
  preview: string;
  /** 右上角时间（HH:mm，空串则不显示） */
  time: string;
  waiting: boolean;
}

export interface MobileHomeTheme {
  pageBg: string;
  surface: string;
  ink: string;
  muted: string;
  line: string;
  /** 搜索框底色 */
  fieldBg: string;
  /** 未读/等待指示点 */
  waitingDot: string;
}

@Component
export struct MobileHome {
  @Prop theme: MobileHomeTheme = {
    pageBg: '#FFFFFF', surface: '#FFFFFF', ink: '#202336', muted: '#6F758B', line: '#E7E9F1',
    fieldBg: '#F1F1F1', waitingDot: '#4D6BFE'
  };
  @Prop entries: MobileHomeEntry[] = [];
  /** 会话所属团队（交给 `ConversationAvatar` 解析群聊叠加） */
  @Prop team: TeamState = { bots: [], rooms: [], models: [] };
  @Prop searchText: string = '';
  @Prop searching: boolean = false;

  /** 主 Bot 大头像的显示名（空串表示不显示该区域） */
  @Prop heroName: string = '';
  /** 主 Bot 头像参数 */
  @Prop heroAvatar: AvatarSpec | undefined = undefined;

  onOpenSettings: () => void = (): void => {};
  onToggleSearch: () => void = (): void => {};
  onSearchChange: (value: string) => void = (): void => {};
  onOpenCreate: () => void = (): void => {};
  onSelect: (entry: MobileHomeEntry) => void = (): void => {};
  /** 单击主 Bot 大头像：打开该会话 */
  onOpenHero: () => void = (): void => {};
  /** 长按主 Bot 大头像：进诊断页 */
  onLongPressHero: () => void = (): void => {};

  build() {
    Column() {
      this.header();
      if (this.searching) {
        TextInput({ placeholder: '搜索会话', text: this.searchText })
          .height(50).margin({ left: 20, right: 20, bottom: 8 }).padding({ left: 18, right: 18 })
          .fontSize(17).fontColor(this.theme.ink).backgroundColor(this.theme.fieldBg)
          .borderRadius(25)
          .onChange((value: string) => this.onSearchChange(value));
      }
      Scroll() {
        Column() {
          this.hero();
          Row() {
            Text('最近会话').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.theme.muted);
            Blank();
            Text(`${this.entries.length}`).fontSize(12).fontColor(this.theme.muted);
          }.width('100%').padding({ left: 8, right: 8, top: 14, bottom: 8 });
          ForEach(this.entries, (entry: MobileHomeEntry) => {
            this.conversationRow(entry);
          }, (entry: MobileHomeEntry) => entry.id);
          if (this.entries.length === 0) {
            Text('没有找到会话').fontSize(16).fontColor(this.theme.muted)
              .width('100%').padding(32).textAlign(TextAlign.Center);
          }
        }
        .width('100%').constraintSize({ minHeight: '100%' }).justifyContent(FlexAlign.Start)
        .padding({ left: 16, right: 16, bottom: 24 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }.width('100%').height('100%').backgroundColor(this.theme.pageBg);
  }

  @Builder
  private header() {
    Row({ space: 10 }) {
      AppMark({ markSize: 38 });
      Column({ space: 1 }) {
        Text('DS Bot').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.ink);
        Text('智能协作工作台').fontSize(11).fontColor(this.theme.muted);
      }.alignItems(HorizontalAlign.Start);
      Blank();
      this.roundButton($r('app.media.ic_search'), 22, (): void => this.onToggleSearch());
      this.roundButton($r('app.media.ic_plus'), 27, (): void => this.onOpenCreate());
      this.roundButton($r('app.media.ic_settings'), 21, (): void => this.onOpenSettings());
    }.width('100%').height(72).padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .border({ width: { bottom: 1 }, color: this.theme.line });
  }

  /** 首页顶部的圆形入口按钮（三个入口共用）。 */
  @Builder
  private roundButton(icon: Resource, iconSize: number, action: () => void) {
    Button() {
      Image(icon).width(iconSize).height(iconSize);
    }
    .width(40).height(40).borderRadius(12).backgroundColor(this.theme.surface)
    .border({ width: 1, color: this.theme.line })
    .onClick(action);
  }

  /** 主 Bot 大头像区（非搜索态且有主会话时显示）。 */
  @Builder
  private hero() {
    if (!this.searching && this.heroName.length > 0) {
      Row({ space: 14 }) {
        BotAvatar({
          spec: this.heroAvatar ?? { shape: '', color: '', image: '', main: false, live: false },
          avatarSize: 58
        });
        Column({ space: 4 }) {
          Text('主 Bot').fontSize(11).fontColor(this.theme.muted);
          Text(this.heroName).fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.theme.ink);
          Row({ space: 5 }) {
            Circle({ width: 7, height: 7 }).fill('#159A72');
            Text('随时可以开始协作').fontSize(12).fontColor(this.theme.muted);
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Image($r('app.media.ic_chevron')).width(18).height(18);
      }
      .width('100%').padding({ left: 16, right: 14, top: 14, bottom: 14 })
      .backgroundColor(this.theme.surface).borderRadius(14)
      .border({ width: 1, color: this.theme.line })
      // 单击打开主会话；长按进诊断页（页内可切换「事件流诊断 / 头像诊断」）。
      .onClick(() => this.onOpenHero())
      .gesture(LongPressGesture().onAction(() => this.onLongPressHero()));
    }
  }

  @Builder
  private conversationRow(entry: MobileHomeEntry) {
    Row({ space: 14 }) {
      ConversationAvatar({
        item: entry.conversation, team: this.team, avatarSize: 50
      });
      Column({ space: 5 }) {
        Text(entry.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.theme.ink)
          .maxLines(1).width('100%');
        Text(entry.preview).fontSize(14).fontColor(this.theme.muted).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
      Column() {
        Text(entry.time).fontSize(13).fontColor(this.theme.muted);
        Blank();
        if (entry.waiting) {
          Circle({ width: 10, height: 10 }).fill(this.theme.waitingDot);
        }
      }.height(52).alignItems(HorizontalAlign.End);
    }
    .width('100%').height(78).padding({ left: 8, right: 8 })
    .border({ width: { bottom: 1 }, color: this.theme.line })
    .onClick(() => this.onSelect(entry));
  }
}
