# DS Bot Mobile

An original native iOS and Android client for a user's own DSH host. This app uses the optional DS Bot mobile bridge and the shared `@ds-bot/mobile-sdk`. Bots, models, tools, and saved team data run on that host. Credential management submits new values to the host without saving them in the phone's message or draft cache.

## Run

Use Node 22 or newer and npm. From `apps/mobile`:

```sh
npm ci
npm run typecheck
npm test
npm run start
```

Build the native development app with `npm run android` (Android SDK and Java 17+) or `npm run ios` (macOS, Xcode, and a configured signing team for physical devices). Expo development builds are the supported native development target. Set a unique bundle identifier and Android package before distributing your own build. Release Android APKs use the encrypted project key and a private password; see [Actions and signing](../../docs/releasing.md). Apple distribution and Google Play signing belong to the app owner.

The companion bridge must already run on the user's computer/server. On the DSH desktop, open **Settings → Mobile devices**, generate a pairing code, and scan it or paste its JSON. Confirm the pending device on the computer. The QR contains a short-lived pairing code, not model credentials. The app verifies the advertised server ID before pairing.

A real device needs a reachable **HTTPS** host. The plugin can generate local HTTPS automatically; the native App verifies the host public key from its pairing QR. No domain, extra app or installed certificate is needed on the same Wi-Fi. Public HTTPS with a system-trusted certificate remains supported. See [one-click local HTTPS](../../docs/mobile-local-https.md). Local development builds expose an explicit **loopback-only HTTP** switch for browser/simulator testing. Production builds never permit HTTP. Android emulators can use `adb reverse tcp:8789 tcp:8789` and loopback for development. There are no TLS verification bypasses.

The public `/mobile/v1/info` handshake must be reachable from the device. Keep the host awake and DSH running. Host disconnection leaves cached conversations and drafts available; the app does not automatically send offline drafts.

## Browser preview

```sh
npm run web -- --port 8081
```

This is a development preview of the same React Native interface, not the shipped app. Device credentials remain in tab memory and are lost on reload. Native builds persist credentials with SecureStore (Keychain/Keystore) and messages/drafts with SQLite; the browser preview uses localStorage for non-credential cache only. Both caches partition data by server ID. Browser permissions and audio formats can differ from physical devices.

```sh
npm run export
```

Exports iOS and Android JS bundles and a static web preview to ignored `dist/`. This validates JS packaging; it is not a signed iOS/Android application build or a physical-device test.

For constrained cloud workspaces where the default user home is read-only, the build commands can use:

```sh
EXPO_NO_TELEMETRY=1 \
__UNSAFE_EXPO_HOME_DIRECTORY=/workspace/.cache/expo \
npm_config_cache=/workspace/.cache/npm \
npx expo export --platform all
```

This redirects Expo's cache; it does not disable package, checksum, or TLS verification.

## Implemented flows

- Pairing QR/manual JSON, host identity check, desktop confirmation, per-device revocation.
- The original team's Main Bots, Bots, groups, and ordinary DSH Agent conversations in a full-screen conversation home; floating profile/search/new-chat controls, grouped settings, conversation search, pin/hide, unread and working states, long-press message actions, details, original character avatars and theme preferences. A Bot keeps one logical conversation across its saved parts.
- Host model selection, streamed text and reasoning, tool calls/results, group member replies, quoted replies, local reactions, Markdown with tables/lists/links/code, copy/share, individual-message Markdown download, and system text-to-speech. Connection state and host execution state are separate.
- Earlier history, cross-part host message search with continuation, saved-part browsing and selected-message context, reconnection, and offline drafts. Waiting host messages are shown separately with explicit queue removal; stopping a reply retains queued messages until a later send resumes them.
- Stable client request IDs persisted before sending. Retry first queries the original receipt. Unknown outcomes are retained for reconciliation; explicit rejection allows recomposing without silently retrying a different request. Send records also bind the device credential: after re-pairing, previous unconfirmed sends become read-only and cannot be replayed. They can be archived to start an empty draft. Clearing the normal cache preserves these records and any unresolved drafts.
- Bot creation, editing, duplication, characters/colors/photos, Main Bot roles and handover; groups with at least two members, optional names, notices, administrators, and Admin leads/Everyone modes. Ordinary DSH Agent sessions can be created, renamed, opened, and archived without becoming Bots.
- User question cards and shared desktop/mobile tool approvals. Approvals show the pending action, allow once or reject, and withdraw on cancellation; another device cannot answer an already settled request.
- Memory summaries and all entries, private/team/topic grouping, character limits, ask/update, regeneration, and removal. Scheduled tasks support once, daily, weekly, and repeating intervals for Bots or groups when the host's Schedule service is available.
- Usage uses the host's actual hourly records, including cache writes in input totals: 24h/7d/30d/12w/12m/custom dates, Bot/group and model filters, previous-period comparisons, stacked charts, rankings, and activity history.
- JPEG/PNG/WebP/GIF images (10 MiB) and files of other MIME types (20 MiB), including PDF/Office/archive uploads through the host's public file-upload service. Host limits may be lower, and interpretation depends on its tools and models. Images are displayed and downloaded with conversation/session ownership checks; generic files currently display metadata without a mobile download or document viewer.
- Camera/library/file picking. Voice recordings up to 60 seconds are transcribed by the host; Voice input leaves an editable draft. The separate Voice chat mode explicitly starts a listening → transcription → accepted reply → read-aloud loop; pause, backgrounding, interruptions, or disconnection stop recording. The host needs Voice Input configured and FFmpeg for native AAC/M4A or browser WebM normalization. No cloud ASR fallback is silently selected.
- Host administration: connector state/connect/retry/disconnect; secret metadata, request cards, scopes, save/delete; credential configured/source/writable states; diagnostics and explicit report sharing; public Harness setting schemas with per-field edits and revision checks. Settings and new credentials require HTTPS. Loopback development permits only synthetic `ds-bot-test-` credential values and rejects all Harness setting writes.
- Installed plugin/bundle inventory and supported enable/disable operations, workspace skill discovery, and DS Bot host-plugin update checks/install. Updating that plugin does not update the phone app. Required management/mobile plugins remain protected from disabling through the phone.

## Current boundaries

| Area | Current scope |
| --- | --- |
| Language | The phone can follow the host/system language or select English/Chinese. Navigation, team settings, chat, attachments, voice, history, Memory/Usage/Schedules and host controls have Chinese translations. User content and plugin-provided schema text remain original; some uncommon dynamic messages still fall back to English. |
| Host settings | Public schema fields and credential references are editable when supported. Complex collection/conditional editors and plugin-specific browser interfaces still need their original host UI. |
| Plugins and skills | Inspect/pin/install/cancel/remove supported packages, manage installed activation, discover/invoke scoped Skills, and edit the host-owned skill library. Protected management/mobile plugins remain protected; arbitrary plugin-specific browser interfaces require their host UI. |
| Desktop browser | Read available host Bot-page information/content. Desktop opt-in enables fixed tab/page controls; browser cookies stay on the computer. Native Electron control is not yet device-tested. |
| Ordinary Agent sessions | Create and manage sessions belonging to the team's DSH Agent. Adopting arbitrary external sessions and reproducing every Harness terminal/plugin-specific surface are not implemented. |
| Files and exports | Authenticated image and generic-file downloads, bounded plain-text preview, and complete available conversation history export to Markdown/JSON across parts. Files are capped at 20 MiB; exported attachment metadata does not include file bytes. |
| Voice | Editable voice input plus a separate explicit listening/transcription/reply/read-aloud loop. No streaming ASR or realtime full-duplex voice. Physical-device microphone, interruption and TTS behavior remain unverified. |
| Offline and background | Cached messages/drafts remain local. Optional native runtime receiver needs HTTPS and notification permission, but no EAS/FCM/APNs: Android uses a visible, stoppable foreground messaging service; iOS uses its limited background-task budget. Expo cloud push is optional for suspended/closed apps and requires platform credentials. Physical-device lifecycle remains unverified. |

The original-feature protocol smoke has passed 24 steps against a real isolated DSH host and the scripted mock model, including four schedule forms, memory/usage, search/context, Agent runtime, credential boundaries, and shared approval allow/reject/cancel. It uses `MOBILE_PARITY=1` with the explicit bench-only approval fixture; see [the smoke script](../../ds-bot/dev/mobile-smoke.mjs). This proves host integration, not physical-device behavior or complete visual/localization parity. The loopback smoke verifies HTTPS rejection for settings writes; it does not exercise a successful HTTPS settings mutation. Detailed evidence and remaining checks are tracked in [the parity checklist](../../docs/mobile-parity.zh.md) and [validation record](../../docs/mobile-validation.zh.md).

The browser parity run also passed 43 UI checks, including real memory/task changes and shared approvals. New checks cover exact UTF-8 file preview/download, Unicode filenames and JSON history export. Eight additional controlled voice lifecycle checks use fixture ASR and silent TTS callbacks; they do not prove audible device speech. Memory, Schedules, and Usage screenshots were inspected at a 390-pixel viewport. These browser checks do not replace native-device verification.

To reproduce with the repository's configured Harness checkout and free test ports, run from `ds-bot/`:

```sh
PARITY_APPROVAL=1 MOBILE_PORT=8791 CONTEXT_WINDOW=100000 \
  dev/bench.sh mobile-parity 3102 8802 start
MOBILE_PARITY=1 node dev/mobile-smoke.mjs mobile-parity 3102 8791
dev/bench.sh mobile-parity 3102 8802 stop
```

Use a new bench name for a clean profile and run the stop command even if a check fails. `PARITY_APPROVAL=1` loads a harmless, explicitly scoped test tool that only calls Harness's public approval service. It never executes a command or changes a file. The tested Harness revision `5badb15` includes Schedule in its Web profile by default; a separate freshly created bench verified both desktop and mobile `schedules.available=true`. Do not add the retired `@deepseek-ai/dsh-experimental-schedule-bundle`. Other host profiles must provide the public Schedule service; an unavailable service is not a successful scheduled task.

## Validation still requiring devices

Development, builds and automated checks stay in the cloud; phone installation, wireless debugging and native acceptance run locally. The [local handoff guide (Chinese)](../../docs/mobile-local-debug.zh.md) includes the standalone Python/ADB helper; the bundled test APK needs no local Metro or native build toolchain.

Before distributing, test iOS and Android physical-device pairing, camera permission denial, microphone interruptions, Bluetooth routing, background/resume, keyboard layout, VoiceOver/TalkBack, and long histories. Test native audio against the actual configured host's Voice Input model. OS text-to-speech voices may need a download. Optional push needs platform configuration and device testing. No always-on background socket, app-store publication, or realtime full-duplex voice is included.

The source is split into `screens/`, reusable `components/`, transport lifecycle `hooks/`, platform storage adapters, and small tested submission logic. The protocol and most transport tests live in `packages/mobile-sdk`.

Scoped Skills, a managed skill library, plugin package installation/removal and dedicated tool cards are implemented. See [the six-feature guide](../../docs/mobile-features.zh.md) for deployment and verification limits.

The mobile UI uses brand blue `#3964FE` and follows system light/dark mode. The fish opens settings from home and animates on launch; reduced motion uses a static fade. Long-press actions provide direct reactions and compact reply/copy/share/save/read controls. One-to-one message bodies hide avatars, while group messages show their speaker. Chat headers use an independent floating avatar-and-name pill, with separate back/more circles and gaps that pass scrolling gestures to the transcript.

The pinned upstream port adds Bot mentions, cached chat-reference chips, thinking levels, permission presets, member work/approval status, grouped turn reasoning and an About/update page. Update the host plugin together with the app; see [the migration and validation notes](../../docs/mobile-upstream.zh.md).
