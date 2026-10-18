import { MemoryEntry, MemoryView } from '../model/Models';
import {
  groupEntries, MemoryRow, toRows, usedChars, usedPercent, scopeLimit
} from '../logic/Memory';
import { SecondaryPageTheme } from './SecondaryPages';

/**
 * 记忆面板（P2-4）。
 *
 * 结构：Bot 选择 → 摘要 → 私有/团队两组记忆（可删除）→ 自然语言问答框。
 *
 * 设计取舍：
 * - **不做本地编辑表单**，改记忆走宿主的 `memory-ask`（模型解析增删改）。
 *   原因是记忆条目是「话题文件里的多行文本」，本地直接改行号很容易与主机失同步；
 *   宿主提供的自然语言入口更安全，也让「加一条/改一条/删一条」统一成一句话。
 * - 删除单条用 `memory-forget`（精确匹配文本），走原生确认。
 */
@Component
export struct MemoryPanel {
  @Prop theme: SecondaryPageTheme = {
    pageBg: '#F5F7FA', rowBg: '#FFFFFF', chipBg: '#FFFFFF', chipLine: '#E3E8F0',
    ink: '#172033', muted: '#657086', line: '#E3E8F0', brand: '#3F5EF5', brandSoft: '#EEF2FF', danger: '#C93F49', dangerBg: '#FFF0F1'
  };
  @Prop view: MemoryView = {};
  @Prop botId: string = '';
  @Prop bots: MemoryBotOption[] = [];
  @Prop loading: boolean = false;
  @Prop error: string = '';
  /** 问答输入（父组件持有） */
  @Prop askText: string = '';
  @Prop asking: boolean = false;
  @Prop askError: string = '';
  /** 上一次问答的结果说明（逐条变更） */
  @Prop askResultLines: string[] = [];

  onClose: () => void = (): void => {};
  onRefresh: () => void = (): void => {};
  onSelectBot: (botId: string) => void = (): void => {};
  onForget: (entry: MemoryEntry) => void = (): void => {};
  onAskTextChange: (text: string) => void = (): void => {};
  onAsk: () => void = (): void => {};

  private ownRows(): MemoryRow[] {
    return toRows(groupEntries(this.view.entries).own);
  }

  private teamRows(): MemoryRow[] {
    return toRows(groupEntries(this.view.entries).team);
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          this.botPicker();
          if (this.view.summarizing === true) {
            Row({ space: 10 }) {
              LoadingProgress().width(20).height(20).color(this.theme.brand);
              Text('主机正在整理记忆摘要…').fontSize(13).fontColor(this.theme.muted);
            }.width('100%').padding(12);
          }
          this.summaryCard();
          // 无参 builder：带参数的 @Builder 在 ArkUI 里不会因状态变化重绘
          //（2026-10-17 实测：删除记忆后列表不刷新，因为 rows 是"按值"传进 builder 的）
          this.ownCard();
          this.teamCard();
          this.askCard();
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor('#C93F49').width('100%')
              .padding(14).backgroundColor(this.theme.rowBg).borderRadius(12);
          }
        }
        .width('100%').padding({ left: 18, right: 18, top: 4, bottom: 28 });
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }
    .width('100%').height('100%').backgroundColor(this.theme.pageBg);
  }

  @Builder
  private header() {
    Row({ space: 12 }) {
      Button('‹').width(40).height(40).borderRadius(20).fontSize(24)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .onClick(() => this.onClose());
      Text('记忆').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.ink)
        .layoutWeight(1);
      Button(this.loading ? '读取中' : '刷新')
        .height(34).borderRadius(17).fontSize(13)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .enabled(!this.loading)
        .onClick(() => this.onRefresh());
    }
    .width('100%').height(64).padding({ left: 16, right: 16 });
  }

  @Builder
  private botPicker() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.bots, (bot: MemoryBotOption) => {
        Button(bot.name)
          .height(34).margin({ right: 8, bottom: 8 }).borderRadius(17).fontSize(13)
          .backgroundColor(this.botId === bot.id ? this.theme.brand : this.theme.rowBg)
          .fontColor(this.botId === bot.id ? '#FFFFFF' : this.theme.ink)
          .onClick(() => this.onSelectBot(bot.id));
      }, (bot: MemoryBotOption) => `${bot.id}#${this.botId === bot.id}`);
    }.width('100%');
  }

  @Builder
  private summaryCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('记忆摘要').fontSize(15).fontColor(this.theme.muted).layoutWeight(1);
        if (this.view.fresh === false) {
          Text('尚未更新').fontSize(11).fontColor(this.theme.muted);
        }
      }.width('100%');
      if (this.view.summary === null || this.view.summary === undefined) {
        Text('还没有摘要。记忆积累后主机会自动生成。')
          .fontSize(13).fontColor(this.theme.muted).width('100%');
      } else {
        Text(this.view.summary.text).fontSize(14).fontColor(this.theme.ink).width('100%');
        if (this.view.summary.at !== undefined && this.view.summary.at.length > 0) {
          Text(`更新于 ${this.view.summary.at}`).fontSize(11)
            .fontColor(this.theme.muted).width('100%');
        }
      }
      if (this.view.error !== undefined && this.view.error !== null && this.view.error.length > 0) {
        Text(this.view.error).fontSize(12).fontColor('#C93F49').width('100%');
      }
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }

  /** Bot 私有记忆卡片（无参 builder，内部读取状态）。 */
  @Builder
  private ownCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('Bot 私有记忆').fontSize(15).fontColor(this.theme.muted).layoutWeight(1);
        Text(`${usedChars(this.view, 'own')} / ${this.limitText('own')}`)
          .fontSize(11).fontColor(this.theme.muted);
      }.width('100%');
      Row() {
        Row()
          .width(`${usedPercent(this.view, 'own')}%`)
          .height(4).borderRadius(2).backgroundColor(this.theme.brand);
      }
      .width('100%').height(4).borderRadius(2).backgroundColor(this.theme.chipLine);
      if (this.ownRows().length === 0) {
        Text('暂无条目').fontSize(13).fontColor(this.theme.muted).width('100%');
      } else {
        ForEach(this.ownRows(), (row: MemoryRow) => {
          Column({ space: 3 }) {
            Row({ space: 8 }) {
              Text(row.topic).fontSize(12).fontColor(this.theme.brand).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              Button('删除')
                .height(28).borderRadius(14).fontSize(11)
                .backgroundColor(this.theme.chipBg).fontColor('#C93F49')
                .onClick(() => this.onForget(row.entry));
            }.width('100%');
            Text(row.text).fontSize(14).fontColor(this.theme.ink).width('100%');
            if (row.meta.length > 0) {
              Text(row.meta).fontSize(11).fontColor(this.theme.muted).width('100%');
            }
          }
          .width('100%').padding({ top: 8, bottom: 8 });
          Divider().color(this.theme.line);
        // key 带文本长度：条目内容变化时强制重建，避免复用旧节点
        }, (row: MemoryRow) => `own#${row.topic}#${row.text.length}#${row.text.slice(0, 8)}`);
      }
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }

  /** 团队共享记忆卡片（无参 builder）。 */
  @Builder
  private teamCard() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('团队共享记忆').fontSize(15).fontColor(this.theme.muted).layoutWeight(1);
        Text(`${usedChars(this.view, 'team')} / ${this.limitText('team')}`)
          .fontSize(11).fontColor(this.theme.muted);
      }.width('100%');
      Row() {
        Row()
          .width(`${usedPercent(this.view, 'team')}%`)
          .height(4).borderRadius(2).backgroundColor(this.theme.brand);
      }
      .width('100%').height(4).borderRadius(2).backgroundColor(this.theme.chipLine);
      if (this.teamRows().length === 0) {
        Text('暂无条目').fontSize(13).fontColor(this.theme.muted).width('100%');
      } else {
        ForEach(this.teamRows(), (row: MemoryRow) => {
          Column({ space: 3 }) {
            Row({ space: 8 }) {
              Text(row.topic).fontSize(12).fontColor(this.theme.brand).layoutWeight(1)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
              Button('删除')
                .height(28).borderRadius(14).fontSize(11)
                .backgroundColor(this.theme.chipBg).fontColor('#C93F49')
                .onClick(() => this.onForget(row.entry));
            }.width('100%');
            Text(row.text).fontSize(14).fontColor(this.theme.ink).width('100%');
            if (row.meta.length > 0) {
              Text(row.meta).fontSize(11).fontColor(this.theme.muted).width('100%');
            }
          }
          .width('100%').padding({ top: 8, bottom: 8 });
          Divider().color(this.theme.line);
        }, (row: MemoryRow) => `team#${row.topic}#${row.text.length}#${row.text.slice(0, 8)}`);
      }
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }

  /**
   * 容量文案：`已用 / 上限 字`。
   *
   * 之前写成 `已用 / 百分比`（如 `14 / 0%`），读起来像"14 除以 0%"，含义不清。
   */
  private limitText(scope: string): string {
    return `${scopeLimit(this.view.limits, scope)} 字`;
  }

  /** 自然语言改记忆 + 变更结果。 */
  @Builder
  private askCard() {
    Column({ space: 10 }) {
      Text('用一句话改记忆').fontSize(15).fontColor(this.theme.muted).width('100%');
      Text('例如「记住我偏好简洁的回答」或「删掉关于旧项目的记忆」。')
        .fontSize(12).fontColor(this.theme.muted).width('100%');
      TextArea({ placeholder: '要记住或要改的内容', text: this.askText })
        .height(80).width('100%').backgroundColor(this.theme.chipBg).borderRadius(12)
        .fontColor(this.theme.ink).fontSize(14)
        .onChange((value: string) => this.onAskTextChange(value));
      if (this.askError.length > 0) {
        Text(this.askError).fontSize(12).fontColor('#C93F49').width('100%');
      }
      if (this.askResultLines.length > 0) {
        Column({ space: 4 }) {
          ForEach(this.askResultLines, (line: string) => {
            Text(line).fontSize(12).fontColor(this.theme.ink).width('100%');
          }, (line: string) => line);
        }.width('100%');
      }
      Button(this.asking ? '主机处理中…' : '提交')
        .width('100%').height(44).borderRadius(12).fontSize(15)
        .backgroundColor(this.theme.brand).fontColor('#FFFFFF')
        .enabled(!this.asking && this.askText.trim().length > 0)
        .onClick(() => this.onAsk());
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }
}

/** Bot 选项。 */
export interface MemoryBotOption {
  id: string;
  name: string;
}
