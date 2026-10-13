# GitHub Actions、Android 签名与发布

[English](releasing.md) | 中文

## 签名已经准备好

仓库的 `apps/mobile/signing/` 保存加密的 `DeepSeekBot.p12`、公开证书 `DeepSeekBot.cer` 和证书 SHA-256 指纹。签名身份是 `CN=DeepSeekBot, O=DeepSeekBot, C=CN`，别名 `deepseekbot`，RSA 4096，有效期 10,000 天。

**密码没有提交到仓库。** 所有者得到的私密备份 ZIP 包含签名文件和 `ANDROID_KEYSTORE_PASSWORD`，请离线妥善保存，不要把 ZIP、密码或包含密码的配置上传 GitHub。加密文件虽可公开，持有它和密码的人可以签署更新。

### 一次性配置 Secret

当前应用授权不能管理 GitHub Secrets，因此维护者需要在 GitHub 完成这一步：

1. 打开本仓库 **Settings → Secrets and variables → Actions → New repository secret**。
2. Name 填 `ANDROID_KEYSTORE_PASSWORD`。
3. Secret 填私密备份中同名文件的完整内容，保存。不要加引号或放到 Variables。
4. 打开 **Actions → Build plugin and Android → Run workflow**，选 `main` 重新运行。

如果 GitHub 显示工作流未启用，先在 Actions 页面启用。不要把生产签名密码提供给来自外部 fork 的 PR 工作流。仓库拥有者的 main/manual 构建才需要签名。

## 工作流会做什么

`.github/workflows/build.yml` 在推送 main、PR、手动运行和 `v*` 标签时触发：

1. 安装锁定依赖，验证插件测试/生成文件/静态检查、SDK 测试、App TypeScript/测试、本地调试脚本测试。
2. 打包插件 `.tgz`，附校验和并上传 `dsbot-plugin`。
3. 在 Java 17、Node 24、Android SDK 上通过 Expo prebuild 生成原生工程，构建 ARM64 和 x86_64 独立 release APK，JS 已打包，无需手机连接 Metro。
4. 有 Secret 时使用项目签名文件签署 APK，验证签名证书与仓库指纹一致；没有 Secret 时仅上传 `-unsigned.apk`，日志给出警告。这种文件不能安装，构建通过也不代表已完成签名。
5. 为 APK 上传校验和及公开证书。`versionCode` 使用工作流 `run_number`；重新运行同一运行保持同一版本号。

`.github/workflows/test.yml` 另外执行 Linux/Windows、Node 22/24 和两个 DSH 版本的插件兼容性检查。iOS 不在这两个 Linux 构建工作流中，不需要 EAS 项目；iOS 发行需单独配置 Apple 签名。

## 下载与标签发布

在成功运行底部的 Artifacts 下载并解压。ARM64 给手机、x86_64 给模拟器，主机安装同一提交的 `dsbot-plugin`。普通 main 构建只上传 Actions artifacts，不创建 Release。

需要发布时，先检查签名 Secret、两个 APK 和插件均通过。将 `ds-bot/package.json`、`apps/mobile/package.json`、两份锁文件及 `apps/mobile/app.json` 的版本更新为标签对应版本，并在 `docs/releases/v主版本.次版本.修订版本.md` 写双语说明。标签校验会在构建前拒绝缺少签名配置、版本不一致或缺少说明的发布。然后创建唯一的正式版本标签，例如：

```sh
git tag v0.1.0
git push origin v0.1.0
```

标签工作流重新构建并创建正式 Release，附配套 `.tgz`、两种已签名 APK（例如 `dsbot-android-arm64-v0.1.0.apk`）、公开证书与总校验和。如果缺少签名 Secret，标签校验失败，不会把未签名包发布成可安装版本。签名密码、私密备份、原生数据与 DSH_HOME 不会作为产物上传。

Artifacts 有 GitHub 保留期限，需要长期保存的版本使用 Releases。Release 的校验和按下载后的平铺文件名记录；Linux 在下载目录执行 `sha256sum -c SHA256SUMS`，macOS 用 `shasum -a 256 -c SHA256SUMS`，Windows 用 PowerShell `Get-FileHash 文件名 -Algorithm SHA256` 核对。

## 本地构建与签名

需要 Node 24、Java 17、Android SDK 36 / Build Tools 36、NDK `27.1.12297006` 和 CMake。Expo/Gradle 按锁定版本下载组件。

```sh
cd apps/mobile
npm ci
npm run typecheck
npm test
DS_BOT_ANDROID_VERSION_CODE=100 npx --no-install expo prebuild --platform android --no-install
cd android
./gradlew assembleRelease --no-daemon --max-workers=2 -PreactNativeArchitectures=arm64-v8a
cd ..
```

`versionCode` 必须高于你已经安装的版本。CI 的运行编号也需要保持高于本地已发行版本，避免随意用高编号发布本地包。将私密密码加载到 `ANDROID_KEYSTORE_PASSWORD` 环境变量，不打印它；设置 `ANDROID_HOME` 后执行：

```sh
bash scripts/sign-android.sh android/app/build/outputs/apk/release/app-release-unsigned.apk dsbot-android-arm64.apk
```

脚本不从命令行接收明文密码，并核对证书指纹。Expo 的默认调试签名不会用于 release。首次替换旧调试 APK 需卸载、重装、重新配对；以后不能随意重建签名密钥，否则无法覆盖更新。切换签名不影响主机保存的 Bot/聊天。

插件本地打包：

```sh
cd ds-bot
npm ci
npm run harness
npm run build
npm test -- --test-concurrency=2
npm run lint
npm pack
```

请自行 fork 的维护者生成自己的签名、替换公开证书/指纹并更改 App application ID，避免混用本项目身份。
