# iOS builds and platform support

[中文](ios.zh.md) · [Back to README](../README.md)

## Current status

The repository includes iOS client source. Current Releases provide no IPA or App Store download. iOS compilation and physical-device validation are still pending; Android validation does not establish iOS support.

## Run locally

Use macOS, Xcode compatible with this project's Expo SDK, an iOS simulator and Node.js 24. Physical devices also require Apple development signing and Developer Mode.

From the repository root:

```sh
cd apps/mobile
npm ci
npm run typecheck
npx --no-install expo prebuild --platform ios
npm run ios
```

`prebuild` generates the native project and installs its dependencies. Generated native directories are not committed. Use `npm run ios -- --device` to choose a physical device and configure Signing & Capabilities in Xcode.

Use a native development build: Expo Go does not include this project's local HTTPS verification module. After the native build, use `npm start` for subsequent JavaScript development. See the [App development guide](../apps/mobile/README.md) for configuration.

## Connect to your host

Follow [Getting started](getting-started.md) to install the DSH plugin and configure a model. Use the same reachable network, enable phone connection in the computer's DS Bot **Settings → Mobile devices**, scan the QR with the App and approve the device on the computer. Allow iOS local-network access when prompted.

The DSH host runs Bots, tools and tasks through its configured model provider and must remain online.

## Background operation and distribution

iOS limits background execution and has no Android-style persistent receiver. System push while the app is suspended requires separate Apple push credentials and optional Expo push configuration; see [notification configuration](mobile-features.zh.md).

Distribution requires the maintainer's Apple signing, provisioning profile and distribution channel. This repository's Android signing key cannot sign iOS apps. Before distributing, test pinned HTTPS pairing, camera/microphone permissions, background/resume, keyboard layout, safe areas and VoiceOver on physical devices, and verify voice and other features against their actual host services.
