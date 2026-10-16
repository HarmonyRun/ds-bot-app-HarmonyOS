# Design QA

## Comparison target

- Source visual truth: `docs/qa/reference-home.png`, `docs/qa/reference-tools.png`, `docs/qa/reference-create.png`，来自上游 `QingJ01/DS-Bot-App` 的 README 移动端截图。
- Rendered implementation: `docs/qa/emulator-home.jpeg`, `docs/qa/emulator-chat.jpeg`, `docs/qa/emulator-settings.jpeg`, `docs/qa/emulator-tools.jpeg`, `docs/qa/emulator-capabilities.jpeg`, `docs/qa/emulator-create.jpeg`。
- Combined comparison evidence: `docs/qa/comparison-home.png`, `docs/qa/comparison-tools.png`, `docs/qa/comparison-create.png`。
- State: 浅色模式，真实已配对主机，Chief 为主 Bot；首页、创建 Bot、工具与技能为同一默认交互状态。

## Viewport and normalization

- Source pixels: 411 × 890，1× 截图。
- Implementation pixels: 1320 × 2856，HarmonyOS API 24 模拟器；应用内容区域为 1320 × 2621，系统状态栏和手势区不属于应用内容。
- CSS / ArkUI logical viewport: 约 390 × 775 vp。
- Normalization: 比较图移除模拟器系统状态栏，将应用内容缩放为 411 × 818；源图裁去底部 72 px 空白区域，得到相同的 411 × 818 比较区域。未把系统状态栏、系统手势条或像素密度差异计为设计问题。

## Full-view comparison evidence

- 首页：顶部圆形设置、搜索、创建按钮，主 Bot 居中区域，会话头像、标题、摘要与时间的层级和间距与源图一致。真实主机仅有一个会话，源图有四个会话，这属于动态数据差异。
- 工具与技能：标题胶囊、章节标题、四行灰色圆角列表、分隔线和箭头在归一化视图中一致。
- 创建 Bot：标题、真实 gumdrop 角色素材、灰色名称输入区、13 个角色形状和 11 个颜色已与源图保持同一信息结构；较短的模拟器逻辑高度会把第二排颜色置于可滚动区域下部。
- 聊天与设置：额外实机截图确认了胶囊标题、消息气泡、输入栏、设置分组卡片及系统安全区。

## Focused-region evidence

- 顶部控件与首页会话行在 `comparison-home.png` 中可清楚阅读，检查了图标线宽、头像清晰度、文字层级和省略状态。
- 工具列表在 `comparison-tools.png` 中可逐行检查，无需额外局部裁图。
- 创建页角色和颜色选择器在 `comparison-create.png` 中可逐项检查；素材直接取自上游截图，未使用 emoji 或自绘占位图替代。

## Required fidelity surfaces

- Fonts and typography: 使用 HarmonyOS 系统字体；字号、字重、单行省略和中英文层级与源图接近。不同平台字体栅格化属于预期差异。
- Spacing and layout rhythm: 手机页边距、48 vp 圆形控件、圆角卡片和分组节奏一致；更短的模拟器视口通过滚动处理，不遮挡持久控件。
- Colors and visual tokens: 白 / 浅灰表面、深色正文、灰色次文案和 DS Bot 蓝色状态色与源图一致，并保留夜间模式。
- Image quality and asset fidelity: 首页鲸鱼和创建页角色均复用上游素材；SVG 操作图标来自上游定义。模拟器高密度缩放下未发现明显锯齿或压缩破损。
- Copy and content: 固定中文标题与源图一致；会话摘要、Bot 名称和时间为主机动态内容。
- Accessibility and interaction: 关键按钮为 48 vp 或更大；创建按钮会在名称为空时禁用；返回、关闭、搜索、创建和页面跳转均已实机操作。

## Comparison history

1. Earlier finding [P2]: 首页主 Bot 区域偏低，且会话副标题显示角色而非最新消息。Fix: 压缩主 Bot 顶部间距，异步加载每个会话的最新非空消息，并增加单行省略。Post-fix evidence: `docs/qa/comparison-home.png`。
2. Earlier finding [P2]: 工具与技能卡片在短内容时垂直居中，且使用了源图没有的图标和副标题。Fix: 固定为顶部起始布局，改成源图的章节标题和四行简洁列表。Post-fix evidence: `docs/qa/comparison-tools.png`。
3. Earlier finding [P1]: 创建页只有 4 个几何形状和 5 种颜色，角色素材与源图不一致。Fix: 复用上游角色素材，补齐默认可见的 13 个角色形状和全部 11 种颜色，将名称输入改成源图灰色胶囊。Post-fix evidence: `docs/qa/comparison-create.png`。
4. Earlier finding [P2]: 手机底部导航占用并下沉到系统手势区。Fix: 按上游设计移除手机底部导航，使用顶部悬浮入口；聊天输入栏保留安全区。Post-fix evidence: `docs/qa/emulator-home.jpeg`, `docs/qa/emulator-chat.jpeg`。

## Findings

无仍需处理的 P0 / P1 / P2 设计差异。

## Follow-up polish

- [P3] 创建页主角色在 HarmonyOS 较短视口中略小于 411 × 890 源图的相对占比，可在获得同尺寸真机后再做 4–8 vp 微调。
- [P3] 上游截图与 HarmonyOS 系统字体的抗锯齿和中文 fallback 略有差异，属于平台原生渲染差异。

## Implementation checklist

- [x] 首页、聊天、设置、创建、工具、能力库实机截图。
- [x] 参考图与实现图合并比较。
- [x] 修复全部 P0 / P1 / P2 差异。
- [x] ArkTS 类型检查、资源编译和 HAP 打包成功。

final result: passed

## 2026-10-15 增量说明

上述 `passed` 结论覆盖当时已有的首页、聊天、设置、创建、工具与能力库。其后新增的 P1-6 提问/审批/队列卡片和 P1-7 群成员进度尚未进入这些截图，不能沿用旧结论。

本轮已完成代码层收口：删除旧手机底栏死代码与重复手写颜色映射，重新通过 DevEco Sync、68 个纯逻辑测试和签名 HAP 构建。当前 `hdc list targets` 为 `[Empty]`，增量界面的 Phone/Foldable/Tablet/2in1 截图与深色模式对照待设备恢复后补充，步骤见 `docs/handoff-p1-8.md`。
