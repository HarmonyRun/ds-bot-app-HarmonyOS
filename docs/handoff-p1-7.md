# P1-7 交接报告：群聊成员进度与停止任务

- 日期：2026-10-15
- 范围：`docs/translation-plan.md` 的 **P1-7**
- 上游参照：`apps/mobile/src/components/GroupProgress.tsx`
- 结论：**代码、纯逻辑测试和 ArkTS 构建已完成；当前 `hdc list targets` 为 `[Empty]`，且设备会话此前已经过期，所以真实群聊进度、停止动作与截图仍待模拟器重新连接和配对后验收。**

## 1. 原来是什么样

| 能力 | 改前状态 | 影响 |
|---|---|---|
| 群消息作者 | 已能显示作者头像与名字 | 已完成，但没有群聊实测证据 |
| `/state.work` | `RawState` 和 `TeamState` 没有模型 | 无法知道哪些成员正在工作或等待审批 |
| `room-progress` | 没有 action、解析或轮询 | 群聊运行时无法显示成员输入、回看、回复或失败状态 |
| `stop-member-work` | 没有入口 | 手机端不能单独停止某个群成员任务 |
| 生命周期 | 只有消息、审批和兜底轮询清理 | 若直接新增 1 秒轮询，容易在切会话或退后台后泄漏 |

早先交接报告写着“返回结构未知”。本轮重新核对了上游 `GroupProgress.tsx` 与 `types.ts`，确认真实契约后再实现，没有根据 action 名猜 JSON。

## 2. 做了什么

### 2.1 协议模型与安全投影

`Models.ets` 新增：

- `MemberWork` / `BotWork` / `WorkApproval` / `TeamWork`
- `RoundReply` / `RoomRound`
- `TeamState.work`

`RawState` 新增 `work`。`Projection.toTeamState()` 通过 `toTeamWork()` 投影，不把原始动态对象直接带进 UI。

新增 `logic/GroupProgress.ets`，负责：

1. 过滤缺少 `botId`、`id`、`callId` 或 `replies` 的坏数据。
2. 同时兼容 `work.rooms[roomId]` 与 `work.bots[botId].roomId` 两种工作证据。
3. 只从当前群成员中选出忙碌/待审批成员，避免显示外部或陈旧 Bot。
4. 按上游顺序计算状态：**等待审批 → 正在输入 → 未能回答 → 正在回看聊天 → 已回复 → 工作中**。

顺带修复了一个状态投影问题：上游 `readOnly` 可为 `null`，现在只有字符串才视为只读，避免 `null !== undefined` 导致可写团队被错误禁用。

### 2.2 轮询与生命周期

- 仅在“当前会话是群聊 + 在线 + 正在运行”时每 1 秒调用 `room-progress { roomId }`。
- 运行结束、切换会话、返回列表或页面销毁时立即清理定时器和轮次。
- 使用 generation 防止旧异步请求在切换会话后回写新页面。
- 防止请求重叠；上一次未完成时不会再发第二次。
- `/state.work` 仍随已有 10 秒状态刷新更新，因此即使轮次暂不可用，仍可显示工作中和等待审批。

### 2.3 群进度与停止交互

手机和宽屏聊天共用 `groupProgress()`：

- 原生横向 `Scroll`，窄屏成员多时可自然滑动，不挤压输入栏。
- 每个成员使用现有矢量 `BotAvatarView`；正在输入时有活动点与强调边框。
- 状态胶囊显示成员名和当前状态。
- 有 work 证据时显示原生 `Button`“停止”，调用：

```text
stop-member-work { roomId, botId }
```

- 停止期间防重复点击；只读团队禁用按钮；失败信息显示在进度区。

上游 ChatScreen 默认不显示停止按钮，只在 TeamScreen 开启 `allowStop`。HarmonyOS 当前没有完整群详情页，因此把按钮放在聊天进度胶囊中，让 P1-7 功能可达；后续完成群详情页后可再决定是否迁移。

### 2.4 使用的鸿蒙原生能力

| 场景 | 原生能力 |
|---|---|
| 多成员横向浏览 | ArkUI `Scroll` + `ScrollDirection.Horizontal` |
| 停止单成员 | ArkUI `Button` 的 `enabled` 状态与点击事件 |
| 自适应布局 | 同一 Builder 在手机、平板、折叠屏和 PC 宽屏分支复用 |
| 生命周期清理 | 页面 `aboutToDisappear()` + 定时器显式释放 |

没有新造横向列表、按钮、加载框或生命周期框架。

## 3. 现在是什么样

### 已完成

- 群成员作者、群运行轮次、主机 work/approval 三类证据都已接入。
- 成员状态与上游优先级一致。
- 群聊运行时 1 秒更新，非运行状态不产生高频请求。
- 可单独停止正在工作的群成员。
- 手机与宽屏复用同一组件；进度区位于消息区和输入区之间，不会让底部输入栏下沉。
- 旧请求不会跨会话污染状态。

### 尚缺运行时证据

本轮构建后执行：

```text
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc list targets
[Empty]
```

因此没有安装本轮 HAP，也没有真实群聊截图。代码完成不等于端到端验收完成；状态看板保留为黄色。

## 4. 验证结果

```text
node entry/src/test/run.mjs
12 Avatar + 4 Composer + 4 GroupProgress + 19 Merge + 26 Markdown + 3 Questions
= 68 passed / 0 failed

hvigor ... assembleHap
TYPE CHECK SUCCESSFUL
BUILD SUCCESSFUL，0 error
```

构建产物：

```text
entry/build/default/outputs/default/entry-default-signed.hap
```

新增 4 个 GroupProgress 用例覆盖：

- work 的 rooms/bots/approvals 投影及坏数据过滤
- room-progress 畸形轮次与回复过滤
- 六种成员状态及优先级
- 当前群成员过滤和 `bots.roomId` 兼容

## 5. 文件变更

| 文件 | 变化 |
|---|---|
| `model/Models.ets` | work、审批、轮次、回复模型 |
| `service/MobileClient.ets` | `RawState.work` |
| `logic/GroupProgress.ets` | 新增安全投影、成员状态与筛选纯逻辑 |
| `service/Projection.ets` | 接入 work；规范 `readOnly: null` |
| `pages/Index.ets` | 1 秒轮询、generation 防串写、进度 UI、停止动作、生命周期清理 |
| `test/group-progress.test.ets` | 4 个回归用例 |
| `test/run.mjs` | 纳入 GroupProgress 模块 |

## 6. 下一位开发者如何继续

1. 在 DevEco Device Manager 启动模拟器，确认上面的 `hdc list targets` 不再是 `[Empty]`。
2. 安装并启动签名 HAP。
3. 重新配对；测试会话约 15 分钟过期。
4. 创建至少含两个 Bot 的群聊，让群内成员分别出现回复、lookup、failed、等待审批。
5. 核对横向状态胶囊、活动边框与状态文案。
6. 在成员工作中点击“停止”，确认 action 成功、work 状态消失且其他成员不受影响。
7. 手机竖屏、平板/折叠屏宽屏、PC 窗口至少各测一次，截图放入 `docs/qa/p1/`。

当前目录仍没有 `.git` 元数据，无法在这里直接提交或推送。
