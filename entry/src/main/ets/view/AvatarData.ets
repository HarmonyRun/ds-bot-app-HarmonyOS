/*
 * 角色头像的矢量数据 + 纯函数。
 *
 * 本文件**不依赖 ArkUI**，因此在两条链路上都能用：
 *  1. 真机：`BotAvatarView.ets` 在 `aboutToAppear` 里读 `rawfile/characters.json`，
 *     用 `parseAvatarCatalog` 解析后 `setAvatarCatalog` 注入本模块；
 *  2. Node 测试：`entry/src/test/avatar.test.ets` 直接从磁盘读同一个 JSON 注入，
 *     再断言下面这些纯函数（执行器见 `entry/src/test/run.mjs`）。
 *
 * 数据源：上游 `apps/mobile/src/components/characterData.json`（原样搬运，未改任何路径/颜色）。
 * 视觉真值：上游 `apps/mobile/src/components/BotAvatar.tsx` 的 `BotAvatar`：
 *   body(主色) → paints(叠加) → shade(黑 0.14) → light(白 0.16)，眼睛用 SVG Mask 在整组上挖空。
 *   eyes 的 5 个数值是 `[中心 x, 中心 y, 眼睛矩形整宽, 眼睛矩形整高, 旋转角(度)]`
 *   —— 第 3/4 个是 Rect 的 width/height（不是半径），上游画的是 `rx = width / 2` 的圆角矩形。
 */

/** 一个角色（形状）的矢量定义。字段与 characterData.json 逐字对应。 */
export interface AvatarCharacter {
  /** 主色填充的轮廓路径（`M… l… z`，坐标系 0..100）。 */
  body: string;
  /** 深色叠加层（上游用黑色 0.14 不透明度绘制）。 */
  shade: string;
  /** 浅色叠加层（上游用白色 0.16 不透明度绘制）。 */
  light: string;
  /** 眼睛：`[x, y, width, height, tilt]`，每个角色 2 个。 */
  eyes: number[][];
  /** 额外的彩色叠加层：`[path, color, opacity]`（只有 whale/moon/wave/zed 有）。 */
  paints?: Array<Array<string | number>>;
  /** 形状的英文展示名（只有 whale/star/moon/wave/squircle/zed/hex 有）。 */
  label?: string;
}

/** 精简后的 `characters.json` 结构。 */
export interface AvatarCatalog {
  characters: Record<string, AvatarCharacter>;
  /** 20 个形状名（顺序与 characters 的键一致）。 */
  shapes: string[];
  /** 12 个颜色名。 */
  colors: string[];
  /** 按 id 哈希挑形状时的候选池。 */
  defaultShapes: string[];
  /** 按 id 哈希挑颜色时的候选池。 */
  defaultColors: string[];
  /** 每个颜色名对应的 `[主色, 深色]`（上游深色主题用第 2 个）。 */
  inks: Record<string, string[]>;
}

/** 一个颜色对应的两种墨色（上游 `inks[color]`）。 */
export interface AvatarColorPair {
  /** 主色（body 填充）。 */
  main: string;
  /** 深色（上游深色主题的 body 填充）。 */
  dark: string;
}

/** 眼睛（已按 scale 缩放；tilt 是角度，不缩放）。 */
export interface AvatarEye {
  x: number;
  y: number;
  width: number;
  height: number;
  tilt: number;
}

/** 一条已缩放的叠加层。 */
export interface AvatarPaint {
  path: string;
  color: string;
  opacity: number;
}

/** `shapePath()` 的结果：`scale = size / 100` 之后可直接喂给 ArkUI 的 `Path({ commands })`。 */
export interface AvatarPathSet {
  /** 实际取到的形状名（未知输入会回退成 gumdrop，这里返回回退后的名字）。 */
  shape: string;
  body: string;
  shade: string;
  light: string;
  eyes: AvatarEye[];
  paints: AvatarPaint[];
}

/** 缺省形状：与上游 `characters[bot.id ? defaultShape(bot.id) : 'gumdrop']` 的兜底一致。 */
export const FALLBACK_SHAPE: string = 'gumdrop';
/** 缺省颜色：本工程约定「未知颜色回退 blue」，见 `entry/src/test/avatar.test.ets` 的注释。 */
export const FALLBACK_COLOR: string = 'blue';
/** 目录未注入或墨色缺失时的兜底主色（= inks.blue[0]）。 */
export const FALLBACK_MAIN: string = '#2A92FE';
/** 目录未注入或墨色缺失时的兜底深色（= inks.blue[1]）。 */
export const FALLBACK_DARK: string = '#0E74E0';
/** 上游 shade 层的不透明度。 */
export const SHADE_OPACITY: number = 0.14;
/** 上游 light 层的不透明度。 */
export const LIGHT_OPACITY: number = 0.16;

/** 已注入的目录（模块级缓存，避免每次渲染重新读文件/解析 JSON）。 */
let catalog: AvatarCatalog | undefined = undefined;

/** 注入目录（ArkUI 侧在 aboutToAppear 里调，测试侧在断言前调）。 */
export function setAvatarCatalog(value: AvatarCatalog): void {
  catalog = value;
}

/** 清掉目录（仅测试用）。 */
export function clearAvatarCatalog(): void {
  catalog = undefined;
}

/** 目录是否已注入。 */
/**
 * 目录里的形状清单（按上游顺序）。
 * 供创建页的形状选择器使用；目录未加载时返回空数组，由调用方回退到硬编码清单。
 */
export function avatarShapes(): string[] {
  const current: AvatarCatalog | undefined = catalog;
  if (current === undefined || current.shapes.length === 0) return [];
  return current.shapes.slice();
}

/**
 * 目录里的颜色清单（12 种，含上游的 `aurora`）。
 * 形状选择器与色板都从这里取，避免两份硬编码清单漂移。
 */
export function avatarPalette(): string[] {
  const current: AvatarCatalog | undefined = catalog;
  if (current === undefined || current.colors.length === 0) return [];
  return current.colors.slice();
}

export function hasAvatarCatalog(): boolean {
  return catalog !== undefined;
}

/** `characters.json` 文本 → 目录。纯函数，ArkTS 与 Node 行为一致。 */
export function parseAvatarCatalog(text: string): AvatarCatalog {
  return JSON.parse(text) as AvatarCatalog;
}

/** 空字符串 / 未知 shape 一律回退 `gumdrop`；合法值原样返回。 */
export function normalizeShape(shape: string): string {
  const current: AvatarCatalog | undefined = catalog;
  if (current === undefined || shape.length === 0) return FALLBACK_SHAPE;
  const character: AvatarCharacter | undefined = current.characters[shape];
  if (character === undefined) return FALLBACK_SHAPE;
  return shape;
}

/** 空字符串 / 未知 color（不在 inks 里）一律回退 `blue`；合法值原样返回。 */
export function normalizeColor(color: string): string {
  const current: AvatarCatalog | undefined = catalog;
  if (current === undefined || color.length === 0) return FALLBACK_COLOR;
  const ink: string[] | undefined = current.inks[color];
  if (ink === undefined || ink.length < 2) return FALLBACK_COLOR;
  return color;
}

/** 颜色名 → `[主色, 深色]`；未知值回退到 `blue`（= `inks.blue`）。 */
export function avatarColors(color: string): AvatarColorPair {
  const key: string = normalizeColor(color);
  const current: AvatarCatalog | undefined = catalog;
  if (current !== undefined) {
    const ink: string[] | undefined = current.inks[key];
    if (ink !== undefined && ink.length >= 2) {
      const pair: AvatarColorPair = { main: ink[0], dark: ink[1] };
      return pair;
    }
  }
  const fallback: AvatarColorPair = { main: FALLBACK_MAIN, dark: FALLBACK_DARK };
  return fallback;
}

/** 字符是不是 0-9。 */
function isDigit(ch: string): boolean {
  return ch >= '0' && ch <= '9';
}

/** index 处是不是一个数字 token 的开头（`.`、数字、或后跟数字/`.` 的正负号）。 */
function startsNumber(commands: string, index: number): boolean {
  const ch: string = commands.charAt(index);
  if (isDigit(ch) || ch === '.') return true;
  if (ch === '+' || ch === '-') {
    const next: string = index + 1 < commands.length ? commands.charAt(index + 1) : '';
    return isDigit(next) || next === '.';
  }
  return false;
}

/** 最多 4 位小数，去掉多余的 0；`-0` 归一成 `0`。 */
function formatScaled(value: number): string {
  const rounded: number = Math.round(value * 10000) / 10000;
  if (rounded === 0) return '0';
  return rounded.toString();
}

/**
 * 把 SVG path 命令里的每个数字乘以 `scale`，命令字母（M/l/z 等）原样保留。
 *
 * - `scale === 1`（或非有限值）时原样返回输入字符串（测试会断言逐字符相同）；
 * - 支持负号、`.5` 这种省略整数位的小数、`l5.1 .1` 这种命令字母后直接跟数字 / 连续数字；
 * - 数据里只有 M / l / z，没有圆弧（A）与指数，因此不需要处理标志位。
 */
export function scalePathCommands(commands: string, scale: number): string {
  if (commands.length === 0) return commands;
  if (!Number.isFinite(scale) || scale === 1) return commands;
  let result: string = '';
  let index: number = 0;
  while (index < commands.length) {
    if (startsNumber(commands, index)) {
      let end: number = index;
      const sign: string = commands.charAt(end);
      if (sign === '+' || sign === '-') end = end + 1;
      while (end < commands.length && isDigit(commands.charAt(end))) end = end + 1;
      if (end < commands.length && commands.charAt(end) === '.') {
        end = end + 1;
        while (end < commands.length && isDigit(commands.charAt(end))) end = end + 1;
      }
      const token: string = commands.substring(index, end);
      result = result + formatScaled(parseFloat(token) * scale);
      index = end;
    } else {
      result = result + commands.charAt(index);
      index = index + 1;
    }
  }
  return result;
}

/** 目录缺失 / 形状缺失时的空结果（调用方仍能安全渲染，只是什么都画不出来）。 */
function emptyPathSet(shape: string): AvatarPathSet {
  const empty: AvatarPathSet = { shape: shape, body: '', shade: '', light: '', eyes: [], paints: [] };
  return empty;
}

/**
 * 形状名 + 缩放比 → 可直接绘制的路径集（路径数字与眼睛坐标都已乘 `scale`，tilt 不缩放）。
 * 未知 / 空形状回退 `gumdrop`；返回值的 `shape` 字段是回退后的实际形状名。
 */
export function shapePath(shape: string, scale: number): AvatarPathSet {
  const key: string = normalizeShape(shape);
  const current: AvatarCatalog | undefined = catalog;
  if (current === undefined) return emptyPathSet(key);
  const character: AvatarCharacter | undefined = current.characters[key];
  if (character === undefined) return emptyPathSet(key);

  const eyes: AvatarEye[] = [];
  for (let i = 0; i < character.eyes.length; i++) {
    const raw: number[] = character.eyes[i];
    const eye: AvatarEye = {
      x: raw[0] * scale,
      y: raw[1] * scale,
      width: raw[2] * scale,
      height: raw[3] * scale,
      tilt: raw[4]
    };
    eyes.push(eye);
  }

  const paints: AvatarPaint[] = [];
  const rawPaints: Array<Array<string | number>> | undefined = character.paints;
  if (rawPaints !== undefined) {
    for (let i = 0; i < rawPaints.length; i++) {
      const raw: Array<string | number> = rawPaints[i];
      const paint: AvatarPaint = {
        path: scalePathCommands(String(raw[0]), scale),
        color: String(raw[1]),
        opacity: raw.length > 2 ? parseFloat(String(raw[2])) : 1
      };
      paints.push(paint);
    }
  }

  const paths: AvatarPathSet = {
    shape: key,
    body: scalePathCommands(character.body, scale),
    shade: scalePathCommands(character.shade, scale),
    light: scalePathCommands(character.light, scale),
    eyes: eyes,
    paints: paints
  };
  return paths;
}
