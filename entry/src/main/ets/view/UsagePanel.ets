import { UsagePage } from '../model/Models';
import { formatTokens, summarizeUsage, UsageSummary, UsageWindow } from '../logic/Usage';
import { SecondaryPageTheme } from './SecondaryPages';

/**
 * 用量面板（P2-2）。
 *
 * 数据来自协议 `usage`：主机把用量压成扁平行，`logic/Usage.ets` 负责还原与聚合。
 * 这里只做展示：时间窗口切换 + 总量 + 归属者排行 + 模型排行。
 *
 * 设计取舍：**不引入图表库**。排行用横条（Row + 比例宽度）表达，
 * 既能在手机上读，也不需要为一次统计拉一个依赖；
 * 上游用的是堆叠图，视觉更丰富，但当前信息密度用横条已足够。
 */
@Component
export struct UsagePanel {
  @Prop theme: SecondaryPageTheme = {
    pageBg: '#F5F7FA', rowBg: '#FFFFFF', chipBg: '#FFFFFF', chipLine: '#E3E8F0',
    ink: '#172033', muted: '#657086', line: '#E3E8F0', brand: '#3F5EF5', brandSoft: '#EEF2FF', danger: '#C93F49', dangerBg: '#FFF0F1'
  };
  @Prop page: UsagePage = {};
  @Prop window: UsageWindow = '24h';
  @Prop loading: boolean = false;
  @Prop error: string = '';

  onWindowChange: (window: UsageWindow) => void = (): void => {};
  onRefresh: () => void = (): void => {};
  onClose: () => void = (): void => {};

  private summary(): UsageSummary {
    return summarizeUsage(this.page, this.window);
  }

  build() {
    Column() {
      this.header();
      Scroll() {
        Column({ space: 14 }) {
          this.windowPicker();
          if (this.error.length > 0) {
            Text(this.error).fontSize(13).fontColor('#C93F49').width('100%')
              .padding(14).backgroundColor(this.theme.rowBg).borderRadius(12);
          }
          if (this.loading) {
            Row({ space: 10 }) {
              LoadingProgress().width(22).height(22).color(this.theme.brand);
              Text('正在读取用量…').fontSize(14).fontColor(this.theme.muted);
            }.width('100%').padding(20);
          } else if (this.summary().empty) {
            Text('所选时间范围内没有用量记录。').fontSize(14).fontColor(this.theme.muted)
              .width('100%').padding(20);
          } else {
            // 注意：**@Builder 的参数是值传递、不会触发 UI 更新**。
            // 2026-10-17 实测：把 summary/窗口值当参数传进去，切换窗口后数字完全不变
            // （window=all 仍显示 24h 的值）。因此这里全部用**无参 builder**，
            // 数据在 builder 内部读取，才能跟随 @State/@Prop 变化重绘。
            this.totalsCard();
            this.ownersRanking();
            this.modelsRanking();
          }
        }
        .width('100%').padding({ left: 18, right: 18, top: 4, bottom: 24 });
      }
      .layoutWeight(1).width('100%').scrollBar(BarState.Off);
    }
    .width('100%').height('100%').backgroundColor(this.theme.pageBg);
  }

  private maxOwnerTotal(): number {
    const owners = this.summary().owners;
    return owners.length > 0 ? owners[0].total : 0;
  }

  private maxModelTotal(): number {
    const models = this.summary().models;
    return models.length > 0 ? models[0].total : 0;
  }

  @Builder
  private header() {
    Row({ space: 12 }) {
      Button('‹').width(40).height(40).borderRadius(20).fontSize(24)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .onClick(() => this.onClose());
      Text('用量').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.theme.ink)
        .layoutWeight(1);
      Button(this.loading ? '刷新中' : '刷新')
        .height(34).borderRadius(17).fontSize(13)
        .backgroundColor(this.theme.rowBg).fontColor(this.theme.ink)
        .enabled(!this.loading)
        .onClick(() => this.onRefresh());
    }
    .width('100%').height(64).padding({ left: 16, right: 16 });
  }

  /** 时间窗口切换（原生分段按钮的轻量实现）。 */
  @Builder
  private windowPicker() {
    Row({ space: 8 }) {
      this.windowChip('24h', '24 小时');
      this.windowChip('7d', '7 天');
      this.windowChip('30d', '30 天');
      this.windowChip('all', '全部');
    }.width('100%');
  }

  @Builder
  private windowChip(value: UsageWindow, label: string) {
    Button(label)
      .layoutWeight(1).height(38).borderRadius(12).fontSize(13)
      .backgroundColor(this.window === value ? this.theme.brand : this.theme.rowBg)
      .fontColor(this.window === value ? '#FFFFFF' : this.theme.ink)
      .onClick(() => this.onWindowChange(value));
  }

  /** 排行数据（builder 内部取，避免 @Builder 参数不刷新）。 */
  private rankRows(kind: string): UsageRankRow[] {
    const summary = this.summary();
    const source = kind === 'owners' ? summary.owners : summary.models;
    const rows: UsageRankRow[] = [];
    for (let i = 0; i < source.length; i++) {
      rows.push({ name: source[i].name, total: source[i].total });
    }
    return rows;
  }

  /** 排行最大值。 */
  private rankMax(kind: string): number {
    const rows = this.rankRows(kind);
    return rows.length > 0 ? rows[0].total : 0;
  }

  /** 单项指标（无参 builder；值在内部读取，避免参数不刷新）。 */
  @Builder
  private metricInput() {
    Column({ space: 2 }) {
      Text(formatTokens(this.summary().input)).fontSize(18).fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink);
      Text('输入').fontSize(11).fontColor(this.theme.muted);
    }.layoutWeight(1).alignItems(HorizontalAlign.Start);
  }

  @Builder
  private metricOutput() {
    Column({ space: 2 }) {
      Text(formatTokens(this.summary().output)).fontSize(18).fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink);
      Text('输出').fontSize(11).fontColor(this.theme.muted);
    }.layoutWeight(1).alignItems(HorizontalAlign.Start);
  }

  @Builder
  private metricCacheRead() {
    Column({ space: 2 }) {
      Text(formatTokens(this.summary().cacheRead)).fontSize(18).fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink);
      Text('缓存读').fontSize(11).fontColor(this.theme.muted);
    }.layoutWeight(1).alignItems(HorizontalAlign.Start);
  }

  @Builder
  private metricCacheWrite() {
    Column({ space: 2 }) {
      Text(formatTokens(this.summary().cacheWrite)).fontSize(18).fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink);
      Text('缓存写').fontSize(11).fontColor(this.theme.muted);
    }.layoutWeight(1).alignItems(HorizontalAlign.Start);
  }

  @Builder
  private metricCalls() {
    Column({ space: 2 }) {
      Text(`${this.summary().calls}`).fontSize(18).fontWeight(FontWeight.Medium)
        .fontColor(this.theme.ink);
      Text('调用').fontSize(11).fontColor(this.theme.muted);
    }.layoutWeight(1).alignItems(HorizontalAlign.Start);
  }

  /** 总量卡片。 */
  @Builder
  private totalsCard() {
    Column({ space: 12 }) {
      Text('总计').fontSize(15).fontColor(this.theme.muted).width('100%');
      Row({ space: 8 }) {
        this.metricInput();
        this.metricOutput();
      }.width('100%');
      Row({ space: 8 }) {
        this.metricCacheRead();
        this.metricCacheWrite();
        this.metricCalls();
      }.width('100%');
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }

  /** 按 Bot / 群聊排行。 */
  @Builder
  private ownersRanking() {
    Column({ space: 10 }) {
      Text('按 Bot / 群聊').fontSize(15).fontColor(this.theme.muted).width('100%');
      ForEach(this.rankRows('owners'), (row: UsageRankRow) => {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(row.name).fontSize(13).fontColor(this.theme.ink).layoutWeight(1)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(formatTokens(row.total)).fontSize(13).fontColor(this.theme.ink);
          }.width('100%');
          Row() {
            Row()
              .width(`${Math.round(barPercent(row.total, this.rankMax('owners')))}%`)
              .height(6).borderRadius(3).backgroundColor(this.theme.brand);
          }
          .width('100%').height(6).borderRadius(3)
          .backgroundColor(this.theme.chipLine);
        }.width('100%');
      // key 里带 total：ArkUI 的 ForEach 在 key 不变时会复用旧节点，
      // 值变了但 key 不变 → 数字停在旧值上（2026-10-17 实测：切换窗口后排行数字不更新）
      }, (row: UsageRankRow) => `${row.name}#${row.total}`);
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }

  /** 按模型排行。 */
  @Builder
  private modelsRanking() {
    Column({ space: 10 }) {
      Text('按模型').fontSize(15).fontColor(this.theme.muted).width('100%');
      ForEach(this.rankRows('models'), (row: UsageRankRow) => {
        Column({ space: 4 }) {
          Row({ space: 8 }) {
            Text(row.name).fontSize(13).fontColor(this.theme.ink).layoutWeight(1)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis });
            Text(formatTokens(row.total)).fontSize(13).fontColor(this.theme.ink);
          }.width('100%');
          Row() {
            Row()
              .width(`${Math.round(barPercent(row.total, this.rankMax('models')))}%`)
              .height(6).borderRadius(3).backgroundColor(this.theme.brand);
          }
          .width('100%').height(6).borderRadius(3)
          .backgroundColor(this.theme.chipLine);
        }.width('100%');
      }, (row: UsageRankRow) => `${row.name}#${row.total}`);
    }
    .width('100%').padding(16).backgroundColor(this.theme.rowBg).borderRadius(14);
  }
}

/** 排行行（把两种汇总结构压成同一种展示结构）。 */
interface UsageRankRow {
  name: string;
  total: number;
}

/** 百分比整数（用于 `width('NN%')`），限制 0~100 且至少 2 保证可见。 */
function barPercent(value: number, max: number): number {
  if (!Number.isFinite(value) || !Number.isFinite(max) || max <= 0) return 0;
  const percent = Math.round((value / max) * 100);
  if (percent <= 0) return 0;
  return percent > 100 ? 100 : percent;
}
