# DS Bot Harmony 转译方案（P0–P3）

- 版本：v1（2026-10-15）
- 上游基线：`QingJ01/ds-bot-app@7e1c3f6c8ebe43bc342caf6abf895d4a2281e9d7`（= 上游当前 HEAD，本地克隆 `/tmp/ds-bot-app-upstream`）
- 本工程现状：ArkTS ≈ 2,000 行 / 5 个 `.ets` / 1 个页面
- 状态：**已评审并开始执行**。P0 已完成（见 `docs/handoff-p0.md`），当前进度看 `docs/plan/status.md`。
- 变更记录：2026-10-15 P0 落地；D1 的结论已按实测更新（见 §4.4）。

---

## 1. 目标、非目标与原则

### 1.1 目标

1. 功能对齐：把上游移动端「能用」的能力补齐到鸿蒙端，优先级以用户可感知程度排序。
2. 体验对齐：实时流式输出、消息渲染、头像与列表视觉与上游同构。
3. 结构可维护：把 1,477 行的单页拆成可持续添加模块的分层结构。
4. 每期可独立验收：有明确的验收标准与端到端验证记录。

### 1.2 非目标（本工程不做）

- 不复制上游的 React Native 代码；只对齐**协议契约、交互语义、视觉结构**。
- 不改主机插件（`ds-bot`）。所有能力都通过现有 `/mobile/v1` HTTP + `/mobile/v1/events` WebSocket 契约获得（本机主机实测 `/info` 返回 78 个 action，清单见 §10.1）。
- 不实现 iOS/Android 特有的原生能力（如 Android 前台服务）；系统通知用鸿蒙的 `reminderAgentManager` / `notificationManager` 对齐语义。

### 1.3 工作原理

1. **协议优先**：先照抄 `packages/mobile-sdk` 的语义（会话、事件、合并、重连、缓存），再谈界面。
2. **小步验收**：每个工作包独立编译通过 + 模拟器实机截图 + 与上游参考图对比。
3. **不破坏现有可用路径**：现有配对/发送/审批在改造期间必须保持可用，改造以「新增模块 + 切换调用点」方式进行，而不是原地重写。
4. **真实主机验证**：端到端一律打本机 `https://127.0.0.1:8788/mobile/v1`（真实 DSH 主机，protocolVersion 1，serverId `d80ef80e-403f-480e-aac7-decf9faeb3c6`）。

### 1.4 需要用户拍板的决策点（D1–D4）

| 编号 | 决策 | 选项 | 影响 |
|---|---|---|---|
| **D1** | 实时通道的证书处理（见 §4.4，**最高优先级**） | A. `webSocket` + `caPath` 钉住主机自签证书（推荐，先做可行性验证）<br>B. `@ohos.net.socket` TCPSocket + TLS 自建帧协议（能力最强，工作量最大）<br>C. 降级：继续用 HTTPS 轮询，不走 WebSocket | 决定 P0 的形态与工作量；A 不可行时 P0 需按 B 重估 |
| **D2** | 头像渲染方案 | A. Path + 路径数据实时绘制（与上游一致，推荐）<br>B. 保留静态 PNG，仅补齐缺失角色 | A 能真正实现「形状 × 颜色」，B 只能近似 |
| **D3** | 本地缓存载体 | A. `relationalStore`（RDB，对齐上游 SQLite）推荐<br>B. `preferences` + JSON 文件 | A 支持分页/搜索/大量消息，B 只适合小数据 |
| **D4** | 交付粒度 | A. 严格按 P0→P1→P2→P3<br>B. 先做一个「垂直切片」（如仅流式 + 头像 + 列表）验收后再继续 | 影响首批交付时间与反馈速度 |

---

## 2. 现状盘点（截至 2026-10-15）

### 2.1 已有的可用能力

| 领域 | 已实现 | 代码位置 |
|---|---|---|
| 配对 | 粘贴配对 JSON、字段校验、`/info` 握手 + serverId 比对、`/pairings`、电脑端批准轮询、`/pairings/complete` | `Index.ets:147-187` |
| 身份与传输 | HTTPS 强制、SPKI SHA-256 转 Base64 证书锁定、Bearer 鉴权、401/403 单次刷新重试、协议版本校验 | `MobileApi.ets:36-161` |
| 持久化 | `preferences` 单 key `profile`（serverUrl/serverName/tlsPin/session） | `ProfileStore.ets:5-38` |
| 会话 | `/state`、`/conversations`、`/messages`、`/read-markers`、置顶/隐藏/显示隐藏、`set-flags` | `Index.ets:189-266, 403-422` |
| 聊天 | 乐观发送、`/target` + `/submissions`、轮询等回复、`/cancel` 停止、推理文本、只读工具卡片 | `Index.ets:268-321, 736-794` |
| 团队 | `create-bot`（仅名称+形状+颜色）、`create-room`（成员+名称） | `Index.ets:323-378` |
| 管理 | `approvals` / `approval-resolve`、`/devices` / `revokeDevice`、登出清凭据 | `Index.ets:380-455` |
| 界面 | 主页、聊天、团队、设置、创建 Bot、工具页、能力库页；深浅色；4 段响应式断点（600/840/1040/1200） | `Index.ets:486-1447` |

### 2.2 规模对比

| 维度 | 上游 | 本工程 | 覆盖度 |
|---|---|---|---|
| 移动端代码 | ≈ 7,600 行 TSX（26 组件 + 5 屏幕 + 9 功能面板 + 16 主机设置面板 + 14 逻辑模块） | 1,477 行 ArkTS（20 个 `@Builder`，2 个已死） | 低 |
| SDK | 548 行 JS / 274 行 d.ts，`MobileClient` 有 35 个公开方法 | 244 行，15 个公开方法 | ≈ 40% |
| action 端点 | 主机支持 78 个 | 使用 4 个 | 5% |
| 事件通道 | WebSocket `/events` + 重连 + 增量合并 | 无 | 0% |
| 本地缓存 | SQLite（消息 + 草稿，按 serverId 分区） | 1 个 preferences key | ≈ 5% |
| 头像素材 | 20 角色 × 12 颜色 + 5 套 ink，矢量路径实时绘制 | 13 张静态 PNG + 11 个色板（颜色不作用于头像） | 视觉不一致 |
| 测试 | 主机侧有 30+ 测试文件与 smoke/parity 脚本 | 无测试 | 0% |

### 2.3 已确认的缺陷清单（改造时必须一并修掉）

| 编号 | 缺陷 | 证据 | 严重度 |
|---|---|---|---|
| B1 | `stop()` 只清 `busy`，不终止 `send()` 的 30×1200ms 轮询循环，输入框在旧循环仍写 `messages` 时重新可用 | `Index.ets:294-321` | P1 |
| B2 | `refreshAll()` 的 single-flight 静默丢弃并发刷新，且 `refreshing` 不驱动任何 UI | `Index.ets:52, 191, 216` | P2 |
| B3 | 3 处滚动 `setTimeout` 从不清理；无 `aboutToDisappear`，页面销毁后轮询继续 | `Index.ets:261, 285, 308` | P2 |
| B4 | ✅ 已解决：删除未引用的手写 `botColor()`，颜色统一来自上游 `characters.json` | `AvatarData.ets` / `characters.json` | P1-8 |
| B5 | 「本机」判定用 `profile.session.deviceId`，忽略主机返回的 `currentDeviceId` | `Index.ets:1076` vs `Models.ets:188` | P3 |
| B6 | 🟡 部分解决：已删除 `bottomBar()` / `bottomButton()`；`ProfileStore.updateSession()` 待清理 | `ProfileStore.ets` | P1-8 / P3 |
| B7 | 创建 Bot 的 `model` 静默取 `team.models[0].ref`，用户无感知 | `Index.ets:336` | P2 |
| B8 | `createBot()` 成功后仅在已刷新列表中存在匹配会话时才跳转，否则静默无反应 | `Index.ets:340-345` | P2 |
| B9 | 访问令牌以明文 JSON 存于应用沙箱 | `ProfileStore.ets:23` | P2（安全） |
| B10 | 设置页 9 个入口无 `onClick`、能力库页为静态占位、聊天 `+`/`⋯` 仅弹 toast | `Index.ets:920, 895, 1124-1175, 1322-1335, 1365-1385` | P2（体验） |

### 2.4 可直接对比的视觉证据

- 合并对比图：`docs/qa/comparison-home.png`、`comparison-tools.png`、`comparison-create.png`
- 上游参考图：`docs/qa/reference-home.png`、`reference-tools.png`、`reference-create.png`
- 本工程实机图：`docs/qa/emulator-home.jpeg`、`emulator-chat.jpeg`、`emulator-settings.jpeg`、`emulator-tools.jpeg`、`emulator-capabilities.jpeg`、`emulator-create.jpeg`

已确认的视觉差异（从 `comparison-home.png` 可直接看到）：会话行使用「蓝圆角方块 + 名称首字」而非主机真实角色头像；缺主 Bot 星标；缺未读蓝点；群聊缺多角色叠加头像。

---

## 3. 差距清单（对照上游 `apps/mobile`）

上游文件 → 本工程对应物 → 状态：

| 上游模块 | 行数 | 本工程现状 | 目标期 |
|---|---|---|---|
| `screens/PairingScreen.tsx` | 223 | 已有（缺二维码扫描、缺 host 列表） | P3（扫码）/ 保留 |
| `screens/ChatScreen.tsx` | 664 | 部分（无流式/Markdown/附件/长按/队列） | P0+P1 |
| `screens/TeamScreen.tsx` | 1,094 | 很少（只有创建） | P2 |
| `screens/SettingsScreen.tsx` | 521 | 骨架（多数入口无响应） | P2 |
| `screens/CreationScreen.tsx` | 73 | 部分（只有名称/形状/颜色） | P2 |
| `hooks/useConversation.ts` | — | 无（逻辑内联在 Index） | P0 |
| `hooks/useWorkspace.ts` | — | 无（逻辑内联） | P0 |
| `hooks/useNotifications.ts` | — | 无 | P3 |
| `logic/conversation-order.ts` | — | 无（会话排序用主机顺序） | P1 |
| `logic/submissions.ts`（请求 ID 与未确认发送） | — | 无（`harmony-时间戳-随机`） | P0 |
| `logic/system-events.ts` | — | 无 | P1 |
| `logic/markdown.ts` + `components/MarkdownText.tsx` | 92 | 无 | P1 |
| `logic/reasoning.ts` + `ThinkingLevelPicker` | 26 | 无 | P1 |
| `logic/tool-results.ts` + `ToolResultView` | 30 | 只读卡片 | P1 |
| `logic/notifications.ts` + `media/notifications.ts` | — | 无 | P3 |
| `logic/voice.ts` + `VoiceMode.tsx` | 200 | 无 | P3 |
| `logic/export.ts` + `ConversationExport.tsx` | 44 | 无 | P3 |
| `logic/localization.ts` + `i18n*` | — | 无（全硬编码中文） | P3 |
| `logic/colors.ts` + `BotAvatar.tsx` | 361 | 静态 PNG | P1 |
| `components/ApprovalCards.tsx` | 93 | 仅设置页列表 | P1 |
| `components/QuestionCard.tsx` | 71 | 无 | P1 |
| `components/MediaComposer.tsx` / `FileAttachment.tsx` | 327+74 | 无（`+` 弹 toast） | P3 |
| `components/MentionMenu.tsx` / `ReferencePicker.tsx` | 19+26 | 无 | P1 |
| `components/MessageBubble.tsx` / `MessageActions.tsx` | 189+31 | 简版气泡、无长按 | P1 |
| `components/AgentDetails.tsx` | 223 | 无 | P2 |
| `components/AvatarEditor.tsx` | 205 | 无 | P2 |
| `components/WorkingFolderPicker.tsx` | 90 | 无（`folders` / `folder-list` 可用） | P2 |
| `components/GroupProgress.tsx` | 184 | 无 | P1 |
| `components/NotificationsPanel.tsx` | 60 | 无 | P3 |
| `components/DesktopBrowser.tsx` | 44 | 无（`browser-*` 可用） | P3 |
| `features/MemoryPanel.tsx` | 370 | 无（`memory-*` 可用） | P2 |
| `features/SchedulesPanel.tsx` | 384 | 无（`schedules` / `schedule-*` 可用） | P2 |
| `features/UsagePanel.tsx` | 687 | 无（`usage` 可用） | P2 |
| `features/HistoryPanels.tsx` | 354 | 无（`parts` / `earlier` / `search` / `context` 可用） | P0+P1 |
| `host-settings/*`（16 个面板） | — | 无（`settings-*` / `plugins-*` / `skills-*` / `credentials-*` 可用） | P3 |
| `storage/cache.ts` | — | 无 | P0 |

---

## 4. 关键技术攻坚点

### 4.1 事件协议（照抄 SDK 语义）

- 端点：`wss://<origin>/mobile/v1/events`（`origin` 与 HTTP 同源）
- 首帧：`{"type":"auth","token":"<accessToken>","conversationId":"<id>","after":<eventSeq>}`
- 事件：`ready` / `delta` / `message` / `reset` / `status` / `error`
- 断线：`4401`/`4403` → 先 `/auth/refresh` 再重连；其他 → 指数退避（750ms 起，上限 15s，最多 8 次翻倍）
- 握手超时：`min(requestTimeout, 20s)`
- 兜底：`onmessage` 解析失败不得中断连接；`error` 事件里的 `unauthorized` / `token_expired` / `invalid_token` 触发刷新
- 必须移植的纯函数：`mergeMessages()`（按 `updatedSeq ?? seq` 去重、tool 卡片合并、pending 排最后）、`applyConversationEvent()`（`reset` / `delta` 累积快照与 `index` 去重 / `message` + `replaceAttemptId` / `status clearAttempt`）

### 4.2 消息模型补强

现在 `Models.ets` 的 `Message` 缺 `attemptId`、`updatedSeq`、`streamIndex`、`pending`、`systemEvent`、`attachments`、`author`；`MessagePage` 缺可用游标。P0 必须先补齐类型，否则 P1 的渲染无从下手。

### 4.3 头像矢量渲染（D2 选 A 时）

- 上游数据源：`apps/mobile/src/components/characterData.json`（20 角色：whale/star/moon/wave/squircle/zed/hex/gumdrop/peanut/saucer/bunny/kitty/beacon/plus/magnet/acorn/pebbles/cushion/ring/gem；每个角色含 `body` / `shade` / `light` 三段路径 + `eyes` 椭圆参数）
- 调色板：12 色（black/brown/red/orange/yellow/green/cyan/blue/violet/magenta/gray/aurora）+ 5 套 ink（deepseek/charcoal/graphite/rose/sky 等）
- 鸿蒙实现路径：ArkUI `Path({ commands })` 支持 SVG 路径字符串，`fill()` / `stroke()` 可设色；`Ellipse` 画眼睛；`Shape` 容器做旋转/对齐。已核实 `component/path.d.ts:406 commands(value: ResourceStr)`、`component/shape.d.ts:543,586 stroke()/fill()`
- 数据落地：把 `characterData.json` 转成 `entry/src/main/resources/rawfile/characters.json`（或 ArkTS 常量模块），避免 20 角色硬编码进 `Index.ets`
- 待验证：`characterData.json` 里路径的紧凑写法（如 `M65.3 20.9l5.1 .1`）在 ArkUI Path 解析器上的兼容性；建议先写一个最小 Demo 页把 20 个角色渲染出来对照上游截图

### 4.4 WebSocket 的证书锁定缺口（**D1，必须最先定**）

已核实的鸿蒙 API 事实：

- `@ohos.net.webSocket` 的 `WebSocketRequestOptions` 只有 `header` / `caPath` / `skipServerCertVerification` / `clientCert` / `proxy` / `protocol`（`@ohos.net.webSocket.d.ts:98-177`），**没有** `certificatePinning`
- `skipServerCertVerification` 的 `@since` 为 20 与 24，与本工程 `compatibleSdkVersion 20` 一致，可用但语义是「完全跳过服务器证书校验」
- 反之 `@ohos.net.http` 支持 `certificatePinning: { publicKeyHash, hashAlgorithm: 'SHA-256' }`（`@ohos.net.http.d.ts:538, 1046-1064`），本工程已在用

上游如何解决：它没有依赖系统 WebSocket，而是自建原生模块 `DSBotLocalTLS`（`apps/mobile/src/network/client.ts:2-6, 30-33`）同时提供**钉住证书的 fetch 与 WebSocket**；SDK 在 `tlsPin` 存在但传输层不是自定义实现时会直接抛 `missing_pinned_transport`（`packages/mobile-sdk/index.js:157`）。也就是说上游的钉住能力来自原生代码，不是 RN 自带的。

**P0 执行后的实测结论（2026-10-15）**：`@ohos.net.socket` 的 `TLSSecureOptions` 也只有 `ca`/`cert`/`key` 等字段，**同样没有自定义校验回调**（`@ohos.net.socket.d.ts:3707-3720`），所以路线 B 必须自己实现完整 WebSocket 帧协议。主机侧只通过配对码下发 SPKI 指纹、不提供证书文件，路线 A 需要拿到证书本体才有意义。

P0 的实际选择：事件流先用 `skipServerCertVerification`（HTTP 仍严格钉住），并把这一降级记入 `docs/handoff-p0.md` §6.1；设备侧 TLS 行为仍待实测（同报告 §7.1）。

鸿蒙侧可行路线（按推荐顺序）：

- **A（推荐先试）**：`caPath` 指向主机自签证书本身。用主机自签证书同时充当信任锚，TLS 完整、加密保留、身份约束退化为「只有持有该证书的主机才能握手」。需要确认：主机是否对外提供证书文件（`local-certificate.js` 有生成逻辑）、`caPath` 是否接受应用沙箱内路径（`filesDir` 拷贝或 `rawfile` 解包路径）、以及校验失败时的报错形态。这是**唯一的纯 API 路线**。
- **B（能力最强）**：`@ohos.net.socket` 的 TCPSocket + TLS（用 `ca` 信任锚）+ 自建 WebSocket 握手与帧解析，在应用层校验对端证书的 SPKI。工作量最大（估 XL），但能真正复刻上游的钉住语义，同一套底层还可服务附件流式下载。
- **C（降级）**：不走 WebSocket，继续 HTTPS 轮询（钉住仍然有效），把 P0 的其余部分（事件合并、分页、缓存、请求 ID）先做掉，实时性等 A/B 落地后再补。

> 无论选哪条，P0 的第一件事都是写一个**最小连接 Demo**（连本机 `127.0.0.1:8788` 的 `/events`，打印 `ready` 事件），用实测结果回报，而不是先写业务代码。

### 4.5 其他已核实的鸿蒙能力（明确可做）

| 能力 | 鸿蒙 API | 状态 |
|---|---|---|
| 文件上传（multipart） | `@ohos.net.http` 的 `multiFormDataList`（`@ohos.net.http.d.ts:530, 842`） | 可用 |
| 图片/文件选择 | `@ohos.file.picker`、`@ohos.file.photoAccessHelper` | 可用 |
| 录音（语音输入） | `@ohos.multimedia.audio` 的 `createAudioCapturer` | 可用（需麦克风权限） |
| 朗读（TTS） | `@hms.ai.textToSpeech` / `@kit.SpeechKit`（HMS 侧） | 可用但依赖 HMS Core 运行时，需在真机确认 |
| 本地缓存 | `@ohos.data.relationalStore`（RDB） | 可用 |
| 凭据加密 | `@ohos.security.huks`（`generateKeyItem` / `importKeyItem`） | 可用 |
| 后台/提醒 | `@ohos.resourceschedule.backgroundTaskManager` + `@ohos.reminderAgentManager` | 可用（需权限与 `usedScene` 声明） |
| 原生工具（Shell 等） | 平台边界 | **不做**，与上游一致（手机不执行主机脚本） |

---

## 5. 目标代码结构

```
entry/src/main/ets/
  entryability/EntryAbility.ets        应用入口（补 onBackPressed / 窗口尺寸 / 生命周期清理）
  model/
    Models.ets                          协议类型（补 Message/Conversation/Approval 上游字段）
    ViewState.ets                       界面状态类型（导航、遮罩、表单）
  service/
    MobileClient.ets                    传输层：HTTPS（钉住）+ WebSocket（见 D1）
    SessionStore.ets                    session 持久化（HUKS 加密）
    MessageCache.ets                    RDB：消息 / 草稿 / 未确认发送记录
    Preferences.ets                     外观、语言、经典模式等偏好
  logic/
    EventStream.ets                     事件订阅、重连、eventSeq 续传
    Merge.ets                           mergeMessages / applyConversationEvent
    ConversationOrder.ets               会话排序（主 Bot 优先、置顶、未读、工作时间）
    Submissions.ets                     requestId 生成与未确认发送对账
    Markdown.ets                        Markdown → 样式片段
    Reasoning.ets                       思考块折叠与档位
    Drafts.ets                          草稿读写
  pages/
    Index.ets                           根：导航与断点分发（目标 < 250 行）
  view/
    pairing/                            连接页（含后续扫码）
    home/                               首页：主 Bot 卡、会话列表、搜索、创建入口
    chat/                               聊天：消息列表、气泡、工具卡、Markdown、审批卡、提问卡、输入栏、队列
    team/                               团队：Bot 详情/编辑、群详情、成员、能力
    settings/                           设置：分组入口 + 各子面板
    tools/                              工具与技能：Skills / Plugins / Connectors / Capabilities
    common/                             头像、胶囊标题、卡片、分组、开关、空态
  i18n/
    zh.json / en.json                   文案（P3）
entry/src/main/resources/
  rawfile/characters.json               头像路径数据
  base/element/…                        颜色与字符串资源（逐步替换硬编码）
```

约束：
- 单文件 ≤ 400 行，超出即拆组件。
- 所有网络调用只能经 `service/MobileClient`，禁止在视图层直接 `http.createHttp()`。
- 所有界面状态变更集中在 `pages/Index` 与各 hook 式模块，视图层只读状态 + 派发动作。

---

## 6. 分期计划

工作量标记：S ≈ 0.5–1 天，M ≈ 2–3 天，L ≈ 4–6 天，XL ≈ 7 天以上（AI 辅助实现的相对估算，不含联调等待）。

### P0 · 协议与实时底座

| 编号 | 工作包 | 内容要点 | 文件级改动范围 | 验收标准 | 量 | 依赖 |
|---|---|---|---|---|---|---|
| P0-1 | 连接能力可行性验证 | 最小 Demo：连本机 `/events` 收 `ready`；分别验证 `caPath` 与 `skipServerCertVerification`；记录 TLS 报错形态 | 新增 `pages/dev/StreamProbe.ets`（临时页，验证后删除或保留为调试入口） | 能收到 `ready`；三种方案各自的实测结论写回本文档 §4.4 | S | D1 |
| P0-2 | 类型补强 | `Message` 补 `attemptId`/`updatedSeq`/`streamIndex`/`systemEvent`/`attachments`/`author`；`MessagePage.cursor` 启用；`Conversation` 补 `parts`/`mode`/`notice`/`admin`；`Approval` 补 `callId`/`createdAt` | `model/Models.ets` | `assembleHap` 通过；类型与上游 `index.d.ts` 逐字段对照有清单 | S | — |
| P0-3 | 纯函数移植 | `mergeMessages` + `applyConversationEvent`（含 `delta` 累积快照去重、tool 卡片合并、`replaceAttemptId`、`clearAttempt`） | 新增 `logic/Merge.ets` | 用上游 `packages/mobile-sdk/test` 的用例思路写等效断言（见 P0-9），全部通过 | M | P0-2 |
| P0-4 | 传输层 | `MobileClient`：现有 HTTP 部分整体迁移（保留钉住与刷新重试），新增 `connect()` 事件订阅、`after`/`eventSeq` 续传、指数退避重连、`4401/4403` 刷新重连、`close()` | 新增 `service/MobileClient.ets`；`service/MobileApi.ets` 保留到切换完成后再删 | 断网 10 秒后自动重连并补回缺失事件；`assembleHap` 通过 | L | P0-1 |
| P0-5 | 消息流替换轮询 | 删除 `send()` 的 30×1200ms 循环与 `pair()` 的 80×1500ms 循环；改为事件驱动；发送链路走 `Submissions`（稳定 requestId + 未确认对账 + `/submissions/{requestId}` 查询） | `pages/Index.ets`、新增 `logic/Submissions.ets` | 发送后逐字出现；`stop()` 后不再有残留写入（B1 复现用例通过）；超时/断线可恢复 | L | P0-4 |
| P0-6 | 历史与续读 | `messages(cursor)` 分页 + 上拉加载更早；`parts` 列出会话分段；`earlier` 续读跨段历史；选中消息 `context` | `logic/*`、`view/chat` | 200 条以上会话可连续翻到最早；跨 part 会话可切换查看 | L | P0-4 |
| P0-7 | 本地缓存与草稿 | RDB 存消息（按 serverId + conversationId 分区）与草稿；冷启动先渲染缓存再拉增量；`clearCachedData`；未确认发送记录不可被清缓存删除 | 新增 `service/MessageCache.ets`；`pages/Index.ets` | 飞行模式冷启动能看到历史与草稿；主机返回后自动补增量 | L | D3, P0-2 |
| P0-8 | 生命周期与清理 | `aboutToDisappear` 关闭事件流；所有 `setTimeout` 记录并可取消；`refreshAll` 改为可等待的串行任务并给 UI 反馈（B2/B3） | `pages/Index.ets`、`entryability/EntryAbility.ets` | 退出页面后无挂起任务；并发点刷新表现为排队而非静默丢弃 | M | P0-4 |
| P0-9 | 回归基线 | 新增 `entry/src/ohosTest`（或独立 Node 脚本）覆盖：`mergeMessages`、`applyConversationEvent`、`normalizedOrigin`、`pinToBase64`、`conversation-order` | 新增测试目录 | 一条命令可跑完全部纯函数测试，通过率 100% | M | P0-3 |
| P0-10 | 凭据加密 | session 迁到 HUKS（或至少 preferences 加密存储），保留可回退迁移路径 | `service/SessionStore.ets`（替换 `ProfileStore.ets`） | 旧 profile 首次启动自动迁移；沙箱内不再出现明文 token（B9） | M | — |

**P0 出口标准**：实时流式可用；无假轮询；历史可分页续读；冷启动有缓存；无残留任务；纯函数测试通过；`assembleHap` 成功；模拟器实机录屏/截图存档。

### P1 · 视觉与交互对齐

| 编号 | 工作包 | 内容要点 | 验收标准 | 量 | 依赖 |
|---|---|---|---|---|---|
| P1-1 | 头像引擎 | `characters.json` + Path/Ellipse 渲染 20 角色 × 12 色 + ink；列表/聊天/团队/详情全部改用同一组件 | 创建页 20 形状与 12 颜色都能实时变色；与上游截图并排对比无明显差异 | L | D2 |
| P1-2 | 首页与列表 | 真实角色头像、主 Bot 星标、未读蓝点、群聊多角色叠加、工作时间状态、排序（`ConversationOrder`） | `comparison-home.png` 重拍后无 P0/P1 差异 | M | P1-1 |
| P1-3 | Markdown 渲染 | 代码块（等宽 + 复制）、表格、列表、链接、行内代码、引用；流式过程中增量重排 | 含表格/代码块的真实回复渲染正确 | L | P0-4 |
| P1-4 | 消息交互 | 可展开思考块（默认折叠 + 过程回看）、长按菜单（复制/分享/引用/本地表情）、工具卡展开、系统事件行、作者标识 | 长按可用；思考块可展开收起；工具卡可展开输入输出 | M | P0-4 |
| P1-5 | 输入栏补全 | 思考档位（`efforts`）、`@` 提及（`mentions` 同规则）、引用会话（`reference-chats` + `dsh-session:` 编码）、多行与字数上限 | 提及与引用发送后主机能正确解析（用真实主机验证一人一 Bot） | L | P0-5 |
| P1-6 | 审批与提问 | 聊天内审批卡（允许一次/拒绝/取消后撤回）、提问卡（单选/多选/自定义答案 `answer-question`）、排队消息查看与移除（`queue` / `queue-remove`） | 不打开设置也能在聊天里处理审批；提问卡能回填答案 | L | P0-4 |
| P1-7 | 群聊呈现 | 群成员回复作者、群进度（`room-progress`）、停止某成员工作（`stop-member-work`） | 多人回复能区分作者；能看到谁在工作 | M | P0-4 |
| P1-8 | 视觉细节收口 | 胶囊标题、圆角与间距令牌化、深色模式对照、SafeArea、B4 颜色 bug | 与上游参考图并排逐页对比无 P0/P1 差异 | M | P1-1…P1-7 |

**P1 出口标准**：`docs/qa/` 下重拍全部实机图 + 合并对比图；聊天页与上游 `ChatScreen` 的关键交互逐一核对；无 P0/P1 差异。

### P2 · 设置与管理

| 编号 | 工作包 | 内容要点 | 验收标准 | 量 |
|---|---|---|---|---|
| P2-1 | 设置骨架重做 | 分组入口全部可点、子页导航、返回栈、加载/空/错态统一 | 9 个空壳入口全部有真实内容 | M |
| P2-2 | 用量面板 | `usage` 的 24h/7d/30d/12w/12m/自定义、Bot/群/模型筛选、环比、堆叠图、排行、活动明细 | 数据与主机真实记录一致 | L |
| P2-3 | 定时任务 | `schedules` / `schedule-create` / `schedule-delete`，四种形态（once/daily/weekly/interval），Bot 与群目标 | 四种形态各建一条并删除，主机侧状态可还原 | L |
| P2-4 | 记忆面板 | `memory-view`（含 summarize/regenerate）、`memory-forget`、`memory-ask`，私有/团队/主题分组与字数上限 | 增删改查闭环，主机侧可还原 | L |
| P2-5 | Bot 管理 | `update-bot` / `duplicate-bot` / `delete-bot` / `set-main`、模型选择（`models`）、思考档位（`efforts`）、角色/指令/简介、头像编辑（形状+颜色+照片）、工作目录（`folders` / `folder-list`） | 编辑/复制/删除/主 Bot 交接在真实主机上闭环 | XL |
| P2-6 | 群管理 | `update-room`（名称/公告/模式 admin-everyone/管理员/成员增删/工作目录）、`delete-room`、`exchange` | 群设置全部可改并生效 | L |
| P2-7 | 能力分配 | `bot-capability` 附件开关、能力库真实数据（MCP / Skill / Pack，含 transport 与审批态） | 能力库显示主机真实能力，开关生效 | L |
| P2-8 | 工具与技能 | `skills-list` / `skills-get` / `skills-library` / `skills-save` / `skills-delete`；`plugins-list` / `plugins-set-enabled` / `bundle-set-enabled` | 三个入口（技能/插件/连接器）都有真实列表与操作 | L |
| P2-9 | 会话与 Agent | 普通 Agent 会话的创建/改名/归档（`add-agent` / `agent-rename` / `agent-archive`）、`set-flags` 扩展、会话导出（Markdown/JSON，`logic/export`） | 经典 Agent 模式开关真实生效；导出文件可打开 | L |
| P2-10 | 设备与诊断 | 移动端设备列表（B5）、撤销、`diagnostics` 上报、`update-check` / `repo-stars`、关于页 | 手机上可管理设备与更新检查 | M |
| P2-11 | 偏好持久化 | 深色（跟随系统）、经典模式、语言、隐藏会话开关全部落盘 | 重启后保持 | S |

### P3 · 扩展层

| 编号 | 工作包 | 内容要点 | 验收标准 | 量 |
|---|---|---|---|---|
| P3-1 | 附件 | 图片（≤10MiB）/ 文件（≤20MiB）选择与 multipart 上传（`/uploads`）、消息内图片显示、附件下载（`/attachments/{id}`，带会话归属校验）、失败与大小限制提示 | 真机选图上传后主机可读；下载能打开 | XL |
| P3-2 | 语音输入 | 录音（≤60s）→ `/transcriptions` → 可编辑草稿；权限与错误态 | 真机录一段得到文本草稿 | L |
| P3-3 | 语音对话 | 听→转写→发送→朗读循环、可暂停/打断、断线停止 | 一轮闭环可用（TTS 依赖 HMS，需真机确认） | L |
| P3-4 | 通知 | `reminderAgentManager` 本地提醒 + 前台长任务保活；审批与任务提醒；通知中心面板；`notifications-*` 系列 action | 退到后台能收到提醒；点击回到对应会话 | L |
| P3-5 | 桌面浏览器 | `browser-pages` / `browser-read` / `browser-control` 只读页列表与控制命令 | 能读主机 Bot 页面信息 | M |
| P3-6 | 主机设置面板 | `settings-describe` / `settings-update` / `settings-mutate`（带 revision 校验）、`credentials-*`、`secret-*`、连接器 `connector-*` | 能改一项主机设置并回读确认 | XL |
| P3-7 | 国际化 | 抽取全部硬编码中文到 `resources/zh_CN`、`en_US`；跟随系统或手动切换 | 切英文后主要页面无残留中文 | L |
| P3-8 | 二维码配对 | 扫码读取配对 JSON（相机权限） | 真机扫码完成配对 | M |

---

## 7. 验证与验收流程

每个工作包按同一闭环执行：

1. **编译**：`assembleHap`（命令见 `README.md`）+ PreviewBuild。
2. **纯函数**：涉及协议/排序/合并的改动，必须先补测试并跑通（P0-9 建立的测试入口）。
3. **实机**：hdc 装到 API 24 模拟器（`127.0.0.1:5555`），按验收标准逐条操作。
4. **真实主机**：配对与所有写操作打 `https://127.0.0.1:8788/mobile/v1`；写操作完成后必须把主机状态还原（置顶/隐藏/定时任务/记忆等）。
5. **截图比对**：新增实机图到 `docs/qa/`，需要视觉对齐的页面生成 `comparison-*.png`。
6. **文档**：更新 `TEST_REPORT.md`（测试记录）与 `design-qa.md`（设计对齐结论），模块级方案变更回写本文档。

验收规定：
- 不允许把「点了没反应」的入口留在已声明完成的期里（P2 结束时不接受任何 toast-only 占位）。
- 每个 action 端点首次接入时，必须在真实主机上完成一次正向 + 一次失败路径验证。
- 涉及破坏性操作（删除 Bot/群、撤销设备、清除缓存）必须有二次确认。

---

## 8. 风险与对策

| 编号 | 风险 | 影响 | 对策 |
|---|---|---|---|
| R1 | WebSocket 无法钉住证书（§4.4） | P0 可能被迫降级为轮询，或需要自建 TLS/WS（XL） | P0-1 先做最小验证；先按 A 试，A 不可行立即回报并按 B/C 重估（D1） |
| R2 | ArkUI Path 对紧凑 SVG 路径解析异常 | 头像矢量方案受阻，回落到静态 PNG（视觉不一致） | P0-1 同批做 20 角色渲染 Demo；若失败，改用手工重排的路径或保留 PNG + 颜色叠加 |
| R3 | `Index.ets` 拆分过程中的预览/编译回归 | 改造期间功能中断 | 先建新模块并以「新增 + 切调用点」推进，旧实现保留到新路径验证通过；每个工作包单独编译 |
| R4 | 模拟器与真机差异（性能、通知、麦克风、HMS TTS） | P3 部分能力无法在模拟器验收 | 明确标注「需真机」的工作包，模拟器只做 UI 与逻辑验证；提前确认是否有真机可用 |
| R5 | 主机能力开关（实测 `transcription: false`） | 语音输入在当前离线主机上不可用 | 语音类工作包先读 `/info` 的 `capabilities`，不支持时给出明确提示并隐藏入口，不静默失败 |
| R6 | 上游继续演进 | 对齐目标漂移 | 固定基线提交；每期开工前核对上游是否有影响协议的新提交，有则单独立项 |
| R7 | 工作量估计偏差（上游 ≈ 7,600 行 vs 本工程 2,000 行） | 总周期被低估 | 每期结束重新估算下一期；P0/P1 是关键路径，先保证它们的质量 |

---

## 9. 建议的执行顺序与首批范围

1. **先做 P0-1（1 个工作包，S）**：只验证 WebSocket 与证书方案，产出结论。这一步决定 P0 的形态，不做完不写业务代码。
2. 然后按 P0-2 → P0-3 → P0-4 → P0-5 推进（类型 → 纯函数 → 传输 → 替换轮询），这四步完成后聊天体验即与上游同构。
3. P0-6 → P0-10 补齐历史、缓存、生命周期、测试、凭据。
4. 进入 P1；P1 结束后重拍全部对比图并做一次完整设计 QA。
5. P2、P3 按表中顺序，每个工作包独立验收。

若希望更快看到效果，可采用 D4 的选项 B：把 **P0-1 + P0-4 + P0-5 + P1-1 + P1-2 + P1-3** 作为一个垂直切片先交付（流式 + 头像 + 列表 + Markdown），验收通过后再补 P0 剩余部分。

---

## 10. 附录

### 10.1 主机可用 action 全量清单（实测 `/info` 返回，78 个，已与主机返回值逐项核对）

`create-bot`、`update-bot`、`duplicate-bot`、`delete-bot`、`set-main`、`create-room`、`update-room`、`delete-room`、`folders`、`folder-list`、`memory-view`、`memory-forget`、`memory-ask`、`answer-question`、`dismiss-question`、`room-progress`、`usage`、`models`、`efforts`、`queue`、`queue-remove`、`set-flags`、`set-prefs`、`exchange`、`earlier`、`parts`、`search`、`context`、`reference-chats`、`bot-capability`、`stop-member-work`、`schedules`、`schedule-create`、`schedule-delete`、`connector-connect`、`connector-retry`、`connector-disconnect`、`browser-pages`、`browser-read`、`browser-control`、`secret-set`、`secret-allow`、`secret-cancel`、`secret-update`、`secret-delete`、`add-agent`、`agent-session`、`agent-archive`、`agent-rename`、`remove-agent`、`diagnostics`、`diagnostics-log`、`diagnostics-clear`、`settings-describe`、`settings-update`、`settings-mutate`、`credentials-describe`、`credentials-set`、`credentials-unset`、`update-check`、`update-install`、`dsh-update-install`、`repo-stars`、`approvals`、`approval-resolve`、`plugins-list`、`plugins-set-enabled`、`bundle-set-enabled`、`skills-list`、`skills-get`、`skills-library`、`skills-save`、`skills-delete`、`plugins-inspect`、`plugins-install`、`plugins-remove`、`plugins-operation`、`plugins-cancel`

当前工程使用其中 4 个：`create-bot`、`create-room`、`set-flags`、`approval-resolve`。

主机 `/info` 实测能力：`images: true`、`files: true`、`transcription: false`、`maxImageBytes: 10MiB`、`maxFileBytes: 20MiB`、`maxAudioBytes: 10MiB`、`maxAudioSeconds: 60`、`audioStreaming: false`、`approvals: true`、`attachmentDownloads: ["image","file"]`、`historyResume: "snapshot-merge"`。

### 10.2 HTTP 端点（`/mobile/v1` 前缀）

`GET /info`、`POST /pairings`、`POST /pairings/complete`、`POST /auth/refresh`、`GET /state`、`GET /conversations`、`GET /conversations/{id}/messages?limit=&cursor=`、`GET /conversations/{id}/target`、`POST /submissions`、`GET /submissions/{requestId}`、`POST /conversations/{id}/cancel`、`POST /actions`、`POST /uploads?conversationId=&sessionId=&name=&mediaType=`、`POST /transcriptions?name=&mediaType=`、`GET /devices`、`DELETE /devices/{id}`、`POST /read-markers`、`GET /attachments/{id}?conversationId=&sessionId=&seq=`、`WS /events`

### 10.3 需要真机才能验收的条目

P3-2 语音输入、P3-3 语音对话与朗读、P3-4 通知与后台保活、P3-8 相机扫码，以及 P1/P2 在高刷新率与折叠屏展开态下的性能表现。

### 10.4 术语与参考

- **上游**：`QingJ01/ds-bot-app`（RN + Expo，Apache-2.0）
- **主机插件**：`ds-bot`（DSH 插件，提供 `/mobile/v1` 桥接与电脑端界面）
- **DSH**：DeepSeek Harness
- 关键上游文件：`packages/mobile-sdk/index.js`、`packages/mobile-sdk/index.d.ts`、`ds-bot/src/mobile/adapter.js`、`ds-bot/src/mobile/management.js`、`apps/mobile/src/network/client.ts`、`apps/mobile/src/components/characterData.json`
