# 插件安装修复 / Plugin installation recovery

## Windows

1. 下载 [v0.1.1 本地安装助手](https://github.com/QingJ01/DS-Bot-App/releases/download/v0.1.1/dsbot-plugin-installer-v0.1.1-r2.zip)，**解压整个 ZIP**。
2. 双击 `prepare-plugin.cmd`。助手校验包的 SHA-256，保存到 `%LOCALAPPDATA%\DSBot\packages\v0.1.1-r2`，并复制完整的 `ds-bot@file:…` 安装文本。
3. 打开 DSH **插件 → 添加插件**，粘贴、安装、启用，完全退出并重启 DSH。无需先卸载。

剪贴板不可用时，从助手窗口或保存目录的 `INSTALL.txt` 复制一整行。保留助手保存的 `.tgz`；pnpm 以后修复依赖时可能需要它。解压的助手文件夹可以删除。无需管理员权限，也不要求另外安装 Node.js 或 pnpm。助手只准备文件，最终安装由 DSH 执行。

ZIP 中的插件与公开 `ds-bot-0.1.1-r2.tgz` 完全相同，没有重新打包或改写旧下载：

```text
SHA-256 b79c61fef0f46e4a54c098706b7d578d47f085c10e5c4f111981b829f3da2a8a
```

## macOS / Linux 或手动安装

下载同一 `.tgz`，校验 `SHA256SUMS-r2`，保存到长期保留的目录。在 DSH 添加插件界面填写 `ds-bot@file:` 加绝对路径，例如：

```text
ds-bot@file:/Users/you/DSBot/packages/ds-bot-0.1.1-r2.tgz
```

Windows 手动路径示例为 `ds-bot@file:C:/Users/you/DSBot/packages/ds-bot-0.1.1-r2.tgz`。替换实际路径，GUI 中不要额外加引号；安装后重启。

## 为什么重装也失败

这次的 `ERR_PNPM_MISSING_TARBALL_INTEGRITY` 与此前旧包字节变化导致的校验不匹配是两个问题。我们用 pnpm `11.7.0` 和 DSH 的 `nodeLinker: hoisted`、`autoInstallPeers: false` 配置复现了：首次下载成功，卸载后复用缓存时，新锁文件缺少远程包的 `integrity` 字段，随后安装被拒绝。显式 `ds-bot@https://…` 也会触发。

本地文件安装会计算并写入正确 SHA-512；安装助手在此之前再核对固定 SHA-256。它不修改 DSH、锁文件或聊天，不关闭任何校验。问题发生在插件加载之前，所以插件运行代码无法修复 DSH 内的包管理器；这里修复的是本项目的安装分发方式。远程 URL 重装入口是否恢复正常，需要 DSH/pnpm 后续修复。

回归检查使用真实包和 pnpm，覆盖首次安装、卸载后缓存重装、失败锁文件恢复、删除 `node_modules` 后冻结锁文件重装；Windows 还检查中文/空格路径、助手重复运行、源包/目标包损坏拒绝。见 [Actions](https://github.com/QingJ01/DS-Bot-App/actions/workflows/plugin-installer.yml)。旧版的原始包恢复记录见[这里](releases/integrity-repair-20261014.md)。

## English

Download the [local installer ZIP](https://github.com/QingJ01/DS-Bot-App/releases/download/v0.1.1/dsbot-plugin-installer-v0.1.1-r2.zip), extract everything and run `prepare-plugin.cmd` on Windows. It verifies the fixed SHA-256 above, saves the unchanged plugin under `%LOCALAPPDATA%\DSBot\packages\v0.1.1-r2`, and copies an explicit `ds-bot@file:…` specification. Paste it into **DSH → Plugins → Add plugin**, install, enable and restart DSH. Uninstalling first is unnecessary. If clipboard access fails, copy the line from the console or the destination's `INSTALL.txt`.

The helper prepares files; DSH performs the installation. It requires no administrator access or separate Node.js/pnpm install. Keep the saved `.tgz` for later dependency repairs. The extracted helper folder can be removed afterward. On macOS/Linux, verify the downloaded tarball using `SHA256SUMS-r2`, keep it in a permanent directory, then enter `ds-bot@file:` followed by its absolute path in DSH. Use the examples above, adjusted for your machine.

The failure is reproducible with pnpm `11.7.0` and DSH's hoisted linker: a cached remote tarball loses its integrity metadata during reinstallation. Naming the remote dependency explicitly does not prevent it. Local archive installs retain the correct SHA-512, and the helper additionally verifies the release SHA-256. This changes distribution, not DSH internals: the failure happens before plugin code runs. Restoring remote-URL reinstalls requires a DSH/pnpm fix.

The workflow tests real cold, cached, failed-state and frozen installs on Windows/Linux, plus Windows helper repeatability, Unicode/space paths and corruption rejection. Existing release tarballs, APKs and tags remain unchanged. No lockfile deletion or integrity bypass is involved.
