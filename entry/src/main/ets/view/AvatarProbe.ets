import { BotAvatarView } from './BotAvatarView';
import { AvatarEye, AvatarPaint, AvatarPathSet, avatarColors, parseAvatarCatalog, setAvatarCatalog, shapePath } from './AvatarData';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';

/**
 * 头像渲染诊断页（临时，P1 调试用）。
 *
 * 目的：把「同一组路径数据在不同坐标系假设下渲染成什么样」并排画出来，
 * 从而确定 ArkUI `Path` / `Shape` 的坐标语义，而不是靠猜。
 *
 * 结论会写回 docs/handoff-p1.md；这个页面在结论落定后可删。
 */
@Component
export struct AvatarProbe {
  @State raw: string = '未开始';
  @State bodyBounds: string = '';
  @State eyeBounds: string = '';
  @State catalogOk: boolean = false;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const bytes = context.resourceManager.getRawFileContentSync('characters.json');
      const text = util.TextDecoder.create('utf-8').decodeToString(bytes);
      const catalog = parseAvatarCatalog(text);
      setAvatarCatalog(catalog);
      this.catalogOk = true;
      // 报告的路径数量与首段字符，用于确认数据确实读进来了
      const whale = shapePath('whale', 1);
      this.raw = `body=${whale.body.length}字 shade=${whale.shade.length}字 light=${whale.light.length}字 eyes=${whale.eyes.length} paints=${whale.paints.length}`;
      this.eyeBounds = JSON.stringify(whale.eyes.map((e: AvatarEye) => [Math.round(e.x), Math.round(e.y)]));
      this.bodyBounds = whale.body.slice(0, 120);
    } catch (error) {
      this.raw = `读取失败：${(error as Error).message}`;
    }
  }

  @Builder
  private cell(label: string, size: number, shape: string, color: string) {
    Column({ space: 6 }) {
      Text(label).fontSize(11).fontColor('#6F758B');
      BotAvatarView({ shape: shape, color: color, avatarSize: size, image: '' });
      Text(`${size}vp`).fontSize(10).fontColor('#6F758B');
    }
    .width(120).alignItems(HorizontalAlign.Center)
  }

  /** 标定用：同一个鲸鱼，只改 px→vp 倍率，找出「填满格子」的那个值。 */
  @Builder
  private calibCell(factor: number, size: number) {
    Column({ space: 6 }) {
      Text(`画布×${factor}`).fontSize(11).fontColor('#6F758B');
      BotAvatarView({ shape: 'whale', color: 'blue', avatarSize: size, image: '', pxFactor: factor });
      Text(`${size}vp`).fontSize(10).fontColor('#6F758B');
    }
    .width(120).alignItems(HorizontalAlign.Center)
  }

  build() {
    Column({ space: 10 }) {
      Text('头像渲染诊断').fontSize(18).fontWeight(FontWeight.Bold).width('100%')
      Text(`数据：${this.raw}`).fontSize(11).fontColor('#6F758B').width('100%')
      Text(`眼睛坐标：${this.eyeBounds}`).fontSize(11).fontColor('#6F758B').width('100%')
      Text(`body 前 120 字：${this.bodyBounds}`).fontSize(10).fontColor('#6F758B').width('100%')

      Text('倍率标定（60vp，找出填满格子的倍率）').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
      Row({ space: 6 }) {
        this.calibCell(100, 60);
        this.calibCell(150, 60);
        this.calibCell(200, 60);
        this.calibCell(300, 60);
      }.width('100%')

      Text('不同尺寸（应为等比缩放的同一个鲸鱼）').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
      Row({ space: 8 }) {
        this.cell('20vp', 20, 'whale', 'blue');
        this.cell('50vp', 50, 'whale', 'blue');
        this.cell('100vp', 100, 'whale', 'blue');
      }.width('100%')

      Text('不同形状（同尺寸 60vp）').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
      Row({ space: 8 }) {
        this.cell('whale', 60, 'whale', 'blue');
        this.cell('star', 60, 'star', 'red');
        this.cell('gumdrop', 60, 'gumdrop', 'green');
      }.width('100%')

      Text('不同颜色（同形状 gumdrop，60vp）').fontSize(12).fontWeight(FontWeight.Medium).width('100%')
      Row({ space: 8 }) {
        this.cell('blue', 60, 'gumdrop', 'blue');
        this.cell('magenta', 60, 'gumdrop', 'magenta');
        this.cell('aurora', 60, 'gumdrop', 'aurora');
      }.width('100%')
      Blank()
    }
    .width('100%').height('100%').padding(16).backgroundColor('#FFFFFF')
  }
}

/** 供诊断页显示的路径数量统计。 */
interface PathStat {
  body: number;
  shade: number;
  light: number;
  eyes: number;
  paints: number;
}
