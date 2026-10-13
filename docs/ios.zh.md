# iOS 构建与支持说明

[English](ios.md) · [返回 README](../README.zh.md)

## 当前状态

仓库提供 iOS 客户端源码，当前 Release 不提供 IPA 或 App Store 下载。iOS 尚未完成编译与真机验收；现有 Android 验证不能替代 iOS 验证。

## 本地运行

需要 macOS、与项目 Expo SDK 兼容的 Xcode、iOS 模拟器和 Node.js 24。真机运行还需配置 Apple 开发签名，并在设备上开启开发者模式。

从仓库根目录执行：

```sh
cd apps/mobile
npm ci
npm run typecheck
npx --no-install expo prebuild --platform ios
npm run ios
```

`prebuild` 生成原生工程并安装所需依赖。原生目录由配置生成，不提交到仓库。真机可通过 `npm run ios -- --device` 选择设备，在 Xcode 中配置 Signing & Capabilities。

使用原生开发构建，Expo Go 不包含本项目的本地 HTTPS 校验模块。原生构建完成后，后续 JS 开发可用 `npm start` 启动开发服务器。更多配置见 [App 开发说明](../apps/mobile/README.md)。

## 连接主机

先按 [安装教程](getting-started.zh.md) 安装 DSH 插件并配置模型。手机与电脑连接同一可达网络，在电脑的 DS Bot **设置 → 移动设备** 启用手机连接，再用 App 扫码并由电脑批准设备。首次连接时允许 iOS 的本地网络访问。

Bot、工具与任务由 DSH 主机执行，使用主机配置的模型；电脑或服务器需要保持在线。

## 后台与发行

iOS 后台执行受系统限制，不提供 Android 式常驻接收服务。应用被挂起后的系统推送需单独配置 Apple 推送凭据与可选 Expo 推送，详见 [通知配置](mobile-features.zh.md)。

正式发行需使用维护者自己的 Apple 签名、Provisioning Profile 和分发渠道；本仓库的 Android 签名不适用于 iOS。发行前应在真机检查 HTTPS 配对、相机与麦克风权限、后台恢复、键盘、安全区域及 VoiceOver，并使用实际主机服务验证语音等功能。
