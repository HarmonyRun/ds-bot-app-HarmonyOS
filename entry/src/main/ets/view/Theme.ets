/**
 * 共享视觉令牌（视图拆分用）。
 *
 * 拆分前，`Index.ets` 用一组私有方法（`pageBg()` / `surface()` / `ink()` / `muted()` / `line()`）
 * 提供颜色，抽出的子组件无法访问它们，只能各自硬编码十六进制值——那会立刻产生
 * 「同一语义多个色值」的漂移（P1-8 刚清掉过一次 `botColor()` 的双重色值）。
 *
 * 因此把所有语义颜色集中到这里，`Index` 与所有子组件共用同一份来源。
 * 约定：**视图里不允许再出现裸十六进制颜色**，只能用这里的令牌或语义化派生色。
 */

/** 一套完整配色（浅色 / 深色各一份）。 */
export interface ThemeTokens {
  /** 页面底色 */
  pageBg: string;
  /** 卡片 / 面板底色 */
  surface: string;
  /** 正文色 */
  ink: string;
  /** 次要文字色 */
  muted: string;
  /** 分隔线与描边 */
  line: string;
  /** 品牌主色 */
  brand: string;
  /** 错误色 */
  danger: string;
  /** 错误底色 */
  dangerBg: string;
  /** 警示色（等待审批、排队等） */
  warning: string;
  /** 警示底色 */
  warningBg: string;
  /** 成功 / 在线色 */
  success: string;
  /** 代码块底色 */
  code: string;
  /** 可点击链接色 */
  link: string;
}

export const LIGHT_THEME: ThemeTokens = {
  pageBg: '#F5F7FA',
  surface: '#FFFFFF',
  ink: '#172033',
  muted: '#657086',
  line: '#E3E8F0',
  brand: '#3F5EF5',
  danger: '#C93F49',
  dangerBg: '#FFF0F1',
  warning: '#B86A16',
  warningBg: '#FFF6E8',
  success: '#159A72',
  code: '#F3F5F9',
  link: '#3155D9'
};

export const DARK_THEME: ThemeTokens = {
  pageBg: '#111722',
  surface: '#19212E',
  ink: '#F3F6FC',
  muted: '#9DA9BC',
  line: '#2B3545',
  brand: '#8EA2FF',
  danger: '#FF8A8A',
  dangerBg: '#3B252B',
  warning: '#F0B45E',
  warningBg: '#3A301F',
  success: '#4ED9A4',
  code: '#222C3A',
  link: '#9AAEFF'
};

/** 按深浅色取令牌。 */
export function themeOf(dark: boolean): ThemeTokens {
  return dark ? DARK_THEME : LIGHT_THEME;
}

/**
 * 消息气泡等场景需要的「固定配色」：用户气泡在深浅色下都是浅底深字
 * （主题只改背景，不改气泡配色），所以这里给出气泡专用的字色。
 */
export const OWN_BUBBLE_INK: string = '#172033';
export const OWN_BUBBLE_MUTED: string = '#52668F';
