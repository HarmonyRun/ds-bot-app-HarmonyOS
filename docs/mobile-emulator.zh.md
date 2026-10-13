# 云端 Android 与 DSH 联调

云端用于开发、构建和原生自动检查；实体手机调试继续在本地进行，见[本地调试指南](mobile-local-debug.zh.md)。这里的脚本使用本次云环境保留的工具目录，不是任意电脑的一键安装器。

## 最小运行配置

Android 11 / API 30，官方 default x86_64 镜像，无 Google 服务；480 × 800、2 GB 内存、2 个虚拟 CPU。此云机没有 `/dev/kvm`，使用软件 CPU 模拟和 SwiftShader、关闭声音与窗口。初次启动和安装较慢，曾遇到一次 System UI 无响应提示；不能据此评估实体手机性能。

隔离 DSH 使用 `.dsh-test-mobile-emulator-20261011a`，Web 端口 3106、测试模型 8806、HTTPS 移动桥接 8796；不访问用户自己的 DSH 数据。ADB 使用独立端口 5038，设备 `emulator-5556`。模型为脚本化 mock；没有使用聊天中提供的 API Key，也没有验证真实模型服务。

## 复现

安装工具与镜像（已执行；可重复）：

```bash
bash /workspace/onboarding/deepseek-bot/android-install.sh
python3 /workspace/onboarding/deepseek-bot/android-emulator-install.py
```

单独构建 x86_64 测试 App，再启动隔离 DSH：

```bash
bash /workspace/onboarding/deepseek-bot/emulator-build.sh
python3 /workspace/onboarding/deepseek-bot/emulator-host-start.py
```

另一个终端启动模拟器，保持该进程运行：

```bash
bash /workspace/onboarding/deepseek-bot/emulator-start.sh
```

在工作终端连接、等待完整启动、安装 App：

```bash
source /workspace/onboarding/deepseek-bot/android-env.sh
source /workspace/onboarding/deepseek-bot/emulator-env.sh
adb -P 5038 -s emulator-5556 wait-for-device
adb -P 5038 -s emulator-5556 shell getprop sys.boot_completed
adb -P 5038 -s emulator-5556 reverse tcp:8796 tcp:8796
adb -P 5038 -s emulator-5556 install -r /workspace/artifacts/deepseek-bot-mobile/ds-bot-mobile-0.1.0-emulator-x86_64.apk
adb -P 5038 -s emulator-5556 shell am start -n app.dsbot.mobile/.MainActivity
```

必须等 `sys.boot_completed` 返回 `1`；不能把 ADB 在线视为 App 已可用。按正常配对流程创建临时配对数据并在主机批准，不输出登录链接、配对 JSON、设备凭证或主机日志。可通过本次保留的原生输入 fixture 和私有检查脚本复现；它们只操作指定模拟器和隔离 bench。

本地 CA 和服务证书有效期两天。构建助手校验证书、到期时重新生成；续期后重新构建 emulator APK 并重启隔离 DSH。只在生成的 `emulator` 构建变体中信任此 CA，保留 HTTPS 链与主机名校验；普通 ARM64 release 不包含测试 CA。不要对系统分区执行 `root/remount/disable-verity`，这会破坏此镜像的 AVB 启动验证。测试 APK 不是实体 ARM 手机安装包。

## 检查范围

本次验证了完整 Android 启动、安装内置 JS 的原生 App、HTTPS 配对与主机批准、读取实际团队和历史、原生输入框发送并渲染 mock 回复、启用后台接收服务；按 Home 后新回复实际触发系统通知，App 内关闭按钮停止服务。原生长消息裁切已修复，并重新构建手机与模拟器 APK。

Android 11 不覆盖 Android 13 通知运行时权限、Android 14+ 前台服务限制或厂商省电策略。未验证实体相机、麦克风、音频中断、Doze、长时间稳定性、原生 Electron 浏览器或 iOS 编译。不需要 EAS、FCM、APNs 才能测试 Android 运行时接收；应用被杀后的云推送仍是单独的可选部署项。

## 停止

在 App 通知中心关闭后台运行提醒，结束启动模拟器的终端进程，再停止本次隔离服务：

```bash
source /workspace/onboarding/deepseek-bot/android-env.sh
adb -P 5038 -s emulator-5556 emu kill
adb -P 5038 kill-server
cd /workspace/DeepSeek-Bot/ds-bot
dev/bench.sh mobile-emulator-20261011a 3106 8806 stop
```

结束任务前清理本次进程。云环境快照不保留运行中的服务；配置草稿也不会自动发布或注入真实模型凭据。
