# 云端开发，本地手机调试

当前采用这个分工：代码修改、插件/APK 构建、自动测试在云端完成；本地电脑连接手机，安装测试包，验证原生功能和桌面浏览器控制。DSH 继续运行在自己的电脑或服务器上。

云端本轮不能直接访问手机的局域网无线调试地址。本指南中的 ADB 命令必须在本地电脑执行；云端检查通过不代表手机已通过验收。

## 下载与准备

从 [v0.1.1 Release](https://github.com/QingJ01/DS-Bot-App/releases/tag/v0.1.1) 下载 `dsbot-android-arm64-v0.1.1-r2.apk`、`SHA256SUMS-r2` 和主机插件 `ds-bot-0.1.1-r2.tgz`。另从仓库下载 [`android-device.py`](../apps/mobile/scripts/android-device.py)，与 APK 放在同一目录。

本地只需：

- [官方 Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools)，解压后把目录加入 PATH，确认 `adb version` 可运行。也可在每条脚本命令中使用 `--adb` 指定 `adb`/`adb.exe` 的完整路径。
- [Python 3](https://www.python.org/downloads/)（建议 3.9 以上）。以下用 `python` 表示命令；Windows 可改成 `py`，macOS/Linux 可改成 `python3`。脚本只使用标准库，没有 pip 依赖。
- ARM64 Android 手机。测试 APK 最低支持 Android 7；系统无线配对功能需要 Android 11 以上。较旧系统可使用 USB 调试。

**运行这个 APK 不需要本地 Node、JDK、Android Studio 或 Metro。**本包是个人测试签名，不是商店发行版。不要用调试 APK 覆盖签名不同的现有 App；脚本遇到签名冲突会停止，不会自动卸载或清空数据。

## 本地无线配对与安装

手机和本地电脑接入同一可互通 Wi-Fi。打开手机 **开发者选项 → 无线调试**。公共 Wi-Fi 的客户端隔离、防火墙或网络切换都可能阻止连接。

以下地址仅为示例，必须换成手机当前显示的地址。**配对端口与连接端口通常不同，重新打开页面后可能变化。**

1. 点 **使用配对码配对设备**，读取弹窗中的配对地址。在本地运行：

   ```sh
   python android-device.py pair 192.168.1.20:37001
   ```

   在 ADB 的本地提示中输入新的一次性配对码。不要把码作为命令参数、写入脚本或发送到聊天。旧码已经失效时重新打开配对窗口。

2. 回到无线调试主页面，读取 **IP 地址和端口**，运行：

   ```sh
   python android-device.py connect 192.168.1.20:37002
   ```

3. 使用同一个连接地址指定目标设备，安装并打开 App：

   ```sh
   python android-device.py install --serial 192.168.1.20:37002 --apk dsbot-android-arm64-v0.1.1-r2.apk --launch
   ```

   脚本安装前按同目录 `SHA256SUMS-r2` 核验 APK，使用 `adb install -r` 保留数据；不会清空缓存、卸载应用或选择列表中的第一台设备。校验文件与 APK 必须来自同一次可信交付。自己构建的新包可使用 `--sha256` 显式提供该包的哈希。

如果 ADB 不在 PATH，例如 Windows：

```powershell
py android-device.py --adb "C:\Android\platform-tools\adb.exe" connect 192.168.1.20:37002
```

USB 调试时先在手机确认电脑授权，运行 `adb devices -l`，把设备序列号传给 `--serial`，直接执行安装步骤。无线连接后端口变更时重新 `connect`；已配对通常无需重复配对。结束后可执行 `adb disconnect IP:连接端口`；不再使用时在手机无线调试页移除该电脑授权。

## App 连接自己的 DSH

**ADB 配对只让电脑安装/诊断手机 App，不会让 App 登录 DSH。**

1. 在自己的 DSH 主机手动安装当前 `ds-bot-0.1.1-r2.tgz`；Desktop 使用 **Plugins → Add plugin**，选择本地包路径，安装后重启。不要运行测试 bench 来操作自己的 DSH 数据，也不要启动两个进程读写同一 DSH home。
2. 在现有配置中启用 Mobile Bridge，并准备手机可达、证书受信任的 HTTPS 地址。按[部署指南](mobile.zh.md#配置-https)配置；保留原来的完整 `bot.config`。本地 Wi-Fi 或私有 VPN 连接不等于 HTTPS 已配置。此 APK 不接受普通局域网 HTTP，也不跳过证书校验。
3. 在 DSH **Settings → Mobile devices** 生成 App 配对二维码或 JSON，手机扫描/粘贴，再回电脑确认设备。
4. 在 App 中打开现有 Bot/群聊。模型请求和工具仍在 DSH 主机执行；主机须保持开机、在线。

主机插件更新和手机 APK 更新是两个操作，每次云端交付会注明需要更新哪一个。这个本地调试脚本不修改 DSH 配置或用户数据。

## 优先做的真机验收

| 检查 | 本地操作与通过条件 |
| --- | --- |
| 连接与聊天 | 配对、主机确认、发送并流式收到回复；断网恢复后同步历史，不自动发送离线草稿；重启 App 后连接可恢复 |
| 界面 | 小屏/横屏、键盘弹出、长文本、中文输入；Sheet 内容和发送按钮可操作 |
| 运行时通知 | 授予通知权限，在通知面板启用后台接收，看到 Android 常驻服务通知；App 切到后台/锁屏后由主机产生新事件，收到本地提醒；点按进入正确对话；停止服务后不被前台恢复静默重启 |
| 权限与省电 | 拒绝通知权限时给出可理解状态；测试厂商省电限制、断网重连、主机重启后恢复；记录手机型号和系统版本。Android 系统“强行停止”后不能靠这个服务持续接收 |
| 语音与相机 | 真机麦克风、扬声器、蓝牙、录音中断、权限拒绝；确认主机 Voice Input 能识别手机音频，照片可上传 |
| Skills/插件/工具 | 读取与调用一个自己的 Skill；对非必需测试插件检查/安装/取消/移除；终端、文件、差异与网页工具结果可展开。不要为测试卸载核心插件 |
| 桌面浏览器 | 在电脑为目标窗口授权，再在手机打开页面、切换标签、点击/输入；撤销授权后控制失效；实际 Electron 窗口需单独确认 |

首版运行时通知不用 EAS、FCM 或 APNs。Android 的可选前台服务使用常驻通知并在后台轮询；系统限制仍可能停止它。iOS 只允许短暂后台执行。暂停/关闭 App 后持续系统推送属于可选云推送能力，需要另行配置平台凭据。

iOS 不使用 ADB 或此 APK，需要在有 macOS/Xcode 和签名的环境进行原生构建与真机调试；当前不把 Android 测试结果算作 iOS 验收。

## 收集结果，再回云端修复

获取少量设备与 App 状态：

```sh
python android-device.py status --serial 192.168.1.20:37002 --output device-status.json
```

App 闪退后获取最近的 Java 崩溃摘要：

```sh
python android-device.py crash --serial 192.168.1.20:37002 --output crash-summary.json
```

报告只保留 API/ABI、App 版本、后台服务是否存在和本 App 的 Java 异常类型/栈帧。脚本不导出原始 logcat、异常消息、设备身份、聊天、凭据或 DSH 文件；已有报告不会被覆盖。摘要可能没有 JS/原生崩溃或已轮转日志，空数组不代表 App 没有故障。回传前检查内容，截图请遮住 App 配对 JSON、密钥和私人对话。

用下面格式反馈，云端据此改代码、跑检查、生成下一版，再由本地更新并复验：

```text
设备型号 / Android 版本：
APK 文件 / SHA-256：
DSH 版本 / 主机插件版本：
复现步骤：
预期结果：
实际结果（含出现时间、前台/后台/锁屏状态）：
附件：已检查的状态 JSON / 崩溃摘要 / 已遮挡的截图
```

本次本地配对、安装、通知、语音、相机和 Electron 真机验收尚未执行。自动测试和构建证据继续维护在[验证记录](mobile-validation.zh.md)，本地实际结果确认后再更新通过状态。
