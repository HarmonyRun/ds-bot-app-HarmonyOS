/*
 * BotAvatarView —— 实时矢量绘制的 Bot 头像（对齐上游 `BotAvatar.tsx` 的 `BotAvatar`）。
 *
 * 为什么不用 static PNG：上游头像不是图片，而是 20 种形状 × 12 种颜色实时组合，
 * `entry/src/main/resources/base/media/avatar_*.png` 只有 13 张固定配色的图，
 * 颜色参数落不到画面上（换颜色看不出效果）。这里用 ArkUI 的 `Path` / `Rect`
 * 在 `0 0 100 100` 画布上现画（与上游 SVG 的 viewBox 一致）。
 *
 * 坐标契约（2026-10-15 在 API 24 模拟器上按像素标定 + 复测，详见 `docs/handoff-p1.md` §3.2）：
 * 1. ArkUI 的 `Path` 把命令里的数字当 **px**，而 `Path.width()/.height()`、`Rect` 的
 *    `width()/height()/position()` 都是 **vp**；`Shape.viewPort` 也不会缩放子 Path 的坐标数字。
 *    因此这里固定一张 100×100 px 画布（vp 尺寸 = 100 ÷ 密度），由容器统一
 *    `.scale(vp2px(avatarSize) / 100)` 缩到目标尺寸；路径数据始终是上游原始的 0..100。
 * 2. 每个 `Path` 都要显式给**相同**的 width/height，否则 ArkUI 会按各自 bbox 居中，图层互相错位。
 * 3. shape 组件自带默认描边（真机实测 6px 纯黑轮廓），每个 Path / Rect 都要 `.strokeWidth(0)`。
 *
 * 绘制顺序（与上游逐层对齐）：
 *   body（主色） → paints（`[path, color, opacity]` 叠加） → shade（黑 0.14） → light（白 0.16）
 *   → 眼睛：上游用 SVG `Mask` 把上面整组在眼睛位置挖成透明；ArkUI 没有等价 API
 *     （`BlendMode.DST_OUT` 实测会把整块 body 一起挖掉），所以退化成实心眼睛，
 *     见 `AVATAR_EYE_CUTOUT` 的实测说明。
 *
 * 数据：`entry/src/main/resources/rawfile/characters.json`（由上游 characterData.json 精简生成），
 * 首次进入 `aboutToAppear` 读一次并缓存，`build()` 里只做 Map 查表。
 *
 * 不依赖任何其它 view 组件，只用了 `@kit.AbilityKit` / `@kit.ArkUI` / `@kit.ArkTS`。
 */

import { common } from '@kit.AbilityKit';
import { display, PathShape } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import {
  AvatarColorPair,
  AvatarEye,
  AvatarPaint,
  AvatarPathSet,
  LIGHT_OPACITY,
  SHADE_OPACITY,
  avatarColors,
  hasAvatarCatalog,
  normalizeColor,
  parseAvatarCatalog,
  setAvatarCatalog,
  shapePath
} from './AvatarData';

/**
 * 眼睛的画法（本文件唯一的视觉开关）：
 * - true  → 用 `BlendMode.DST_OUT` 把眼睛从 body/shade/light 上挖空，对应上游的 SVG Mask；
 * - false → 眼睛画成实心色块（对应上游 `BotAvatar` 的 `eyeFill` 分支）。
 * **实测结论（2026-10-15，API 24 模拟器）**：`DST_OUT` 在 ArkUI 上会连同 body 一起挖掉，
 * 列表里的小头像只剩眼睛和一小块头顶（见 docs/handoff-p1.md 的截图对比），因此默认改为
 * false（实心眼睛）。上游用 SVG `Mask` 的语义在 ArkUI 上没有等价 API。
 */
const AVATAR_EYE_CUTOUT: boolean = false;
/** AVATAR_EYE_CUTOUT = false 时的眼睛颜色。 */
const AVATAR_EYE_FILL: string = '#FFFFFF';
/** size 非法（<=0 / NaN）时的兜底边长，与上游 `size = 36` 一致。 */
const AVATAR_DEFAULT_SIZE: number = 36;
/** 画布边长（= 上游 SVG 的 viewBox 100，单位是 `Path.commands` 的 **px**）。 */
const AVATAR_CANVAS: number = 100;
/**
 * `aurora` 专用渐变：上游 `BotAvatar.tsx` 对 `color === 'aurora'` 把 body 的 fill 换成
 * `<LinearGradient x1=18 y1=10 x2=78 y2=92 gradientUnits="userSpaceOnUse">`。
 *
 * 真机标定（API 24 模拟器，2026-10-15；标定过程与本轮量化证据由 Lead 归档到 handoff）：
 * 1. **角度**：ArkUI 的 `linearGradient` 只能对「组件盒子」做渐变（没有 userSpace 端点），
 *    角度沿用 CSS 语义（0=向上、90=向右、180=向下，默认 180）。上游方向向量 (60, 82),
 *    换算成 CSS 角度 = atan2(60, -82) ≈ **144°**；实测该角度下方向与上游一致。
 * 2. **stop 位置**：ArkUI 的渐变轴长是盒子投影 `|W·sinθ| + |H·cosθ| = 139.7`（画布 100×100），
 *    而上游的渐变段只有 `|(60,82)| = 101.6`，照抄上游的 0/.42/1 会把颜色「压扁」。
 *    两者都沿同一条轴线性，换算得 `t_box = 0.134 + 0.7273 · t_user`
 *    → 0.134 / 0.439 / 0.861。实测整身与上游 SVG 参考渲染的平均 ΔRGB 从 7.2 降到 **2.1**。
 * 3. `linearGradient` 画的是**矩形背景**而不是形状填充，必须配 `clipShape(PathShape)`；
 *    直接加在 Path 上会渲染成一个渐变方块（实测）。
 */
const AURORA_ANGLE: number = 144;
/** aurora 的三段 stop（颜色与上游逐字一致，位置按上面第 2 条换算过）。 */
const AURORA_STOPS: Array<[ResourceColor, number]> = [
  ['#A4FFB0', 0.134],
  ['#00F0E4', 0.439],
  ['#2E9EF7', 0.861]
];
/** 路径缓存上限，防止调用方用任意 size 把缓存撑爆。 */
const AVATAR_CACHE_LIMIT: number = 96;

/** rawfile 只读一次。 */
let avatarCatalogLoaded: boolean = false;
/** 原始（0..100）路径缓存：key = `shape@raw`。 */
const avatarPathCache: Map<string, AvatarPathSet> = new Map<string, AvatarPathSet>();

/** 读一次缓存，没有就按 `size / 100` 缩放并放进缓存。 */
function cachedAvatarPaths(shape: string): AvatarPathSet {
  const key: string = `${shape}@raw`;
  const hit: AvatarPathSet | undefined = avatarPathCache.get(key);
  if (hit !== undefined) return hit;
  if (avatarPathCache.size >= AVATAR_CACHE_LIMIT) avatarPathCache.clear();
  // 始终持有原始 0..100 数据；显示缩放由容器统一处理（见 vectorAvatar）。
  const value: AvatarPathSet = shapePath(shape, 1);
  avatarPathCache.set(key, value);
  return value;
}

@Component
export struct BotAvatarView {
  /** 形状名：'whale' … 共 20 种；空或未知回退 'gumdrop'。 */
  @Prop shape: string = 'gumdrop';
  /** 颜色名：'blue' … 共 12 种（也接受 inks 里的 deepseek/charcoal 等）；空或未知回退 'blue'。 */
  @Prop color: string = 'blue';
  /**
   * 边长（vp）。
   * 注意：不能命名为 `size`——ArkUI 的 `CustomComponent` 基类已有 `size` 属性，
   * 同名 `@Prop` 会报「not assignable to the same property in base type」。
   */
  @Prop avatarSize: number = AVATAR_DEFAULT_SIZE;
  /**
   * 标定用：px→vp 的倍率覆盖。`0` 表示自动取显示密度（`densityPixels`）。
   * 保留这个入口是为了在真机上标定路径渲染比例，正常业务不要传。
   */
  @Prop pxFactor: number = 0;
  /** 非空时优先显示照片。支持 http(s):// / file:// / data: URI；**不能**传 `$r(...)` 资源名。 */
  @Prop image: string = '';

  aboutToAppear(): void {
    if (avatarCatalogLoaded) return;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const bytes: Uint8Array = context.resourceManager.getRawFileContentSync('characters.json');
      const text: string = util.TextDecoder.create('utf-8').decodeToString(bytes);
      setAvatarCatalog(parseAvatarCatalog(text));
      avatarCatalogLoaded = true;
    } catch (error) {
      // 读失败时**不**置 avatarCatalogLoaded，下一个组件实例会再试一次；
      // 同时 build() 里会用 hasAvatarCatalog() 判断，画一个带正确颜色的圆角方块兜底，
      // 不会出现「什么都没有」的空头像。
      console.error(`BotAvatarView: 读取 rawfile/characters.json 失败，头像回退圆角方块：${(error as Error).message}`);
    }
  }

  /** 实际使用的边长（非法值回退 36）。 */
  private side(): number {
    return this.avatarSize > 0 ? this.avatarSize : AVATAR_DEFAULT_SIZE;
  }

  private paths(): AvatarPathSet {
    return cachedAvatarPaths(this.shape);
  }

  private ink(): AvatarColorPair {
    return avatarColors(this.color);
  }

  private hasPhoto(): boolean {
    return this.image.length > 0;
  }

  /** 是否走上游的 aurora 渐变特判（空/未知颜色会被 normalizeColor 归一，不会是 aurora）。 */
  private isAurora(): boolean {
    return normalizeColor(this.color) === 'aurora';
  }

  /**
   * 一个眼睛：上游 `translate(cx cy) rotate(tilt)` + `Rect(-w/2, -h/2, w, h, rx = w/2)`。
   * 这里用 `position`（左上角）+ `rotate`（默认绕组件中心，正好是 (cx, cy)）等价表达。
   *
   * 注意：**当前渲染不走这里**（`vectorAvatar()` 里内联了实心眼睛），保留它是为了记录
   * 「上游 Mask 语义」的两种写法：`AVATAR_EYE_CUTOUT = true` 是 `BlendMode.DST_OUT`
   * （实测会把 body 一起挖掉，不可用），`false` 是实心眼睛（当前生效的写法）。
   */
  @Builder
  private eyeShape(eye: AvatarEye) {
    if (AVATAR_EYE_CUTOUT) {
      Rect()
        .width(this.canvasVp(eye.width))
        .height(this.canvasVp(eye.height))
        .radius(this.canvasVp(eye.width / 2))
        .position({ x: this.canvasVp(eye.x - eye.width / 2), y: this.canvasVp(eye.y - eye.height / 2) })
        .rotate({ angle: eye.tilt })
        .strokeWidth(0)
        .blendMode(BlendMode.DST_OUT, BlendApplyType.OFFSCREEN)
    } else {
      Rect()
        .width(this.canvasVp(eye.width))
        .height(this.canvasVp(eye.height))
        .radius(this.canvasVp(eye.width / 2))
        .position({ x: this.canvasVp(eye.x - eye.width / 2), y: this.canvasVp(eye.y - eye.height / 2) })
        .rotate({ angle: eye.tilt })
        .strokeWidth(0)
        .fill(AVATAR_EYE_FILL)
    }
  }

  /** 单条叠加层（参考实现，当前 `vectorAvatar()` 里内联了同样的两层属性）。 */
  @Builder
  private paintLayer(paint: AvatarPaint) {
    Path({ commands: paint.path })
      .width(this.canvasSize())
      .height(this.canvasSize())
      .fill(paint.color)
      .opacity(paint.opacity)
  }

  /**
   * 在固定的 `0 0 100 100` **px** 画布里渲染整组图层，再由外层 `.scale()` 统一换算到 vp。
   *
   * 三条硬约束（都是 2026-10-15 在 API 24 模拟器上按像素量出来的，不是理论推导）：
   * 1. `Path.commands` 的数字是 **px**，`Path.width()/.height()` 是 **vp**，`Shape.viewPort`
   *    也不会缩放子 Path 的坐标数字 → 所以整组固定画布 + 一次 `.scale(vp2px(size)/100)`。
   * 2. 每个 `Path` **必须显式给相同的 width/height（= 100px 对应的 vp）**。不给尺寸时 ArkUI
   *    按各自的紧 bbox 测量并在 `Stack` 里居中，body / shade / light 会各自居中而互相错位
   *    （gumdrop 的 light 中心在 (33.7, 11.1)，body 中心在 (50, 50)）。
   * 3. shape 组件会带上默认描边（真机实测轮廓有 6px 纯黑，密度 3）→ 每个 Path / Rect 都要
   *    显式 `.strokeWidth(0)`，否则所有头像都有一圈黑边，上游没有。
   *
   * 画布保持 100×100 不裁剪：所有路径的绝对坐标都落在 4..96 内
   * （`avatar.test.ets` 第 12 个用例会断言这一点）。
   * 眼睛 / 挖空：`AVATAR_EYE_CUTOUT = false`，只画实心眼睛。
   */
  @Builder
  private vectorAvatar() {
    Stack() {
      // 1) 主色轮廓。aurora 走上游的三段渐变：先铺一层纯色（= inks.aurora[0]）作为兜底，
      //    再叠一层「按 body 形状裁剪」的渐变。关键：`linearGradient` 是**矩形背景**，
      //    直接加在 Path 上会画成方块（实测），必须用 `clipShape(PathShape)` 裁成 body 轮廓。
      //    渐变若在该 API 版本上不生效/裁不出来，下面的纯色仍然完整可见，不会出现透明头像。
      //    其余 11 色仍然只有这一层纯色，行为与之前完全一致。
      Path({ commands: this.paths().body })
        .width(this.canvasSize())
        .height(this.canvasSize())
        .strokeWidth(0)
        .fill(this.ink().main)
      if (this.isAurora()) {
        Column()
          .width(this.canvasSize())
          .height(this.canvasSize())
          .linearGradient({ angle: AURORA_ANGLE, colors: AURORA_STOPS })
          .clipShape(new PathShape({ commands: this.paths().body }))
      }
      ForEach(this.paths().paints, (item: AvatarPaint) => {
        Path({ commands: item.path })
          .width(this.canvasSize())
          .height(this.canvasSize())
          .strokeWidth(0)
          .fill(item.color)
          .opacity(item.opacity)
      }, (item: AvatarPaint, index: number) => `${index}:${item.color}`)
      Path({ commands: this.paths().shade })
        .width(this.canvasSize())
        .height(this.canvasSize())
        .strokeWidth(0)
        .fill('#000000')
        .opacity(SHADE_OPACITY)
      Path({ commands: this.paths().light })
        .width(this.canvasSize())
        .height(this.canvasSize())
        .strokeWidth(0)
        .fill('#FFFFFF')
        .opacity(LIGHT_OPACITY)
      ForEach(this.paths().eyes, (item: AvatarEye) => {
        Rect()
          .width(this.canvasVp(item.width))
          .height(this.canvasVp(item.height))
          .radius(this.canvasVp(item.width / 2))
          .position({
            x: this.canvasVp(item.x - item.width / 2),
            y: this.canvasVp(item.y - item.height / 2)
          })
          .rotate({ angle: item.tilt })
          .strokeWidth(0)
          .fill(AVATAR_EYE_FILL)
      }, (item: AvatarEye, index: number) => `${index}:${item.x}`)
    }
    .width(this.canvasSize())
    .height(this.canvasSize())
    .scale({ x: this.renderScale(), y: this.renderScale() })
  }

  /**
   * 把 100×100 的 px 画布缩放到目标 vp 尺寸。
   *
   * 标定过程（API 24 模拟器，密度 3，见 `docs/handoff-p1.md` 的对照截图）：
   * - `renderScale = 1`（完全不缩放）→ 100px 的路径在 3x 屏上只有约 1/3 大；
   * - `renderScale = 3`（只乘密度、不含 `size / 100`）→ 头像是格子的 3 倍，聊天标题栏一眼可见地溢出；
   * - `renderScale = vp2px(size) / 100` → 比例正确（100px 画布 × 系数 = 目标的 px 尺寸）。
   * 结论：画布是 **px** 语义、目标尺寸是 **vp** 语义，必须用 `vp2px` 换算，且全程只换算一次。
   */
  private renderScale(): number {
    if (this.pxFactor > 0) return this.pxFactor / 100;
    // 目标尺寸对应的 px 数 / 画布(100) = 需要的缩放倍数。
    // `vp2px` 是官方换算（`UIContext.vp2px`），比自己去读 densityPixels 更可靠。
    const px = this.vpToPx(this.side());
    return px / 100;
  }

  /** vp → px；取不到时回退到显示密度。 */
  private vpToPx(value: number): number {
    try {
      return this.getUIContext().vp2px(value);
    } catch (_error) {
      try {
        return value * display.getDefaultDisplaySync().densityPixels;
      } catch (_inner) {
        return value;
      }
    }
  }

  /** 1vp 等于多少 px（= 设备密度）。 */
  private density(): number {
    const px = this.vpToPx(1);
    return px > 0 ? px : 1;
  }

  /**
   * 画布单位（px）→ vp。
   *
   * `Path.commands` 的数字是 **px**，而 `Rect().width()/.height()/.position()` 是 **vp**，
   * 同一个 `Stack` 里两者不能混用：真机实测（API 24 模拟器，密度 3）50vp 的鲸鱼眼睛完全偏移、
   * gumdrop 的眼睛变成一大块白斑。所以眼睛的几何一律先换算成 vp 再交给 `Rect`。
   */
  private canvasVp(units: number): number {
    return units / this.density();
  }

  /** 整张画布的 vp 尺寸：100px ÷ 密度。所有图层用它做显式尺寸，才能共享同一坐标系。 */
  private canvasSize(): number {
    return this.canvasVp(AVATAR_CANVAS);
  }

  build() {
    Stack() {
      if (this.hasPhoto()) {
        Image(this.image)
          .width(this.side())
          .height(this.side())
          .objectFit(ImageFit.Contain)
      } else if (!hasAvatarCatalog()) {
        // 兜底：rawfile 还没读到（或读取失败）时，至少画一个带正确主色的圆角方块，
        // 避免整个头像不可见。
        Rect()
          .width(this.side())
          .height(this.side())
          .radius(this.side() * 0.46)
          .fill(this.ink().main)
      } else {
        this.vectorAvatar();
      }
    }
    .width(this.side())
    .height(this.side())
    .alignContent(Alignment.Center)
  }
}
