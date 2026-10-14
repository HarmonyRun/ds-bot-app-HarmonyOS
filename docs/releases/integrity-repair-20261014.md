## 安装校验修复 / Installation integrity repair — 2026-10-14

原下载地址 `ds-bot-0.1.0.tgz` 已恢复为最初 Actions 发布的原包，匹配旧锁文件的 `sha512-8506Zru5…`。源码提交：`12dcc77718ee15d7b0b8189b032b19a2b4286dc7`。此前重发的 `sha512-she1FgmT…` 文件原样保留为 `ds-bot-0.1.0-republished.tgz`，对应提交 `74bd6cfcd9b64e9c65ed48ca74b16cf2336bac65`。原校验文件保留为 `SHA256SUMS-before-integrity-repair`；当前 `SHA256SUMS` 校验上述两个插件包和未改动的 APK、公开证书。`v0.1.0` 源码标签和 APK 未改动。

**安装和升级请使用 [0.1.1 修订版](https://github.com/QingJ01/DS-Bot-App/releases/tag/v0.1.1)，同步更新插件与 App。** 在 DSH「插件 → 添加插件」直接填写以下完整包规格：

```text
ds-bot@https://github.com/QingJ01/DS-Bot-App/releases/download/v0.1.1/ds-bot-0.1.1-r2.tgz
```

显式包名让 pnpm 先替换 `ds-bot` 依赖，避免先读取旧地址。无论旧锁记录原包还是重发包，均可采用这个方式；无需清空锁文件、改写校验值或删除聊天。安装完成后完全退出并重启 DSH。直接更新旧 `0.1.0` 地址不会升级到 `0.1.1`。

The original archive has been restored at `ds-bot-0.1.0.tgz`, matching the original `sha512-8506Zru5…` lockfile integrity and source commit `12dcc77718ee15d7b0b8189b032b19a2b4286dc7`. The later `sha512-she1FgmT…` archive is preserved unchanged as `ds-bot-0.1.0-republished.tgz` (source `74bd6cfcd9b64e9c65ed48ca74b16cf2336bac65`). The previous checksum file is archived as `SHA256SUMS-before-integrity-repair`; the current `SHA256SUMS` covers both plugin archives and the unchanged APKs/certificate. The existing source tag and APKs remain unchanged.

Use the [0.1.1 revision release](https://github.com/QingJ01/DS-Bot-App/releases/tag/v0.1.1) for matching current plugin/App packages. Paste the explicit `ds-bot@https://…/ds-bot-0.1.1-r2.tgz` specification shown above into DSH's Add plugin dialog. Naming the dependency lets pnpm replace it before inspecting the old URL, including lockfiles created from the republished archive. Do not delete lockfiles/data or bypass integrity checks. Fully restart DSH after installation.

---

