# 移动客户端

最简单的同一 Wi-Fi 连接请看[一键本地 HTTPS](mobile-local-https.zh.md)：电脑启用、手机扫码、电脑批准，无需域名或额外 App。

电脑有公网 IPv6、手机网络支持 IPv6 时，也可以使用[公网 IPv6 直连](mobile-local-https.zh.md#ipv6-直连)跨网络连接，无需域名或中继；路由器和电脑防火墙需放行所选手机连接端口。需安装包含 IPv6 支持的新插件构建，已发布的 `v0.1.0` 仍只自动列出 IPv4。

[English](mobile.md) | 中文

首次安装请看[手机端部署安装](mobile-install.zh.md)：说明 VPS、局域网、公网 IPv6、HTTPS 隧道和 Tailscale 部署。

已完成的检查和待做真机测试见[验证记录](mobile-validation.zh.md)。当前仍为预览版。

当前采用[云端开发、本地手机调试](mobile-local-debug.zh.md)：云端构建测试包，本地安装、无线调试与真机验收；使用内置 JavaScript 的 APK 时，本地无需搭建完整开发环境。

iOS/Android 源码预览连接的是**自己正在运行的 DSH 主机**。React Native App、可复用 SDK 和可选主机 Bridge 分别位于 `apps/mobile/`、`packages/mobile-sdk/`、`ds-bot/src/mobile/`。Bridge 使用协议版本 1，与 Desktop/Web 共用同一个 DSH 进程、团队和数据，不另起 Agent 引擎，也不建立云账号服务。

[原始改造方案](mobile-plan.zh.md)保留完整路线图；[对齐清单](mobile-parity.zh.md)记录原版 DS Bot/Harness 行为与平台边界。本指南说明当前部署方式与限制。下面的命令和验收表是操作说明，不代表某台真机或发行构建已经通过测试。

## 准备条件

- DSH `0.2.1-alpha.1`、从当前源码构建的 DS Bot，以及可工作的模型配置。先在主机为 Chief 选择模型。
- 构建插件需要 Node.js `22.19` 以上及[仓库开发环境](../CONTRIBUTING.md#setup)。
- 真机需要能访问的 HTTPS 地址，证书须受手机信任。可以使用带 HTTPS 的私有 VPN；仅连接 VPN 不会把 HTTP 地址变成 HTTPS。
- 原生开发需要 Android SDK/JDK 和模拟器或设备；本地 iOS 构建需要 macOS/Xcode 及签名配置。也可选择受支持的云构建服务，另行满足其账号和签名要求。
- 可选语音转写需要主机配置 DSH 整段音频识别提供者；需要转换格式时，主机还须安装 `ffmpeg`。文字聊天不依赖 ASR。

沿用正在使用的 DSH 进程和 `DSH_HOME`，不要为了手机另起一个读写同一 home 的 Web/Desktop 进程。主机休眠、退出或断网后，不能继续响应手机。

## 安装主机预览版

在仓库根目录开始，构建本地插件包：

```sh
cd ds-bot
npm ci
npm run build
npm pack
```

在 DSH Desktop 的 **Plugins → Add plugin** 中填写生成的 `ds-bot-0.1.0.tgz` 的绝对路径，安装后重启 DSH。应使用当前源码打包，旧的 npm 发布版不一定包含 Mobile Bridge。已有 DSH Web profile 可以使用：

```sh
npx @deepseek-ai/dsh@0.2.1-alpha.1 plugin --profile web add /absolute/path/ds-bot-0.1.0.tgz
```

在 profile 的 `cordis.patch.yml` 中配置 `bot`。Web 也可以单独创建 `mobile.patch.yml`：

```yaml
- id: bot
  config:
    mobile:
      enabled: true
      host: 127.0.0.1
      port: 8788
      publicUrl: https://bot.example.com
```

**DSH patch 会替换整个 `bot.config`，不会递归合并配置。**加入 `mobile` 时保留原有 `home`、`workspace`、记忆和模型相关配置。此类机器专用配置放在仓库外。`publicUrl` 必须是手机实际可达的 HTTPS origin，不带路径前缀。

先停止原有 Web 实例，再用此配置启动：

```sh
npx @deepseek-ai/dsh@0.2.1-alpha.1 web --patch /absolute/path/mobile.patch.yml
```

Desktop 用户将上述选项合并到现有 `<DSH_HOME>/profiles/desktop/cordis.patch.yml`，完全退出后重新打开 Desktop。CLI 不能启动 `--profile desktop`，它由 Electron 管理。继续使用原来的 DSH home。

## 配置 HTTPS

选择以下一种方式。不要暴露 DSH 原有浏览器端口；它的 cookie、Host/Origin 认证与 Mobile Bridge 是两套入口。

**同一主机上的反向代理。**Bridge 保持监听 `127.0.0.1:8788`。已有自己控制的域名并完成证书签发条件后，可使用以下 Caddyfile：

```caddyfile
bot.example.com {
    reverse_proxy 127.0.0.1:8788
}
```

将 `publicUrl` 设为 `https://bot.example.com`，域名指向 Caddy 主机，再运行例如 `caddy run --config /absolute/path/Caddyfile`。Caddy 支持转发 WebSocket 升级。公开证书签发还需要正确的 DNS/验证方式；此示例不会替你注册域名或开放防火墙。私有部署应限制为自己的私网可访问。

**带 HTTPS 的私有 VPN。**手机和 DSH 主机加入同一私网，通过它的 HTTPS 服务功能转发到 `http://127.0.0.1:8788`。例如使用 Tailscale Serve 和有效的 tailnet HTTPS 域名，无需启用 Funnel 公网暴露。将 `publicUrl` 设为实际生成的 HTTPS origin，先验证手机可达性与证书信任，再配对。

**Bridge 直接提供 TLS。**在主机准备匹配的证书链和私钥：

```yaml
- id: bot
  config:
    mobile:
      enabled: true
      host: 0.0.0.0
      port: 8788
      publicUrl: https://bot.example.com:8788
      certPath: /absolute/path/fullchain.pem
      keyPath: /absolute/path/privkey.pem
```

非 loopback 监听必须使用 TLS。将网络访问范围限制为自己的设备，私钥放在仓库外并保护读取权限。手机必须信任证书及其域名；未安装信任的自签证书会失败，不能用关闭验证解决。

## 构建手机 App 并配对

在仓库根目录开始：

```sh
cd apps/mobile
npm ci
npm run typecheck
npm run android
```

macOS 上可用 `npm run ios` 构建 iOS。两者使用 Expo development build，需要对应原生 SDK；Expo Go 不是验收环境。开发构建安装后，`npm start` 启动 Metro。分发发行版前需配置自己的应用标识与签名，签名材料和凭据不要进入仓库。

1. 在主机 DS Bot 的 **Settings → Mobile devices** 生成配对码。
2. App 扫描二维码，或粘贴完整配对 JSON；核对主机身份，填写设备名称。
3. 回主机确认待配对设备。仅知道一次性配对码不会直接获得访问权限。
4. 打开 Chief 或已有 Bot/群聊。Bot 的长期对话跨内部上下文分段连续展示。
5. 不再需要设备时，在主机撤销它。移除手机本地连接与撤销主机授权是不同操作。

二维码/JSON 是临时凭据，不要放进截图或问题报告。App 使用系统安全存储保存设备凭据，模型 API Key 留在主机。所有已配对设备代表同一个主人，聊天可能让 Bot 执行主机工具；此预览不提供独立团队成员账号或只读访客角色。

## 构建个人测试用 Android APK

当前 Expo SDK 54 / React Native 0.81 使用 JDK 17、Android SDK/build-tools 36、NDK `27.1.12297006` 和 CMake `3.30.5`；部分原生依赖还需要 build-tools `35.0.0` 与 CMake `3.22.1`。安装[官方 Android 命令行工具](https://developer.android.com/studio#command-tools)，解压前核对官网 SHA-256；将 `JAVA_HOME` 指向 JDK 17，`ANDROID_HOME` 指向 SDK。仅编译 APK 不需要下载模拟器镜像。

```sh
sdkmanager --licenses
sdkmanager 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'build-tools;35.0.0' 'ndk;27.1.12297006' 'cmake;3.30.5' 'cmake;3.22.1'
```

在 `apps/mobile/` 完成 `npm ci` 后运行：

```sh
npx expo prebuild --platform android --no-install
cd android
./gradlew :app:assembleRelease -PreactNativeArchitectures=arm64-v8a --max-workers=2 --no-daemon
```

此构建面向 64 位 ARM 手机，内置 JavaScript，运行时不需要 Metro。生成的 `android/` 和构建产物已被 Git 忽略。任务成功后，APK 位于相对 `apps/mobile/` 的 `android/app/build/outputs/apk/release/app-release.apk`。

**当前生成模板的 release 任务使用 Android 标准 debug key 签名。**它只是个人测试包，不是正式发行签名或商店发布。正式分发须另行配置自己保护的签名材料与应用标识。在 `apps/mobile/android/` 可以验证并安装测试包：

```sh
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose app/build/outputs/apk/release/app-release.apk
"$ANDROID_HOME/platform-tools/adb" install -r app/build/outputs/apk/release/app-release.apk
```

安装步骤需要自己已连接并授权的 Android 设备。编译通过不能证明该设备的录音、相机、HTTPS 配对或后台恢复已验证；iOS 仍需在相应平台单独原生构建和真机验收。

受限构建环境中，即使 `curl` 可联网，Java/Gradle 也可能需要单独配置代理。沿用环境已有代理和可信系统 CA，保持证书验证。Gradle 8.14.3 官方分发包的 SHA-256 为 `bd71102213493060956ec229d946beee57158dbd89d0e62b91bca0fa2c5f3531`，可在生成的 `android/gradle/wrapper/gradle-wrapper.properties` 中设置 `distributionSha256Sum` 验证下载。

## 聊天、附件与语音

- 在对话列表选择 Bot 或群聊。创建另一个 Bot 是明确的团队操作，不会用“新聊天”偷偷替换当前 part。
- 在线时流式显示文字，重连后从主机恢复历史和状态。停止当前生成不代表所有团队排队消息都被删除。
- 附件支持 PNG/JPEG/WebP/GIF 图片（每张最多 10 MiB）和文件（每个最多 20 MiB）。原生选择器将 HEIC 图片转成 JPEG；UTF-8 TXT/MD 可提供文本，其他文件通过 Harness 文件上传服务保存，其用途取决于主机工具与模型能力。上传 PDF/Office 不代表已支持解析。暂存上传 15 分钟后过期，主机可设置更小的传输上限。上传与当前 Session 绑定；Bot 切换 part 后若提示过期，重新准备附件。
- 图片需要主机的视觉模型或已配置的图片转文字路线。群聊可能向成员传递图片的文字描述，而非原始视觉输入。
- **语音输入**将整段录音发送到主机识别，返回文字后先检查再发送。**语音对话**是独立入口：点按开始聆听后，检测到说话后的停顿便转写并自动发送，再朗读与本轮请求对应的回复，随后继续聆听。暂停、离开前台、断线或录音中断都会停止麦克风，恢复连接不会自行录音。不提供流式 ASR，也不会自动切换到付费云服务。录音最多 60 秒、10 MiB。在主机 **Plugins** 启用 **Voice Input**，进入详情并完成本地识别器的 **Download and prepare**；必要时用 `ffmpeg` 转换为 16 kHz、单声道 PCM16 WAV。模型准备与手机配对是独立步骤。
- 朗读使用手机系统 TTS。可用声音、声音下载和网络需求取决于设备设置。
- 工具审批卡与 Bot 提问分开显示，展示主机待批准动作，通过共享主机 broker 允许或拒绝。另一设备已决定、取消或过期都会使卡片失效；重连不会自动批准。最终仍由主机审批策略约束。

## 团队与主机设置

Bot/群详情、Main Bot 权限、外观、记忆、定时任务和用量使用同一份主机团队状态。在线历史搜索通过主机跨 part 查询，需要保持连接。主机设置提供受支持的 schema 字段及 revision 冲突校验、既有凭据引用、插件包检查/安装/移除与启停、Skills 作用域目录/调用/自有库管理和 DS Bot 主机插件更新。语言可跟随主机或系统，也可在本机选择英文/中文。主要导航与设置已有原生翻译；部分详细状态、错误和插件返回的描述仍保留英文。

Connectors 与 Secrets 只显示元信息和授权范围。新值用密码框输入，经 HTTPS 单次提交，在提交或离开前台时清空，不进入草稿、缓存、重放队列或响应。Feedback 先在本机预览诊断；复制、导出日志与打开 issue 都需要用户主动操作，不会自动发送报告。

复杂条件配置表单、集合项增删和任意插件专属 DOM 页面仍需进入主机对应设置页；已存在的集合值可逐项编辑。插件变更会提示需要主机重启或被其他 profile 覆盖。维持连接的 DS Bot 插件必须在主机管理；主机插件更新不会升级手机 App。

## 数据与当前限制

Session、Bot 状态、记忆和模型凭据以主机为准。手机用本地 SQLite 缓存消息和草稿。**App 没有对这份 SQLite 缓存加密**，依赖操作系统的应用存储保护；设备凭据另存于 Keychain/Keystore 支持的安全存储。每个对话最多缓存 1,000 条最终消息，缓存并不是主机全部历史的副本。**Clear cached history and drafts** 会保留未确认发送、对应草稿和旧配对的归档提交，其中包含原始消息内容；归档不等于删除。断开连接会移除保存的连接和凭据，但保留按主机分区的缓存。要彻底删除这些保留记录，使用操作系统的应用数据清理功能（iOS 删除 App，而非保留数据的卸载），浏览器预览则清除该站点存储。撤销设备不会远程擦除其缓存，也不会取消主机已接受的工作。

离线只能查看已缓存内容和编辑草稿。恢复网络后，不自动补发离线草稿或重放动作；对结果不确定的提交，先按原 request ID 查询，再重试。主机重启可能中断工作，恢复不能静默重复产生外部副作用。

预览仅连接一个当前主机，不包含 SaaS 账号与计费、实时双向语音，也不承诺任意 PDF/Office 解析。Android 可选常驻接收服务在后台运行时触发本地通知，无需 EAS/FCM/APNs；iOS 仅在系统允许的短暂后台时间内接收。App 被暂停或关闭后的云推送可选，需平台凭据。桌面浏览器控制需要电脑端逐窗口授权。Expo Web 预览不能验证原生音频、安全存储与设备生命周期。

## 开发检查

以下各段均从仓库根目录开始：

```sh
cd packages/mobile-sdk
npm test
```

```sh
cd apps/mobile
npm ci
npx expo install --check
npm run typecheck
npm test
npm run export
```

```sh
cd ds-bot
npm ci
npm run build
npm test
node scripts/build-client.mjs --check
```

插件测试需要 [CONTRIBUTING](../CONTRIBUTING.md) 中说明的 Harness checkout。主机代码变更还需执行其中的 mock smoke。测试仅使用 `.dsh-test-<name>/`，不能指向用户真实 DSH home；结束后停止自己启动的所有 bench 和进程。`npm run export` 导出 JavaScript/资源，不会生成签名 APK/IPA，也不代表真机通过。

移动协议 smoke 使用真实 DSH 进程和 mock 模型。在 `ds-bot/` 选择空闲端口后运行：

```sh
MOBILE_PORT=8789 CONTEXT_WINDOW=100000 dev/bench.sh mobile-smoke 3098 8798 reset
node dev/mobile-smoke.mjs mobile-smoke 3098 8789
dev/bench.sh mobile-smoke 3098 8798 stop
```

`reset` 只清除此名称的测试 bench。即使检查失败，也执行最后的停止命令。该流程检查缺少 ASR 时正确报错，不代表真实识别器的语音质量测试。

使用本地 mock 主机配合浏览器预览时，先选择空闲端口，在 `ds-bot/` 执行：

```sh
MOBILE_PORT=8894 MOBILE_WEB_ORIGIN=http://localhost:8081 dev/bench.sh mobile 3193 8893 start
```

另开终端，在 `apps/mobile/` 执行 `npm run web -- --port 8081`，用 `http://localhost:8081` 打开预览；实际 origin 必须与 bench 允许的地址完全一致。通过 bench 已认证的 DS Bot **Mobile devices** 页面配对。完成后在 `ds-bot/` 执行 `dev/bench.sh mobile 3193 8893 stop`，并停止 Metro。`start` 保留已有 bench 数据，需要全新数据时改用另一个 bench 名称。

仅浏览器/模拟器开发时，可在 loopback HTTP Bridge 上显式设置 `devAllowInsecure: true`，并打开 App 仅在开发构建出现的 HTTP 选项。不得绑定明文 LAN 地址。真机的 `localhost` 指手机自己，连接电脑须使用 HTTPS。浏览器预览凭据仅保存在当前页面内存，刷新后失效。

## 真机发行前的人工验收

每项记录 commit、DSH 版本、主机系统、手机型号/系统、网络和结果。单元测试或 Web 导出通过不代表下表通过。

| 场景 | 预期 |
|---|---|
| 配对 | 过期/复用配对码失败；新设备等待主机确认；撤销后新请求和已有流都不可用 |
| 历史 | 手机与主机显示同一 Bot/群聊消息；旧 part 分页正确，群聊与私聊不串线 |
| 重试与恢复 | 回执丢失、切网和 App 重启后，不重复提交已接受消息或重复显示最终回复 |
| 主机生命周期 | 休眠/退出显示离线；回前台恢复历史；主机重启不批准过期请求或重放动作 |
| 附件 | 允许的图片/文件送达正确 Bot；类型错误、上传中断和 part 切换可以恢复 |
| 音频 | iOS/Android 上拒绝权限、转写失败、音频中断及取消朗读均可恢复 |
| 团队与审批 | Bot/群变更与主机一致；提问与工具审批清楚区分；多端无法重复决定同一请求 |
| 主机设置 | 旧 revision 安全拒绝；密钥不出现在缓存和错误中；插件变更反映真实主机状态 |
| 两台设备 | 同看一台主机；撤销设备失去访问权限，另一台正常使用 |
| 数据 | 离线可看缓存、草稿不自动发送；清理本地数据不删除主机历史 |

首轮完整语音验收至少选择一种真实主机系统和一条可工作的 ASR 路线，其他主机平台分别验证。本指南不证明相机、音频、签名、商店上架或全部平台兼容性已完成。

## 常见问题

| 问题 | 检查项 |
|---|---|
| 没有 Mobile devices 页面 | 安装/构建当前源码的插件后重启；不要假设已发布包包含此功能 |
| 主机不可达 | DSH/Bridge 是否运行、手机能否解析 `publicUrl`、VPN/代理/防火墙路线 |
| HTTPS 失败 | 证书域名、证书链与手机信任；不要绕过 TLS 验证 |
| 配对一直等待或过期 | 在有效窗口内到主机确认；过期后生成新码 |
| 已连接却没有回答 | 在主机为 Bot 选择可用模型并检查状态，不要反复重新配对 |
| 无法转写 | 启用支持的 DSH 整段 ASR 提供者并检查 `ffmpeg`；文字聊天仍可使用 |
| 长对话后附件失败 | 更新当前发送目标并重新附加，upload receipt 不能跨 Session part |

报告问题时提供脱敏后的错误与版本，不附带配对数据、设备凭据、模型密钥或私人 Session 文件。

## 文件与完整对话导出

点按消息中的文件可下载并用系统分享菜单保存或打开。常见文本格式可预览前 64 KiB；预览不会执行 HTML 或脚本。主机会核对文件所属的会话及消息位置，并完整校验文件后提供不超过 20 MiB 的下载。

在聊天的对话历史菜单选择“导出对话”，可将主机所有可读取分段导出为 Markdown 或 JSON。导出列出附件信息，文件内容单独下载；不包含设备凭证、发送回执或未提交的流片段。取消或分页异常时不输出半成品。手机导出最多 50,000 条消息、32 MiB；超过限制请在主机处理。

## 本轮六项补齐

界面细节、工具专用卡片、Skills、插件管理、桌面浏览器控制和移动通知已实现。Android 测试 APK 包含无需平台凭据的后台运行接收模块；可选云推送未配置 EAS/FCM/APNs。操作方式和实机验证边界见[六项功能说明](mobile-features.zh.md)。
