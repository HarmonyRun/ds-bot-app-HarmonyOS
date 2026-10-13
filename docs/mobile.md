# Mobile client

For the simplest same-Wi-Fi setup, use [one-click local HTTPS](mobile-local-https.md): enable on the computer, scan in the updated native app, and approve. No domain or extra app is required.

English | [中文](mobile.zh.md)

See the [validation record (Chinese)](mobile-validation.zh.md) for completed checks and remaining device tests. This remains a preview.

Development, builds and automated checks run in the cloud; device installation, wireless debugging and native acceptance run on your local computer. See the [local Android handoff guide (Chinese)](mobile-local-debug.zh.md) and [standalone helper](../apps/mobile/scripts/android-device.py). The bundled APK runs without local Metro or the native build toolchain.

The iOS/Android source preview connects to **your own running DSH host**. The React Native app, portable SDK and optional host Bridge live in `apps/mobile/`, `packages/mobile-sdk/` and `ds-bot/src/mobile/`. The Bridge uses protocol version 1 and the same DSH process, team and data as Desktop/Web. It does not start another agent runtime or a cloud account service.

The [original implementation plan, in Chinese](mobile-plan.zh.md) records the broader roadmap. The [parity matrix, in Chinese](mobile-parity.zh.md) records the original DS Bot/Harness behavior and platform boundaries. This guide describes the current setup and limits. Commands and acceptance cases below are instructions, not evidence that a particular device or release build has passed them.

## Prerequisites

- DSH `0.2.1-alpha.1` with DS Bot from this checkout and a working model configuration. Set up Chief's model on the host first.
- Node.js `22.19` or later and the [repository development prerequisites](../CONTRIBUTING.md#setup) for building the plugin.
- For a phone: an HTTPS address reachable from it, with a certificate trusted by the device. A private VPN with HTTPS is suitable. A VPN alone does not make an HTTP URL an HTTPS URL.
- For native development: Android SDK/JDK and an emulator or device; for local iOS builds, macOS/Xcode and the required signing setup. Supported cloud builds are another option, with their own account and signing requirements.
- Optional transcription: a configured DSH whole-clip speech-to-text provider and `ffmpeg` on the host where audio conversion is needed. Text chat does not require ASR.

Use the existing DSH process and its existing `DSH_HOME`. Do not start a second Web/desktop process against the same home to serve the phone. If the host sleeps, stops or loses network access, it cannot answer the phone.

## Install the host preview

Build a local plugin package from the repository root:

```sh
cd ds-bot
npm ci
npm run build
npm pack
```

In DSH Desktop, use **Plugins → Add plugin** with the absolute path to the resulting `ds-bot-0.1.0.tgz`, then restart DSH. Use the package from this checkout; an older registry release may not contain Mobile Bridge. For an existing DSH Web profile, the corresponding install command is:

```sh
npx @deepseek-ai/dsh@0.2.1-alpha.1 plugin --profile web add /absolute/path/ds-bot-0.1.0.tgz
```

Configure the `bot` entry in the profile's `cordis.patch.yml`. For Web, a separate `mobile.patch.yml` can hold the following overlay:

```yaml
- id: bot
  config:
    mobile:
      enabled: true
      host: 127.0.0.1
      port: 8788
      publicUrl: https://bot.example.com
```

**A DSH patch replaces the entire `bot.config`; it does not merge nested keys.** Preserve all existing options such as `home`, `workspace` and memory/model-related preferences when adding `mobile`. Keep this machine-specific patch outside the repository. `publicUrl` is the HTTPS origin the phone can actually reach, without a path prefix.

After stopping the existing Web instance, start it with the overlay:

```sh
npx @deepseek-ai/dsh@0.2.1-alpha.1 web --patch /absolute/path/mobile.patch.yml
```

For Desktop, merge the options into its existing `<DSH_HOME>/profiles/desktop/cordis.patch.yml`, fully quit Desktop, then reopen it. The CLI cannot boot `--profile desktop`; that profile belongs to Electron. Keep using the same DSH home as before.

## Provide HTTPS

Choose one route. Do not expose DSH's existing browser port: its cookie/Host/Origin authentication is separate from Mobile Bridge.

**Reverse proxy on the same host.** Leave Bridge on `127.0.0.1:8788`. With a domain you control and working certificate issuance, a Caddyfile can be:

```caddyfile
bot.example.com {
    reverse_proxy 127.0.0.1:8788
}
```

Set `publicUrl` to `https://bot.example.com`, point the name at the Caddy host, and run Caddy with that file, for example `caddy run --config /absolute/path/Caddyfile`. Caddy forwards WebSocket upgrades. Public certificate issuance requires the appropriate DNS/challenge setup; this example does not create a domain or open firewall ports for you. A private deployment should restrict access to its private network.

**Private VPN with HTTPS.** Join the phone and DSH host to your private network, then configure its HTTPS serving feature to forward to `http://127.0.0.1:8788`. For example, use Tailscale Serve with a valid HTTPS tailnet name, not Funnel/public exposure. Set `publicUrl` to the actual resulting HTTPS origin. Verify phone reachability and certificate trust before pairing.

**Direct TLS.** Supply a matching certificate chain and key on the host:

```yaml
- id: bot
  config:
    mobile:
      enabled: true
      host: 0.0.0.0
      port: 8788
      publicUrl: https://bot.example.com:8788
      certPath: /absolute/path/fullchain.pem
      keyPath: /absolute/path/privkey.pem
```

A non-loopback listener requires TLS. Limit network reachability to your intended devices; protect the private key and keep it outside the checkout. The phone must trust the certificate and its hostname. A self-signed certificate without installed trust will fail; disabling verification is not a deployment method.

## Build the phone app and pair

From the repository root:

```sh
cd apps/mobile
npm ci
npm run typecheck
npm run android
```

On macOS, use `npm run ios` for iOS. These use Expo development builds and need their native SDKs; Expo Go is not the acceptance environment. After installing a development build, `npm start` runs Metro for it. Configure your own application identifiers and signing before distributing a release; credentials and signing material must stay out of the repository.

1. On the host, open DS Bot **Settings → Mobile devices** and generate a pairing code.
2. In the app, scan the QR code or paste its complete pairing JSON. Check the host identity and enter a device name.
3. Confirm the pending device on the host. The one-time pairing code alone does not grant access.
4. Open Chief or an existing Bot/group. A Bot's conversation continues across its internal context parts.
5. To remove access, revoke that device on the host. Removing the local app connection and revoking host authorization are distinct operations.

Treat the pairing QR/JSON as a temporary credential: do not include it in screenshots or bug reports. The app stores device credentials using native secure storage; model keys remain on the host. Every paired device acts for the same owner and may ask Bots to run host tools. There are no separate team-member accounts or read-only guest roles in this preview.

## Build an Android APK for personal testing

Expo SDK 54 / React Native 0.81 uses JDK 17, Android SDK/build-tools 36, NDK `27.1.12297006` and CMake `3.30.5` here; native dependencies also require build-tools `35.0.0` and CMake `3.22.1`. Install the [official Android command-line tools](https://developer.android.com/studio#command-tools) and verify their published SHA-256 before extraction. Set `JAVA_HOME` to JDK 17 and `ANDROID_HOME` to your SDK directory. An emulator image is not needed to compile an APK.

```sh
sdkmanager --licenses
sdkmanager 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0' 'build-tools;35.0.0' 'ndk;27.1.12297006' 'cmake;3.30.5' 'cmake;3.22.1'
```

From `apps/mobile/`, after `npm ci`:

```sh
npx expo prebuild --platform android --no-install
cd android
./gradlew :app:assembleRelease -PreactNativeArchitectures=arm64-v8a --max-workers=2 --no-daemon
```

This targets 64-bit ARM phones and bundles the JavaScript so Metro is not needed at runtime. Generated `android/` files and build output are ignored by Git. A successful task produces `android/app/build/outputs/apk/release/app-release.apk` relative to `apps/mobile/`.

**The generated template currently signs this release task with the standard Android debug key.** It is only a personal test package, not a production signing configuration or store release. Use your own protected signing setup and application identifiers for distribution. To verify/install a locally built test package from `apps/mobile/android/`:

```sh
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose app/build/outputs/apk/release/app-release.apk
"$ANDROID_HOME/platform-tools/adb" install -r app/build/outputs/apk/release/app-release.apk
```

The install step needs your connected, authorized Android device. Compilation does not validate recording, camera access, HTTPS pairing or lifecycle behavior on that device. iOS still needs a separate native build and device validation on the appropriate platform.

For restricted build hosts, Java/Gradle may need explicit proxy configuration even when `curl` works. Use the environment's existing proxy and trusted system CA store; keep certificate verification enabled. Gradle 8.14.3's official distribution SHA-256 is `bd71102213493060956ec229d946beee57158dbd89d0e62b91bca0fa2c5f3531`; it can be set as `distributionSha256Sum` in generated `android/gradle/wrapper/gradle-wrapper.properties` to verify that download.

## Chat, attachments and voice

- Use the conversation list to pick a Bot or group. Creating another Bot is an explicit team operation, not a hidden “new part” action.
- Text streams while connected. After reconnecting, the app retrieves host history and state. Stopping a current generation does not promise to erase every queued team message.
- Attachments include PNG/JPEG/WebP/GIF images (up to 10 MiB each) and files (up to 20 MiB each). The native picker converts HEIC images to JPEG. UTF-8 TXT/MD can supply text; other files use Harness file uploads, and their usefulness depends on host tools and model support. Uploading a PDF/Office file does not promise document parsing. Staged uploads expire after 15 minutes; the host may set a smaller transport limit. An upload is bound to its current Session; if the Bot advances to another part, prepare the attachment again when prompted.
- Images require a visual model or a configured image-to-text route on the host. Group handling can pass textual descriptions rather than original images to each member.
- **Voice input** transcribes a whole clip into an editable draft. The separate **Voice chat** mode starts explicitly: a pause after speech triggers transcription and automatic submission, reads the reply associated with that accepted request, then resumes listening. Pause, backgrounding, disconnection and recording interruptions stop the microphone; reconnecting requires an explicit resume. There is no streaming ASR or automatic fallback to a paid cloud provider. Recordings are limited to 60 seconds and 10 MiB. In the host's **Plugins**, enable **Voice Input**, open its details, and complete **Download and prepare** for the local recognizer. Where necessary, `ffmpeg` converts audio to 16 kHz, mono PCM16 WAV. Model preparation is separate from pairing.
- Read-aloud uses the phone's system TTS. Available voices and whether voice downloads/network access are required depend on the device.
- Tool approval cards are distinct from Bot questions. They show the host's pending action and support allow/deny through a shared host broker. A decision on another device, cancellation or expiry invalidates the card; reconnecting does not approve it automatically. The host still enforces its approval policy.

## Team and host settings

Bot/group details, Main Bot roles, appearance, memory, schedules and usage use the same host team state. Online history search queries the host across conversation parts; it requires a connection. Host configuration exposes supported schema fields with revision checks, existing credential references, plugin package inspection/installation/removal and activation, scoped Skills discovery/invocation and library management, and the DS Bot host plugin updater. Language can follow the host or system, or be set locally to English/Chinese. Main navigation and settings have native translations; some detailed statuses, errors and plugin-provided descriptions still fall back to English.

Connectors and Secrets display metadata and permissions. New values are masked, submitted once over HTTPS and cleared on submission or leaving the foreground; they are never placed in drafts, cache, replay queues or responses. Feedback previews diagnostics locally; copying, exporting logs and opening an issue each require a user action. No report is sent automatically.

Complex conditional configuration forms, adding/removing collection entries and custom browser-only plugin pages still require the host's corresponding settings page. Existing collection values can be edited individually. Plugin changes report when a host restart is needed or another profile overrides the change. The DS Bot plugin that maintains the connection must be managed on the host. The host plugin updater does not update this phone app.

## Data and current limits

The host owns Sessions, Bot state, memories and model credentials. Mobile stores a local SQLite cache of messages and drafts. **That SQLite cache is not encrypted by this app**; it relies on the operating system's app storage protection. Device credentials use Keychain/Keystore-backed storage. Each conversation caches up to 1,000 final messages; the cache is not a complete copy of host history. **Clear cached history and drafts** preserves unresolved sends, their drafts and archived submissions from previous pairings, including their original message content. Archiving is not deletion. Disconnecting removes the saved connection and credentials but keeps server-scoped cached data. To erase retained records completely, use the operating system's app-data removal (delete the app on iOS, rather than offloading it), or clear the preview site's browser storage. Revoking a device does not remotely erase its cache or cancel work already accepted by the host.

Offline use is limited to already-cached content and drafts. The app does not automatically send offline drafts or replay actions after reconnecting. An uncertain submission is queried by its retained request ID before retrying. Host restarts can interrupt work; recovery must not silently repeat external side effects.

This preview has one active host, no SaaS account/billing, no duplex voice, Desktop browser control requiring per-window opt-in and no promise of arbitrary PDF/Office parsing. Runtime notifications need no EAS/FCM/APNs: Android uses a visible foreground messaging service, and iOS uses its limited background-task budget. Expo cloud push for suspended/closed apps is optional and requires platform credentials. The web preview does not validate native audio, secure storage or device lifecycle behavior.

## Development checks

Run each block from the repository root:

```sh
cd packages/mobile-sdk
npm test
```

```sh
cd apps/mobile
npm ci
npx expo install --check
npm run typecheck
npm test
npm run export
```

```sh
cd ds-bot
npm ci
npm run build
npm test
node scripts/build-client.mjs --check
```

Plugin tests use the Harness checkout described in [CONTRIBUTING](../CONTRIBUTING.md). Host changes also require its mock smoke test. Tests must use `.dsh-test-<name>/`, never the user's real DSH home. Stop all benches and processes you start. `npm run export` produces JavaScript/assets, not a signed APK/IPA and not a native device test.

The mobile protocol smoke test exercises a real DSH process with the mock model. From `ds-bot/`, using free ports:

```sh
MOBILE_PORT=8789 CONTEXT_WINDOW=100000 dev/bench.sh mobile-smoke 3098 8798 reset
node dev/mobile-smoke.mjs mobile-smoke 3098 8789
dev/bench.sh mobile-smoke 3098 8798 stop
```

`reset` clears this named test bench only. Run the stop command even when a check fails. This flow checks that missing ASR is reported; it does not test a real recognizer's audio quality.

For a local mock host with the browser preview, choose free ports and start a bench from `ds-bot/`:

```sh
MOBILE_PORT=8894 MOBILE_WEB_ORIGIN=http://localhost:8081 dev/bench.sh mobile 3193 8893 start
```

In another terminal, run `npm run web -- --port 8081` from `apps/mobile/`. Open the preview as `http://localhost:8081`; its exact origin must match the bench allowlist. Pair through the bench's authenticated DS Bot **Mobile devices** page. When finished, run `dev/bench.sh mobile 3193 8893 stop` from `ds-bot/` and stop Metro. `start` preserves existing bench data; use a different bench name for a fresh dataset.

For browser/simulator work only, Bridge can explicitly enable `devAllowInsecure: true` on a loopback HTTP listener, and the app's development-only HTTP option must also be enabled. Do not bind this to a LAN address. A physical phone's `localhost` is the phone itself; use HTTPS to reach the computer. Browser-preview credentials are memory-only and disappear on reload.

## Manual acceptance before a device release

Record the commit, DSH version, host OS, phone OS/device, network and result for each case. A passed unit test or web export does not mark these cases passed.

| Case | Expected result |
|---|---|
| Pairing | Expired/reused codes fail; a new device waits for host approval; revocation blocks new requests and existing streams |
| History | Phone and host show the same Bot/group messages; older parts paginate without mixing private and group chats |
| Retry/reconnect | Lost acknowledgments, network changes and app restarts do not duplicate accepted submissions or final messages |
| Host lifecycle | Sleep/stop appears offline; foreground return recovers history; host restart does not approve stale requests or replay actions |
| Attachments | Allowed images and files reach the intended Bot; invalid types, interrupted uploads and part changes are recoverable |
| Audio | Permission denial, transcription failure, audio interruption and TTS cancellation recover on iOS and Android |
| Team and approvals | Bot/group changes match the host; questions and tool approvals remain distinct; multiple devices cannot decide a request twice |
| Host settings | Stale revisions fail safely; secret values never appear in cache or errors; plugin changes reflect actual host state |
| Two devices | Both view the same host; revoked device loses access; another device continues normally |
| Data | Cached messages are usable offline; drafts stay unsent; clearing local data does not delete host history |

For initial voice acceptance, select at least one actual host OS and one working ASR provider. Other host platforms remain separate compatibility checks. Do not infer camera, audio, signing, store readiness or cross-platform support from this guide.

## Troubleshooting

| Symptom | Check |
|---|---|
| No Mobile devices page | Install/build this checkout's plugin and restart; do not assume the published package includes it |
| Host unreachable | DSH and Bridge are running; `publicUrl` resolves from the phone; VPN/proxy/firewall route is correct |
| HTTPS fails | Certificate hostname, chain and phone trust; never bypass TLS verification |
| Pairing waits/expires | Approve on the host while the window is active; generate a new code if it expired |
| Connected but no reply | Select a working model for the Bot on the host; inspect host status rather than re-pairing repeatedly |
| Voice unavailable | Enable a supported DSH whole-clip ASR provider and verify `ffmpeg`; text chat still works |
| Upload fails after a long chat | Refresh the current target and reattach; upload receipts cannot cross Session parts |

Share redacted error messages and versions when reporting a problem. Do not include pairing payloads, device credentials, model keys or personal Session files.

## Files and full conversation export

Tap a file in a message to download it and use the system share sheet to save or open it. Common text formats preview the first 64 KiB without executing HTML or scripts. The host verifies the owning Session, exact visible message reference and complete file before serving downloads up to 20 MiB.

Choose **Export conversation** in chat history to export all available host history across parts as Markdown or JSON. Attachment metadata is included; download file bytes separately. Device credentials, submission receipts and uncommitted stream fragments are excluded. Cancellation and invalid pagination do not produce partial exports. Mobile exports are limited to 50,000 messages and 32 MiB; use the host for larger histories.

## Additional mobile features

The preview now includes scoped Skills, a host-owned skill library, inspected/pinned plugin installation and removal, dedicated tool cards, avatar interaction, opt-in Desktop control and a durable notification inbox. The Android APK includes a runtime background receiver that needs no platform push credentials; iOS runtime reception is limited by its background-task budget. Optional Expo cloud push is unconfigured. Native background delivery, physical devices and Electron remain unverified. See [feature details](mobile-features.zh.md).
