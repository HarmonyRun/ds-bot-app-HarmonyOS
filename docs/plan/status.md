# 进度看板

> 每个阶段完成后更新本页。开工前先读这一页，再读对应的交接报告。
>
> - 规划：`docs/translation-plan.md`（P0–P3 全部工作包、验收标准、风险）
> - P0 交接报告：`docs/handoff-p0.md`（改了什么、为什么、怎么验证、还差什么）

最后更新：2026-10-17（第二套「专业协作工作台」跨设备 UI 优化）

---

## 总览

| 阶段 | 名称 | 状态 | 报告 |
|---|---|---|---|
| **P0** | 协议与实时底座 | 🟡 **核心协议与实时链路已端到端验证**；当前会话分页已接，跨 part 与 HUKS 凭据迁移仍待完成 | [handoff-p0.md](../handoff-p0.md)、[P0-6](../handoff-p0-6.md) |
| **P1** | 视觉与交互对齐 | 🟡 **P1-1～P1-7 完成（P1-6/P1-7 已有运行时证据）；P1-8 仅缺 Foldable/Tablet/2in1 与深色模式截图** | [handoff-p1.md](../handoff-p1.md)、[P1-5](../handoff-p1-5.md)、[P1-6](../handoff-p1-6.md)、[P1-7](../handoff-p1-7.md)、[P1-8](../handoff-p1-8.md) |
| P2 | 设置与管理 | ⬜ 未开始 | — |
| P3 | 扩展层 | ⬜ 未开始 | — |

## 专业协作工作台 UI（2026-10-17）

- 用户选定第二套效果图，已将其落到手机、折叠屏、平板和 PC 响应式结构。
- 统一瓷白 / 深海军蓝 / 钴蓝视觉令牌，重做手机首页、宽屏侧栏、消息气泡、输入栏、团队页、设置页、配对页和创建 Bot 页。
- PC `>=1200vp` 新增任务与活动上下文栏；折叠屏和平板保持更克制的两/三栏结构。
- 团队栅格改为按实际内容区宽度计算，修复折叠屏 Bot 信息被挤掉的问题。
- 折叠屏会话、团队、设置布局扫描均为 0 越界；103 项测试和签名 HAP 构建通过。
- 完整交接：[handoff-ui-professional.md](../handoff-ui-professional.md)。

图例：⬜ 未开始 · 🟡 进行中 · ✅ 完成

---

## P0 工作包状态

| 编号 | 工作包 | 状态 | 证据 |
|---|---|---|---|
| P0-1 | 连接能力可行性验证 | ✅ 已完成 | 协议帧见 P0 报告 §3.1；Origin 历史问题及解决见 P1 报告 §4.1 |
| P0-2 | 类型补强 | ✅ | `model/Models.ets` 206 → 313 行 |
| P0-3 | 纯函数移植 | ✅ | `logic/Merge.ets`；与上游 8,000 次比较 0 差异 |
| P0-4 | 传输层 | ✅ | `service/MobileClient.ets` 743 行 |
| P0-5 | 替换轮询 | ✅ | 30×1200ms 与 80×1500ms 两个循环均已删除；事件流不可用时退化为 5 秒兜底轮询 |
| P0-6 | 历史与续读 | 🟡 当前会话分页已接，跨 part 待做 | `messages(cursor)` 已接原生“加载更早消息”，含去重、加载态、reset 保留历史与跨会话防串写；`parts` 分段选择器待做。见 `docs/handoff-p0-6.md` |
| P0-7 | 本地缓存与草稿 | ✅ | `service/MessageCache.ets` |
| P0-8 | 生命周期与清理 | ✅ | `aboutToDisappear` + 定时器登记 + 会话失效兜底 |
| P0-9 | 回归基线 | ✅ | `node entry/src/test/run.mjs` → 103 passed / 0 failed |
| P0-10 | 凭据加密（HUKS） | ⬜ 未开始 | — |
| P0-10 | 凭据加密（HUKS） | ⬜ 未开始 | — |

---

## 真机实测（2026-10-15，HUAWEI Pura X Max / HOP-AL00 / API 26）

- 真机签名已打通：`build-profile.json5` 的 product 需有 `"signingConfig": "default"`（DevEco 的 Apply 只写了候选池）；构建要带 `JAVA_HOME=.../jbr/Contents/Home`。
- 真机密度 **2.765 px/vp**、窗口约 **935 vp** ⇒ 走宽屏多栏分支（`>=600`/`>=840`），模拟器从未覆盖。
- 真机复测：三栏布局、主 Bot 星标、真实消息摘要、Markdown、实时状态均正确；头像近黑像素 **0**。
- 真机暴露并修复：桌面版会话列表与团队页仍用旧的「圆底 + 首字母」占位（两份实现），已统一到 `conversationAvatar` / `botAvatar`。
- 详情见 P1 报告 §8。

---

## P1 工作包状态

| 编号 | 工作包 | 状态 | 证据 |
|---|---|---|---|
| P1-1 | 头像引擎（20 形状 × 12 颜色矢量绘制 + aurora 渐变） | ✅ | `view/BotAvatarView.ets` + `view/AvatarData.ets`；像素复核黑描边 **0**、aurora hue 跨度 **32.1°** 严格单调（见 P1 报告 §3、§4.2） |
| P1-2 | 首页与列表（真实头像、主 Bot 星标、waiting 点、群聊叠加、首页主头像与创建页矢量化） | ✅ | `docs/qa/p1/emulator-home-avatars.jpeg`、`emulator-create-shapes.jpeg`、`emulator-create-colors.jpeg` |
| P1-3 | Markdown 渲染 | ✅ | `logic/Markdown.ets` + `view/MarkdownView.ets`，26 个用例 |
| P1-4 | 消息交互（可展开思考、长按动作、工具卡展开） | ✅ | `docs/qa/p1/emulator-chat-markdown.jpeg` |
| P1-5 | 输入栏补全（思考档位 / `@` 提及 / 会话引用） | ✅ | `logic/Composer.ets`；61 tests；真实主机识别引用并把 `@Searcher` 转为 `message_bot`；截图见 `docs/qa/p1/emulator-reference-sheet.jpeg`、`emulator-mention-menu.jpeg`。当前模型无非空 effort 可选项，限制见 P1-5 报告 §5 |
| P1-6 | 聊天内审批卡、提问卡、排队消息 | ✅ **三块均取得运行时证据** | 受控模拟主机上：提问卡 / 审批卡 / 排队面板均真实渲染，`queue-remove` 端到端确认。证据见 P1 报告 §9.2。过程中发现并修复 `efforts` 投影崩溃 |
| P1-7 | 群成员作者、群进度、停止成员工作 | ✅ **三块均取得运行时证据** | 群进度胶囊 + `停止` 按钮实证；`room-progress` 轮询与 `stop-member-work {roomId, botId}` 均在 mock 侧确认。证据见 P1 报告 §9.2 |
| P1-8 | 视觉细节收口与对比图重拍 | 🟡 | 死代码清理与断点复核已完成；折叠屏侧栏已改为统一 SVG 图标并取得设备截图，应用图标已与原作者蓝色鲸鱼统一。Tablet/2in1 与深色模式仍待补。见 [图标交接报告](../handoff-icon-navigation.md) |

### 实时通道已解除阻塞（P0 遗留）

主机侧配置已加入鸿蒙 WebSocket 的 Origin（`~/.dsh/profiles/desktop/cordis.patch.yml` 的 `mobile.allowedOrigins`）。
重启 DSH 后生效；诊断页与聊天标题会显示「实时已连接」。详情见 P1 报告 §3.1。

---

## 溢出问题的最终状态（2026-10-16）

表格、代码块、嵌套列表、引用、工具卡的越出**已收口**。根因是两类固定缺陷：

1. 给**有确定宽度的父容器**里的元素传了「手算的固定文字宽度」→ 撑破父容器；
2. 嵌套容器**每层少扣一次缩进** → 逐层累积越出。

**规则（新增 UI 时按此写）**：
- 元素在**有确定宽度**的父容器里 → 用 `width('100%')`，不要手算数值；
- 元素在**只有 maxWidth 的容器**里、且自己会按内容测量（`Scroll`/`Flex`）→ 必须传确定数值；
- **行内文字**（列表/引用）需要数值来扣缩进与符号位，但要**留足余量**（推导不可靠，实测收敛）。

**验收方法**（此前失效过，务必用这个）：
- 逐节点比对「**最近更窄祖先**」，而不是只看紧邻容器（父子一起越界时会漏检）；
- **扫完整个会话**再看结果，不要只看当前一屏；
- 脚本：`docs/qa/p1/sweep_message_area.sh` 采集，`check_text_bounds.py` 校验。

---

## 设备侧 UI 回归门槛（改 UI 后请跑）

```bash
bash docs/qa/p1/ui_regression.sh -s 8 --enter-chat      # 逐层校验越界，有新增越出 exit 1
bash docs/qa/p1/ui_regression.sh -b <baseline.json>     # 只报新增
bash docs/qa/p1/ui_regression.sh --save-baseline        # 建立/更新基线
```

口径是「每个文本 vs 它**紧邻的** Column/Row/Flex 祖先」——只与气泡比对会漏掉中间层溢出
（工具卡、嵌套列表都曾因此漏检四轮）。表格列的横向 Scroll 自动豁免。

---

## 宽屏可调节分栏（2026-10-16）

宽屏（>=600vp）用鸿蒙原生 **`SideBarContainer`**：分隔条可拖拽，用户在会话区与聊天区之间自由调比例。

- 初始 339vp 侧栏 / 366vp 内容区（706vp 窗口）；范围 240~520vp
- `autoHide(false)`：拖到最小也不隐藏侧栏
- `showControlButton(false)`：导航栏已有一级入口，不要系统折叠按钮

实测：拖动分隔条 `339vp → 475vp` 生效；折叠屏与手机双端越界校验均 0。

### 折叠屏侧栏图标与品牌统一（2026-10-16）

- 应用图标、启动窗口图标与侧栏品牌标记统一为原作者 1024×1024 蓝色鲸鱼。
- `✦ / ◎ / ⚙` 字体字符替换为同一 24×24 网格、1.8 描边的「对话 / 团队 / 设置」SVG。
- 收起态图标与按钮中心偏差实测为 0px；展开态仍保持图文左对齐。
- 顶部 `↻` 字符刷新按钮也已换成同风格圆角线性 SVG，点击验证正常。
- 折叠屏 `2416×2210` 实测三个入口与灰色常态/紫色选中态正确；UI 越界检查为 0。
- 主报告：`docs/handoff-p1.md` §9.8；独立报告：`docs/handoff-icon-navigation.md`。
- 证据：`device-nav-icons-final.jpeg/.json`、`device-launcher-icon.jpeg`、`device-refresh-button-final.jpeg`。

---

## 当前可用命令

```bash
# 编译
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
export DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk"
export HARMONYOS_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk/default"
"/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
  --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap

# 纯函数测试
node entry/src/test/run.mjs

# 装到模拟器并启动
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc shell "aa start -a EntryAbility -b app.dsbot.harmony"
```

---

## 已解决的历史阻塞：WebSocket Origin

P0 时的 Origin 白名单阻塞已在 P1 通过主机 `mobile.allowedOrigins` 配置解决，真实设备当前显示“实时已连接”并可逐字流式。App 仍保留 5 秒兜底轮询；WebSocket 无证书锁定仍是安全限制。完整过程见 `docs/handoff-p1.md` §4.1。

---

## 2026-10-16 受控模拟主机验收（新增手段）

设备侧配对受阻时，可用**受控模拟主机**做 UI 运行时验收：

- 夹具脚本：`/tmp/dsprobe/mock-host.mjs`（用主机证书提供 `/mobile/v1` 受控应答 + RFC 6455 事件流）。
- 接入方式：把 mock 凭据直接写进 App 私有 preferences（`uitest inputText` 对含引号/中文的 JSON 不可靠）。
- 已验收：提问卡完整渲染。
- 顺带发现并修复：`efforts` 应答缺字段导致 `@State effortOptions` 变 `undefined`，重渲染读 `.length` 崩溃
  （`Index.ets:2272`）。修复见 `logic/Efforts.ets` + `test/efforts.test.ets`。

**新约定**：任何来自主机的动态对象进入 `@State` 前必须过一次显式投影，不要直接赋 `result.xxx`。

### 原生能力优先（用户明确要求）

审计后替换了三处自造控件：错误提示 → `bindPopup`（已实证）、消息操作面板 → `bindSheet`（已实证）、
撤销设备确认 → `promptAction.showDialog`（待宽屏/真机实证）。
已在使用且无需改动的：`bindMenu` / `Select` / `Radio` / `Checkbox` / `Search` / `TextAreaController` /
`onTextSelectionChange` / `List` / `Grid` / `Scroll` / `LoadingProgress` / `Toggle` / `Divider` / `showToast`。

### 已修复的用户报告缺陷

- **聊天文字溢出消息卡片边界**（2026-10-16）：根因是 `constraintSize({ maxWidth: '90%' })`
  在 `Row → Blank → Column` 嵌套里按内容解析，且未设 `wordBreak`。
  改为显式 vp 宽度 + `WordBreak.BREAK_WORD`/`BREAK_ALL`。量化验收：消息区最大右边界 1299px / 屏宽 1320px。
  见 P1 报告 §9.6。

### 视图拆分进度

`Index.ets` 当前约 **2818 行**；已抽出：

| 组件 | 说明 |
|---|---|
| `view/Theme.ets` | 共享语义色令牌（浅/深两套） |
| `view/MessageActionSheet.ets` | 消息长按面板（原生 `bindSheet`） |
| `view/BotAvatar.ets` | 角色头像（星标/活跃点单点实现） |
| `view/GroupProgressBar.ets` | 群成员进度条（父算子、子渲染） |
| `view/QueuePanel.ets` | 排队消息面板（展开态内聚） |
| `view/ChatApprovals.ets` | 审批卡（回调交回，不接触 API） |
| `view/ToolCard.ets` | 工具卡（展开态整体迁移） |
| `view/QuestionCard.ets` | 提问卡（每卡自持草稿，消掉父组件 map） |
| `view/TeamPage.ets` | Bot 团队页（父算子视图模型 + 回调） |
| `view/MobileHome.ets` | 手机首页（入口 + 主 Bot 大头像 + 会话列表） |
| `view/MobileCreateBotPage.ets` | 创建 Bot 整页（矢量形状/色板实时预览） |
| `view/PairingPage.ets` | 配对页（自持表单状态，品牌标记由父注入） |
| `view/ChatMessageList.ets` | 消息滚动区（`@BuilderParam` 注入插槽，两面板共用） |
| `view/ChatComposer.ets` | 聊天输入栏（两面板共用） |
| `view/SecondaryPages.ets` | 工具与技能 / 能力库两个二级页 |
| `view/DesktopSidebar.ets` | 宽屏左栏（导航 + 会话列表） |
| `view/ConversationAvatarView.ets` | 会话头像（复用 ConversationAvatar 纯逻辑） |
| `view/ChatComposer.ets` | 聊天输入栏（两个面板共用一份） |
| `view/AppMark.ets` | 应用标记（品牌图单点实现） |

四个卡片组件都在设备上用 mock 场景验过渲染与回调（`queue-remove` / `approval-resolve` /
工具卡展开 / `answer-question`）。剩余页面级结构约 600 行需先做状态容器，见 P1 报告 §9.5。

### 2026-10-17 系统安全区视觉修复

- 已用窗口原生 `setWindowSystemBarProperties` 统一顶部状态栏、底部导航栏与应用主题配色；
- 已用 ArkUI `expandSafeArea` 只延伸背景层，内容仍由系统安全区避让；
- 深色模式切换会同步系统栏背景与图标明暗；
- 手机、折叠屏模拟器覆盖安装验证完成，ArkTS 构建成功，纯逻辑测试 103/103 通过；
- 详细前后对比与布局数据见 `docs/handoff-ui-professional.md` 的“顶部与底部留白修复”。

---

## 给下一个执行者的三条提醒

1. **先读 `docs/handoff-p1.md` §4.1**：P0 的 Origin 阻塞已经通过 `mobile.allowedOrigins` 解决；P0 报告 §6.2 记录的 WebSocket **没有证书锁定**（鸿蒙 API 限制）仍然成立，HTTP 仍钉住。
2. **改动协议层前先抓真帧**：用真实主机连 `/mobile/v1/events` 打一遍，别照着上游 JS 猜。抓取方法与诱捕服务端思路见 P0 报告 §9。
3. **接新 action 时先在真实主机验证正反两条路径**（成功一次、失败一次），再写界面。
4. **搬上游 SVG 到 ArkUI 前先读 P1 报告 §4.2**：`Path` 的数字是 px、`.width()` 是 vp，
   `Shape.viewPort` 不缩放坐标；用 `vp2px(size)/100` 做 `.scale()` 才是对的。
   另外**每个 `Path`/`Rect` 都要显式 `.strokeWidth(0)`**，并且显式给 `width/height` 才能共享原点
   （否则 shape 默认描边 + 各自居中会产生黑边与图层错位，详见 P1 报告 §3）。
6. **图形/布局类改动必须量化验收**：黑像素计数、轮廓 IoU、bbox 中心这类断言要进验收标准，
   不能只看「能渲染出来」——这是 P1 的教训。
5. **真机回归前先重新配一次对**：设备会话 15 分钟过期，过期后 App 会按设计回到连接页。
6. **真机取证据**：`bash docs/qa/p1/realdevice.sh`（默认设备 `6HQ0226401001596`）会启动应用并采集「截图 + 布局 dump」；
   头像黑边用 `python3 docs/qa/p1/check_black_pixels.py <截图> "x0,y0,x1,y1:标签"` 量化（区域从布局 dump 的 bounds 取）。
7. **宽屏与手机是两套分支**：改任何界面元素时，`mobileHome`（手机）与 `conversationList`/`teamPage`（宽屏）都要检查——
   真机上就因为这个漏改了桌面分支的头像。
