import { Conversation, TeamState } from '../model/Models';
import { ConversationAvatar } from './ConversationAvatarView';
import { ThemeTokens } from './Theme';
import { AppMark } from './AppMark';

/**
 * 宽屏左侧栏（抽自 `Index.ets`）：应用标记 + 导航栏 + 会话列表。
 *
 * 三者同属宽屏左栏、共享同一套配色与宽度断点，所以合成一个组件，
 * 避免它们各自重复声明宽度（`>=1040` 展开文字、`>=840` 固定 320vp 列表）而彼此不一致。
 *
 * 设计取舍：**会话行数据由父组件算好**（`ConversationEntry`），
 * 组件不做 `team` 查找、不碰缓存。这样组件对状态形状的变化不敏感，也能用固定数据直接渲染。
 */

/** 导航项。 */
export interface RailItem {
  /** 同一套 24×24 单色矢量图标。 */
  icon: Resource;
  /** 紫色选中态；SVG 描边不受 Image.fillColor 可靠着色，因此使用成对资源。 */
  selectedIcon: Resource;
  label: string;
  section: string;
}

/** 会话列表的一行（父组件已算好全部显示数据）。 */
export interface ConversationEntry {
  id: string;
  /** 原始会话（头像组件需要它） */
  conversation: Conversation;
  name: string;
  /** 摘要（消息预览或角色回退） */
  preview: string;
  pinned: boolean;
  hidden: boolean;
  /** 是否有待处理（等待中） */
  waiting: boolean;
  selected: boolean;
}

export interface SidebarTheme {
  surface: string;
  ink: string;
  muted: string;
  line: string;
  pageBg: string;
  /** 选中态底色 */
  selectedBg: string;
  /** 圆角按钮底色 */
  chipBg: string;
  brand: string;
  /** 等待指示点 */
  waitingDot: string;
  online: boolean;
}

@Component
export struct DesktopSidebar {
  @Prop tokens: SidebarTheme = {
    surface: '#FFFFFF', ink: '#172033', muted: '#657086', line: '#E3E8F0', pageBg: '#F5F7FA',
    selectedBg: '#EEF2FF', chipBg: '#F3F5F9', brand: '#3F5EF5', waitingDot: '#E89432', online: false
  };
  @Prop themeTokens: ThemeTokens | undefined = undefined;
  /** 当前窗口宽（决定 76 / 180 / 320vp 三档） */
  @Prop windowWidth: number = 1320;
  /**
   * 外部指定总宽（vp）。为 0 时按 `windowWidth` 自行计算。
   *
   * 为什么需要：宽屏改用原生 `SideBarContainer` 后，**宽度由容器决定**（用户可拖拽），
   * 子组件若再自己算一次就会和容器打架——这是上一轮"两个子项各自声明宽度"踩过的坑。
   */
  @Prop forcedWidth: number = 0;
  /** 当前选中分区 */
  @Prop section: string = 'chat';
  @Prop railItems: RailItem[] = [];
  @Prop serverName: string = '';
  @Prop entries: ConversationEntry[] = [];
  @Prop team: TeamState = { bots: [], rooms: [], models: [] };
  @Prop searchText: string = '';
  @Prop showHidden: boolean = false;

  onSelectSection: (section: string) => void = (): void => {};
  onRefresh: () => void = (): void => {};
  onSearch: (value: string) => void = (): void => {};
  onToggleHidden: (value: boolean) => void = (): void => {};
  onSelectConversation: (item: Conversation) => void = (): void => {};

  build() {
    Row() {
      this.rail();
      this.conversationList();
    }
    // **必须给确定宽度**：本组件是外层 Row 的第一个子项。
    // 若用 `width('100%')` 会吃掉整行，把右侧聊天面板挤成 0 宽；
    // 若不给宽度则退化为"内容宽"，而内层 List 的可用宽会反向把它撑到满宽
    // （2026-10-16 折叠屏实测：列表 1972px、聊天面板 0px）。两者都会坏。
    .width(this.sidebarWidth()).height('100%');
  }

  private expanded(): boolean {
    return this.windowWidth >= 1040;
  }

  /** 左栏总宽：外部指定优先，否则 导航栏 + 会话列表。 */
  private sidebarWidth(): number {
    if (this.forcedWidth > 0) return this.forcedWidth;
    const rail = this.expanded() ? 180 : 76;
    return rail + 320;
  }

  /** 会话列表宽 = 总宽 − 导航栏宽。 */
  private listWidth(): number {
    const rail = this.expanded() ? 180 : 76;
    const width = this.sidebarWidth() - rail;
    return width > 160 ? width : 160;
  }

  /**
   * 是否处于「宽度由外部容器决定」的模式（原生 `SideBarContainer`）。
   *
   * 此时根 Row 必须撑满给定宽度、会话列表必须吃掉剩余空间：
   * 若两者都按内容宽布局，容器被用户拖宽后内部会留出一大片空白
   * （2026-10-16 折叠屏实测：侧栏容器 445vp、内部只用到 263vp，右侧空 330px）。
   */
  private externalWidth(): boolean {
    return this.forcedWidth > 0;
  }

  /** 应用标记（与桌面图标共用同一资源，实现见 view/AppMark.ets）。 */
  @Builder
  private appMark(size: number) {
    AppMark({ markSize: size });
  }

  @Builder
  private rail() {
    Stack() {
      // 只延伸本栏背景，不延伸交互内容；透明系统栏下可保持分栏配色。
      Column()
        .width('100%').height('100%')
        .backgroundColor(this.tokens.pageBg)
        .border({ width: { right: 1 }, color: this.tokens.line })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
      Column() {
        Row({ space: 10 }) {
          this.appMark(this.expanded() ? 36 : 34);
          if (this.expanded()) {
            Column() {
              Text('DS Bot').fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.tokens.ink);
              Text('智能协作工作台').fontSize(10).fontColor(this.tokens.muted).maxLines(1);
            }.alignItems(HorizontalAlign.Start);
          }
        }.width('100%').padding({ left: 10, right: 10, top: 18, bottom: 22 });

        ForEach(this.railItems, (item: RailItem) => {
          this.railButton(item);
        }, (item: RailItem) => item.section);

        Blank();
        this.statusPill();
      }
      .width('100%').height('100%')
      .padding({ left: 8, right: 8, bottom: 16 });
    }
    .width(this.expanded() ? 180 : 76).height('100%')
    .backgroundColor(this.tokens.pageBg)
    .border({ width: { right: 1 }, color: this.tokens.line });
  }

  @Builder
  private railButton(item: RailItem) {
    Button() {
      Row({ space: this.expanded() ? 12 : 0 }) {
        Image(this.section === item.section ? item.selectedIcon : item.icon)
          .width(24).height(24)
          .objectFit(ImageFit.Contain);
        if (this.expanded()) {
          Text(item.label).fontSize(15)
            .fontWeight(this.section === item.section ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(this.section === item.section ? this.tokens.brand : this.tokens.ink);
        }
      }
      .width('100%')
      // 折叠屏的 76vp 收起栏只有图标，必须在按钮内水平居中；
      // 展开栏包含「图标 + 文字」，继续从左侧起排。
      .justifyContent(this.expanded() ? FlexAlign.Start : FlexAlign.Center);
    }
    .height(44).width('100%').margin({ bottom: 6 })
    .backgroundColor(this.section === item.section ? this.tokens.selectedBg : Color.Transparent)
    .borderRadius(10)
    .onClick(() => this.onSelectSection(item.section));
  }

  @Builder
  private statusPill() {
    // 收起态（rail 76vp，去掉左右 padding 后仅约 60vp）必须放得下：
    // 圆点 8 + 间距 6 + 文字“已连接”≈ 40vp，再加左右 padding 6*2 = 60vp，
    // 之前用 padding 10 + fontSize 12 会超出 rail 约 3px（折叠屏实测）。
    Row({ space: 5 }) {
      Circle({ width: 7, height: 7 }).fill(this.tokens.online ? '#159A72' : '#A4A9BB');
      Text(this.tokens.online ? '已连接' : '离线').fontSize(11).fontColor(this.tokens.muted);
    }
    .padding({ left: 6, right: 6, top: 6, bottom: 6 })
    .backgroundColor(this.tokens.chipBg)
    .borderRadius(16);
  }

  @Builder
  private conversationList() {
    Stack() {
      Column()
        .width('100%').height('100%')
        .backgroundColor(this.tokens.surface)
        .border({ width: { right: this.windowWidth >= 840 ? 1 : 0 }, color: this.tokens.line })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
      Column() {
        Row() {
          Column({ space: 2 }) {
            Text('会话').fontSize(21).fontWeight(FontWeight.Bold).fontColor(this.tokens.ink);
            Text(`${this.entries.length} 个工作会话`).fontSize(11).fontColor(this.tokens.muted);
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          Button() {
            Image($r('app.media.ic_refresh'))
              .width(21).height(21)
              .objectFit(ImageFit.Contain);
          }
            .width(36).height(36).borderRadius(10)
            .padding(0)
            .backgroundColor(this.tokens.chipBg)
            .onClick(() => this.onRefresh());
        }.width('100%').padding({ left: 18, right: 14, top: 18, bottom: 14 });
        TextInput({ placeholder: '搜索会话', text: this.searchText })
          .height(40).margin({ left: 14, right: 14, bottom: 12 }).borderRadius(10)
          .backgroundColor(this.tokens.pageBg).fontColor(this.tokens.ink)
          .border({ width: 1, color: this.tokens.line })
          .onChange((value: string) => this.onSearch(value));
        Row() {
          Text('最近会话').fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.tokens.muted).layoutWeight(1);
          Text('显示隐藏').fontSize(11).fontColor(this.tokens.muted).margin({ right: 6 });
          Toggle({ type: ToggleType.Switch, isOn: this.showHidden })
            .onChange((value: boolean) => this.onToggleHidden(value));
        }.width('100%').padding({ left: 16, right: 14, bottom: 8 });
        List({ space: 4 }) {
          ForEach(this.entries, (entry: ConversationEntry) => {
            ListItem() {
              this.entryRow(entry);
            }.onClick(() => this.onSelectConversation(entry.conversation));
          }, (entry: ConversationEntry) => entry.id);
        }
        .layoutWeight(1).padding({ left: 8, right: 8 })
        .scrollBar(BarState.Off);
      }
      .width('100%').height('100%');
    }
    // **必须用确定宽度**：`width('100%')` 在 Row 里会吃掉 include 全部剩余宽度，
    // 把右侧聊天面板挤成 0 宽（2026-10-16 折叠屏实测：List 宽 1972px = 整行剩余全宽，
    // 摘要文字被裁切）。窄屏（<840）才是"占满剩余"。
    // 外部定宽模式下会话列表吃掉剩余空间（layoutWeight），否则用固定宽
    .width(this.externalWidth() ? undefined : this.listWidth())
    .layoutWeight(this.externalWidth() ? 1 : 0)
    .height('100%')
    .backgroundColor(this.tokens.surface)
    .border({ width: { right: this.windowWidth >= 840 ? 1 : 0 }, color: this.tokens.line });
  }

  @Builder
  private entryRow(entry: ConversationEntry) {
    Row({ space: 11 }) {
      // 会话头像统一走 view/ConversationAvatarView.ets（叠加算法在 logic/ConversationAvatar.ets）
      ConversationAvatar({
        item: entry.conversation, team: this.team, avatarSize: 50, dark: false
      });
      Column({ space: 4 }) {
        Row() {
          Text(entry.name).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor(this.tokens.ink).maxLines(1).layoutWeight(1);
          if (entry.pinned) Text('置顶').fontSize(10).fontColor(this.tokens.brand);
          if (entry.hidden) Text('隐藏').fontSize(10).fontColor(this.tokens.muted);
          if (entry.waiting) Circle({ width: 8, height: 8 }).fill(this.tokens.waitingDot);
        }.width('100%');
        Text(entry.preview).fontSize(12).fontColor(this.tokens.muted).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%');
      }.alignItems(HorizontalAlign.Start).layoutWeight(1);
    }
    .width('100%').constraintSize({ minHeight: 72 }).padding({ left: 11, right: 10, top: 9, bottom: 9 })
    .backgroundColor(entry.selected ? this.tokens.selectedBg : Color.Transparent)
    .borderRadius(10)
    .border({ width: { left: entry.selected ? 3 : 0 }, color: this.tokens.brand });
  }
}
