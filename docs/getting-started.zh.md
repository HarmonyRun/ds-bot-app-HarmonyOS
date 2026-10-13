# 安装与配置 DS Bot

[English](getting-started.md) | 中文

## 先准备什么

- 一台运行 DSH 的 Windows/macOS 电脑，或运行 DSH Web 的 Linux 服务器。
- 主机配置可用的模型与凭据；API Key 只填写到 DSH 的凭据界面，不发到聊天或提交到仓库。
- Android ARM64 手机。x86_64 APK 用于对应模拟器；当前构建不包含 ARM32。iOS 源码需另行用 macOS/Xcode 构建。
- 初次连接建议两端使用同一个 Wi-Fi，电脑保持开机。手机不是独立的模型服务器。

主机集成基线为官方 npm DSH `0.2.0-rc.2`，CI 另检查 `0.2.1-alpha.1` 兼容性；建议先使用上述已验证版本。

## 下载配套插件和 App

在 [v0.1.0 Release](https://github.com/QingJ01/DS-Bot-App/releases/tag/v0.1.0) 下载配套文件。本次替换最初撤回的构建，包含上游 v0.1.4 和修复后的移动控件；旧源码保存在 `archive/withdrawn-v0.1.0`。以下 Actions 下载方式供开发构建使用。

打开本仓库 [Actions → Build plugin and Android](https://github.com/QingJ01/DS-Bot-App/actions/workflows/build.yml)，选择同一提交的成功运行，在 Artifacts 下载：

| 产物 | 用途 |
| --- | --- |
| `dsbot-plugin` | 解压后包含 `ds-bot-0.1.0.tgz`，供 DSH 安装 |
| `dsbot-android-arm64` | 手机使用的 ARM64 APK |
| `dsbot-android-x86_64` | Android x86_64 模拟器 APK |

Artifacts 是 ZIP，先解压。已签名 APK 的文件名为 `dsbot-android-arm64.apk`；含 `-unsigned` 的文件没有签名，不能安装，需要维护者配置签名 Secret 并重新构建。每个产物附带 `SHA256SUMS`。已有发布版本时也可从 [Releases](https://github.com/QingJ01/DS-Bot-App/releases) 下载同一版本的插件和 App。

**不要直接安装 npm 的 `ds-bot` 来替代这个包。** npm 名称属于上游项目；本分支的手机桥接、HTTPS 和管理功能由本仓库源码打包。

## 电脑安装

1. 从 [DSH 官方 Releases](https://github.com/deepseek-ai/deepseek-harness/releases) 安装适合系统的 Desktop。
2. 打开 DSH 的 **插件 → 添加插件**，填下载的 `.tgz` 完整路径。例如 Windows 的 `C:\Downloads\ds-bot-0.1.0.tgz`。
3. 安装、启用，完全退出 DSH 再打开；更新插件也需要重启。已有数据不需要删除。
4. 在 Harness 设置中添加模型提供商，配置凭据，确认提供商能列出模型。为 Chief 选择模型，发送一句话确认能正常回复。
5. 可以让 Chief 创建 Bot 与群聊，也可以用客户端的新建入口配置名称、角色、指令和模型。

### 使用 DSH Web

需要 Node.js 24 LTS 和 pnpm。在自己的工作目录执行，路径改成实际值：

```sh
npm install -g pnpm
npx @deepseek-ai/dsh@0.2.0-rc.2 plugin --profile web add /absolute/path/ds-bot-0.1.0.tgz
npx @deepseek-ai/dsh@0.2.0-rc.2 web
```

使用 DSH 启动输出中的本机登录链接，在电脑配置模型。不要公开该登录链接或管理入口。已有 DSH 用户继续使用原数据目录，不要让两个进程同时读写同一份数据。需要远程部署时见[域名、VPS、隧道与 Tailscale 教程](mobile-install.zh.md)。

## 手机安装与一键连接

1. 手机安装已签名 ARM64 APK；系统提示时允许当前安装来源安装应用。
2. 电脑 DS Bot 打开 **设置 → 手机设备**，点击 **Enable phone connection / 启用手机连接**。
3. 插件自动生成证书并启动 HTTPS，默认端口 `8788`。有多个网卡时选择手机能访问的 Wi-Fi 地址；防火墙提示时允许专用网络访问。
4. 手机 App 扫描电脑上的二维码，允许相机权限；也可粘贴完整配对 JSON。
5. 电脑核对设备名称，在待配对设备旁点击 **Approve / 批准**。手机进入会话列表后打开 Chief 发消息验证。

无需域名、额外 App 或手动安装证书。二维码带短期配对码与主机公钥指纹，App 验证主机身份后保存设备凭据。二维码过期需重新生成；不要把二维码或配对 JSON 发给别人。电脑重启会恢复手机入口；更换 IP/网络需重新取得新地址的二维码。关闭入口和撤销设备是不同操作。[完整 HTTPS 说明](mobile-local-https.zh.md)。

**从旧测试 APK 换到正式项目签名时**：旧包使用调试证书，Android 不允许直接覆盖。先导出需要保留的本地内容，再卸载旧包、安装新包并重新配对；主机上的 Bot 与聊天仍然保留。以后使用同一项目签名并增加 `versionCode` 即可覆盖更新。

## 常用功能怎么配置

| 功能 | 配置位置与前提 |
| --- | --- |
| 中英文、夜间模式 | 主页面左上角鱼形入口打开设置，选择语言与外观；也可跟随系统 |
| 定时任务、记忆、用量 | 设置或 Bot/群详情中的对应页面；任务要求主机 Schedule 服务可用、主机持续运行 |
| Skills、插件、连接器 | 设置中的主机管理入口；仅开放 DSH 公开 API 支持的操作，插件专属复杂界面仍使用电脑 |
| 图片与文件 | 聊天输入框 `+`，选择相册、相机或文件；是否能理解内容取决于主机模型/工具能力 |
| 语音输入与对话 | 在主机配置 Voice Input，并安装 FFmpeg；手机批准麦克风权限。手机系统朗读语音可能需要下载 |
| 桌面浏览器控制 | 需要 DSH Desktop、主机提供浏览器能力，并在主机明确启用手机控制；Web 主机不会凭空拥有桌面浏览器 |
| 工具批准 | 对话中的批准卡片核对具体操作，允许一次或拒绝；多个设备共享结果 |

## 无 FCM/APNs 的 Android 后台通知

手机设置打开通知中心，启用 **后台运行提醒** 并允许系统通知权限。Android 会显示可停止的常驻服务通知。按 Home 到后台，主机完成任务时可发系统通知。需要手机仍能连接主机，且系统允许服务运行；强制停止、电池限制、网络中断会影响接收。

该模式不需要 EAS、FCM 或 APNs。需要应用被挂起/关闭后仍通过平台推送提醒时，才配置可选 Expo 云推送及平台凭据，详见[通知配置](mobile-features.zh.md)。iOS 没有 Android 常驻服务，只允许有限后台执行；源码尚未在本环境编译或真机验证。

## 排错

- **扫描后连接失败**：确认主机开启入口，两端地址可达；访客 Wi-Fi、AP 隔离、多网卡或防火墙可能阻断 `8788`。
- **浏览器提示自签证书不可信**：一键本地证书由原生 App 根据二维码验证；不要以浏览器无法信任自签证书判断 App 故障，也不要关闭 TLS 校验。
- **配对一直等待**：回到电脑批准；过期则重新生成二维码。
- **聊天没有模型回复**：先在电脑测试同一个 Bot 的模型/凭据，查看主机连接状态。
- **更新插件后功能未出现**：核对安装的是本仓库构建的 `.tgz`，并完全退出重启 DSH。
- **APK 安装失败**：确认是 ARM64 已签名包；旧调试签名需卸载，版本号低于已安装版本时重新构建更高 `versionCode`。
- **通知不出现**：允许通知、开启后台服务、检查电池优化与主机网络。不要把通知权限等同于服务已启动。

构建/签名见[发布教程](releasing.zh.md)，无线调试见[本地调试指南](mobile-local-debug.zh.md)，验证历史与未完成真机项见[验证记录](mobile-validation.zh.md)。
