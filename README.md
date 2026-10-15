# DS Bot Harmony

DS Bot Harmony 是 [DS Bot App](https://github.com/QingJ01/ds-bot-app) 的原生 HarmonyOS 客户端转译版，使用 ArkTS 与 ArkUI 开发。当前源码以原项目提交 `7e1c3f6c8ebe43bc342caf6abf895d4a2281e9d7` 的移动协议为兼容基线。

## 设备与系统

- 最低版本：HarmonyOS 6.0.0（API 20）
- 当前编译目标：HarmonyOS 6.1.1（API 24）
- 设备类型：手机、平板、折叠屏、HarmonyOS PC / 2in1
- 自适应布局：小于 600 vp 使用手机单栏与底部导航；600 vp 以上使用多栏布局；840 vp 以上同时显示会话列表和聊天内容

折叠屏展开、自由多窗和 PC 窗口缩放时，界面会根据实时窗口宽度切换布局，不绑定特定设备型号。

## 已实现

- 粘贴电脑端配对 JSON、电脑端批准、会话凭据持久化
- `/mobile/v1` 主机信息、配对、令牌刷新、团队状态和会话协议
- 本地 HTTPS 公钥指纹转换与 Network Kit 动态证书锁定
- Bot 与群聊会话列表、搜索、历史消息、发送、停止和自动轮询结果
- 推理摘要、工具运行状态、输入与输出卡片
- Bot 创建、群聊创建与成员选择
- 待批准工具操作的允许一次 / 拒绝
- 已配对设备列表、断开并清除本机凭据
- 浅色 / 深色外观
- 手机、平板、折叠屏和 PC 的响应式导航

## 尚未转译

以下能力在原 React Native 客户端中依赖较多平台模块，本版尚未实现：二维码相机扫描、WebSocket 增量流、附件上传和预览、语音输入与语音对话、系统通知与后台保活、桌面浏览器控制、Skills / 插件 / Secrets 的完整管理界面、离线消息缓存、Markdown 富文本渲染。

当前聊天通过主机消息接口轮询回复，因此核心对话可用，但体验不等同于原客户端的逐字流式输出。

## 工程结构

```text
AppScope/app.json5                              应用配置
entry/src/main/module.json5                    设备与权限声明
entry/src/main/ets/entryability/EntryAbility.ets  应用入口
entry/src/main/ets/pages/Index.ets             自适应界面与交互
entry/src/main/ets/service/MobileApi.ets        DS Bot 移动协议客户端
entry/src/main/ets/service/ProfileStore.ets     本机连接信息存储
entry/src/main/ets/model/Models.ets             ArkTS 数据模型
```

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
