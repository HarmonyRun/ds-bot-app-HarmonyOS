# P1-5 交接报告：输入栏补全

- 日期：2026-10-15
- 范围：`docs/translation-plan.md` 的 **P1-5**
- 上游参考：`QingJ01/DS-Bot-App` 的 `apps/mobile/src/logic/composer.ts`、`ChatScreen.tsx`、`ThinkingLevelPicker.tsx`、`ReferencePicker.tsx`
- 结论：**代码完成，ArkTS 构建与 61 个纯逻辑用例通过；`@` 提及和会话引用已在真实主机端到端验证。当前主机模型未提供可选思考档位，因此思考档位完成了协议、UI 与空态验证，尚无可选值可做写入实测。**

---

## 1. 原来是什么样

| 能力 | 改前状态 | 实际问题 |
|---|---|---|
| 思考档位 | 没有入口；`Wire.ets` 只有一个未使用的 `EffortOption` 类型 | 无法查询模型的 `efforts`，也无法给 Bot 写入 `effort` |
| `@` 提及 | Markdown 只会把已经存在的 `@名字` 高亮 | 输入时没有候选；不知道单聊应排除自身、群聊应只列成员，也没有“所有人” |
| 消息引用 | 长按消息只能插入 Markdown `>` 引用 | 这不是上游的“引用另一个会话”；主机收不到 `dsh-session:` 上下文 |
| 多行与长度 | `TextArea` 固定 48/56 vp，最大 32,000 字符 | 上游协议允许 100,000 字符；引用编码还会占用隐藏长度 |
| 交互实现 | 附件按钮只弹“正在转译中”Toast | 没有使用鸿蒙菜单、Sheet、Search、Select、文本选区控制等原生能力 |

## 2. 做了什么

### 2.1 新增纯逻辑输入模块

新增 `entry/src/main/ets/logic/Composer.ets`，职责集中为：

1. `sessionMention()`：生成 DSH 规范的 `@[label](dsh-session:<base64url(JSON sessionId)>)`。
2. `referenceDraft()` / `composeReferenceDraft()`：把缓存中的隐藏引用头与用户可见正文无损拆合；非法引用不吞正文。
3. `mentionQuery()`：按真实光标与选区查找正在输入的 `@`，排除邮箱、URL、路径、Markdown 代码。
4. `mentionCandidates()`：单聊排除自己；群聊严格按成员列表；多人群聊提供“所有人”。
5. 自带 UTF-8 + base64url 编解码，不依赖 Web API，也不引入三方库。

对应新增 `entry/src/test/composer.test.ets` 4 个回归用例，并接入现有 `run.mjs`。

### 2.2 接通真实协议

| 场景 | 主机 action / 请求 | HarmonyOS 处理 |
|---|---|---|
| 查询思考档位 | `efforts { ref }` | 打开会话时按 Bot 的模型查询；无档位时不占输入区 |
| 写入思考档位 | `update-bot { id, effort }` | 选择“默认”发送 `null`，其他项发送真实 effort id；失败时回滚 UI |
| 读取可引用会话 | `reference-chats { conversationId }` | 每次打开选择器重新读取，避免使用过期授权范围 |
| 发送引用 | 仍走 `/submissions` | 引用编码在草稿头部，与正文一并发送；最大 3 条 |
| `@` 提及 | 普通消息正文 | UI 只辅助生成与主机规则一致的 `@Name `，没有另造协议 |

`Bot` 模型增加 `effort?: string`，`Projection.ets` 同步读取主机状态。

### 2.3 优先使用 HarmonyOS / ArkUI 原生交互

| 需求 | 使用的原生能力 | 没有重复实现的部分 |
|---|---|---|
| “+”操作入口 | `bindMenu(MenuElement[])` | 系统菜单定位、点击外部关闭、键鼠交互 |
| 引用会话选择 | `bindSheet` + `SheetSize.MEDIUM` | 手机底部抽屉与大屏弹层适配、拖拽条、关闭行为 |
| 引用搜索 | `Search` | 输入、清除、键盘与可访问性 |
| 思考档位 | `Select` | 下拉菜单、选中态、键鼠操作 |
| 光标处 `@` 补全 | `TextAreaController` + `onTextSelectionChange` | 光标/选区同步与插入后光标复位 |
| 多设备布局 | 复用同一组 Builder | 手机、平板、折叠屏、2in1/PC 不维护两套协议逻辑 |

引用仍以芯片显示，删除后会重新序列化草稿；输入框只展示正文，不暴露长串 `dsh-session:` 编码。

## 3. 现在是什么样

### 3.1 用户可见行为

- 点击输入栏“+”会出现原生菜单；“引用会话”打开自适应 Sheet。
- Sheet 从真实主机列出其他 Bot 会话和最近会话，并支持搜索。
- 选中后，输入栏上方出现可删除的会话芯片；最多 3 个。
- 输入 `@` 会在光标处出现候选；选中后替换为 `@名字 ` 并恢复光标。
- 有推理档位的 Bot 会显示原生下拉选择；没有档位时输入栏保持简洁。
- 输入上限与主机协议对齐到 100,000 字符，并扣除隐藏引用头占用。
- 手机与宽屏聊天分支共用上述能力。

### 3.2 真实主机验证

设备：当前已连接的 HUAWEI Pura X Max（宽屏分支，`2584×1828 px`）。

1. `reference-chats` 返回 Searcher 与多个最近会话；Sheet 正常显示。
2. 选择 Searcher 后出现引用芯片，删除也能正常清理缓存草稿。
3. 输入 `@S` 出现 Searcher；点击后正文变为 `@Searcher `。
4. 实际发送“引用 Searcher + `@Searcher`”消息，主机接受提交，没有返回 `mobile/reference-invalid` / `mobile/reference-denied`。
5. 主机随后产生 `message_bot` 工具调用并把消息转给 Searcher，证明 `@` 路由被真实主机识别；Searcher 会话收到了请求并返回响应。
6. 测试结束后输入草稿已清空，没有遗留未发送文本。

截图证据：

- `docs/qa/p1/emulator-reference-sheet.jpeg`
- `docs/qa/p1/emulator-mention-menu.jpeg`

### 3.3 自动验证

```text
node entry/src/test/run.mjs
12 Avatar + 4 Composer + 19 Merge + 26 Markdown = 61 passed / 0 failed

hvigor ... assembleHap
BUILD SUCCESSFUL，0 error
```

构建仍有 Network Kit / Preferences 的既有“可能抛异常”警告；本轮没有新增编译错误。

## 4. 文件变更

| 文件 | 变化 |
|---|---|
| `logic/Composer.ets` | 新增引用编码、草稿拆合、@ 查询与候选规则 |
| `test/composer.test.ets` | 新增 4 个与上游规则对齐的回归用例 |
| `test/run.mjs` | 把 Composer 纳入测试执行器 |
| `model/Models.ets` | `Bot` 增加 `effort` |
| `service/Projection.ets` | 投影主机返回的 `effort` |
| `pages/Index.ets` | 接入原生 Menu / Sheet / Search / Select / TextAreaController，以及手机、宽屏输入栏 |
| `docs/plan/status.md` | 更新 P1-5 与实时通道状态 |
| `docs/handoff-p1.md` | 汇总本轮结论并指向本报告 |

## 5. 已知限制与下一步

1. **思考档位的非空写入尚缺真实样本**：当前 Chief、Searcher 均未从 `efforts` 得到可选项，所以已验证“无档位不显示”的空态，未验证选择 low/high 后的主机持久化。换到提供 reasoning efforts 的模型后，按“选择 → 刷新 → 重进会话仍保持”补一条证据即可。
2. 输入栏高度仍是现有固定高度，已经支持换行但没有像上游一样在 44–150 vp 之间随内容自适应；这是视觉优化，不影响协议。
3. 用户消息气泡目前由通用 Markdown 渲染器处理会话引用，没有上游专用的“引用来源卡片”；发送语义已经正确，展示细节可放到 P1-8。
4. `Index.ets` 仍同时承载手机和宽屏 Builder。后续应把 Composer UI 拆成独立组件，但协议与纯逻辑已经集中到 `Composer.ets`，拆分时无需重写规则。
5. 当前工作目录没有 `.git` 元数据，本轮无法在本机生成提交；文件改动与可安装 signed HAP 均已落盘。

## 6. 给后续开发者 / 大模型的注意事项

- 不要把引用当作普通 Markdown 引用；只有 `dsh-session:` 格式才会让主机注入只读会话上下文。
- 不要自己猜 base64：必须是 **UTF-8 → JSON 字符串 → base64url（无 padding）**。
- 引用候选每次从 `reference-chats` 读取。主机会做权限复核，缓存只能用于展示，不能绕过重新选择。
- `@` 的识别必须使用文本选区，不要永远在字符串末尾查找，否则用户在中间编辑会替换错位置。
- 思考档位属于 Bot 配置，不属于单次 Submission；不要把 `effort` 塞进 `/submissions`。
- 继续优先采用 ArkUI 原生能力：选择类用 `Select`/Picker，临时层用 `bindSheet`/`bindMenu`，文本编辑用 Controller 和原生选区事件。
