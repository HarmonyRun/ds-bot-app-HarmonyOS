# P1-6 交接报告：审批、提问与排队交互

- 日期：2026-10-15
- 范围：`docs/translation-plan.md` 的 **P1-6**
- 本轮重点：补齐聊天内提问卡，并修复 questions 不会自动刷新的状态链路
- 结论：**P1-6 三块功能均已完成代码接线；64 个纯逻辑用例与 ArkTS 构建通过。审批、提问、排队都仍需要在重新配对后各触发一次真实场景做最终视觉与 action 回执验收。**

---

## 1. 原来是什么样

| 能力 | 本轮开始前状态 | 缺口 |
|---|---|---|
| 审批卡 | 已有聊天卡片、10 秒轮询和允许/拒绝动作 | 当前主机未触发审批，尚无真实视觉证据 |
| 排队消息 | 已有 status queue 面板与 `queue-remove` | 当前主机未捕获非空 queue，尚无真实动作证据 |
| 提问卡 | 完全没有实现 | `RawState` / `TeamState` 不含 questions；无法显示或回答 Bot 问题 |
| 状态刷新 | 10 秒定时器只请求 approvals | questions 来自 `/state` 且不通过消息 WebSocket 推送；即使主机在等回答，手机也可能一直看不到 |

## 2. 做了什么

### 2.1 补齐 questions 协议模型与安全投影

新增模型：

- `QuestionOption`：`label`、`value`、`description`
- `Question`：标题、问题正文、说明、单选/多选、自定义回答、会话与逻辑会话归属
- `TeamState.questions`
- `RawState.questions`

新增 `logic/Questions.ets`：

1. 把动态 `Record<sessionId, rawQuestion>` 投影成强类型。
2. 同时兼容字符串选项和 `{ label, value, description }` 对象选项。
3. 忽略缺 id 的坏问题和缺标签的坏选项。
4. 按上游同样的规则归属当前会话：优先 `conversationId`，旧主机数据回退 `sessionId`。
5. 群聊隐藏成员 Session 仍能映射到公开 room，不会因此开放隐藏历史。

`Projection.toTeamState()` 现在会调用 `toQuestions(raw.questions)`。

### 2.2 聊天内提问卡

提问卡支持：

- 标题、问题正文、详情说明
- 单选：原生 `Radio`，选中后直接提交
- 多选：原生 `Checkbox`，可选多项后统一提交
- 自定义回答：原生 `TextArea`
- 跳过/关闭：`dismiss-question { sessionId }`
- 回答：`answer-question { sessionId, questionId, answer: { selected, custom? } }`
- 提交中禁用重复操作；失败错误保留在对应卡片内
- 成功后刷新 `/state`，主机已解决的问题会从聊天中消失
- 卡片放在消息滚动区顶部，选项较多时跟消息一起滚动，不会挤掉输入栏

### 2.3 修复“问题不会出现”的刷新缺陷

原审批定时器每 10 秒只调用 `loadAdminData()`，它请求：

- `/actions approvals`
- `/devices`

但 questions 只存在于 `/state`。本轮增加 `loadQuestionState()`，同一定时器现在还会请求 `/state` 并更新 `team.questions`。它不会重拉消息历史，也不会重建事件流。

### 2.4 原生能力使用

| 交互 | ArkUI 原生能力 |
|---|---|
| 单选问题 | `Radio` + 原生 group |
| 多选问题 | `Checkbox` |
| 自定义回答 | `TextArea` |
| 提交/跳过/关闭 | `Button` 的 enabled/loading 状态 |
| 长问题滚动 | 复用原生 `Scroll` 消息容器 |

没有新建一套选择控件、输入控件或弹层系统。

## 3. 现在是什么样

### 已完成

- `/state.questions` 能进入强类型 `TeamState`。
- 当前 Bot、群聊隐藏成员 Session、旧版仅 sessionId 的问题都能正确归属。
- 单选、多选、自定义回答、跳过/关闭均已接到真实 action 名称与载荷。
- 问题状态每 10 秒自动刷新。
- 手机与宽屏聊天共用同一张提问卡 Builder。
- 只读团队会禁用回答控件。
- 回答期间防重复提交，失败可保留卡片重试。

### 2026-10-16 补：受控模拟主机上的运行时验收（发现并修复一个崩溃）

设备侧重新配对受阻（真机 USB Offline、模拟器需要电脑端批准，而主机控制面在 DSH GUI 里拿不到），
因此改用**受控模拟主机**做 UI 运行时验收：

- 夹具：`/tmp/dsprobe/mock-host.mjs`（用主机自己的证书提供 `/mobile/v1` 的受控应答 + RFC 6455 事件流），
  不接触真实主机、不写主机数据。
- 连接方式：把 mock 的凭据直接写入 App 私有 preferences（与之前给模拟器注入会话的做法一致），
  因为 `uitest inputText` 对含引号/中文的 JSON 不可靠。
- 结果：App 成功通过**证书钉住**连上 mock（`GET /info` → `/state` → `/conversations` → `/messages`
  → `actions efforts/approvals` → `UPGRADE /events origin=https://10.0.2.2`），
  并**真实渲染出提问卡**：标题、问题正文、三个选项（单选/多选）、`自定义回答`、`跳过`、`提交`。
  证据：`docs/qa/p1/device-question-card.jpeg`。

#### 顺带发现并修复一个真实崩溃（P1 遗留缺陷）

mock 对 `efforts` 返回 `{"ok":true}`（不含 `efforts` 字段）时，App **崩溃退出**。故障日志：

```
jscrash-app.dsbot.harmony-20020075-20261016152040834.log
Reason:TypeError
Error message:Cannot read property length of undefined
Stacktrace:
    at anonymous entry (entry/src/main/ets/pages/Index.ets:2272:68)
```

第 2272 行是 `if (this.composerReferences().length > 0 || this.effortOptions.length > 0 …)`，
**第 68 列正好是 `this.effortOptions.length` 的 `l`**。根因：

```ts
this.effortOptions = result.efforts;   // 主机应答不含该字段时 → undefined
```

`@State effortOptions` 一旦变成 `undefined`，下一次重渲染读 `.length` 就抛 TypeError。
这与本仓库其它动态对象的处理约定不一致（`toQuestions()` / `toTeamWork()` 都会做类型校验），
`loadEfforts` 是漏掉投影的那一处。

修复：新增 `logic/Efforts.ets` 的 `toEffortOptions()` / `toDefaultEffort()` 做显式投影，
`loadEfforts` 改为经投影赋值；新增 `test/efforts.test.ets` 6 个用例锁定
「投影永不返回 undefined、坏档位被丢弃、name 缺失回退 id」。

**给后续开发者**：任何来自主机的动态对象进入 `@State` 前都要过一次显式投影，
不要直接赋 `result.xxx`。渲染路径对状态做 `.length` / 索引访问时，先保证状态类型不可变。

### 尚未完成的运行时证据

安装本轮 HAP 后，之前的 15 分钟设备会话已经过期，应用按设计回到了配对页。因此本轮无法继续让 Chief 触发 `ask_user_question`，也无法生成真实提问卡截图。

重新配对后建议按下面顺序验收：

1. 对 Chief 发送：“请使用 ask_user_question 问我下一步做哪个功能，提供两个选项并允许多选”。
2. 最多等待 10 秒，确认卡片自动出现，无需手动刷新。
3. 勾选两项并提交，确认主机继续执行、卡片消失。
4. 再触发一次带自定义回答的问题，验证自定义文本。
5. 再触发一次并点击关闭，验证 `dismiss-question`。

## 4. 验证

```text
node entry/src/test/run.mjs
12 Avatar + 4 Composer + 19 Merge + 26 Markdown + 3 Questions
= 64 passed / 0 failed

hvigor ... assembleHap
BUILD SUCCESSFUL，0 error
```

新增的 Questions 用例覆盖：

- 字符串/对象选项与描述字段
- 多选、自定义回答标志
- 坏记录过滤
- Bot conversationId / sessionId 归属
- 群聊隐藏成员 Session → room 归属

## 5. 文件变更

| 文件 | 变化 |
|---|---|
| `model/Models.ets` | 新增 `QuestionOption`、`Question`、`TeamState.questions` |
| `service/MobileClient.ets` | `RawState` 增加 questions |
| `logic/Questions.ets` | 新增问题投影与会话归属纯逻辑 |
| `service/Projection.ets` | 把 raw questions 接入 TeamState |
| `pages/Index.ets` | 提问卡、回答/关闭动作、临时选择状态、10 秒 questions 刷新 |
| `test/questions.test.ets` | 3 个问题回归用例 |
| `test/run.mjs` | Questions 模块纳入测试 |

## 6. 后续开发者注意事项

1. `questions` 的对象 key 是真实 `sessionId`，不一定等于聊天列表里的 `conversation.id`。
2. 群聊问题可能来自隐藏成员 Session；必须使用主机给出的 `conversationId` 映射，不能要求该 Session 出现在会话列表。
3. `dismiss-question` 只传 `sessionId`；`answer-question` 还必须传 `questionId` 与 `{ selected, custom? }`。
4. questions 当前不是 WebSocket 事件，删除 `/state` 轮询会让卡片无法及时出现。
5. 单选遵循上游行为：点选即提交；多选和自定义回答才显示“提交”按钮。
6. 当前目录仍没有 `.git` 元数据，本轮无法直接提交或推送。
