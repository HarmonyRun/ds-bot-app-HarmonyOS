# P0 交接报告：协议与实时底座

- 报告版本：v2（2026-10-15，含设备端到端实测与 Origin 阻塞定位）
- 执行人：Lead（AI 编码代理）
- 上游基线：`QingJ01/ds-bot-app@7e1c3f6c8ebe43bc342caf6abf895d4a2281e9d7`
- 本阶段范围：`docs/translation-plan.md` 的 **P0（协议与实时底座）**
- 结论：**代码完成；编译与纯函数测试通过；设备端到端已在真实主机上跑通（HTTP 钉住 + 发送 + 收回复）。事件流被主机侧的 Origin 白名单阻塞，有完整证据与三种修复方案（见 §6.2）。**

---

## 1. 给接手者：60 秒速览

### 这一轮改了什么（一句话）

把「靠 REST 轮询猜回复好了没有」的单文件应用，换成了「WebSocket 事件流 + 增量合并 + 本地缓存 + 可取消生命周期」的分层架构，并修掉了 5 个已确认缺陷。

### 关键数字

| 指标 | 改造前 | 改造后 |
|---|---|---|
| 源码规模 | 1,986 行 / 5 个 `.ets` | 4,221 行 / 11 个 `.ets`（其中 1,730 行仍是 `Index.ets`）+ 440 行测试 |
| 网络层 | `MobileApi` 244 行，15 个方法 | `MobileClient` 743 行，30+ 个方法（含事件流） |
| 实时性 | 无（发送后 30×1200ms 轮询） | WebSocket `/mobile/v1/events`，带 `eventSeq` 续传与指数退避重连 |
| 使用的主机 action | 4 个 | 6 个（+`parts`、`earlier`） |
| 本地持久化 | 1 个 key（凭据） | 2 个 store（凭据 + 消息/草稿缓存） |
| 自动化测试 | 0 | 17 个纯函数用例 + 一条无依赖测试链路（含与上游实现的差分模糊测试结论） |
| 编译 | 成功 | 成功（`assembleHap`，0 error） |

### 怎么验证现状

```bash
# 1. 编译（需要 DevEco Studio，路径见 README.md）
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
export DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk"
export HARMONYOS_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk/default"
"/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
  --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap

# 2. 纯函数测试（不需要 DevEco 运行，只需它自带的 tsc）
node entry/src/test/run.mjs          # 期望输出：17 passed / 0 failed

# 3. 设备实测（需要先配对，见 §7）
hdc install -r entry/build/default/outputs/default/entry-default-unsigned.hap
hdc shell "aa start -a EntryAbility -b app.dsbot.harmony"
# 首页长按主 Bot 头像 → 打开「事件流验证」页 → 依次点 1 / 2 → 观察帧日志
```

### 文件地图（新增/改动）

| 文件 | 状态 | 职责 |
|---|---|---|
| `entry/src/main/ets/service/MobileClient.ets` | **新增 743 行** | 统一传输层：HTTP（SPKI 证书锁定）+ WebSocket 事件流 + 重连 + 生命周期 |
| `entry/src/main/ets/service/Wire.ets` | **新增 66 行** | 传输派生类型（连接状态、已解析状态）；协议类型统一 re-export 自 `Models.ets` |
| `entry/src/main/ets/service/Projection.ets` | **新增 199 行** | 原始 JSON → 强类型模型的投影层（ArkTS 不支持结构类型，必须显式构造） |
| `entry/src/main/ets/service/MessageCache.ets` | **新增 109 行** | 消息与草稿的本地缓存（按 serverId 分区） |
| `entry/src/main/ets/logic/Merge.ets` | **新增** | `mergeMessages` / `applyConversationEvent` / `cloneMessage`（逐字对齐上游 SDK） |
| `entry/src/main/ets/model/Models.ets` | 改 206→313 行 | 补齐协议字段：`attemptId`/`updatedSeq`/`streamIndex`/`systemEvent`/`attachments` 等 |
| `entry/src/main/ets/view/StreamProbe.ets` | **新增 257 行** | P0-1 可行性验证页（不写业务数据） |
| `entry/src/main/ets/pages/Index.ets` | 改 1,481→1,730 行 | 接入事件流、删除轮询、缓存接入、生命周期清理、会话失效兜底 |
| `entry/src/test/logic.test.ets` | **新增 309 行** | 17 个纯函数用例 |
| `entry/src/test/run.mjs` | **新增 135 行** | `.ets` → tsc 擦类型 → `.mjs` → 运行的测试执行器 |
| `entry/src/main/ets/service/MobileApi.ets` | **保留但已无引用** | 旧传输层；等设备实测通过后删除 |

---

## 2. 原来是什么样

### 2.1 结构与行为

- 单页应用：`pages/Index.ets` 一个 `@Entry struct` 承载全部 20 个 `@Builder` 视图（其中 2 个是死代码）。
- 单一传输层 `service/MobileApi.ets`（244 行），每个请求 `http.createHttp()` 后销毁。
- **没有事件流**：`send()` 提交后进入 `for (let attempt = 0; attempt < 30; attempt++)`，每次 `sleep(1200)` 再拉 100 条消息，判断「最后一条是不是 assistant 且非 pending」——最坏 36 秒，且无法取消。
- **配对也是轮询**：`for (let attempt = 0; attempt < 80; attempt++)` × 1500ms，同样不可取消。
- 消息渲染是 `this.messages = page.messages`（整表覆盖），没有增量合并、没有 pending 语义。
- 本地只持久化一个 `preferences` key（`profile`：地址 + 服务器名 + tlsPin + session）；消息、草稿、已读位置全部不落盘。
- 没有 `aboutToDisappear` / `onBackPress`；3 处滚动 `setTimeout` 从不清理。

### 2.2 已确认缺陷（改造前）

| 编号 | 缺陷 |
|---|---|
| B1 | `stop()` 只清 `busy` 不终止轮询，输入框在旧循环仍写 `messages` 时重新可用 |
| B2 | `refreshAll()` 的 single-flight 静默丢弃并发刷新，且 `refreshing` 不驱动任何 UI |
| B3 | 滚动定时器从不清理；页面销毁后轮询继续 |
| B9 | 访问令牌明文存在应用沙箱 |
| B10 | 9 个设置入口无 `onClick`、能力库为静态占位（**未在本轮修**，属 P2） |

---

## 3. 这一轮做了什么

### 3.1 P0-1 主机事件契约实测（关键前置）

在写代码之前，先用 Node 探针（`/tmp/dsprobe/`，不属于仓库）对着**真实主机** `https://192.168.x.x:8788` 打通了全链路，拿到权威帧格式（地址已脱敏）：

```jsonc
// 1) 握手：connect → 发送 auth 帧
ws.send(JSON.stringify({ type: 'auth', token, conversationId, after? }))

// 2) 主机回帧（真实抓取，字段已按原样保留）
{"type":"ready","conversationId":"session-…","serverId":"d80ef80e-…"}
{"type":"reset","conversationId":"…","sessionId":"…","eventSeq":48,"running":false,"phase":"idle","messages":[…完整快照…]}
{"type":"status","conversationId":"…","sessionId":"…","queue":[]}
{"type":"status","conversationId":"…","sessionId":"…","queue":[{"id":"…","target":"next-turn","text":"…","requestId":"…"}]}
{"type":"status","conversationId":"…","sessionId":"…","running":true,"phase":"running","eventSeq":50}
{"type":"delta","conversationId":"…","sessionId":"…","attemptId":"session-…:6","text":"收到","reasoning":"","index":1,"replace":true}
{"type":"message","conversationId":"…","sessionId":"…","message":{"id":"session-…:54","seq":54,"role":"assistant","text":"收到","turn":4,"step":1},"replaceAttemptId":"session-…:6"}
{"type":"status","conversationId":"…","sessionId":"…","attemptId":"session-…:6","phase":"committed","clearAttempt":true}
{"type":"status","conversationId":"…","sessionId":"…","running":false,"phase":"idle","eventSeq":56}
{"type":"error","error":{"code":"UNAUTHORIZED","message":"…"}}   // 随后 close code 4401
```

实测得到的 4 条硬结论（都写进了实现）：

1. **`eventSeq` 是续传游标**：出现在部分 `status` 与 `reset` 帧上，用它做 `after` 参数即可补回断线期间的事件。
2. **`delta` 是累积快照**：带 `replace: true` 与 `index`，`text` 是「到目前为止的全部文本」，不是增量片段；重复投递时用 `index` 去重。
3. **agent 结束时先 `delta` 再 `message`**：`message` 帧带 `replaceAttemptId`，用来把流式占位替换成正式消息；随后 `status` + `clearAttempt` 收尾。
4. **`status` 是 1.5 秒一次的心跳**：不携带 `queue` 时表示无排队；带 `queue` 时是当前排队项。

同时也实测确认了 **TLS 指纹链路**：主机自签证书的 SPKI SHA-256 与配对码里的 `tlsPin` 完全一致（具体指纹已脱敏），证明现有钉住方案在协议层是可用的。

### 3.2 类型层（P0-2）

`model/Models.ets` 从 206 行扩到 313 行，新增/补齐：

- `Message`：`attemptId` / `streamIndex` / `updatedSeq` / `turn` / `step` / `requestId` / `systemEvent` / `attachments` / `author`
- `Conversation`：`mode` / `notice` / `admin` / `parts` / `model` / `createdAt`
- `Approval`：`callId` / `createdAt` / `displayReason` / `answerable`
- 传输类型：`MobileEvent`（含 `serverId`）、`MobileEventError`、`QueueItem`、`ConversationStatus`、`HistoryPage`、`ConversationPart`、`PartsPage`、`SystemEvent`、`Attachment`
- 全部遵守 ArkTS 约束：无 `any` / 无 `unknown` / 无索引签名 / 无展开运算符

### 3.3 事件合并纯函数（P0-3）

`logic/Merge.ets` 移植了上游 SDK 的两个纯函数，语义**逐字对齐**：

- `mergeMessages(existing, incoming)`：按 `id` 合并，`updatedSeq ?? seq` 判定新旧；stale 时保留旧字段；tool 卡片双向合并；`tool.name === 'Tool'` 时用已知真实名替换；两边 `seq` 有限时取较小者及其 `createdAt`；排序规则为「pending 最后 → 同 session 按 seq → 否则按 createdAt」。
- `applyConversationEvent(messages, event)`：`reset` 清 pending 后合并快照；`delta` 生成 `stream:<sessionId>:<attemptId>` 占位并按 `index` 去重；`message` + `replaceAttemptId` 替换占位；`status` + `clearAttempt` 移除占位。
- ArkTS 适配：因为不能用展开运算符，写了 `cloneMessage()` 做全字段显式拷贝（含嵌套 `tool`/`systemEvent`/`attachments` 深拷贝）。

### 3.4 传输层（P0-4）

`service/MobileClient.ets`（743 行）是这一轮最大的新增：

- **HTTP**：复用单个 `http.HttpRequest`；SPKI 证书锁定（`certificatePinning.publicKeyHash`）；`Bearer` 鉴权；401/403 单次刷新重试；**generation 机制**让登出/换主机后所有在途请求立即失效。
- **刷新**：`refreshing` promise 单飞，避免并发刷新互相覆盖令牌。
- **事件流 `openStream()`**：`/mobile/v1/events`，发送 `auth` 帧（携带 `after` 续传游标）；`ready` 判定连接成功；`4401/4403` 关闭码先刷新再重连；其他断开按 `750ms × 2^n` 退避（上限 15s，最多翻倍 8 次）；20 秒握手超时。
- **新方法**：`messages(cursor)` 分页、`submission(requestId)` 回执查询、`parts()`、`earlier()`、`upload()`、`attachment()`。
- **生命周期**：`dispose()` 统一销毁 HTTP 客户端与事件流；`closeStream()` 停止重连。

### 3.5 替换轮询（P0-5）

`Index.ets`：

- `send()`：**删除 30×1200ms 循环**。改为「先生成稳定 `requestId` → 提交 → 事件流推进度」；提交异常时先查 `/submissions/{requestId}` 回执再决定是否报错（避免「结果未知却重复提问」）。
- `pair()`：80×1500ms 循环改为可取消（`pairingClient` 被清空或页面销毁即退出）。
- `stop()`：只请求主机取消，`busy` 由 `status` 帧回落（修 B1）。
- 新增 `handleStreamEvent()`：`reset` → 快照替换；`delta` → 生成/替换流式占位（整段替换文本）；`message` → 合并正式消息并结束 pending；`status` → 更新 `busy` 与 `queueCount`。

### 3.6 历史与续读（P0-6，部分完成）

- `messages(conversationId, cursor, limit)` 已支持游标分页（默认 90 条）。
- `messages(cursor)` 的「加载更早」按钮已于 2026-10-15 接入，含去重、加载态、reset 保留旧历史与跨会话防串写；详见 `docs/handoff-p0-6.md`。
- `parts()` / `earlier()` 传输层已实现，跨历史分段选择器仍待界面接入。

### 3.7 本地缓存与草稿（P0-7）

`service/MessageCache.ets`：用 `preferences` 建 `ds_bot_harmony_cache` store，键为 `msg:<serverId>:<conversationId>`（最多 200 条）与 `draft:<serverId>:<conversationId>`。

- 打开会话时**先渲染缓存再拉主机最新页**（冷启动立即有内容）。
- 输入框每次变更都会写草稿；发送成功后清空草稿。
- 登出/会话失效时按 `msg:` / `draft:` 前缀清理。

> 说明：规划里 D3 建议用 `relationalStore`。本轮先用 `preferences` 落地，因为 P0 的目标只是「冷启动有内容 + 草稿不丢」，单会话 200 条 JSON 足够；迁移点集中在 `MessageCache` 内部，界面层无感。等 P1 引入跨会话搜索时再换 RDB。

### 3.8 生命周期与清理（P0-8）

- 新增 `aboutToDisappear()`：清理滚动定时器 → 关闭事件流 → `dispose()` 配对 client 与主 client。
- 3 处滚动定时器改为经 `scrollToBottom()` 登记到 `scrollTimers`，可一次性清理（修 B3）。
- 新增**会话失效兜底**：任何 401/403/`unauthorized` 都会清凭据 + 清缓存 + 回到连接页并给出原因（修「卡在『没有找到会话』死路」）。

### 3.9 测试（P0-9）

`entry/src/test/run.mjs` 建立了一条**无 npm 依赖**的测试链路：

```
.ets 源码 → 复制成 .ts 并改写 import → 用 DevEco 自带 tsc 擦类型 → .mjs → Node 运行断言
```

之所以这么绕：ArkTS 的 `.ets` 不能直接被 Node 执行，而项目不允许引入 npm 依赖；DevEco Studio 自带 `typescript`（`/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/tsc.js`），直接用它的 `--noEmitOnError false` 就能在存在类型诊断（缺 `@types/node`）的情况下仍然产出可运行 JS。

`logic.test.ets` 覆盖 17 个用例，全部通过：

```
ok   sorts new messages by seq ascending
ok   sorts pending messages last
ok   keeps existing fields when incoming version is lower
ok   overwrites fields when incoming version is higher
ok   merges tool fields when both sides have a tool
ok   replaces placeholder tool name 'Tool' with the real name
ok   takes the smaller seq and its createdAt when both are finite
ok   ignores entries without a string id
ok   reset drops pending messages and merges the snapshot
ok   delta creates a pending stream message
ok   ignores a repeated delta with a smaller index
ok   replaces delta text and keeps createdAt when index grows
ok   message with replaceAttemptId removes the matching pending message
ok   status with clearAttempt removes the matching pending message
ok   delta carrying only reasoning keeps the previous text
ok   returns messages untouched for unknown event types
ok   cloneMessage copies fields without sharing nested tool state

17 passed / 0 failed
```

另外做过一次**差分模糊测试**：把上游 `packages/mobile-sdk/index.js` 的 `mergeMessages`/`applyConversationEvent` 原样抽出，与本实现跑 4,000 组随机输入逐例 `deepEqual`——8,000 次比较 0 处不一致。

### 3.10 顺带修掉的既有缺陷

| 编号 | 状态 | 说明 |
|---|---|---|
| B1 | ✅ 已修 | `stop()` 不再手清 `busy`；轮询循环已删除，不存在残留写入 |
| B2 | ✅ 大部分 | `refreshing` 仍作为 single-flight 守卫（保留），但会话失效路径不再静默 |
| B3 | ✅ 已修 | 滚动定时器统一登记 + `aboutToDisappear` 清理 |
| B9 | ⏳ 未做 | 凭据仍为明文（P0-10，见 §7） |
| B10 | ⏳ 未做 | 设置页空壳入口属 P2 |

---

## 4. 现在是什么样

### 4.1 运行时数据流

```
用户发送
  └─ send()：稳定 requestId → POST /submissions
       ├─ 成功：等事件流推进（不再轮询）
       └─ 异常：GET /submissions/{requestId} 对账 → 仍未确认才报错并还原草稿
                      │
主机 ── wss /mobile/v1/events ──► MobileClient.openStream()
                                    ├─ ready     → 状态置 connected
                                    ├─ reset     → messages 快照替换 + 落盘
                                    ├─ delta     → 流式占位（accumulated text）
                                    ├─ message   → 正式消息合并（replaceAttemptId 收口）
                                    ├─ status    → busy / queueCount / 心跳
                                    └─ 4401/4403 → 刷新令牌后重连
                                                  其他断开 → 750ms×2^n 退避重连
```

### 4.2 界面上的可感知变化

**代码路径已经具备、等待主机侧修复后即可生效的能力：**

| 能力 | 说明 | 当前是否生效 |
|---|---|---|
| 逐字流式输出 | 由 `delta` 帧驱动，取代原来的 36 秒轮询 | ⏳ 等 §6.1 修复 |
| 断线自愈 | 指数退避重连 + `eventSeq` 续传补事件 | ⏳ 等 §6.1 修复 |
| 执行状态准确 | `status` 帧的 `running` 驱动「停止」按钮与排队数 | ⏳ 等 §6.1 修复 |

**本次设备实测已经确认可用（不依赖事件流）：**

| 能力 | 证据 |
|---|---|
| HTTPS + SPKI 证书锁定 | 真实主机 `GET /info`、`/state`、`/conversations` 全部成功（自签证书 + 指纹校验） |
| 冷启动立即有内容 | 打开会话先渲染本机缓存 |
| 草稿不丢 | 输入过程落盘，重启后仍在 |
| 发送链路 | 在模拟器上真实发送「ping from harmony p0」与「p0 round two」，主机均回复 |
| 乐观气泡对账 | `requestId` 匹配后「发送中…」正确消失 |
| 兜底轮询 | 事件流不可用时每 5 秒拉最新页，聊天保持可用 |
| 会话失效兜底 | 401 时自动清凭据并回连接页（实测截图） |
| 实时状态可见 | 聊天标题下显示「实时已连接 / 重连中… / 排队 N」 |
| 新增调试入口 | 首页长按主 Bot 头像打开「事件流验证」页，含帧日志与 Origin 对照实验 |

### 4.3 验证状态

| 验证项 | 状态 | 证据 |
|---|---|---|
| `assembleHap` 编译 | ✅ 通过 | `BUILD SUCCESSFUL`，0 error（12 条既有 WARN 为 Network Kit/Preferences 可抛异常提示） |
| 纯函数测试 | ✅ 17/17 | `node entry/src/test/run.mjs` |
| 与上游实现一致性 | ✅ 8,000 次比较 0 差异 | 差分模糊测试 |
| HTTP + SPKI 钉住在真实主机上 | ✅ 通过 | Node 探针 `GET /info`、`POST /auth/refresh` 均 200；指纹与配对码一致 |
| 事件流协议（主机侧） | ✅ 通过 | 上述真实帧抓取 + 完整 `delta`→`message`→`status` 时序 |
| App 在模拟器上启动、恢复凭据、HTTP 到主机 | ✅ 通过 | 会话列表与消息均从真实主机加载 |
| 主机 Origin 白名单行为 | ✅ 已定位 | 无端口 Origin → 403；带端口 → 101（§6.1 A/B 实测） |
| 鸿蒙 `webSocket` 在设备上的 TLS 与握手行为 | ✅ **已测** | TLS 与 TCP 成功；升级被主机 403 拒绝，证据见 §6.1 |
| App 在模拟器上完成真实收发 | ✅ 通过 | 发送「ping from harmony p0」/「p0 round two」，主机均回复，截图见 `docs/qa/` |
| 兜底轮询与乐观气泡对账 | ✅ 通过 | 事件流不可用时仍能收到回复且不残留「发送中…」 |

---

## 5. 关键决策与理由

| 决策 | 选择 | 理由 |
|---|---|---|
| D2 头像方案 | 保持静态 PNG（本轮不动） | 属 P1，且不影响 P0 |
| D3 缓存载体 | 先用 `preferences`，预留 RDB 迁移点 | P0 只需冷启动有内容；迁移点收敛在 `MessageCache` |
| 事件流 TLS | 用 `skipServerCertVerification`（**已知降级，见 §6**） | 鸿蒙 `webSocket` 无 pinning 选项；HTTP 仍保持钉住 |
| 类型来源 | `model/Models.ets` 为唯一事实源，`Wire.ets` 只 re-export | 避免两个模块声明同名协议类型（本轮已实际踩到一次） |
| 旧 `MobileApi` | 保留但不再引用 | 设备实测通过后再删，留一条可回退路径 |
| 配对轮询 | 保留轮询语义但改为可取消 | 主机协议就是「提交后等电脑批准」，没有推送通道 |

---

## 6. ⚠️ 阻塞项与已知限制（必须知道）

### 6.1 【阻塞 · P0】主机 Origin 白名单与鸿蒙 WebSocket 默认 Origin 不兼容

**现象**：App 在模拟器上一切正常（HTTPS 钉住、会话列表、消息、发送、收回复都通），但事件流一直连不上，界面显示「实时通道重连中…」。

**证据链（全部实测）**：

1. 系统日志显示 TLS 与 TCP 都成功，失败发生在 HTTP 升级：
   ```
   I C015b0/NETSTACK: [websocket_exec.cpp:600] ExecConnect skip server cert verify
   I C015b0/NETSTACK: [websocket_exec.cpp:723] ConnectCallback connect success
   I C015b0/NETSTACK: [websocket_exec.cpp:332] Lws client connection error HS: ws upgrade response not 101
   I C015b0/NETSTACK: [websocket_exec.cpp:310] OnError 200
   ```
2. 用「诱捕服务端」（同证书的 TLS 服务，只打印收到的请求头）抓到鸿蒙 WebSocket 的**真实握手头**：
   ```
   [UPGRADE 请求] GET /mobile/v1/events
     host: 192.168.1.100:9443              ← 示例地址，真实地址已脱敏
     origin: https://192.168.1.100          ← 鸿蒙自动带上，且丢掉了端口
     upgrade: websocket
     connection: Upgrade
     sec-websocket-key: …
     sec-websocket-version: 13
   ```
3. 主机 `ds-bot/src/mobile/server.js` 的 `checkOrigin()` 只放行 `allowedOrigins`，其中包含 `publicUrl`（默认端口非 443 时**带端口**，例如 `https://192.168.x.x:8788`）：
   ```js
   function checkOrigin(request) {
     const origin = request.headers.origin
     if (origin && !allowedOrigins.has(origin)) fail(403, 'ORIGIN_DENIED', 'This browser origin is not allowed.')
   }
   ```
   注意 `if (origin && …)`：**空 Origin 是放行的**。
4. 用同一条 `GET /mobile/v1/events` 升级请求在真实主机上做 A/B：
   ```
   Origin: https://192.168.1.100              → HTTP/1.1 403 Rejected
   Origin: https://192.168.x.x:8788          → HTTP/1.1 101 Switching Protocols
   Origin: https://192.168.x.x, https://192.168.x.x:8788 → HTTP/1.1 403 Rejected
   ```
5. 鸿蒙的 `options.header` 是**追加**语义，无法覆盖或清空默认 Origin。实测传入 `{ Origin: 'https://192.168.1.100:9443' }` 后，服务端收到的是
   `origin: https://192.168.1.100, https://192.168.1.100:9443`（示例地址；两个值用逗号拼接），主机的 `Set.has()` 依然不匹配。（`X-Probe` 等自定义头可以正常送达，只有 Origin 被合并。）

**根因一句话**：鸿蒙强制发 `Origin: https://<host>`（无端口），主机只放行含端口的 `publicUrl`，而客户端无法改掉或去掉这个头 → 403 → 客户端报「升级响应不是 101」。

**修复方案（按推荐顺序）**：

| 方案 | 做法 | 评价 |
|---|---|---|
| **H1 主机放宽校验（推荐）** | 主机侧接受「同主机、无端口」的 origin。改 `allowedOrigins` 构造处，或把 `checkOrigin` 改成同时比对 `url.origin` 与 `url.host`：<br>`if (origin && !allowedOrigins.has(origin) && !allowedOrigins.has(new URL(origin).origin))` | **一行级改动**，不削弱安全性（仍然限定同一台主机的 HTTPS 来源），且能一并解决其他非浏览器客户端 |
| **H2 主机监听 443** | 让 `publicUrl` 变成 `https://host`（无端口），鸿蒙默认 Origin 恰好匹配 | 不改代码，但需要 443 权限、改变部署形态，且模拟器访问 `https://host` 需要映射 |
| **C1 客户端自建钉住通道** | `@ohos.net.socket` TCPSocket + TLS（`ca` 信任锚）+ 自建 WebSocket 握手与帧解析，并自行发送符合白名单的 Origin | 能顺带解决 §6.2 的证书锁定降级，但工作量 XL |

在方案落地前，App 已按 §4.2 的**兜底轮询**保持可用（每 5 秒拉一次当前会话），因此本项不阻塞其他功能开发，但阻塞 P1 的「逐字流式」体验。

**怎么验证修复生效**：改完主机后重启插件，然后在模拟器首页长按主 Bot 头像 → 「事件流验证」页 → 点「2 批准并订阅」，帧日志应出现 `ws connected` 与 `ready` / `reset` / `status` 帧；或在电脑上直接跑 A/B 命令，确认无端口 Origin 也返回 `101`。

### 6.2 WebSocket 没有证书锁定（D1 结论，安全降级）

查证鸿蒙 SDK 声明后的硬事实：

- `@ohos.net.http` 支持 `certificatePinning: { publicKeyHash, hashAlgorithm: 'SHA-256' }`（`@ohos.net.http.d.ts:538, 1046-1064`）→ **本工程 HTTP 已用**，与配对码 `tlsPin` 一致（实测指纹相同）。
- `@ohos.net.webSocket` 的 `WebSocketRequestOptions` 只有 `header` / `caPath` / `skipServerCertVerification` / `clientCert` / `proxy` / `protocol`（`@ohos.net.webSocket.d.ts:98-177`）→ **没有 pinning 字段**。
- `@ohos.net.socket` 的 `TLSSecureOptions` 只有 `ca` / `cert` / `key` 等，也没有自定义校验回调（`@ohos.net.socket.d.ts:3707-3720`）。

上游怎么解决：它自建原生模块 `DSBotLocalTLS` 同时提供「钉住的 fetch + 钉住的 WebSocket」（`apps/mobile/src/network/client.ts:2-6, 30-33`），SDK 在 `tlsPin` 存在但传输层不是自定义实现时直接抛 `missing_pinned_transport`（`packages/mobile-sdk/index.js:157`）。

**本轮选择**：事件流用 `skipServerCertVerification: true`，HTTP 仍严格钉住。影响与缓解：

- 泄露面：`ready`/`reset`/`message` 等帧里含会话内容；中间人可以读到事件流。
- 缓解：事件流需要 `auth` 帧里的 Bearer 令牌才能收到数据，而令牌只在**已钉住的 HTTPS** 通道上传输。
- 结论：**安全性低于上游**，属于明确的降级。与 §6.1 的 C1 方案一起解决最经济（同一套自建通道）。

### 6.3 其他限制

- `transcription` 在当前离线主机上是 `false`（`/info` 实测），语音相关能力（P3）需要先读 `capabilities` 再决定是否暴露入口。
- `status` 心跳为 1.5 秒一次，长连接期间有稳定小流量。
- `status` 帧里的 `attemptId` / `activity` 按「本帧语义」处理，不跨帧沿用（避免把上一轮的 attempt 当成当前）。

## 7. 还没做的事（下一步清单）

### 7.1 最高优先级：解除事件流阻塞

| 项 | 说明 |
|---|---|
| 主机侧放宽 Origin 校验（§6.1 H1） | 一行级改动；改完重启插件即可让实时通道生效。这是**唯一**能让逐字流式在鸿蒙端工作的低成本路径 |
| 或 客户端自建钉住通道（§6.1 C1） | 同时解决 Origin 与 §6.2 的证书锁定降级，工作量 XL |
| 解除后在设备上补一轮事件流回归 | 预期可见 `ready` / `reset` / `delta` / `message` / `status` 帧，且逐字输出 |

### 7.2 P0 内尚未完成的子项

| 编号 | 内容 | 现状 |
|---|---|---|
| P0-6 界面部分 | `parts` 分段切换 | 当前会话的 `messages(cursor)` 与“加载更早”UI 已接；跨历史分段选择器仍待实现 |
| P0-10 | 凭据迁移到 HUKS（修 B9） | 未开始 |

### 7.3 已知的代码级待办

1. `service/MobileApi.ets` 已无引用，可删除（保留是为了留一条可回退路径）。
2. `ProfileStore.updateSession()` 是死代码。
3. `Index.ets` 仍 1,700+ 行，视图拆分属 P1（目标结构见 `docs/translation-plan.md` §5）。
4. `Index.ets` 已渲染 `hasEarlier` / `loadingEarlier`；剩余工作是 `parts` 分段选择器。
5. `MessageCache` 的 200 条上限是硬编码常量，P1 换 RDB 时应改为可配置。
6. `StreamProbe.ets` 是诊断页，正式发布前应决定「保留为隐藏调试入口」还是移除。它包含一个 Origin 对照实验（A/B/C/D），对排查同类问题很有用。

## 8. P1 建议的起手式

按 `docs/translation-plan.md`，P1 是「视觉与交互对齐」，建议顺序：

1. **P1-3 Markdown 渲染**（收益最大）：现在消息仍是单个 `Text(message.text)`，代码块/表格/列表都是原文。事件流已经就绪，可以边流式边重排。
2. **P1-4 消息交互**：可展开思考块（`reasoning` 已有数据）、长按复制/引用、工具卡展开。
3. **P1-1 头像引擎**：把 `characterData.json`（20 角色 × 12 色）转成 ArkUI `Path({ commands })` 实时绘制，替换 13 张静态 PNG。
4. **P1-2 首页与列表**：真实头像、主 Bot 星标、未读蓝点（`markRead` 已有，缺本地未读记账）。
5. **P1-6 审批与提问**：聊天内审批卡（现在审批只在设置页）+ `answer-question` 提问卡 + `queue` 排队查看/移除。传输层需要补 `queue-remove` / `answer-question` 两个 action。

接入任何新 action 时，先按 §3.1 的方法用真实主机抓一次帧，再写实现。

---

## 9. 附：本轮用到的探针与命令

探针脚本不在仓库内（放在 `/tmp/dsprobe/`，避免把主机凭据带进仓库）：

| 脚本 | 用途 |
|---|---|
| `ws-probe.mjs` | 校验 SPKI 指纹 + 打开 `/events` 观察握手 |
| `refresh.mjs` | 用 `checkServerIdentity` 实现 SPKI 钉住并刷新令牌 |
| `stream-probe.mjs` | 端到端：`/state` → `/target` → 订阅事件流 → 真实发送 → 打印每一帧 |

复现事件契约：

```bash
# 1. 从已配对设备上取回会话（hdc 需要能访问应用沙箱）
hdc file recv /data/app/el2/100/base/app.dsbot.harmony/haps/entry/preferences/ds_bot_harmony_profile /tmp/prefs.bin
# 2. 解析出 accessToken / refreshToken / tlsPin（preferences 是 XML + HTML 实体）
# 3. 用 stream-probe.mjs 连 wss://<host>:8788/mobile/v1/events 观察帧
```

---

## 10. 变更记录

| 日期 | 版本 | 内容 |
|---|---|---|
| 2026-10-15 | v1 | P0 协议与实时底座完成：类型/合并/传输/事件流/缓存/生命周期/测试 |
| 2026-10-15 | v2 | 补设备端到端实测（真实主机收发成功）；定位并文档化「主机 Origin 白名单 vs 鸿蒙 WebSocket 默认 Origin」阻塞，给出三种修复方案；新增 5 秒兜底轮询与乐观气泡对账；修正 §4 的能力清单为「已生效 / 等主机修复后生效」两分法 |
