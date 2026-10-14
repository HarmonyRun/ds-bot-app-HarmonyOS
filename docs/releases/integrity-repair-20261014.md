## 安装校验修复 / Installation integrity repair — 2026-10-14

原下载地址 `ds-bot-0.1.0.tgz` 已恢复为最初 Actions 发布的原包，匹配旧锁文件的 `sha512-8506Zru5…`。源码提交：`12dcc77718ee15d7b0b8189b032b19a2b4286dc7`。此前重发的 `sha512-she1FgmT…` 文件原样保留为 `ds-bot-0.1.0-republished.tgz`，对应提交 `74bd6cfcd9b64e9c65ed48ca74b16cf2336bac65`。原校验文件保留为 `SHA256SUMS-before-integrity-repair`；当前 `SHA256SUMS` 校验上述两个插件包和未改动的 APK、公开证书。`v0.1.0` 源码标签和 APK 未改动。

**安装和升级使用 [0.1.1 修订版](https://github.com/QingJ01/DS-Bot-App/releases/tag/v0.1.1)。** 按[当前安装说明](../plugin-install-recovery.md)在 DSH 粘贴 GitHub 安装文本。旧 `0.1.0` 校验值不匹配时先在 DSH 卸载旧插件，再安装；不要删除聊天或锁文件。旧下载字节恢复与 pnpm 缓存缺少 `integrity` 是两个不同问题。

The original archive has been restored at `ds-bot-0.1.0.tgz`, matching the original `sha512-8506Zru5…` lockfile integrity and source commit `12dcc77718ee15d7b0b8189b032b19a2b4286dc7`. The later `sha512-she1FgmT…` archive is preserved unchanged as `ds-bot-0.1.0-republished.tgz` (source `74bd6cfcd9b64e9c65ed48ca74b16cf2336bac65`). The previous checksum file is archived as `SHA256SUMS-before-integrity-repair`; the current `SHA256SUMS` covers both plugin archives and the unchanged APKs/certificate. The existing source tag and APKs remain unchanged.

Use the [0.1.1 revision release](https://github.com/QingJ01/DS-Bot-App/releases/tag/v0.1.1) and the [current GitHub installation text](../plugin-install-recovery.md). For a legacy 0.1.0 checksum mismatch, uninstall the old plugin in DSH first, then install again; do not delete chats or lockfiles. Restoring old download bytes and pnpm's cached missing-integrity failure are separate issues.

---

