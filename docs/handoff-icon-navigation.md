# 应用图标与折叠屏导航图标交接报告

日期：2026-10-16

## 原来是什么样

- 桌面、任务卡片和启动页使用临时的「紫底白色机器人」`app_icon.svg`，与原作者 DS Bot App 的品牌图标不一致。
- 折叠屏宽屏侧栏直接用 `✦`、`◎`、`⚙` 三个字体字符作为导航图标。三个字符来自不同字形，线宽、尺寸和视觉中心不一致；其中齿轮还会受系统 Emoji 字体影响，呈现拟物风格。
- 侧栏顶部又使用一套「紫色方块 + ✦」应用标记，形成第三套视觉语言。

## 做了什么

### 1. 与原作者统一应用图标

- 从原作者仓库 `QingJ01/DS-Bot-App` 的 `apps/mobile/assets/icon.png` 引入原始 1024×1024 蓝色鲸鱼图标，保存为：
  `entry/src/main/resources/base/media/app_icon_original.png`。
- `AppScope/app.json5`、`entry/src/main/module.json5` 的应用图标、Ability 图标和启动窗口图标统一改为 `$media:app_icon_original`。
- 宽屏侧栏顶部的应用标记也复用同一资源，不再手绘另一套 Logo。

### 2. 统一折叠屏侧栏导航图标

- 新增「对话 / 团队 / 设置」三枚 24×24 SVG 线性图标，统一：
  - `1.8` 描边；
  - 圆角端点与圆角连接；
  - 24×24 视觉网格；
  - 24vp 实际显示尺寸。
- 每枚图标提供灰色常态和紫色选中态。最初尝试用 `Image.fillColor()` 动态着色，但设备实测确认它不会可靠覆盖 SVG 的 `stroke`，因此改为成对资源，避免只在预览器正确、设备上仍为黑色。
- `RailItem.icon` 从字体字符串改为 `Resource`，新增 `selectedIcon`；`DesktopSidebar` 按当前 section 选择对应资源。

## 现在是什么样

- 桌面图标、Dock 图标、启动页图标和应用内侧栏标记均为原作者的蓝色鲸鱼。
- 折叠屏侧栏三枚导航图标风格一致，不再出现 Emoji 齿轮。
- 未选中项为灰色，选中项为紫色，并继续使用原有淡紫色圆角选中背景。
- 对话、团队、设置三个入口均完成点击切换验证。
- 折叠屏收起栏的按钮内容按栏宽水平居中；展开栏仍保持「图标 + 文字」左对齐。

## 验证

- ArkTS 类型检查：通过。
- HAP 构建、打包、签名：`BUILD SUCCESSFUL`。
- 折叠屏模拟器：`2416×2210`，API 26 环境覆盖安装并运行成功。
- UI 回归：`ui_regression.sh -d 127.0.0.1:5557 -s 1`，越出紧邻容器文本 `0`，新增 `0`。
- 桌面图标实证：[device-launcher-icon.jpeg](qa/p1/device-launcher-icon.jpeg)。
- 折叠屏侧栏实证：[device-nav-icons-final.jpeg](qa/p1/device-nav-icons-final.jpeg)。

### 2026-10-16 对齐补丁

首版 SVG 替换后，按钮内部 `Row.width('100%')` 仍采用默认左对齐，导致 76vp 收起栏中的图标相对按钮背景偏左。
现按断点设置 `justifyContent`：收起态 `FlexAlign.Center`，展开态 `FlexAlign.Start`；同时收起态去掉无意义的图文间距。

设备布局 dump 的量化结果：三个按钮均为 `x=25..210`（中心 `117.5px`），对应图标均为
`x=80..155`（中心同为 `117.5px`），按钮与图标中心差为 **0px**。最终截图和布局树分别归档为
`device-nav-icons-final.jpeg`、`device-nav-icons-final.json`。

## 主要文件

- `AppScope/app.json5`
- `entry/src/main/module.json5`
- `entry/src/main/ets/pages/Index.ets`
- `entry/src/main/ets/view/DesktopSidebar.ets`
- `entry/src/main/resources/base/media/app_icon_original.png`
- `entry/src/main/resources/base/media/ic_nav_*.svg`

## 独立复核（2026-10-16，接手人）

对报告逐条核对代码与资源，结论：**内容属实**。

| 报告结论 | 复核结果 |
|---|---|
| 图标资源已引入 | ✅ `app_icon_original.png`(60949B) + 6 枚 `ic_nav_*.svg` + `ic_refresh.svg` 均在 `base/media/` |
| 清单已切换 | ✅ `AppScope/app.json5` 与 `module.json5` 的 icon / startWindowIcon 均为 `$media:app_icon_original` |
| `RailItem.icon` 改为 `Resource` 并加 `selectedIcon` | ✅ 结构一致；`Index` 传入成对资源 |
| 收起栏图标居中 | ✅ 实测按钮 `x=62..187`（中心 124.5）、图标 `x=80..155`（中心 117.5）；报告中的 `x=25..210` 是按钮**内容区**坐标（按钮含 margin/padding 后为 62..187），差值同样为 0 |
| 折叠屏/手机均正常 | ✅ 双端 0 越出；侧栏数值自洽（rail 238 + List 825 = 分隔条 1063） |

### 复核中发现并修复的一处遗漏：应用标记仍有两套实现

侧栏换成了鲸鱼品牌图，但 **`Index.appMark()` 仍是旧的「紫底 + ✦」字体标记**，且它还被 3 处引用：

| 位置 | 界面 |
|---|---|
| `pairingPage()` | 连接/配对页（首次启动可见） |
| `chatPanel()` 空态 | 宽屏未选会话时的「选择一个 Bot 开始对话」 |
| `mainContent()` 加载页 | 启动时的「正在准备 DS Bot…」 |

也就是说**桌面图标、侧栏是鲸鱼，而连接页与启动页是紫底 ✦**——同一个 app 仍有两套品牌形象，
正好是报告「不再手绘另一套 Logo」想消除的情况，只是漏了这三处。

修法：抽出 `view/AppMark.ets`（唯一实现，引用 `app_icon_original`），
`Index.appMark()` 与 `DesktopSidebar.appMark()` 都改为委托它。
这样以后换图标只需改一处——与此前 `BotAvatar` / `ConversationAvatar` 的处理方式一致。

实测：折叠屏侧栏与手机首页渲染正常；双端越界校验 0。

### 复核结论

报告里「`app_icon.svg` 保留但不再被清单引用，可清理」**已确认**：
全仓库搜索 `media:app_icon` 仅命中 `app_icon_original`，`app_icon.svg` 确为死资源（本次未删除，留待统一清理）。

## 后续注意事项

- `app_icon.svg` 目前保留但不再被清单引用，可在后续统一清理未使用资源时删除。
- 侧栏 SVG 使用固定灰/紫两套描边资源，是基于设备实测后的兼容取舍；若未来改用鸿蒙系统 `SymbolGlyph`，应先确认 API 20 的系统 symbol 名称及手机、折叠屏、PC 字形一致性。

### 2026-10-16 会话刷新按钮收口

- 原实现为字体字符 `Button('↻')`，弧度、粗细与垂直位置受系统字体影响，和侧栏 SVG 风格不一致。
- 改为 24×24 圆角线性双箭头 `ic_refresh.svg`，实际显示 21vp；按钮保留 40×40 圆形点击热区并清除默认内边距，确保图标在圆形背景中居中。
- 折叠屏覆盖安装后点击刷新成功，应用保持前台运行；截图见 `docs/qa/p1/device-refresh-button-final.jpeg`。
