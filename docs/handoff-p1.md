# P1 交接报告：视觉与交互对齐

- 报告版本：v9（2026-10-15，含 P1-8 视觉代码收口）
- 上游基线：`QingJ01/ds-bot-app@7e1c3f6c8ebe43bc342caf6abf895d4a2281e9d7`
- 本阶段范围：`docs/translation-plan.md` 的 **P1**（视觉与交互对齐）
- 结论：**P1-1～P1-5 已完成；P1-6、P1-7、P1-8 代码完成，待重新连接模拟器并配对补真实触发与新界面截图。详见 `docs/handoff-p1-5.md` 至 `docs/handoff-p1-8.md`。**

---

## 1. 60 秒速览

### 一句话

头像从「13 张静态 PNG、颜色不起作用」换成了**20 形状 × 12 颜色的矢量实时绘制**；消息从「整段纯文本」换成了**Markdown 渲染**；思考过程可展开、消息可长按操作、工具卡可展开；并且**实时通道首次真正连上了主机**（逐字流式生效）。

### 关键数字

| 指标 | P0 结束时 | P1 现在 |
|---|---|---|
| 源码规模 | 4,221 行 / 11 个 `.ets` | 5,478 行 / 15 个 `.ets`（不含测试）+ 866 行测试 |
| 测试用例 | 26 | **68**（Merge 19 + Markdown 26 + Avatar 12 + Composer 4 + Questions 3 + GroupProgress 4） |
| 头像能力 | 13 张 PNG，颜色无效 | 20 形状 × 12 颜色 + 19 套 ink，矢量绘制 |
| 消息渲染 | 单个 `Text` | Markdown（标题/代码块/列表/引用/表格/粗斜体/链接/提及） |
| 实时通道 | 被主机 Origin 白名单阻塞 | **已连上**（配置修复，见 §3.1） |

### 新增文件

| 文件 | 行数 | 职责 |
|---|---|---|
| `logic/Markdown.ets` | 580 | 轻量 Markdown 解析器（块 + 行内），输出扁平显式模型 |
| `view/MarkdownView.ets` | 275 | Markdown → ArkUI 渲染（代码块带复制、表格可横向滚动） |
| `view/AvatarData.ets` | 261 | 头像数据与纯逻辑（读 rawfile、回退、路径缩放） |
| `view/BotAvatarView.ets` | 267 | 矢量头像组件（20 形状 × 12 颜色） |
| `view/AvatarProbe.ets` | 109 | 头像渲染诊断页（标定用，见 §3.2） |
| `resources/rawfile/characters.json` | 23 KB | 从上游 `characterData.json` 精简生成 |
| `test/markdown.test.ets` | 239 | 26 个解析器用例 |
| `test/avatar.test.ets` | 314 | 12 个头像数据用例 |

---

## 2. 改前 → 改后

| 界面 | 改前 | 改后 |
|---|---|---|
| 首页会话行 | 蓝圆角方块 + 名称首字 | 真实角色矢量头像；主 Bot 右下角白底金星；`waiting` 时左下角橙点 |
| 群聊头像 | 灰底「群」字 | 2/3/4 个成员头像叠放 |
| 消息正文 | 整段纯文本，`**星号**` 原样显示 | Markdown 渲染（代码块带语言名与复制按钮、列表、表格、引用、分隔线） |
| 思考过程 | 固定 `maxLines` 截断 | 默认折叠成一行，点击展开全文，可复制 |
| 消息操作 | 无 | 长按弹出「复制消息 / 复制思考过程 / 引用到输入框」 |
| 工具卡 | 只读，输入输出固定截断 | 点击展开完整输入输出，显示耗时，可复制输出 |
| 发送中状态 | 用户气泡与助手气泡共用文案 | 用户「发送中…」/ 助手「正在输出…」，并标注「进行中」 |
| 用户气泡文字 | 浅底 + 白字（**几乎不可见**） | 浅底 + 深字（`#1B1F35`） |
| 实时状态 | 无显示 | 聊天标题下显示「实时已连接 / 实时通道重连中… / 排队 N」 |

---

## 3. 头像渲染的像素级复核与修复（v2 新增）

### 3.0 背景：Lead 的第一次验收不严

Lead 在 v1 里写「头像已在真机验证通过」，验收标准是**肉眼确认能渲染**。队友 `avatar-engine` 在同一台模拟器上逐像素复核，量出 3 个 Lead 漏掉的真实缺陷：

| # | 缺陷 | 像素证据 |
|---|---|---|
| 1 | **所有矢量头像有一圈纯黑描边**（ArkUI shape 组件默认描边） | 列表 Chief 轮廓连续 6px 纯 `(0,0,0)`；黑像素 2239（Chief）/ 1871（Searcher）；对照组 PNG 鲸鱼 0 个黑像素 |
| 2 | **图层不共享原点**：没显式 `width/height` 的 `Path` 被 ArkUI 按各自紧 bbox 居中，body/shade/light 因此互相错位 | gumdrop 的 light bbox 中心 (33.7, 11.1) vs body 中心 (50, 50) |
| 3 | **眼睛单位不一致**：`Path.commands` 是 px，而 `Rect.width()/position()` 是 vp，差一个设备密度（3x） | 50vp 鲸鱼眼睛完全不可见；gumdrop 眼睛变成一大块白斑 |

修复（只改 `view/BotAvatarView.ets`）：每个 `Path`/`Rect` 加 `.strokeWidth(0)`；每个 `Path` 显式 `.width/height(canvasSize())`（`AVATAR_CANVAS / density`）以共享原点；眼睛几何改走新增的 `canvasVp()`（px→vp）。

**Lead 的独立复核**（不采信结论、重装重拍后量化）：

```
hero 主头像:     0 / 144000 黑像素
Chief 列表头像:  0 / 28900  黑像素
Searcher 列表头像: 0 / 28900  黑像素
```

修复后截图：`docs/qa/p1/emulator-home-avatars.jpeg`、`docs/qa/p1/probe-avatar-calibration.jpeg`。
对比图（左旧右新）已从 `/tmp` 归档进仓库：`docs/qa/p1/before_after_chief.png`、`before_after_searcher.png`，轮廓 IoU 0.891。

**教训（写进流程）**：验收「组件渲染正确」不能只看「能渲染出来」，要量化（黑像素、轮廓重合、坐标中心）。Lead 已在 §6 的验收清单里补了这条。

### 3.1 本轮补完的头像接线（队友文件范围外）

| 位置 | 改前 | 改后 |
|---|---|---|
| 首页顶部 100vp 主头像（`Index.ets`） | `Image($r('app.media.ds_whale'))`，换颜色无效 | `BotAvatarView` 矢量渲染，颜色/形状跟随主 Bot 数据 |
| 创建页预览 | 14 张 PNG + 手绘圆/方/菱形占位 | `BotAvatarView`，显示「形状 · 颜色」实时联动 |
| 创建页形状选择器 | 13 张固定配色 PNG | **20 个形状**全部矢量渲染（颜色跟随当前选择） |
| 创建页色板 | 11 色手绘圆点（缺 `aurora`，且颜色对形状无效） | **12 色**（含 `aurora`），每格是「当前形状 + 该颜色」的真实渲染 |
| 诊断页入口 | 只能靠首页长按手势（实测常触发不到） | 设置 → 维护 → 诊断页（可靠入口） |

顺带在设置页「维护」分组补了「刷新主机信息」与「清空本机缓存」。

## 4. 两个关键发现（本轮最重要的产出）

### 4.1 事件流阻塞的真正原因（P0 遗留问题已解决）

P0 报告 §6.1 记录了「主机 Origin 白名单与鸿蒙 WebSocket 默认 Origin 不兼容」。本轮**用配置而不是改主机代码**解决了它：

主机插件支持 `rt.config.mobile.allowedOrigins`（`server.js:74`），因此在 `~/.dsh/profiles/desktop/cordis.patch.yml` 追加：

```yaml
- id: bot
  name: ds-bot
  config:
    mobile:
      allowedOrigins:
        - https://192.168.x.x         # 鸿蒙 WebSocket 强制发送（示例，无端口）
        - https://192.168.x.x:8788    # 主机自身 publicUrl（示例，保留原行为）
```

**生效证据**：模拟器上聊天标题显示绿色「实时已连接」，助手消息出现「正在输出…」与「进行中」，说明 `delta` 帧正在驱动界面。附件截图：`docs/qa/p1/emulator-chat-streaming.jpeg`。

> ⚠️ 两点必须知道：
> 1. 这是**主机侧配置修改**，不是 App 代码改动。原文件已备份在 `/tmp/dsprobe/cordis.patch.yml.bak`（临时目录，重启会丢）；如需回滚，删掉那段 `- id: bot` 条目即可。
> 2. 配置在 **DSH 重启后**才被读取。本轮之所以能看到实时连接，是因为插件在过程中被重新加载过；如果发现又变回「重连中」，先确认这段配置还在、并重启 DSH。

### 4.2 ArkUI `linearGradient` 的三个非直觉行为（aurora 渐变）

上游对 `color === 'aurora'` 有特判：body 的填充换成三段 `LinearGradient`（`#A4FFB0` 0% → `#00F0E4` 42% → `#2E9EF7` 100%，userSpace 从 (18,10) 到 (78,92)）。我们原来只取了 `inks.aurora[0]` 纯色。补齐过程中在真机上标定出三个事实：

| # | 事实 | 后果 |
|---|---|---|
| 1 | ArkUI `linearGradient` **只能对组件盒子**做渐变，没有 SVG 的 userSpace 端点 | 角度要用 CSS 语义换算：上游方向向量 (60,82) → `atan2(60,-82) ≈ **144°**` |
| 2 | `linearGradient` 画的是**矩形背景**，不是形状填充 | 直接加在 `Path` 上会渲染成**一个渐变方块**（第一版实测如此）；必须配 `clipShape(new PathShape({ commands: body }))` 裁成轮廓 |
| 3 | ArkUI 的渐变轴长是盒子投影 `|W·sinθ|+|H·cosθ| = 139.7`，上游渐变段只有 `|(60,82)| = 101.6` | 照抄 stop 会把颜色压扁；需换算 `t_box = 0.134 + 0.7273·t_user` → **0.134 / 0.439 / 0.861** |

实现是**结构性兜底**：aurora 时先照旧画纯色 body，再叠加「按 body 裁剪的渐变层」；渐变层失效只会露出纯色，不会透明。与上游参考渲染同形状逐像素对比：17,489 个身体像素**平均 ΔRGB = 2.1/255**（换算 stop 前是 7.2）。其余 11 色代码路径未动。

### 4.3 ArkUI `Path` 的 px/vp 语义（踩了 4 轮才定位）

把上游 SVG 路径搬到 ArkUI 时，头像一度只有正确的 1/3～1/4 大，或反过来溢出 3 倍。根因是一条没有文档化的行为：

- `Path({ commands })` 里的数字被当作 **px** 解析；
- `.width()` / `.height()` 的单位是 **vp**；
- `Shape.viewPort` **不会**缩放子 Path 的坐标数字（试了两次，图形仍是 1/4 大）；
- `resourceManager.getDeviceCapabilitySync().screenDensity` 返回的是 **DPI（480）**，不是密度倍数，拿它当倍数会把头像缩到不可见；
- 正确做法：`Path` 用 `.scale(this.getUIContext().vp2px(size) / 100)` 做统一换算，画布固定 100×100。

标定过程与对照截图保留在 `docs/qa/p1/probe-avatar-calibration.jpeg` 与诊断页（首页长按主 Bot 头像 → 「头像诊断」标签）。**这条结论对任何「上游 SVG 资源搬到 ArkUI」的场景都适用**，建议写进团队知识。

---

## 5. 现在是什么样（实测）

### 5.1 已验证可用

| 能力 | 证据 |
|---|---|
| 矢量头像（20 形状 × 12 颜色） | 诊断页并排渲染 whale/star/gumdrop × blue/magenta/aurora，全部正确 |
| 主 Bot 星标 / waiting 橙点 / 群聊叠加头像 | 首页截图 `docs/qa/p1/emulator-home-avatars.jpeg` |
| Markdown：代码块、列表、引用、粗斜体 | 聊天截图 `docs/qa/p1/emulator-chat-markdown.jpeg` |
| 逐字流式 | 助手气泡「正在输出…」+ 思考块「进行中」，截图 `docs/qa/p1/emulator-chat-streaming.jpeg` |
| 可展开思考过程 | 折叠/展开两态实机验证 |
| 长按消息动作 | 面板可弹出（复制/引用） |
| 矢量头像（零黑描边） | ✅ 像素量化：三个头像区域黑像素均为 **0** |
| 创建页 20 形状 × 12 颜色 | ✅ 截图 `docs/qa/p1/emulator-create-shapes.jpeg`、`emulator-create-colors.jpeg` |
| **aurora 渐变**（上游差异补齐） | ✅ 量化验收：沿上游方向左上/中心/右下取样，本机 hue **163.6° → 181.1° → 195.7°**（跨度 **32.1°**、严格单调；纯色应为 ≈0）。队友的独立测量为 158.1→181.4→198.6（跨度 40.5°），取样窗口不同但结论一致。截图 `docs/qa/p1/emulator-create-aurora.jpeg` |
| 首页主头像矢量化 | ✅ 截图 `docs/qa/p1/emulator-home-avatars.jpeg` |
| 设置 → 维护（诊断页 / 刷新主机信息 / 清空本机缓存） | ✅ 实机点按验证，诊断页两标签可用 |
| 聊天内审批卡（P1-6 部分） | ⚠️ **代码完成、编译通过，但未做真机视觉验证**：当前主机在正常对话里不产生审批请求（`list_agents` 等工具在白名单内），需要一次会触发审批的工具调用才能看到卡片。筛选与轮询逻辑已在代码层复核 |
| 排队消息面板（P1-6 部分） | ⚠️ **代码完成、编译通过，真机未捕获到队列帧**（见 §6.2 第 8 条）。`queue` 数据来自 `status` 帧，主机只在真有排队时下发 |
| 工具卡展开 | 显示耗时（3 ms）与状态 |
| 用户气泡对比度 | 修前白字不可见，修后深字清晰 |

### 5.2 验证状态

| 验证项 | 状态 |
|---|---|
| `assembleHap` | ✅ 通过，0 error |
| `node entry/src/test/run.mjs` | ✅ **68 passed / 0 failed**（Merge 19 + Markdown 26 + Avatar 12 + Composer 4 + Questions 3 + GroupProgress 4） |
| 真机（API 24 模拟器）渲染与交互 | ✅ 逐项截图验证 |
| 真实主机端到端（含实时流） | ✅ 发送/收回复/流式均通过 |

---

## 6. 已知限制与待办

### 6.1 P1 未完成项

| 编号 | 内容 | 现状 |
|---|---|---|
| P1-5 | 输入栏补全：思考档位（`efforts`）、`@` 提及、引用其他会话（`reference-chats`） | ✅ **已完成**：原生 Menu/Sheet/Search/Select/TextArea 选区能力；真实主机已接受 `dsh-session:` 并把 `@Searcher` 路由为 `message_bot`。当前主机模型没有非空 effort 选项，详见 `docs/handoff-p1-5.md` |
| P1-6 | 聊天内审批卡、提问卡（`answer-question`）、排队消息查看/移除（`queue` / `queue-remove`） | 🟡 **三块代码均完成**。提问卡已补 `TeamState.questions`、单选/多选/自定义回答、answer/dismiss action，并修复 questions 不会自动刷新的缺陷。设备会话已过期，三类真实触发仍待重新配对验收；详见 `docs/handoff-p1-6.md` |
| P1-7 | 群成员作者标识、群进度（`room-progress`）、停止某成员工作（`stop-member-work`） | 🟡 **代码完成**：按上游 `GroupProgress.tsx` 确认契约，补 `/state.work` 投影、1 秒轮询、状态胶囊和单成员停止；4 个新增用例通过。当前 `hdc` 无设备且无真实群聊证据，详见 `docs/handoff-p1-7.md` |
| P1-8 | 视觉细节收口与对比图重拍 | 🟡 代码审查完成：旧下沉底栏和 B4 手写颜色死代码已移除；新界面对比图待设备恢复后重拍，见 `docs/handoff-p1-8.md` |
| P1-6a | 聊天内审批卡 + 审批轮询 | ✅ 代码完成（`conversationApprovals()` 筛选 + `chatApprovals()` 卡片 + `startApprovalPoll()` 10 秒轮询）；真机视觉待审批请求出现时确认 |

### 6.2 本轮新发现的待办

1. **Markdown 标题内的行内样式不生效**：标题按纯文本渲染（`plainOf()`），`## a \`code\` b` 会丢掉反引号但不着色。属已知取舍，记录在 `Markdown.ets` 顶部注释。
2. **链接点击只复制、不跳转**：`safeMarkdownLink` 校验后复制到剪贴板。系统跳转需要 `Want` 与用户确认，留给 P3。
3. **`AvatarProbe.ets` 是诊断页**：内含 `pxFactor` 标定入口，正式发布前需决定保留（隐藏调试）或删除。现在已经挂在「设置 → 维护 → 诊断页」，不再依赖手势，也可以直接删掉这个入口。
4. **`BotAvatarView` 的 `@Prop avatarSize` 不能改名回 `size`**：与 `CustomComponent` 基类属性冲突（编译报错）。这是硬约束。
5. **`pxFactor` 是标定用参数**：正常业务不要传（默认 0 = 自动）。
6. `MarkdownView` 的表格列宽固定 148 vp，窄屏需要横向滚动。
7. **验收标准要量化**（本轮教训）：涉及图形/布局的改动，验收必须包含像素级或坐标级断言（黑像素计数、轮廓重合、bbox 中心），不能只看「能渲染」。
8. **`cloneMessage` 对 `author` 是浅拷贝（已修）**：补完群聊作者渲染后，我给 `Merge` 加了一条回归用例，结果**测试直接失败**——`cloneMessage` 原来写的是 `out.author = message.author`，副本与缓存里的消息共享同一个作者对象，调用方改副本会污染原消息。已改为显式深拷贝（`Author { id, name }` 逐字段）。用例：`cloneMessage keeps the group author object`（Merge 组从 18 → **19** 例）。
9. **群聊作者标识修掉一个真实类型错误**：主机 `projection.js` 下发的是 `author: { id, name }`（对象），而 `Models.ets` 原来声明 `author?: string`。这意味着**群聊里原本无法显示是谁在说话**（数据一直在，类型挡住了）。已改为 `author?: Author`（新增 `Author { id?, name? }`），并在气泡里渲染「成员头像 + 名字」。群聊场景真机未验证（主机当前无群聊），但类型已与主机契约一致。
10. **排队消息面板（P1-6）已实现但真机未捕获到队列帧**：代码路径是 `status` 帧 → `MobileClient.lastStatus.queue` → `handleStreamEvent` → `queuePanel()`（输入栏上方，可展开、单条「移除」走 `queue-remove`）。实测时连发两条消息（第二条在 `正在输出…` 期间发出）没有在 4 秒窗口内看到面板，也没有抓到 `status` 帧带非空 `queue`；同时主机侧我的探针令牌已失效（App 已自行刷新并持新令牌），无法从外部核对队列。**结论：代码完成、编译通过、真机行为未确认**，与审批卡同属「等一次真实排队场景」。
11. **`queue-remove` 需要 `sessionId`**：实现里先调 `/conversations/{id}/target` 取当前 `sessionId` 再提交，避免用会话列表里可能过期的那份。

### 6.3 环境注意事项

- **测试设备的会话是 15 分钟有效期**：本轮多次遇到「设备会话已失效，请重新与电脑配对」。App 会正确回到连接页（这是 P0 加固的行为），但**做真机回归前需要先重新配对一次**。
- 主机 `~/.dsh/bot/mobile/bridge.json` 中的设备记录曾被本轮排查修改过，已用备份还原；随后用户重新配对了一台新设备，当前有效。

---

## 7. P2 建议的起手式

按 `docs/translation-plan.md`，P2 是「设置与管理」：

1. **P2-1 设置骨架重做**（先做）：9 个空壳入口（用量/定时任务/Bot 电脑/通知中心/技能/插件/连接器/经典模式/设备）目前点了没反应。先搭子页导航与统一加载/空/错态，再逐个填内容。
2. **P2-2～P2-4 只读面板优先**：用量（`usage`）、记忆（`memory-view`）、定时任务（`schedules`）都是「读一次 + 少量写」，能快速让设置页看起来是完整的。
3. **P2-5 Bot 管理**（最大块）：`update-bot` / `duplicate-bot` / `delete-bot` / `set-main` + 模型选择 + 头像编辑器。头像编辑器现在可以直接复用 `BotAvatarView`（形状+颜色已可用）。
4. 接任何新 action 前，先按 P0 报告 §9 的方法用真实主机抓一次请求/响应。

---

## 8. 真机实测（HUAWEI Pura X Max · HOP-AL00 · API 26）

2026-10-15 首次用**真机**验证。这一步同时暴露了三个只有真机/真实场景才会出现的问题。

### 8.1 解除"装不上真机"的阻塞：签名配置少了一行引用

真机拒绝未签名 HAP（`code:9568320 no signature file`；模拟器接受 unsigned，所以此前没暴露）。

DevEco 的 `Project Structure → Signing Configs → Apply` **只写了 `app.signingConfigs`（候选池），没有在 product 上写引用**。hvigor 的取值逻辑（`hvigor-ohos-plugin/src/tasks/sign/sign-util.js`）：

```js
const i = this._targetProduct.signingConfig;   // 读的是 product 上的 signingConfig
if (undefined === i) return void (this.signingConfigCheckLogStr = `No signingConfig found for product ${this._targetProduct.name}`);
```

所以在 `build-profile.json5` 的 product 里补一行 **`"signingConfig": "default"`** 即可，命令行构建立刻产出 `entry-default-signed.hap`。

> ⚠️ 若之后在 DevEco 里再点一次 Apply，这一行**可能被覆盖掉**，症状是又变回 `No signingConfig found` + unsigned 产物。
> 构建命令必须带 `JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home`，否则 `PackageHap` 报 `Unable to locate a Java Runtime`。

### 8.2 真机密度的量化口径

真机截图 2584×1828（横屏）。用布局 dump 里已知 vp 尺寸的控件反推密度：

| 标尺 | vp | 实测 px | 反推 px/vp |
|---|---|---|---|
| 「置顶」按钮高度 | 34 | 94 | 2.765 |

→ 密度 **2.765**，窗口宽约 **935 vp** ⇒ 走 `>=600`（多栏）与 `>=840`（会话列表定宽 320vp）两个分支，**未到 1040**（导航栏 76vp 而非 180vp）。实测布局正是「76vp 导航栏 + 320vp 会话列表 + 聊天面板」，与断点预期一致。

> 结论：真机覆盖了模拟器**从未走过**的宽屏多栏分支。这对后续任何布局改动都是必测项。

### 8.3 真机暴露的真实缺陷：桌面分支仍在用旧头像占位

首轮真机截图里会话列表和团队页显示的是「蓝圆底 + 首字母」，而手机版是矢量头像。原因不是渲染失败，而是**同一功能有两份实现**：`mobileHome` 用的是 `conversationAvatar`，但**桌面版会话列表与团队页各自内联了一份 `Circle` + `name.slice(0,1)` 占位**——P1-2 集成时只改了手机版，漏了宽屏分支。

已统一到 `conversationAvatar` / `botAvatar`（真机 `uitest dumpLayout` 里现在能看到 `★` 主 Bot 星标，会话摘要也从角色名变成了真实消息预览）。

**教训**：同一界面在「手机/桌面」两个分支各写一份时，改一处必然漏另一处。后续新增界面元素应抽成单一 Builder 并两边共用；本项目的 `mobileHome` / `conversationList` 就是反例。

### 8.4 真机量化结果

| 项 | 模拟器（API 24，密度 3） | 真机（API 26，密度 2.765） |
|---|---|---|
| 头像近黑像素（黑边回归） | hero 0/144000、Chief 0/28900、Searcher 0/28900 | Chief **0/24000**、Searcher **0/24000** |
| 宽屏多栏布局 | 未覆盖 | ✅ 三栏 + 主 Bot 星标 + 真实摘要 |
| Markdown 渲染 | ✅ | ✅（代码块 + 复制 + 列表） |
| 实时状态 | ✅「实时已连接」 | ✅「实时已连接」 |

**`strokeWidth(0)` 的修复在另一台设备、另一种密度下依然成立**——这是跨设备验证，比模拟器单点更有说服力。

证据：`docs/qa/p1/realdevice-home.jpeg`、`realdevice-home.json`（布局 dump）、取证据脚本 `realdevice.sh`、量化工具 `check_black_pixels.py`。

## 9. 受控模拟主机验收 + 原生能力收口（2026-10-16）

### 9.1 为什么用受控模拟主机

设备侧重新配对受阻（真机 USB Offline、模拟器需电脑端批准，主机控制面在 DSH GUI 内拿不到），
因此自建 `/tmp/dsprobe/mock-host.mjs`：用主机自己的证书提供 `/mobile/v1` 受控应答 + RFC 6455 事件流。
不接触真实主机、不写主机数据。凭据通过直接写 App 私有 preferences 注入
（`uitest inputText` 对含引号/中文的 JSON 不可靠）。

**这一步顺带发现并修复了一个真实崩溃**（详见 `docs/handoff-p1-6.md`）：`efforts` 应答缺字段时
`@State effortOptions` 被写成 `undefined`，重渲染读 `.length` 崩溃（`Index.ets:2272`）。
修复：`logic/Efforts.ets` + `test/efforts.test.ets`。

### 9.2 P1-6 / P1-7 待验收项现已全部有运行时证据

| 项 | 证据 | mock 侧确认 |
|---|---|---|
| 提问卡 | `docs/qa/p1/device-question-card.jpeg` | 选项/单选多选/自定义回答/跳过/提交全部渲染 |
| 审批卡 | `docs/qa/p1/device-approval-card.jpeg` | `待批准` + 工具名 + 原因 + 允许一次/拒绝 |
| 排队面板 | `docs/qa/p1/device-queue-panel.jpeg` | 标题显示「排队 2」，条目与「下一轮对话」标签正确 |
| 队列移除 action | 同上 | mock 收到 `queue-remove {conversationId, sessionId, itemId}`，UI 从 2 → 1 |
| 群进度 + 停止成员 | `docs/qa/p1/device-group-progress.jpeg` | 成员状态胶囊 + `停止`；mock 收到 `stop-member-work {roomId, botId}`；`room-progress` 轮询确认在跑 |
| 错误提示（原生） | `docs/qa/p1/device-error-popup.jpeg` | 注入 500 后原生 popup 显示「请求失败（HTTP 500）」 |

### 9.3 原生能力优先：本轮替换掉的三处重复造车

按要求「多使用鸿蒙原生能力，避免重复造车」，审计后改了三处：

| 位置 | 改前（自造） | 改后（原生） | 验证深度 |
|---|---|---|---|
| 消息长按操作面板 | `Stack` + `#66000000` 遮罩 + 手写底部卡片 + 手写「取消」行 | `bindSheet(SheetSize.FIT_CONTENT)`，与已存在的 `referencePickerSheet` 同一模式 | ✅ **已实证**（2026-10-16 补）：抽成 `view/MessageActionSheet.ets` 并在诊断页加了按钮入口（绕开 uitest 无法触发长按的限制），系统底部面板正常展开；点击「复制消息」后回调触发、面板自动关闭。见 `device-native-sheet.jpeg` |
| 撤销设备确认 | 「同一按钮点两次」+ Toast 提示 | 原生 `promptAction.showDialog`（标题/正文/取消/确认） | 编译通过；设备列表区只在宽屏分支渲染（`>=600`），手机模拟器不可达，**UI 未实证**。可用真机或 Foldable 模拟器补 |
| 错误提示 | 绝对定位浮动横幅 + 手写关闭按钮 | 原生 `bindPopup` | ✅ **已实证**：注入 500 后系统样式气泡出现，见 `device-error-popup.jpeg` |

**如实说明**：前两处未取得 UI 实证。`bindSheet` 与工程里已正常工作的 `referencePickerSheet` 同模式、
`bindSheet`/`showDialog` 都是官方 API，风险低；但没有截图我就不标「已验证」。

### 9.4 原生能力审计结果（保留的好实践）

已在使用且无需改动的原生能力：`bindMenu`（“+”菜单）、`bindSheet`（引用选择器）、
`Select`（思考档位）、`Radio`/`Checkbox`（提问卡）、`Search`（引用搜索）、
`TextAreaController` + `onTextSelectionChange`（光标处 `@` 补全）、`List`/`Grid`/`Scroll`、
`LoadingProgress`、`Divider`、`Toggle`、`promptAction.showToast`。

### 9.6 修复：聊天文字溢出消息卡片边界（2026-10-16，用户报告）

**现象**：消息文字越出气泡背景（用户明确：「文字超出气泡背景」，手机单栏）。
**这个问题一共修了四轮才对。前三轮都是错的，过程比结论更值得后来者读。**

#### 三轮失败尝试（都是同一个错误：没量准就下结论）

| 轮次 | 我的判断 | 为什么错 |
|---|---|---|
| 1 | 气泡宽度用了百分比 `'90%'` + 缺 `wordBreak` | 只给 `Text` 加了断行。**用自己构造的三种文本量出「无溢出」就收尾**，而真实溢出在用户气泡与长 URL，不在这三种里 |
| 2 | 行内混排用 `Flex` 而非 `Text`+`Span`（这条是对的） | 修对了 A，但漏了 B，就宣布修好 |
| 3 | 内层 `width('100%')` 在 `constraintSize` 父容器里解析成内容宽（也对） | 又漏了 C，还宣布修好 |

**第 3 轮我甚至报告了「170 行越出 → 4 行」的假数据**——那次我改完 `listWidth` 后没有重新测量嵌套列表，
而实际改动让深层列表越出得更多（最深处文字到 1279px，容器右边界仅 1115px，超出 164px）。

> **教训（写给后来者）**：
> 1. 不要用自己构造的用例给用户报告的问题收尾。要么拿到用户截图/确切触发条件，要么把该组件的**所有布局分支**都枚举到。
> 2. 改完必须**重新量**，尤其是改了宽度/缩进这类会互相作用的属性——我第三轮就是因为没复测而报告了假数据。
> 3. 像素颜色探测容易误报（浅色元素互相干扰）。**最可靠的是 `uitest dumpLayout`**：直接读节点 bounds，无歧义。

#### 真正的三个根因（缺一不可）

**根因 A：行内混排用 `Flex` 装多个 `Text`**

`Flex` 是通用容器，测量时把每个子 `Text` 当**不可分割的盒子**；`wordBreak` 只作用于文本自身换行，
无法让 `Flex` 在字符间断开 → 长 URL / 无空格串整体溢出。
修：`Text() { ForEach(...) { Span(...) } }`。`Text` 才是文本容器，断行断词由它统一计算。

**根因 B：容器用 `width('100%')`**

在「父容器只有 `constraintSize({ maxWidth })`」时，百分比按**内容**解析，把宽度算成内容宽并越出气泡。
修：全部改为确定宽度 `blockWidth()`（由父组件传入 `maxContentWidth`）。

**根因 C（主因，最隐蔽）：行内文本宽度没有扣除缩进**

铁证（布局 dump）：

```
Text   bounds=(323, 1829, 1279, 1961) 宽=956   ← 起点已被缩进推到 323，宽度仍是气泡全宽 956
Column 气泡右边界 = 1075
→ 323 + 956 = 1279 > 1075，必然越出
```

列表/引用通过 `padding` 把内容推右，而 `inlineSpans` 固定用 `blockWidth()`（气泡全宽）排版，
两者相加必然越界，且**层级越深越严重**。
修：`inlineSpans(spans, size, availWidth)` 接收可用宽度；列表传 `listTextWidth(depth)`（逐层扣减缩进+
符号+间距+余量 4vp），表格单元格传 128vp（列宽 148 − 内边距），引用块传 `blockWidth() - 40`。

另外把宽度口径收敛成**单一来源**：`bubblePadding()` 定义内边距，`bubbleMaxWidth()` 与
`bubbleContentWidth()` 都由它推导。之前两处各自扣一次内边距，是我前几轮反复微调数字的根源。

#### 量化验收（这次覆盖全会话，不是抽样）

```
用 uitest dumpLayout 取节点 bounds，逐个文本比对其所属气泡容器的右边界：
  跨 6 次滚动、108 个去重文本节点 → 越出气泡 = 0  →  ✅
```

证据：`device-text-overflow-fixed.jpeg` + `.json`。

#### 修复：表格同行单元格高度不统一（2026-10-16，用户报告）

**现象**：表格同一行里左右单元格高度不一致，背景色与底边框只覆盖各自内容高度。

**根因**：`Row.alignItems()` 只接受 `VerticalAlign`，而该枚举**只有 Top / Center / Bottom，没有 Stretch**
（`ItemAlign` 才有 `Stretch`）。所以 `Row().alignItems(VerticalAlign.Top)` 下，
同排内容少的单元格只按自身内容高度绘制。

**修法**：行容器从 `Row` 换成 `Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch })`，
单元格在交叉轴拉伸到行高。

**踩到的坑**（值得记下）：中间版本我给单元格同时加了 `.height('100%')`，
结果在 `Scroll > Column > Flex` 这种**高度不确定**的上下文里，`height('100%')` 把单元格撑到了容器全高
（实测 1831px，整张表彻底变形），而且单元格宽度也被挤成 317px。
**去掉 `height('100%')`、只留 `ItemAlign.Stretch` 才是对的**——拉伸不该由显式高度表达。

**量化验收**（新增可复跑脚本 `docs/qa/p1/check_table_cells.py`）：

```
单元格 9 个，分 3 行
  行 y0=1926  格数 3  宽度 [317]  高度 [135]  ✅ 等高
  行 y0=2061  格数 3  宽度 [317]  高度 [259]  ✅ 等高
  行 y0=2320  格数 3  宽度 [317]  高度 [200]  ✅ 等高
判定：3/3 行等高
```

证据：`device-table-equal-height.jpeg`。

#### 修复：工具卡与嵌套列表越出容器（2026-10-16，用户报告工具卡溢出）

**背景**：文字溢出问题收敛后，用户又发现**工具卡**同样越出气泡。**同一个根因**——
内层组件用 `width('100%')`，在「父容器只有 `constraintSize(maxWidth)`」时按内容解析，
于是按气泡全宽排版，越出气泡自身的内边距。

**这次改进了验收方法，才发现之前漏掉的一类**：我原先只拿文本与**气泡右边界**比对，
所以漏掉了「越出**紧邻子容器**」的溢出。新增 `docs/qa/p1/check_text_bounds.py`：
对每个文本节点都与**最近的 Column/Row/Flex 祖先**比对右边界。用它一扫就暴露出
**嵌套列表也一直在越出子容器约 35px**（之前四轮都没发现，因为只跟气泡比是"没超"）。

| 缺陷 | 实测证据 | 修法 |
|---|---|---|
| 工具卡越出气泡 | 卡片头部 `Row` x0=164 x1=**1156**，气泡内边界仅 1138 | `ToolCard` 增加 `@Prop maxWidth`，卡片与内部行/文本都用确定宽度（`bubbleContentWidth()` 传入） |
| 嵌套列表越出子容器 | 深层列表文本 x1=1150，紧邻父容器右 1115（超 35px ≈ 12vp） | `listTextWidth()` 余量 4vp → 16vp（按**紧邻父容器**收敛，不再只对气泡） |

**修复后实测**：

```
工具卡头部 Row：  1156 → 1033（正好等于父容器边界，不再越出）
卡片内文本：      1033 < 父容器 1075（留白 42px）
嵌套列表：        不再越出（严格校验 0 条）
```

**教训（补进 §9.6 的方法论）**：验收口径必须**按容器的每一层**比对，
只对最外层（气泡）比对会漏掉中间层溢出。`check_text_bounds.py` 就是这个口径的可复跑实现。

#### 顺带修复：表格完全不渲染

用户截图暴露的另一个缺陷（原样输出 `| 名称 | 说明 |`）。最小复现把失败条件精确到一行：

```
A 仅表格        → table        ✅
B 加粗行+表格   → paragraph    ❌  ← 表格被前面那行吞掉
C 空行+表格     → table        ✅
D 代码块+表格   → code,table   ✅
```

根因：**段落累积循环的终止条件漏了表格**。它检查了标题/围栏/分隔线/引用/项目符号/有序列表，
唯独没有表格——而表格判定是「本行含 `|` 且下一行是分隔行」，不属于任何行首模式，于是整张表被吞成段落。
真实回复里 `**2) 表格**` 紧跟着表格行，正好命中。
修：抽出 `isTableStart(lines, start)` 让「表格检测」与「段落终止条件」**共用同一判定**（两处判定分叉正是成因），
加 3 个回归用例（Markdown 26 → 29）。

### 9.5 视图拆分：第一步（2026-10-16）

`Index.ets` 已 3,138 行 / 33 个 `@Builder`，而 P2 还要加 9 个设置面板，因此开始拆分。
第一步（本轮）：

| 新增文件 | 作用 |
|---|---|
| `view/Theme.ets` | **共享语义颜色令牌**（浅/深两套 + `themeOf()`）。拆分后子组件无法访问 `Index` 的私有 `pageBg()/surface()/ink()`…，若各自硬编码十六进制会立刻产生色值漂移（P1-8 刚清掉过一次 `botColor()` 双重色值）。约定：视图里不再写裸十六进制色 |
| `view/MessageActionSheet.ets` | 消息操作面板，`@Prop actions` + `tokens` + `onAction`/`onClose` 回调，完全无业务依赖 |
| `Index.ets` | `messageActionSheet()` 改为薄封装的 `messageSheetBuilder()`，并接上 `tokens()` |

**顺序原则**：先抽「无业务状态依赖」的纯 UI 组件，再抽需要大量状态与动作的页面级组件。
这样每一步都能独立编译与实证，不会一次动到 3000 行的数据流。

第二步（同日）：

| 新增文件 | 作用 | 关键设计 |
|---|---|---|
| `view/GroupProgressBar.ets` | 群成员工作进度条 | **父组件算数据、子组件只渲染**：定义 `MemberChip` 视图模型 + `onStop` 回调。原实现直接依赖 `Index` 的 12 个成员，照搬会变成「Index 的镜像」 |
| `view/BotAvatar.ets` | 角色头像（矢量底图 + 主 Bot 星标 + 活跃点） | 星标/活跃点只能有**一处**实现——真机曾因两份头像实现不一致而漏改（§8.3） |

第三步（同日）：把聊天里四张卡片全部抽出。

| 新增文件 | 行数 | 关键设计 | 设备实测 |
|---|---|---|---|
| `view/QueuePanel.ets` | 84 | 展开状态内聚到组件（`Index` 少一个 `showQueue`） | 渲染正确；`queue-remove` 回调确认 |
| `view/ChatApprovals.ets` | 95 | 决定通过回调交回，组件不接触 API；顺带把重复的「警示面板配色」抽成 `NoticePanelTheme` | 渲染正确；`approval-resolve {id, decision}` 确认 |
| `view/ToolCard.ets` | 107 | **整个 `expandedTools: string[]` 状态与 `toolGlyph`/`toggleTool` 一起搬进组件** | 渲染 + 展开（输入/输出 JSON）确认 |
| `view/QuestionCard.ets` | 191 | **每张卡自己持草稿**：消掉 `Index` 上 `questionDrafts` 那套按 key 查找的 map，以及 6 个辅助方法 | 渲染正确；多选 `answer-question` 回调确认 |

**这一步的收益是实打实的**：`Index.ets` **3146 → 3003 行（-143）**，
`view/` 目录累计 2299 行。拆出的每个组件都在设备上用 mock 场景验过渲染与回调
（不只是"编译通过"），共 4 组 action 确认：`queue-remove`、`approval-resolve`、
工具卡展开、`answer-question`。

**抽组件的三条经验**（本轮反复用到）：
1. **父算子、子渲染**：把显示数据算成视图模型（`MemberChip`）传入，别把 `Index` 的状态方法照搬成一堆 `@Prop`。
2. **纯展示状态跟着组件走**：`showQueue`、`expandedTools`、每张提问卡的草稿都属于展示细节，搬进组件后 `Index` 真的变短。
3. **抽完必须验渲染与回调**：本轮 4 个组件各验一次；抽共享头像时还额外量了黑边（0 近黑像素），
   因为组件抽取最容易在像素级细节上悄悄回归。

第四步（同日）：抽**纯逻辑**而非视图——`logic/ConversationAvatar.ets`。

群头像的叠加布局（1 人铺满 / 2 人对角 0.66 / 3-4 人四角 0.54）原本是页面里的 4 个私有方法，
属于**纯几何计算**却埋在 3000 行里，只能靠截图目测。抽出后：

| 新增 | 内容 |
|---|---|
| `logic/ConversationAvatar.ets` | `mainBotIdsOf` / `isMainBotIdOf` / `isMainConversation` / `botOf` / `roomMembersOf` / `memberSlotCount` / `memberSlotSize` / `memberSlotOffset` / `isMainAvatar` |
| `test/conversation-avatar.test.ets` | **14 个用例**：叠加个数截断、边长比例、2/3/4 人位置、成员为空回退、`bot:` 前缀兼容、越界断言 |

`Index` 侧保留同名私有方法，**内部改为委托**给模块——这样 29 个调用点一处不动
（避免漏改），而算法本体已移出并有单测覆盖。

新增用例里有一条是**通用不变量**：`所有叠加头像都落在群头像外框内`（对 1~4 人遍历断言
`offset + inner <= size`）。这类断言以前写不出来，因为算法和 UI 混在一起。

第五步（同日）：继续抽纯逻辑——`logic/ViewUtil.ets`。

| 函数 | 为什么值得抽 |
|---|---|
| `isAuthFailure` | 判定结果决定「是否清凭据回连接页」，**判错会让用户卡死路或误登出**，此前零断言 |
| `conversationTime` | 时间解析 + 边界（见下方缺陷） |
| `isConfirmedLocally` | 本地乐观消息是否被主机确认 |
| `questionKeyOf` | 提问卡去重键 |

新增 12 个用例（总 103 tests）。**其中一个用例当场抓到一个真实缺陷**：

> `conversationTime` 原实现直接 `new Date(item.updatedAt)`。而 `updatedAt` 的类型是
> `number | string`，主机 JSON 常把时间戳序列化成**字符串毫秒数**——而
> **`new Date("1792132200000")` 在 JS 里返回 `Invalid Date`**（只有数字才被当时间戳，
> 字符串会走日期解析）。后果是会话列表时间**静默空白**，且不报错。
> 修法：数值字符串显式 `Number()` 后再构造 Date。`Index` 侧只传 `item.updatedAt`
> （ArkTS 不支持结构类型，不能把 `Conversation` 当轻量接口传）。

第六步（同日）：开始拆**页面级结构**——`view/SettingsPage.ets`。

`mobileSettingsPage` 是 142 行的独立整页，只依赖 6 个状态与 7 个方法，是全工程最干净的一页。
抽成**纯展示组件**：自己不改任何业务状态，9 个交互全部通过回调发出意图
（关页 / 切深色 / 进工具页 / 进团队页 / 进诊断页 / 刷新 / 清缓存 / 断开 / 审批决定），
因此可以用固定 props 直接渲染，不依赖真实会话。

顺带把 P2 要复用的结构固定下来：`groupTitle()` / `rowLabel()` 两个 `@Builder`，
行高 64/78、卡片圆角 22、`rowBg` 统一底色——**P2 加 9 个面板时只追加「标题 + 卡片」，不另起样式**。

#### 设备实测中发现并修复的可用性缺陷

点「断开此设备」时**直接登出、没有任何确认**——误触一次就清空凭据回到连接页，必须重新配对。
（我在 P1-8 给「撤销设备」加过确认，但 `logout()` 漏了。）已补原生 `showDialog` 确认；
`clearLocalCache()` 同属不可恢复操作，一并加上。

实测确认框：

```
标题「断开此设备」+ 说明「将清除本机的会话凭据并返回连接页，需要重新配对才能再次连接。」
按钮「取消」/「断开」
→ 点「取消」后仍保持已配对状态，停在本页 ✅
```

这同时补上了之前标注「未实证」的原生 `promptAction.showDialog`。

第七步（同日）：抽 `view/SecondaryPages.ets`——「工具与技能」与「能力库」两个二级页。

两页结构同源（顶部返回/关闭胶囊栏 + 卡片列表），放在同一文件里共用 `pageHeader` 结构。
抽完后 `mobileOverlay` 的路由状态仍留在 `Index`，页面只通过 `onClose` / `onOpenCapabilities` /
`onBack` 发出意图。**为避免两页各写一套顶部栏，把 header 也一并收进组件**。

设备实测：工具页四个入口（技能/插件/连接器/能力库）渲染正确，
点「能力库」进入能力库页（Bot 标签 Chief/Searcher + 三张能力卡）。

> 顺带记录一个易错点：用脚本批量替换 `@Builder` 方法体时**容易把 `@Builder` 装饰器一起吃掉**，
> 编译期报 `Only UI component syntax can be written here`。本次就踩到了，替换后要回头核对装饰器。

第八步（同日）：抽 `view/DesktopSidebar.ets`（宽屏左栏 = 应用标记 + 导航栏 + 会话列表）。
三者同属一栏、共享宽度断点，合成一个组件可以避免各自声明宽度而彼此不一致。

同时把会话头像抽成 `view/ConversationAvatarView.ets`（单聊 Bot 头像 / 群聊最多 4 成员叠加），
直接消费 `logic/ConversationAvatar.ets` 的纯函数——**叠加算法只有一处且已被 14 个用例覆盖**。

#### 抽完后暴露并修复的两个真实布局缺陷（折叠屏实测）

抽组件把「宽度由谁决定」这件事摆到了台面上，一次暴露两个问题：

**缺陷 1：左栏占满整行，聊天面板被挤成 0 宽**

```
修复前：List 宽 1972px（整行剩余全宽）；聊天面板 bounds 宽 = 0px
```

原因有两层，**都要修**：
1. 组件根 `Row` 用了 `width('100%')` → 吃掉整行；
2. 去掉后仍不对：内层 `List` 的 `width('100%')` 会**反向把父 Column 撑到可用宽度**，
   组件退化成"内容宽 = 满宽"。

修法：给组件根与会话列表**都设确定宽度**（`sidebarWidth() = rail + 320`）。
修复后 `List` 宽 1000px（= 320vp），聊天面板拿到 972px，两者之和正好等于窗口 2210px。

> **通用结论**：`width('100%')` 在「Row 的兄弟节点」和「父容器宽度待定的 Column 内」
> 这两种位置都会意外改变外层尺寸。确定宽度要由**共同父级**分配，不能让子项各自声明。

**缺陷 2：导航栏状态药丸超出 rail 3px**

收起态 rail 仅 76vp，去掉左右 padding 后约 60vp；药丸用 `padding 10` + `fontSize 12`
放不下「● 已连接」。收窄为 `padding 6` + `fontSize 11` 后归零。
（这类 3px 级溢出人眼几乎看不出，是 `ui_regression.py` 报出来的。）

**双端实测**：折叠屏（706vp，走宽屏分支）与手机（440vp）均 **0 越出**；
证据 `device-desktop-sidebar.jpeg`。

第九步（同日）：宽屏分栏改用**原生可拖拽分栏**（用户反馈「会话区太宽、聊天区太窄，希望能手动调节比例」）。

#### 用的是鸿蒙原生能力，不自造

| 方案 | 结论 |
|---|---|
| **`SideBarContainer`** ✅ 采用 | 专为「侧栏 + 内容」设计；`sideBarWidth` / `minSideBarWidth` / `maxSideBarWidth` / `autoHide` / `onChange`；**分隔条由系统提供且可拖拽** |
| `Navigation` + `enableDragBar(true)` | 同样原生可拖拽（API 14 起），但需要 `NavPathStack` + `NavDestination` 改造主结构，改动更大 |

实现：

```ts
SideBarContainer(SideBarContainerType.Embed) {
  this.desktopSidebar();   // 侧栏
  this.desktopPane();      // 聊天 / 团队 / 设置
}
.showSideBar(true)
.showControlButton(false)   // 导航栏已有一级入口，不要系统折叠按钮
.autoHide(false)            // **关键**：默认 true，拖到最小会把侧栏整个吞掉
.sideBarWidth(340)          // 初始：339vp 侧栏 / 366vp 内容区（706vp 窗口下较均衡）
.minSideBarWidth(240)       // SDK 默认下限
.maxSideBarWidth(520)       // 避免聊天区被压得过窄
.onChange((visible: boolean) => { this.sideBarShown = visible; })
```

#### 实测：分隔条确实可拖拽

```
初始：  侧栏 339vp / 内容区 366vp（分隔条 x=1063）
拖动后：侧栏 475vp / 内容区 231vp（分隔条 x=1487，+424px）
```

`uitest uiInput swipe <分隔条x> ...` 即可拖动；分隔条是系统 `Divider` 节点（3px 宽）。
证据：`device-resizable-split.jpeg`。双端校验均 **0 越出**（折叠屏 706vp / 手机 440vp）。

#### 过程中修掉的侧栏内部留白

改成容器定宽后暴露：侧栏根 `Row` 原本只有 `height('100%')`、会话列表用固定宽，
**容器被拖宽时内部不跟着填满**（实测容器 445vp、内部只用到 263vp，右侧空 330px）。

修法：`forcedWidth > 0`（即由 `SideBarContainer` 决定宽度）时，会话列表改用 `layoutWeight(1)` 吃掉剩余空间；
未指定宽度时仍用固定宽。修后拖动过程中「侧栏内空白」恒为 0px。

> 又一次印证上一轮的结论：**确定宽度要由共同父级分配**；子项各自声明宽度，一旦外层变了就会露出空白或溢出。

**仍然没拆的大头**： + `chatPanel`(99) + `mobileChatPanel`(99) +
`mainContent`(88) + `mobileHome`(81) + `teamPage`(83) ≈ 600 行，深度依赖 `Index` 的 40+ 个状态字段与动作。
要拆得先理出页面级状态容器（或引入 `@ObservedV2`/`@Trace` 细粒度观测），属于独立一步，不宜与小步混做。

## 9.7 设备侧 UI 回归门槛（2026-10-16）

把「文字/内容越出容器」这类**单测覆盖不到**的布局缺陷变成一条命令可判定的门槛。

```bash
# 启动应用 → 逐段滚动采集布局 → 逐层校验越界（默认模拟器 127.0.0.1:5555）
bash docs/qa/p1/ui_regression.sh -s 8 --enter-chat

# 只报告「新增」越出（用于已有基线时）
bash docs/qa/p1/ui_regression.sh -b docs/qa/p1/baseline.json

# 首次建立基线
bash docs/qa/p1/ui_regression.sh --save-baseline
```

| 文件 | 作用 |
|---|---|
| `docs/qa/p1/ui_regression.sh` | 驱动：设备检查 → 启动 → 逐段滚动采集 dump → 调校验 → 截图存证；有新增越出时退出码 1 |
| `docs/qa/p1/ui_regression.py` | 校验：对**每个文本节点**与它**紧邻的 Column/Row/Flex 祖先**比对右边界 |

**校验口径**（这是本脚本存在的意义）：只与最外层（气泡）比对会漏掉中间层溢出——
工具卡越出内边距、嵌套列表越出子容器就是这么被漏掉四轮的。脚本改为**逐层比对**，
并自动豁免「祖先里有明显窄于窗口的横向 `Scroll`」的节点（表格列横向滚动属设计行为，不靠硬编码坐标识别）。

**自证有效性**（关键：一个从不失败的检查等于没检查）：

```
修复前的 dump（g4.json / tcv.json）：
  ❌ x1=1150 父 Column 右=1115 超 35px  '第二层嵌套项目符号内容…'
  ❌ x1=1150 父 Column 右=1115 超 35px  '第三层更深嵌套的项目符号内容…'
  → rc=1

当前构建：越出 0  → rc=0
基线机制：--save-baseline 后，同一 dump 用 --baseline 复跑 → 新增 0
```

## 9.8 品牌图标与折叠屏侧栏图标收口（2026-10-16）

### 原来是什么样

- 桌面、任务卡片和启动窗口仍使用临时的「紫底白色机器人」`app_icon.svg`，与原作者 DS Bot App 的蓝色鲸鱼图标不一致。
- 折叠屏的 76vp 侧栏使用 `✦ / ◎ / ⚙` 三个字体字符作为「对话 / 团队 / 设置」图标。它们来自不同字形，线宽、尺寸、视觉中心不一致；齿轮还可能被系统 Emoji 字体渲染成拟物图标。
- 会话标题右侧的刷新入口是 `Button('↻')`，弧度、粗细和垂直位置同样依赖字体，与侧栏图标不成体系。
- 首次换成 SVG 后又发现一个对齐问题：按钮内部 `Row.width('100%')` 默认从左侧起排，收起侧栏中的图标相对按钮背景偏左。

### 做了什么

1. 从原作者仓库 `apps/mobile/assets/icon.png` 引入 1024×1024 蓝色鲸鱼，保存为
   `entry/src/main/resources/base/media/app_icon_original.png`。
2. `AppScope/app.json5`、`entry/src/main/module.json5` 的应用图标、Ability 图标与启动窗口图标统一改为
   `$media:app_icon_original`；侧栏顶部的应用标记也复用同一资源。
3. 新增同一 24×24 网格、`1.8` 圆角描边的「对话 / 团队 / 设置」SVG。每枚图标提供灰色常态和紫色选中态；
   `RailItem.icon` 从字符串改为 `Resource`，并新增 `selectedIcon`。
4. 设备实测发现 `Image.fillColor()` 不会可靠覆盖 SVG 的 `stroke`，因此没有依赖动态着色，改用灰/紫成对资源，
   避免预览器与设备表现不一致。
5. `railButton()` 在收起态使用 `FlexAlign.Center`、展开态使用 `FlexAlign.Start`；收起态同时去掉无意义的图文间距。
6. 刷新按钮从字体字符换成 `ic_refresh.svg`：21vp 图标、40×40 圆形点击热区、零默认内边距。

### 现在是什么样

- 桌面图标、Dock、启动页和应用内品牌标记均使用原作者蓝色鲸鱼。
- 折叠屏侧栏三枚入口采用统一线宽、圆角与尺寸；未选中为灰色，选中为紫色并保留淡紫色圆角背景。
- 收起态图标与按钮严格同中心，展开态仍保持「图标 + 文字」左对齐。
- 刷新按钮与侧栏图标属于同一线性视觉语言，不再受系统字体影响。

### 量化与运行时验收

| 验收项 | 结果 |
|---|---|
| ArkTS / HAP | 类型检查通过，`BUILD SUCCESSFUL` |
| 设备 | 折叠屏模拟器 `2416×2210` 覆盖安装、启动正常 |
| 三个侧栏入口 | 对话 / 团队 / 设置逐一点击切换正常 |
| 图标居中 | 按钮 `x=25..210`、图标 `x=80..155`，两者中心均为 `117.5px`，偏差 **0px** |
| 刷新入口 | 点击后应用保持前台，刷新动作无崩溃 |
| UI 回归 | `ui_regression.sh -d 127.0.0.1:5557 -s 1`：越出 0，新增 0 |

独立细节报告见 `docs/handoff-icon-navigation.md`。

## 10. 证据与可复跑脚本索引

`/tmp` 里的证据会随重启丢失，因此已全部归档进 `docs/qa/p1/`（脚本里的硬编码 `/tmp` 路径在归档时改成了脚本同目录的相对路径）：

| 文件 | 内容 |
|---|---|
| `emulator-home-avatars.jpeg` | 首页：矢量头像 + 主 Bot 星标 + 矢量主头像 |
| `emulator-create-shapes.jpeg` | 创建页：20 个形状全部矢量渲染 |
| `emulator-create-colors.jpeg` | 创建页：12 色板（每格是「当前形状 × 该颜色」） |
| `emulator-create-aurora.jpeg` | 创建页：aurora 渐变选中态 |
| `emulator-chat-markdown.jpeg` | 聊天：Markdown 代码块与列表 |
| `emulator-chat-streaming.jpeg` | 聊天：逐字流式（「正在输出…」/「进行中」） |
| `probe-avatar-calibration.jpeg` | 诊断页：倍率标定 / 不同尺寸 / 不同形状 / 不同颜色 |
| `before_after_chief.png`、`before_after_searcher.png` | 黑描边修复前后对照（左旧右新） |
| `a1.jpeg` | aurora 第一版的失败证据（`linearGradient` 未裁剪 → 渐变方块） |
| `final_aurora.jpeg`、`aurora_ref_gumdrop.svg.png` | aurora 本机渲染 vs 上游参考渲染 |
| `cmp_aurora.py` | **可复跑**：bbox 对齐 + 沿 (60,82) 十分位 hue + ΔRGB 直方图 |
| `aurora_ref.py` | **可复跑**：只用 `characters.json` 生成上游 SVG 参考渲染 |
| `preview.py` | **可复跑**：上游图层 + SVG Mask 的整组预览 |
| `device-launcher-icon.jpeg` | 折叠屏桌面与 Dock：原作者蓝色鲸鱼应用图标 |
| `device-nav-icons-final.jpeg` / `.json` | 折叠屏侧栏最终截图与布局树；三枚图标相对按钮中心偏差 0px |
| `device-refresh-button-final.jpeg` | 会话列表顶部统一后的 SVG 刷新按钮 |

运行前提：`Pillow`（本机 11.3.0 可用）；对比脚本需要同目录下存在对应截图。

## 11. 变更记录

| 日期 | 版本 | 内容 |
|---|---|---|
| 2026-10-16 | v25 | 应用图标统一为原作者蓝色鲸鱼（桌面 / Dock / 启动页 / 侧栏标记）；折叠屏侧栏 `✦ / ◎ / ⚙` 字符替换为统一 SVG 灰/紫状态资源并修复收起态居中（量化偏差 0px）；`↻` 刷新字符替换为同风格 SVG；折叠屏运行时与 UI 越界门槛通过 |
| 2026-10-15 | v1 | P1-1/P1-2/P1-3/P1-4 完成并真机验证；解除事件流阻塞；定位并文档化 ArkUI Path 的 px/vp 语义；测试增至 57 例 |
| 2026-10-15 | v2 | 队友像素级复核发现 3 个头像缺陷（黑描边/原点不共享/眼睛单位），已修复并由 Lead 用黑像素计数独立复核（全 0）；补完首页主头像、创建页预览、20 形状与 12 色选择器的矢量接线；诊断页改为设置内可靠入口 |
| 2026-10-15 | v3 | P1-6 补排队消息面板（`queue` / `queue-remove`）与设置页「维护」分组；排队面板真机未捕获队列帧，如实标注为未确认（§6.2 第 9 条）；aurora 渐变已排给 `avatar-engine` 实施 |
| 2026-10-15 | v4 | P1-7 补群聊作者标识，并修正 `Message.author` 的真实类型（`string` → `{ id, name }`，此前群聊无法显示发言人）；记录 `room-progress` / `stop-member-work` 无实现线索、无可验证场景，暂不写 UI |
| 2026-10-15 | v5 | aurora 渐变补齐并量化验收（Lead 独立复核 hue 跨度 32.1°、严格单调）；新增 §4.2 记录 ArkUI `linearGradient` 的三个非直觉行为 |
| 2026-10-15 | v6 | 单测发现并修复 `cloneMessage` 对 `author` 的浅拷贝（Merge 用例 18→19，总计 57）；把队友留在 `/tmp` 的可复跑脚本与对照图归档进 `docs/qa/p1/` 并去掉硬编码路径 |
| 2026-10-16 | v24 | 宽屏分栏改用原生 `SideBarContainer`（可拖拽分隔条 + `autoHide(false)` + 240~520vp 范围），用户可手动调节会话区/聊天区比例；修复容器定宽后侧栏内部留白；双端 0 越出 |
| 2026-10-16 | v23 | 抽出 `view/DesktopSidebar.ets` 与 `view/ConversationAvatarView.ets`；折叠屏实测暴露并修复两个布局缺陷（左栏占满整行致聊天面板 0 宽、状态药丸超 rail 3px）；双端 0 越出 |
| 2026-10-16 | v22 | 抽出 `view/SecondaryPages.ets`（ToolsPage / CapabilitiesPage 两个二级页，共用顶部栏结构）；设备实测两页与跳转均正常 |
| 2026-10-16 | v21 | 抽出 `view/SettingsPage.ets`（142 行整页 → 纯展示组件 + 9 个回调），并为其 P2 扩展固定 `groupTitle`/`rowLabel` 结构；设备实测发现 `logout()` **无确认即登出**，已补原生 `showDialog`（顺带完成 `showDialog` 的实证） |
| 2026-10-16 | v20 | 抽出 `logic/ViewUtil.ets`（鉴权失败判定 / 时间格式化 / 本地确认判定）与 12 个用例（总 103 tests）；**用例抓到真实缺陷**：`new Date("字符串毫秒数")` 返回 Invalid Date，会让会话时间静默空白，已修 |
| 2026-10-16 | v19 | 抽出 `logic/ConversationAvatar.ets`（群头像叠加布局 + 主 Bot 判定）与 14 个几何用例（总 91 tests）；`Index` 保留同名方法但改为委托，29 个调用点零改动；设备复测头像 3/3 区域 0 近黑像素、UI 门槛 0 越出 |
| 2026-10-16 | v18 | 新增设备侧 UI 回归门槛 `ui_regression.sh` + `ui_regression.py`（逐层比对 + 横向 Scroll 自动豁免 + baseline）；用修复前的 dump 自证能抓到 35px 越出，当前构建 0 越出 |
| 2026-10-16 | v17 | 修复工具卡越出气泡（`ToolCard` 增加确定宽度 `maxWidth`）；新增 `check_text_bounds.py` 按「紧邻容器」逐层校验，借此发现并修复嵌套列表越出子容器 35px 的老问题 |
| 2026-10-16 | v16 | 视图拆分第三步：抽出 QueuePanel / ChatApprovals / ToolCard / QuestionCard 四张聊天卡片（+477 行组件，Index 3146→3003）；`expandedTools`、`showQueue`、提问草稿 map 等展示状态随组件迁移；4 组 action 回调在设备上确认 |
| 2026-10-16 | v15 | 修复表格同行单元格高度不统一：`Row.alignItems` 无 Stretch，改用 `Flex + ItemAlign.Stretch`（中间版本误加 `height('100%')` 把单元格撑到 1831px，已回退）；新增等高校验脚本 `check_table_cells.py`，3/3 行等高 |
| 2026-10-16 | v14 | **文字溢出第四次修复（前三轮均未修好，且第三轮报告了假数据）**：真正根因是 `inlineSpans` 用气泡全宽排版、未扣除列表/引用缩进（铁证 Text x0=323 宽=956 vs 气泡右 1075）；另统一宽度口径为单一来源。验收升级为全会话 dump 扫描：108 个文本节点越出 0 |
| 2026-10-16 | v13 | 修复表格不渲染：段落累积循环漏了表格判定，`**2) 表格**` 紧跟表格时整张表被吞成段落；抽出 `isTableStart()` 共用判定 + 3 个回归用例（77 tests） |
| 2026-10-16 | v12 | **重做文字溢出修复**（第一次只加 wordBreak 且用自造用例验收，是错的）：真正根因是行内混排用 `Flex` 而非 `Text`+`Span`，以及气泡内层 `width('100%')` 在 maxWidth 父容器里解析成内容宽；另移除 `Blank()` 改 `justifyContent` 对齐。量化验收：消息区最大右边界 1201/1320 |
| 2026-10-16 | v11 | 视图拆分第二步：抽出 `view/GroupProgressBar.ets`（视图模型 + 回调，父算子渲染）与 `view/BotAvatar.ets`（星标/活跃点单点实现）；抽取后复测群进度与头像黑边（0 近黑像素） |
| 2026-10-16 | v10 | 修复聊天文字溢出气泡（`constraintSize` 百分比 → 显式 vp + `wordBreak` 断行）；构造三种极端文本并量化验收无溢出 |
| 2026-10-16 | v9 | 视图拆分第一步：新增 `view/Theme.ets` 共享令牌与 `view/MessageActionSheet.ets`；`bindSheet` 由未实证升级为已实证（诊断页按钮入口 + 回调闭环） |
| 2026-10-16 | v8 | 受控模拟主机验收：P1-6/P1-7 待验收项全部取得运行时证据；发现并修复 `efforts` 投影崩溃（新增 Efforts 模块与 6 个用例）；按「原生优先」替换三处重复造车（bindSheet / showDialog / bindPopup） |
| 2026-10-15 | v7 | **真机实测**（Pura X Max / API 26）：解除真机签名阻塞（`product.signingConfig` 缺引用）；量化真机密度 2.765、窗口 935vp 并验证宽屏多栏分支；发现并修复桌面分支仍用旧头像占位（两份实现）；真机头像近黑像素 0 |
| 2026-10-15 | v8 | P1-7 补齐 `/state.work` 投影、`room-progress` 1 秒轮询、群成员状态胶囊与 `stop-member-work`；加入异步 generation 防跨会话回写，测试增至 68；`hdc` 当前无设备，真实群聊验收待补 |
| 2026-10-15 | v9 | P1-8 代码收口：删除 B4 错误色值的未引用 `botColor()`，删除曾导致手机导航下沉的旧 `bottomBar()` 死代码；复核响应式断点与 SafeArea，新增 P1-8 交接报告 |
