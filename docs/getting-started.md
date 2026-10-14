# Install and configure DS Bot

English | [中文](getting-started.zh.md)

## Requirements

Use a running DSH Desktop computer or DSH Web server, a working model/provider credential configured on that host, and an ARM64 Android phone. The x86_64 build is for matching emulators; ARM32 is not included. See the [iOS guide](ios.md) for builds and platform support. The host runs the models, tools and Bots and must remain on. Start with both devices on the same Wi-Fi.

The official npm integration baseline is DSH `0.2.0-rc.2`; CI also checks `0.2.1-alpha.1` compatibility. Keep API keys in DSH's credential UI, never in Git or chats.

## Download matching packages

Download matching files from the [v0.1.1 Release](https://github.com/QingJ01/DS-Bot-App/releases/tag/v0.1.1). Choose the **r2** plugin and APK for the recent-message ordering fix; verify them with `SHA256SUMS-r2`. Original files remain available for existing lockfiles. Actions downloads below are development builds.

Open [Actions → Build plugin and Android](https://github.com/QingJ01/DS-Bot-App/actions/workflows/build.yml). From a successful run for the same commit, download `dsbot-plugin` and `dsbot-android-arm64`; extract the ZIP artifacts first. The Actions plugin is `ds-bot-0.1.1.tgz` (the Release revision is renamed to `ds-bot-0.1.1-r2.tgz`); an installable APK is `dsbot-android-arm64.apk`. Names ending in `-unsigned.apk` are not installable: the maintainer must configure the signing Secret and rebuild. `dsbot-android-x86_64` is for emulators. Each artifact includes `SHA256SUMS`.

You can also use matching files from [Releases](https://github.com/QingJ01/DS-Bot-App/releases). **The npm package `ds-bot` is upstream and does not contain this fork's complete mobile implementation.** Install this repository's tarball.

## Host installation

1. Install [DSH Desktop](https://github.com/deepseek-ai/deepseek-harness/releases).
2. On Windows, download `dsbot-plugin-installer-v0.1.1-r2.zip` from the Release, extract it and run `prepare-plugin.cmd`. Paste the copied text into Plugins → Add plugin, then install, enable and restart DSH. The helper verifies and saves the package; no separate Node.js or pnpm installation is needed. Other systems can use the local-file method below.
3. In Harness settings, configure your provider and credential. Choose Chief's model and test a message on the computer.
4. Ask Chief to create Bots/groups, or use the client creation pages to set names, roles, instructions and models.

### Updating an existing installation

Use a local archive for first installs, upgrades and reinstalls. The Windows helper saves it in a permanent location and copies the installation text. For manual installation, save the `.tgz` in a permanent folder and enter `ds-bot@file:` followed by its absolute path in **Plugins → Add plugin**:

```text
ds-bot@file:C:/Users/you/DSBot/packages/ds-bot-0.1.1-r2.tgz
```

On macOS/Linux, use a real absolute path such as `ds-bot@file:/Users/you/DSBot/packages/ds-bot-0.1.1-r2.tgz`. Paste the entire line without quotes into the GUI. Restart DSH afterward and update the App. Keep the saved archive for future dependency repairs. Do not delete lockfiles or conversation data.

**Direct GitHub tarball URLs are no longer the recommended installation method.** With DSH's hoisted linker, pnpm `11.7.0` can omit `integrity` when reinstalling a cached remote archive, even with an explicit `ds-bot@` name. Local archive installation retains the correct checksum. See the [installer and recovery guide](plugin-install-recovery.md).

The original `0.1.0` URL has been restored to the initial archive matching `sha512-8506Zru5…`; the later republication is preserved separately. See the [legacy integrity repair](releases/integrity-repair-20261014.md). Upgrade either version using the local specification above.

For DSH Web, install Node.js 24 LTS and pnpm, then run in your own workspace:

```sh
npm install -g pnpm
npx @deepseek-ai/dsh@0.2.0-rc.2 plugin --profile web add "ds-bot@file:/absolute/path/ds-bot-0.1.1-r2.tgz"
npx @deepseek-ai/dsh@0.2.0-rc.2 web
```

Open the local authenticated link printed by DSH on your computer and configure the model. Do not share this management link. Reuse your existing data directory and avoid two processes writing to it. [VPS, tunnel and private-network deployment](mobile-install.zh.md).

## Phone installation and pairing

1. Install the signed ARM64 APK; allow this installation source when Android prompts.
2. On the computer, open DS Bot Settings → Mobile devices → Enable phone connection. The plugin generates a certificate and starts HTTPS, normally on port `8788`. Select the reachable Wi-Fi interface if the host has several adapters; allow private-network firewall access when prompted.
3. In the native App, scan the QR (camera permission required), or paste the complete pairing JSON.
4. On the computer, check the device name and approve it. Open Chief on the phone and send a message.

No domain, additional app or certificate installation is required. The QR contains a short-lived pairing code and host public-key fingerprint; the App verifies the host before saving credentials. Do not share the QR/JSON. Expired codes need regeneration. Restart restores the host entry; a changed IP/network needs a QR with the new address. [HTTPS and identity details](mobile-local-https.md).

Earlier test APKs used debug signing. When switching to the DeepSeekBot release certificate, export any local content you need, uninstall the old App, install the new one and pair again. Host Bots/history remain. Later updates require the same certificate and an increasing Android `versionCode`.

## Configure features

| Feature | Where / prerequisites |
| --- | --- |
| Language and appearance | Home's upper-left fish opens settings; select Chinese/English and light/dark/system |
| Tasks, memory and usage | Settings or Bot/group details; scheduled work needs the host Schedule service and a running host |
| Skills, plugins and connectors | Host-management pages; operations depend on public DSH APIs, with complex plugin interfaces on the computer |
| Images and files | Chat `+` → library, camera or file; understanding depends on host models/tools |
| Voice | Configure host Voice Input and FFmpeg; allow microphone permission; system read-aloud voices may need downloading |
| Desktop browser | Requires DSH Desktop browser capability and explicit host opt-in; a Web-only host does not gain a desktop browser |
| Tool approval | Review the action card and allow once or reject; results are shared with the desktop/other devices |

## Android runtime notifications

In App settings → Notifications, enable background runtime notifications and allow OS notification permission. Android runs a visible, stoppable foreground receiver. Press Home and check a completion notification from the host. The phone must remain connected; force-stop, battery restrictions and network loss can interrupt delivery.

This mode needs no EAS, FCM or APNs. Optional Expo cloud push for suspended/closed apps needs platform setup. iOS has a limited background execution budget and no Android-style persistent service; its source has not been compiled/device-tested here.

## Troubleshooting

- If installation reports missing `integrity`, including after uninstalling, use the helper or local package specification above. Cache deletion and disabling verification are unnecessary.
- Check that HTTPS is enabled, the QR's address is reachable, and Wi-Fi isolation/firewall is not blocking port `8788`.
- A browser does not trust the automatically generated self-signed certificate. The native App verifies its key from the QR; do not disable TLS validation.
- Pairing waits until the computer approves; regenerate expired QR codes.
- Test the Bot/model on the computer before diagnosing a missing phone reply.
- After plugin updates, restart DSH and confirm you installed this repository's tarball.
- Installation failures: use a signed ARM64 APK, uninstall an old differently signed test App, and check `versionCode`.
- Missing notifications: check permission, receiver activation, battery settings, host availability and network.

[Build/signing guide](releasing.md) · [Local wireless debugging](mobile-local-debug.zh.md) · [Validation record](mobile-validation.zh.md).
