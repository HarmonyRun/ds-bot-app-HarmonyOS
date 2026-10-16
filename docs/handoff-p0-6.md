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
