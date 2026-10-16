# DS Bot Harmony

DS Bot Harmony 是 [DS Bot App](https://github.com/QingJ01/ds-bot-app) 的原生 HarmonyOS 客户端转译版，使用 ArkTS 与 ArkUI 开发。当前源码以原项目提交 `7e1c3f6c8ebe43bc342caf6abf895d4a2281e9d7` 的移动协议为兼容基线。

## 设备与系统

- 最低版本：HarmonyOS 6.0.0（API 20）
- 当前编译目标：HarmonyOS 6.1.1（API 24）
- 设备类型：手机、平板、折叠屏、HarmonyOS PC / 2in1
- 自适应布局：小于 600 vp 使用与上游移动端一致的单栏页面和悬浮操作按钮；600 vp 以上使用多栏布局；840 vp 以上同时显示会话列表和聊天内容

折叠屏展开、自由多窗和 PC 窗口缩放时，界面会根据实时窗口宽度切换布局，不绑定特定设备型号。

## 已实现

- 粘贴电脑端配对 JSON、电脑端批准、会话凭据持久化
- `/mobile/v1` 主机信息、配对、令牌刷新、团队状态和会话协议
- 本地 HTTPS 公钥指纹转换与 Network Kit 动态证书锁定（HTTP 请求层面）
- Bot 与群聊会话列表、搜索、历史消息、发送与停止（结果由 WebSocket 事件流推进，见下节）
- 首页展示主 Bot、最新消息摘要、更新时间和会话状态，视觉结构与上游 README 截图对齐
- 会话置顶、隐藏与恢复，以及本机已读位置同步到主机
- 推理摘要、工具运行状态、输入与输出卡片
- Bot 创建、13 种上游角色形状、11 种颜色、群聊创建与成员选择
- 原生工具与技能入口、Skills / 插件 / 连接器列表，以及能力库浏览页面
- 待批准工具操作的允许一次 / 拒绝
- 已配对设备列表、移除其他设备、断开并清除本机凭据
- 浅色 / 深色外观
- 手机、平板、折叠屏和 PC 的响应式导航

## 实时与缓存（P0 已完成）

- 聊天回复改为 **WebSocket 事件流**（`/mobile/v1/events`）：`reset` / `delta` / `message` / `status` 四类帧驱动界面，支持 `eventSeq` 断线续传与指数退避重连；原来的「发送后 30 次轮询」与「配对 80 次轮询」已删除。
- 消息按上游 SDK 语义做**增量合并**（`mergeMessages` / `applyConversationEvent`），流式片段用占位消息呈现，正式消息到达时按 `replaceAttemptId` 收口。
- **本地缓存与草稿**：打开会话先渲染本机缓存再拉主机最新页；输入内容实时落盘，重启不丢。
- 发送使用稳定 `requestId`，异常时先查 `/submissions/{requestId}` 回执再决定是否报错，避免重复提问。
- 会话失效（401/403）会自动清理本机凭据并回到连接页，不再卡在死路。

> ⚠️ 已知限制：鸿蒙 `@ohos.net.webSocket` 没有证书锁定选项，事件流的 TLS 校验强度低于 HTTPS 请求（HTTP 仍按配对码 SPKI 严格钉住）。详见 [docs/handoff-p0.md](docs/handoff-p0.md) §6.1。

## 视觉与交互（P1 第一批已完成）

- **矢量头像**：20 种角色形状 × 12 种颜色（含 `aurora`）实时绘制（数据来自上游 `characterData.json`），首页主头像、会话列表、团队页、聊天标题、创建页预览与形状/色板选择器全部统一使用；主 Bot 显示星标，`waiting` 显示橙点，群聊显示成员头像叠放。创建 Bot 时形状与颜色所见即所得。
- **Markdown 渲染**：标题、围栏代码块（带语言名与复制）、有序/无序列表、引用、分隔线、GFM 表格、粗体/斜体/删除线/行内代码/链接/提及。
- **消息交互**：思考过程默认折叠、点击展开；长按消息可复制、复制思考过程、引用到输入框；工具卡可展开查看完整输入输出与耗时；群聊消息显示发言人（头像 + 名字）。
- **审批与排队**：待批准操作在聊天内直接显示（允许一次 / 拒绝，按会话筛选）；主机排队中的消息显示在输入栏上方，可单条移除。
- **实时状态可见**：聊天标题下显示「实时已连接 / 重连中… / 排队 N」。

## 尚未转译

以下能力在原 React Native 客户端中依赖较多平台模块，本版尚未实现：二维码相机扫描、附件上传和预览、语音输入与语音对话、系统通知与后台保活、桌面浏览器控制、Skills / 插件 / Secrets / 能力分配的完整主机写入管理、历史消息的上拉分页界面，以及输入栏的思考档位 / `@` 提及 / 会话引用。

进度与下一步见 [docs/plan/status.md](docs/plan/status.md)；各阶段交接报告见 [docs/handoff-p0.md](docs/handoff-p0.md)（协议与实时底座）与 [docs/handoff-p1.md](docs/handoff-p1.md)（视觉与交互）。

## 工程结构

```text
AppScope/app.json5                              应用配置
entry/src/main/module.json5                    设备与权限声明
entry/src/main/ets/entryability/EntryAbility.ets  应用入口
entry/src/main/ets/pages/Index.ets             自适应界面、导航与断点分发
entry/src/main/ets/view/BotAvatarView.ets      矢量头像组件（20 形状 × 12 颜色）
entry/src/main/ets/view/AvatarData.ets         头像数据与纯逻辑（读 rawfile、回退、路径缩放）
entry/src/main/ets/view/MarkdownView.ets       Markdown 渲染组件
entry/src/main/ets/logic/Markdown.ets          轻量 Markdown 解析器
entry/src/main/ets/view/StreamProbe.ets        诊断页（设置 → 维护 → 诊断页，含事件流/头像两个标签）
entry/src/main/ets/view/AvatarProbe.ets        头像渲染诊断与倍率标定页
entry/src/main/ets/service/MobileClient.ets    DS Bot 协议客户端（HTTPS 钉住 + WebSocket 事件流）
entry/src/main/ets/service/Wire.ets            传输层类型（协议类型统一来自 Models.ets）
entry/src/main/ets/service/Projection.ets      主机原始 JSON → 强类型模型的投影
entry/src/main/ets/service/MessageCache.ets    消息与草稿的本地缓存
entry/src/main/ets/service/ProfileStore.ets    本机连接信息存储
entry/src/main/ets/logic/Merge.ets             事件与消息的增量合并纯函数
entry/src/main/ets/model/Models.ets            ArkTS 协议数据模型
entry/src/main/ets/service/MobileApi.ets       旧传输层（已无引用，设备实测通过后删除）
entry/src/test/run.mjs                         纯函数测试执行器
entry/src/test/logic.test.ets                  19 个协议层用例
```

## 测试

```bash
node entry/src/test/run.mjs    # 期望：68 passed / 0 failed
```

执行器会把 `.ets` 转成 `.ts`、用 DevEco 自带的 TypeScript 擦除类型，再由 Node 运行断言；不需要安装 npm 依赖。

## 构建

推荐使用 DevEco Studio 6.0 或更高版本直接打开本目录，等待 Sync 完成后选择 `entry` 运行。首次运行需要在 **Project Structure > Signing Configs** 中启用自动签名。

命令行构建示例（路径按本机 DevEco Studio 安装位置调整）：

```bash
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
export DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk"
export HARMONYOS_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk/default"

"/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
  --mode module \
  -p product=default \
  -p module=entry@default \
  -p buildMode=debug \
  assembleHap
```

未配置签名时，构建产物位于：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

当前编译、预览与设备覆盖结果见 [TEST_REPORT.md](TEST_REPORT.md)。

## 使用

1. 在电脑或服务器安装并启用原 DS Bot 配套插件。
2. 打开 DS Bot 设置 → 移动设备 → 启用手机连接。
3. 复制电脑端显示的完整配对 JSON。
4. 在鸿蒙客户端粘贴配对 JSON，填写设备名并连接。
5. 回到电脑端批准设备。

主机需要保持在线。Bot、模型、工具和工作目录仍由 DSH 主机执行，鸿蒙 App 只负责安全连接和交互。

## 安全说明

- 正式连接只接受 HTTPS。
- 配对码内的 `sha256:` SPKI 指纹会转换为 HarmonyOS Network Kit 所需的 Base64 SHA-256 公钥摘要，并用于动态证书锁定。
- 访问令牌不会写入日志或仓库；当前版本保存在 HarmonyOS 应用私有 preferences 沙箱中。发布前建议进一步迁移到 HUKS 加密存储。
- 工具结果只展示主机返回的有限投影，不在鸿蒙设备上执行其中的脚本。

## 许可

本转译工程沿用上游项目的 Apache License 2.0 许可。DS Bot App 是独立社区项目，并非 DeepSeek 官方产品。
