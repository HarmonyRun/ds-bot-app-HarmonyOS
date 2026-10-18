# P0-6 增量交接：聊天历史分页

- 日期：2026-10-15
- 结论：**当前会话的游标分页 UI 已完成并通过 ArkTS 构建；跨历史分段（parts）选择器仍未接界面。**

## 原来是什么样

- `MobileClient.messages(conversationId, cursor, limit)`、`parts()`、`earlier()` 已存在。
- `hasEarlier` / `loadingEarlier` 状态已经声明，但从不使用。
- 聊天永远只显示最新 90 条。
- WebSocket `reset` 直接用空数组重建消息，会把用户刚加载的旧历史清掉。
- `loadMessages()` 没记录请求发起时的 conversationId，快速切换会话存在旧响应回写风险。

## 做了什么

1. 新增 `historyCursor` 和初始化标记；最新页首次返回时保存主机 cursor。
2. 手机与宽屏共用原生“加载更早消息”按钮，仅在 cursor 非空时出现。
3. 点击后按 cursor 拉 90 条，使用 `mergeMessages()` 去重并按协议顺序合并。
4. 加载旧页后不调用 `scrollToBottom()`，避免读历史时被强制拉回最新消息。
5. cursor 为空即隐藏入口；离线或加载中禁用重复请求。
6. `reset` 改走已有且已测试的 `applyConversationEvent()`：删除 pending 占位，但保留已加载的正式历史。
7. `loadMessages()` 捕获 conversationId，响应返回时再次比对，防止跨会话串写。

## 现在是什么样

- 少于一页的聊天不显示无意义按钮。
- 长聊天可以逐页向前读取，直至主机不再返回 cursor。
- 新事件和 reset 不会清空已加载历史。
- 切换会话会重置分页游标和加载态。
- 合并后的消息继续写入本机缓存。

## 验证

```text
node entry/src/test/run.mjs
68 passed / 0 failed

hvigor ... assembleHap
BUILD SUCCESSFUL，0 error
```

现有 Merge 用例已经覆盖 `reset drops pending messages and merges the snapshot`。当前 `hdc` 无设备，真实 90 条以上会话的连续翻页仍待设备恢复后验证。

## 仍未完成

上游还提供“会话历史分段”Sheet：先调 `parts` 选择 session，再按该 part 的 cursor 浏览。HarmonyOS 目前只完成当前链路的连续游标分页，尚无 parts 选择器；不要把 P0-6 整体标为完成。

---

## 2026-10-17：跨历史分段（parts）选择器已完成

上一版遗留的「会话历史分段 Sheet」已补上，P0-6 可标为完成。

### 做了什么

**协议**：`MobileClient.parts(conversationId)` → `PartsPage{currentSessionId, parts[]}`，
每个 `ConversationPart` 带 `sessionId / number / current / cursor / startedAt / endedAt`；
按某分段读取用 `MobileClient.earlier(sessionId, cursor)`。

**状态**（`Index.ets`）：

| 字段 | 作用 |
|---|---|
| `parts` / `partsLoadedFor` | 分段列表 + 按会话缓存，避免重复请求 |
| `partsVisible` | 原生 `bindSheet` 开关 |
| `viewingPartSessionId` / `viewingPartNumber` | 正在查看的历史分段 |
| `partCursor` / `partHasEarlier` | 该分段自己的翻页游标 |

**交互**：

- 消息列表顶部新增「历史分段（N）」入口，**仅在主机返回多于 1 段时出现**；
- 点击打开原生 `bindSheet`，列出「第 N 段 / MM-DD HH:mm 范围 / 当前标记」；
- 选择较早分段 → `earlier(sessionId, cursor)` 拉该段消息，顶部显示
  **「正在查看历史分段 · 第 N 段」横幅 + 回到当前**；
- 分段内可继续「加载更早消息」，走该分段自己的 cursor；
- 「回到当前」或**系统返回**都会退出历史视图；
- 查看历史时**输入栏禁用**（发送属于当前分段）。

### 两个必须处理的正确性问题

1. **实时事件隔离**：查看历史分段时，当前分段的 `reset/delta/message` 事件
   **不能写入消息列表**，否则历史与实时混在一条时间线上。
   `handleStreamEvent` 在 `viewingPartSessionId` 非空时跳过（`status` 仍处理）。
2. **切换会话必须清空分段状态**：否则会把上一条会话的 parts/游标带到新会话
   （防串会话）。

### 验证（折叠屏模拟器 + 受控 mock）

mock 新增 `parts` / `earlier` 两个 action（3 个分段，第 3 段为当前）。

```
选择分段 number=1 current=false cursor=p1-c0
分段首屏 messages=2 cursor=part-1-older
分段翻页返回 messages=1 cursor=
合并后总数=3
```

| 检查项 | 结果 |
|---|---|
| 「历史分段（3）」入口出现 | ✅ |
| Sheet 列出 3 段 + 「当前」标记 + 日期范围 | ✅ `docs/qa/p1/device-parts-sheet.jpeg` |
| 选择第 1 段 → 加载该段消息 + 横幅 | ✅ |
| 分段内「加载更早消息」→ 合并到 3 条、按钮消失 | ✅ |
| 「回到当前」→ 横幅消失、恢复当前会话 | ✅ |
| 布局越界 | ✅ 0 |
| 构建 / 纯逻辑测试 | ✅ `BUILD SUCCESSFUL` / 113 passed |

### 踩到的两个坑（mock 自身的，非 App 缺陷）

1. mock 的 `parts/earlier` 处理里把**整个请求体**当成了动作参数，实际参数在
   `payload.payload` —— 导致 cursor 永远被读成空串、分页永远返回同一页。
2. 日志只记 path 不记 query，无法判断分页参数是否发出（已在 mock 里补 query 记录）。

> 教训同上一次分页验收：**验证工具本身要能观察到被测行为**，
> 否则「点了没变化」会被误判成 App 的问题。

### 仍未验证

- 真实主机（DSH 生产环境）的 `parts` 响应形状：mock 完全按协议文档构造，
  真机尚未产生过 >1 分段的会话，因此**多分段实景未验证**；
- 分段数量很多（>10）时的 sheet 滚动表现未测。
