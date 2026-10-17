import { BotCard } from './TeamPage';
import { BotAvatar } from './BotAvatar';
import { ThemeTokens } from './Theme';

/**
 * PC 专属上下文栏。
 *
 * 只在足够宽的窗口显示，把团队状态、当前任务与最近活动从聊天时间线中分离出来。
 * 数据全部由 Index 投影，组件不读取协议对象，也不发起网络请求。
 */
@Component
export struct WorkspaceInspector {
  @Prop tokens: ThemeTokens = {
    pageBg: '#F5F7FA', surface: '#FFFFFF', ink: '#172033', muted: '#657086', line: '#E3E8F0',
    brand: '#3F5EF5', danger: '#C93F49', dangerBg: '#FFF0F1', warning: '#B86A16',
    warningBg: '#FFF6E8', success: '#159A72', code: '#F3F5F9', link: '#3155D9'
  };
  @Prop title: string = '会话详情';
  @Prop bots: BotCard[] = [];
  @Prop busy: boolean = false;
  @Prop queueCount: number = 0;
  @Prop activities: string[] = [];

  onOpenBot: (card: BotCard) => void = (): void => {};

  build() {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text('任务与活动').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.tokens.ink);
          Text(this.title).fontSize(11).fontColor(this.tokens.muted).maxLines(1);
        }.alignItems(HorizontalAlign.Start).layoutWeight(1);
        Text(this.busy ? '进行中' : '就绪')
          .fontSize(11).fontColor(this.busy ? this.tokens.warning : this.tokens.success)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(this.busy ? this.tokens.warningBg : '#EAF8F3').borderRadius(8);
      }.width('100%').height(68).padding({ left: 16, right: 14 })
        .border({ width: { bottom: 1 }, color: this.tokens.line });

      Scroll() {
        Column({ space: 20 }) {
          this.teamSection();
          this.taskSection();
          this.activitySection();
        }.width('100%').padding({ left: 14, right: 14, top: 16, bottom: 20 });
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }
    .width(286).height('100%').backgroundColor(this.tokens.surface)
    .border({ width: { left: 1 }, color: this.tokens.line });
  }

  @Builder
  private sectionTitle(title: string, meta: string) {
    Row() {
      Text(title).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.tokens.muted).layoutWeight(1);
      if (meta.length > 0) Text(meta).fontSize(11).fontColor(this.tokens.muted);
    }.width('100%');
  }

  @Builder
  private teamSection() {
    Column({ space: 10 }) {
      this.sectionTitle('团队成员', `${this.bots.length}`);
      ForEach(this.bots, (card: BotCard) => {
        Row({ space: 10 }) {
          BotAvatar({ spec: card.avatar, avatarSize: 34 });
          Column({ space: 2 }) {
            Text(card.name).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.tokens.ink).maxLines(1);
            Text(card.waiting ? '正在输入…' : '可用').fontSize(11)
              .fontColor(card.waiting ? this.tokens.warning : this.tokens.muted);
          }.alignItems(HorizontalAlign.Start).layoutWeight(1);
          Circle({ width: 7, height: 7 }).fill(card.waiting ? this.tokens.warning : this.tokens.success);
        }
        .width('100%').padding({ left: 10, right: 10, top: 9, bottom: 9 })
        .backgroundColor(this.tokens.pageBg).borderRadius(10)
        .onClick(() => this.onOpenBot(card));
      }, (card: BotCard) => card.id);
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  private taskSection() {
    Column({ space: 10 }) {
      this.sectionTitle('当前任务', this.queueCount > 0 ? `排队 ${this.queueCount}` : '');
      Column({ space: 8 }) {
        Text(this.busy ? 'Bot 团队正在处理当前请求' : '等待新的协作请求')
          .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.tokens.ink).width('100%');
        Text(this.busy ? '你可以继续查看消息，任务状态会实时同步。' : '发送消息后，团队进度会显示在这里。')
          .fontSize(11).fontColor(this.tokens.muted).width('100%')
          .wordBreak(WordBreak.BREAK_WORD);
        if (this.busy) {
          LoadingProgress().width(20).height(20).color(this.tokens.brand);
        }
      }
      .width('100%').padding(12).backgroundColor(this.tokens.pageBg).borderRadius(10)
      .border({ width: 1, color: this.tokens.line });
    }.width('100%').alignItems(HorizontalAlign.Start);
  }

  @Builder
  private activitySection() {
    Column({ space: 8 }) {
      this.sectionTitle('最近活动', '');
      if (this.activities.length === 0) {
        Text('当前会话还没有活动记录').fontSize(12).fontColor(this.tokens.muted)
          .width('100%').padding({ top: 8, bottom: 8 });
      } else {
        ForEach(this.activities, (activity: string, index: number) => {
          Row({ space: 9 }) {
            Circle({ width: 6, height: 6 }).fill(index === 0 ? this.tokens.brand : this.tokens.line);
            Text(activity).fontSize(12).fontColor(this.tokens.ink).maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1);
          }.width('100%').padding({ top: 7, bottom: 7 });
        }, (activity: string, index: number) => `${index}:${activity}`);
      }
    }.width('100%').alignItems(HorizontalAlign.Start);
  }
}
