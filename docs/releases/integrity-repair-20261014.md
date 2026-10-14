## 安装校验修复 / Installation integrity repair — 2026-10-14

原下载地址 `ds-bot-0.1.0.tgz` 已恢复为最初 Actions 发布的原包，匹配旧锁文件的 `sha512-8506Zru5…`。源码提交：`12dcc77718ee15d7b0b8189b032b19a2b4286dc7`。此前重发的 `sha512-she1FgmT…` 文件原样保留为 `ds-bot-0.1.0-republished.tgz`，对应提交 `74bd6cfcd9b64e9c65ed48ca74b16cf2336bac65`。原校验文件保留为 `SHA256SUMS-before-integrity-repair`；当前 `SHA256SUMS` 校验上述两个插件包和未改动的 APK、公开证书。`v0.1.0` 源码标签和 APK 未改动。

**安装和升级请使用 [0.1.1 修订版](https://github.com/QingJ01/DS-Bot-App/releases/tag/v0.1.1)，同步更新插件与 App。** 推荐使用[本地安装助手或 `ds-bot@file:…` 方式](../plugin-install-recovery.md)。显式包名会先替换旧依赖，本地文件避免 pnpm `11.7.0` 缓存远程包时漏写 `integrity` 的另一项问题；只改成 `ds-bot@https://…` 不能解决后者。无需清空锁文件、改写校验值或删除聊天，安装后重启 DSH。直接更新旧 `0.1.0` 地址不会升级到 `0.1.1`。

The original archive has been restored at `ds-bot-0.1.0.tgz`, matching the original `sha512-8506Zru5…` lockfile integrity and source commit `12dcc77718ee15d7b0b8189b032b19a2b4286dc7`. The later `sha512-she1FgmT…` archive is preserved unchanged as `ds-bot-0.1.0-republished.tgz` (source `74bd6cfcd9b64e9c65ed48ca74b16cf2336bac65`). The previous checksum file is archived as `SHA256SUMS-before-integrity-repair`; the current `SHA256SUMS` covers both plugin archives and the unchanged APKs/certificate. The existing source tag and APKs remain unchanged.

Use the [0.1.1 revision release](https://github.com/QingJ01/DS-Bot-App/releases/tag/v0.1.1) for matching plugin/App packages and follow the [local installer or `ds-bot@file:…` instructions](../plugin-install-recovery.md). Naming the dependency replaces the old URL; local archives also avoid pnpm 11.7.0's separate missing-integrity bug for cached remote tarballs. An explicit remote URL alone cannot fix that bug. Do not delete lockfiles/data or bypass integrity checks. Restart DSH afterward.

---

