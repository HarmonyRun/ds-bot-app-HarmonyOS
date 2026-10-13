# Install and configure DS Bot

English | [中文](getting-started.zh.md)

## Requirements

Use a running DSH Desktop computer or DSH Web server, a working model/provider credential configured on that host, and an ARM64 Android phone. The x86_64 build is for matching emulators; ARM32 is not included. iOS requires a separate macOS/Xcode build. The host runs the models, tools and Bots and must remain on. Start with both devices on the same Wi-Fi.

The official npm integration baseline is DSH `0.2.0-rc.2`; CI also checks `0.2.1-alpha.1` compatibility. Keep API keys in DSH's credential UI, never in Git or chats.

## Download matching packages

Use the [v0.1.0 Release](https://github.com/QingJ01/DS-Bot-App/releases/tag/v0.1.0): `ds-bot-0.1.0.tgz` and `dsbot-android-arm64-v0.1.0.apk` for phones, or `dsbot-android-x86_64-v0.1.0.apk` for emulators. The Actions downloads below are for development builds.

Open [Actions → Build plugin and Android](https://github.com/QingJ01/DS-Bot-App/actions/workflows/build.yml). From a successful run for the same commit, download `dsbot-plugin` and `dsbot-android-arm64`; extract the ZIP artifacts first. The plugin is `ds-bot-0.1.0.tgz`; an installable APK is `dsbot-android-arm64.apk`. Names ending in `-unsigned.apk` are not installable: the maintainer must configure the signing Secret and rebuild. `dsbot-android-x86_64` is for emulators. Each artifact includes `SHA256SUMS`.

You can also use matching files from [Releases](https://github.com/QingJ01/DS-Bot-App/releases). **The npm package `ds-bot` is upstream and does not contain this fork's complete mobile implementation.** Install this repository's tarball.

## Host installation

1. Install [DSH Desktop](https://github.com/deepseek-ai/deepseek-harness/releases).
2. In Plugins → Add plugin, enter the downloaded `.tgz`'s absolute path, install and enable it, then fully quit and restart DSH. Existing host data does not need to be removed.
3. In Harness settings, configure your provider and credential. Choose Chief's model and test a message on the computer.
4. Ask Chief to create Bots/groups, or use the client creation pages to set names, roles, instructions and models.

For DSH Web, install Node.js 24 LTS and pnpm, then run in your own workspace:

```sh
npm install -g pnpm
npx @deepseek-ai/dsh@0.2.0-rc.2 plugin --profile web add /absolute/path/ds-bot-0.1.0.tgz
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

- Check that HTTPS is enabled, the QR's address is reachable, and Wi-Fi isolation/firewall is not blocking port `8788`.
- A browser does not trust the automatically generated self-signed certificate. The native App verifies its key from the QR; do not disable TLS validation.
- Pairing waits until the computer approves; regenerate expired QR codes.
- Test the Bot/model on the computer before diagnosing a missing phone reply.
- After plugin updates, restart DSH and confirm you installed this repository's tarball.
- Installation failures: use a signed ARM64 APK, uninstall an old differently signed test App, and check `versionCode`.
- Missing notifications: check permission, receiver activation, battery settings, host availability and network.

[Build/signing guide](releasing.md) · [Local wireless debugging](mobile-local-debug.zh.md) · [Validation record](mobile-validation.zh.md).
