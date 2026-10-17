/**
 * 应用标记（品牌图）。抽自 `Index.ets` 与 `view/DesktopSidebar.ets`。
 *
 * 为什么抽成组件：应用标记原本有**两份实现**——
 * - `Index.appMark()`：`Rect` 紫底 + `✦` 字体字符（旧版临时 Logo）
 * - `DesktopSidebar.appMark()`：蓝鲸位图（2026-10-16 与原作者统一后引入）
 *
 * 结果是「连接页 / 聊天空态 / 启动加载页」仍显示旧紫底标记，与侧栏、桌面图标不一致
 * （同一个 app 出现两套品牌形象）。抽成组件后只保留一处实现，替换图标时不会再漏。
 *
 * 资源：`app_icon_original.png` —— 上游 `QingJ01/DS-Bot-App` 的原版图标，
 * 同时被桌面图标、Ability 图标与启动窗口图标引用（见 `AppScope/app.json5`、`module.json5`）。
 */
@Component
export struct AppMark {
  /** 边长（vp）。 */
  @Prop markSize: number = 42;

  build() {
    Image($r('app.media.app_icon_original'))
      .width(this.markSize).height(this.markSize)
      .borderRadius(this.markSize * 0.28)
      .objectFit(ImageFit.Cover);
  }
}
