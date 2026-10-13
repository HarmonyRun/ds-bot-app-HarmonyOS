<p align="center">

  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.svg">
    <img src="docs/images/logo.svg" alt="DeepSeek Bot" width="260">
  </picture>
</p>

# DS Bot

[English](README.md) | 中文

![版本](https://img.shields.io/badge/版本-v0.1_预览-blue) ![DSH](https://img.shields.io/badge/DSH-0.2.0--rc.2-4D6BFE) ![许可](https://img.shields.io/badge/许可-Apache_2.0-green)

DeepSeek Bot（简称 DS Bot）是一个基于 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（简称 dsh）的 bot 插件，插件将 dsh 改造为 bot 形式。你可以与自己创建的 bot 交流、工作。

![和 Chief 说一句话，它就把 bot 和群聊建好](docs/images/team.zh.png)

## 安装与连接

本仓库包含 DSH 插件、手机连接桥接、独立 Android/iOS 客户端和共用 SDK。Bot、工具和模型运行在自己的电脑或服务器上，手机负责交互；主机必须保持开机并运行 DSH。

1. 从 [GitHub Actions](https://github.com/QingJ01/DS-Bot-App/actions/workflows/build.yml) 下载同一次构建的 `dsbot-plugin` 和 `dsbot-android-arm64`，或者从 [Releases](https://github.com/QingJ01/DS-Bot-App/releases) 下载 `.tgz` 与已签名 `.apk`。Actions 下载的是 ZIP，先解压。文件名含 `-unsigned` 的 APK 未签名，不能安装。
2. 安装 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness/releases)，在 **插件 → 添加插件** 中填写下载的 `.tgz` 的完整路径，安装、启用并重启 DSH。此分支不要直接安装 npm 上的 `ds-bot`，那是上游版本，不含这里的完整移动端功能。
3. 在电脑配置模型提供商和凭据，为 Chief 选择模型，先确认电脑聊天正常。
4. 手机安装 ARM64 APK。电脑打开 **设置 → 手机设备 → 启用手机连接**，两端连接同一 Wi-Fi，在 App 扫码，然后回到电脑批准。

插件自动配置本地 HTTPS，无需域名、额外 App 或安装证书；手机按二维码中的公钥验证主机身份。Android 开启后台接收服务后可接收运行时通知，无需 FCM/APNs。见[完整安装与配置教程](docs/getting-started.zh.md)、[一键 HTTPS](docs/mobile-local-https.zh.md)、[远程/VPS 部署](docs/mobile-install.zh.md)。

## 移动端能力与限制

已接入 Bot/群聊、流式回复与思考、长按消息操作、图片和文件、语音输入/对话、定时任务、记忆、用量、Skills、插件管理、专属工具结果、明确的工具批准和可选桌面浏览器控制。支持中英文、日间/夜间主题与原创鱼形图案。Bot 数据保留在主机；手机用安全存储保存凭据、本地缓存保存消息与草稿。

Android 配对、聊天、公钥验证和运行时后台通知已在模拟器连接真实隔离 DSH、使用模拟模型验证。iOS 包含源码，尚未编译或真机验证，后台运行有系统时间限制。语音需要主机配置 Voice Input 和 FFmpeg；部分插件专属界面仍需电脑操作。目前没有应用商店发行或持续运行的托管云服务。[详细能力边界](apps/mobile/README.md)。

## 构建与发布

[GitHub Actions](.github/workflows/build.yml) 执行插件/SDK/App 检查、打包插件，并构建 ARM64 和 x86_64 Android APK。仓库保存加密的 `DeepSeekBot` 签名文件（国家 `CN`），密码由 GitHub Secret `ANDROID_KEYSTORE_PASSWORD` 提供。未配置 Secret 时只生成明确标注的**未签名** APK，并阻止标签发布；密码不会写入 Git。

见[Actions、签名、下载与发布教程](docs/releasing.zh.md)。iOS 构建需要 macOS/Xcode 和 Apple 签名身份。开发命令见 [CONTRIBUTING.md](CONTRIBUTING.md)、[插件说明](ds-bot/README.md)及 [App 说明](apps/mobile/README.md)。

## 功能

### Bot

你可以在一个窗口中和一个 bot 完成所有对话和工作，你无需担心背后的上下文问题。你可以在 bot 详情页查看 bot 信息，也可以为 bot 选择你想使用的模型。你可以随时切换模型，但我仍然建议你为一个 bot 长期保持一个模型，仅在真正必要的时刻切换。

另外，bot 拥有记忆，它会记住你的喜好并在下次的工作中应用。你可以在 bot 的详情页管理记忆，也可以直接和 bot 对话来进行管理。

![bot 详情页：模型、记忆、用量](docs/images/details.zh.png)

### Main bot

这个 bot 作为你的 chief，它拥有非常高的权限，可以管理其他 bot 和群聊。第一次进入 ds bot 时，默认会有一个 main bot 叫 Chief。你可以直接和它对话，让它引导你完成配置。

总之，有问题，找 main bot。

### 群聊

ds bot 拥有群聊功能。群聊是非常好的多 bot 协作方式，但它会带来非常明显的费用问题。ds bot 为此特意做了优化：在一个群聊中，你需要设置一个管理员。你的消息默认由管理员回复，它会帮你调用其他 bot。你也可以直接 @ 你需要沟通的 bot，它会直接回应你：输入 @，从列表里选 bot 就行。想让 bot 参考另一段对话，点输入框的 + → 引用对话。

![群聊：管理员 Chief 把活派给写手和程序员](docs/images/group.zh.png)

### 用量

在 设置 → 用量 里，可以按时间、按 bot、按模型查看 Token 用量。

![用量页](docs/images/usage.zh.png)

## 数据

Bot 的权威数据保留在自己的 DSH 主机上，位于 dsh 主目录（默认 `~/.dsh`）的 `bot/` 和 `sessions/` 中。卸载插件不会删除这些数据。移动客户端还会在手机缓存对话和草稿；模型请求仍使用 DSH 中配置的提供商。详见[移动端数据与当前限制](docs/mobile.zh.md#数据与当前限制)。

## 开发

插件源码在 [`ds-bot/`](ds-bot/)。配置项和内部结构见 [`ds-bot/README.md`](ds-bot/README.md)，开发和测试见 [CONTRIBUTING.md](CONTRIBUTING.md)，版本变化见 [CHANGELOG.md](CHANGELOG.md)。

## 致谢

- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)：ds bot 建在 dsh 的插件系统上。每个 bot 都是一个 dsh 会话，用的是 dsh 的工具和模型。
- [esbuild](https://esbuild.github.io/)：用来打包插件的界面代码。
- 感谢下面这些项目公开的设计思路。ds bot 参考了它们的思路，没有使用它们的代码：
  - [AgentMemoryRepo](https://github.com/AgentMemoryRepo/agentmemoryrepo)：bot 记忆的 Markdown 格式。
  - [OpenAI Codex](https://github.com/openai/codex)：压缩时把用户原话留在摘要旁边，以及搜索聊天记录用的消息锚点。
  - [OpenMausBot](https://github.com/milind-soni/OpenMausBot)：群聊轮流发言和 @ 接力。
  - [Hermes Agent](https://github.com/NousResearch/hermes-agent) 和 [Hermes Bot Mode](https://github.com/NousResearch/Hermes-Bot-Mode)：每个成员在每个群里一个会话，以及交接时带上用户之前的原话。
  - [OpenCode](https://github.com/sst/opencode)、[goose](https://github.com/block/goose)、[pi](https://github.com/badlogic/pi-mono)、[Gemini CLI](https://github.com/google-gemini/gemini-cli)：长对话什么时候压缩，交接笔记写哪些内容。
  - [obelisk](https://github.com/tommy0103/obelisk)：用 SQLite 全文索引搜索聊天记录。
- 每一位试用 ds bot、提问题、报 bug 的人。

## 许可

[Apache License 2.0](LICENSE)。按“原样”提供，不附带任何担保。用到的第三方代码和它的许可见 [NOTICE](NOTICE)。

## 声明

ds bot 是独立的社区项目，**不是 DeepSeek 官方产品**，与 DeepSeek 没有隶属、认可或赞助关系。“DeepSeek”“DeepSeek Harness”等名称是各自所有者的商标，这里只用来说明本插件和什么一起用。

bot 会消耗你自己的模型额度，也会按你的要求读写文件、运行命令。重要的操作请自己检查。

本轮上游更新、手机点名与会话引用，以及透明悬浮聊天顶栏见[上游移植说明](docs/mobile-upstream.zh.md)。
