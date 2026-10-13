<p align="center">

  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.svg">
    <img src="docs/images/logo.svg" alt="DeepSeek Bot" width="260">
  </picture>
</p>

# DS Bot

English | [中文](README.zh.md)

![version](https://img.shields.io/badge/version-v0.1_preview-blue) ![DSH](https://img.shields.io/badge/DSH-0.2.0--rc.2-4D6BFE) ![license](https://img.shields.io/badge/license-Apache_2.0-green)

DeepSeek Bot (DS Bot) is a bot plugin for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (DSH). It turns DSH into bots. You create your own bots, then talk and work with them.

![Say one sentence to Chief, and it sets up the bots and the group chat](docs/images/team.png)

## Install and connect

This repository contains the DSH plugin, its mobile bridge, a standalone Android/iOS client, and the shared SDK. Your computer/server runs the Bots, tools and models; the phone connects to it. It must stay running.

1. Download matching `dsbot-plugin` and `dsbot-android-arm64` artifacts from [GitHub Actions](https://github.com/QingJ01/DS-Bot-App/actions/workflows/build.yml), or download the `.tgz` and signed `.apk` from [Releases](https://github.com/QingJ01/DS-Bot-App/releases). Actions artifacts are ZIPs: extract them first. An APK with `-unsigned` in its name cannot be installed.
2. Install [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness/releases), add the **downloaded plugin tarball** in Plugins → Add plugin, enable it and restart DSH. Do not install the upstream npm `ds-bot` package for this fork.
3. Configure a model/provider credential on the computer and test Chief there.
4. Install the ARM64 APK on your Android phone. On the computer, open Settings → Mobile devices → Enable phone connection. Connect both to the same Wi-Fi, scan the QR in the App and approve on the computer.

The plugin configures local HTTPS automatically: no domain, extra app or certificate installation. The phone verifies the host public key from the QR. Android background notifications need neither FCM nor APNs while the optional foreground receiver is running. See the [complete installation and configuration tutorial](docs/getting-started.md), [one-click HTTPS](docs/mobile-local-https.md), and [remote/VPS options](docs/mobile-install.zh.md).

## Mobile features and limits

Bot and group chats, streamed replies/reasoning, long-press message actions, image/file uploads, voice input/chat, task schedules, memory, usage, Skills, plugin management, tool-result cards, explicit tool approval and opt-in desktop browser control are included. The interface supports Chinese/English, light/dark themes and original fish graphics. Bot data stays on the host; phone credentials use secure storage and messages/drafts use a local cache.

Android native pairing, chat, pinned TLS and runtime background notifications have been checked in an emulator with a real isolated DSH host and a mock model. iOS source is included but has not been compiled or device-tested; iOS background execution is limited. Voice depends on host Voice Input and FFmpeg. Some host plugin interfaces need the desktop UI. Neither app-store distribution nor an always-on hosted service is included. [Detailed scope](apps/mobile/README.md).

## Build and release

[GitHub Actions](.github/workflows/build.yml) runs plugin/SDK/App checks, packs the plugin, and builds ARM64 and x86_64 Android APKs. Release signing uses the encrypted `DeepSeekBot` key (`C=CN`) in the repository and the `ANDROID_KEYSTORE_PASSWORD` GitHub Secret. Without that Secret, Actions produces explicitly **unsigned** APKs and will not publish a tag release. Passwords are never stored in Git.

See [Actions, signing, artifacts and release instructions](docs/releasing.md). iOS requires macOS/Xcode and an Apple signing identity. Development commands are in [CONTRIBUTING.md](CONTRIBUTING.md), [the plugin guide](ds-bot/README.md), and [the App guide](apps/mobile/README.md).

## Features

### Bot

You can do all your talking and work with one bot, in one window. You don't need to worry about the context behind it. The bot's details page shows its info, and there you can pick the model you want it to use. You can switch models at any time, but I still recommend that you keep one model for a bot for a long time, and switch only when you really need to.

Bots also have memory. A bot remembers what you like and uses it in later work. You can manage its memory on the bot's details page, or just tell the bot.

![Bot details: model, memory, usage](docs/images/details.png)

### Main bot

The main bot is your chief. It has very high rights: it manages the other bots and the group chats. The first time you open DS Bot, there is already a main bot called Chief. Talk to it, and it walks you through the setup.

In short: have a question? Ask the main bot.

### Group chats

DS Bot has group chats. A group chat is a great way to get several bots to work together, but it clearly costs more. So DS Bot does this: every group chat has an admin. The admin answers your messages by default and calls in the other bots for you. You can also @ a bot directly, and it answers you directly: type @ and pick the bot from the list. To give the bots another chat as context, use + → Reference a chat in the message box.

![Group chat: the admin, Chief, hands the work to Writer and Coder](docs/images/group.png)

### Usage

In **Settings** → **Usage**, you can see token usage by time, by bot and by model.

![Usage page](docs/images/usage.png)

## Data

The authoritative Bot data stays on your DSH host, in `bot/` and `sessions/` in the DSH home folder (`~/.dsh` by default). Uninstalling the plugin does not delete this data. The mobile client also caches conversations and drafts on the phone; model requests still use the providers configured in DSH. See [mobile data and limits](docs/mobile.md#data-and-current-limits).

## Development

The plugin source is in [`ds-bot/`](ds-bot/). For options and internals, see [`ds-bot/README.md`](ds-bot/README.md). For development and tests, see [CONTRIBUTING.md](CONTRIBUTING.md). For changes between versions, see [CHANGELOG.md](CHANGELOG.md).

## Acknowledgments

- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness): DS Bot is built on the DSH plugin system. Every bot is a DSH session and uses the DSH tools and models.
- [esbuild](https://esbuild.github.io/): bundles the plugin's interface code.
- Thanks to these projects for the ideas they published. DS Bot learned from their designs and does not contain their code:
  - [AgentMemoryRepo](https://github.com/AgentMemoryRepo/agentmemoryrepo): the Markdown format of Bot memory.
  - [OpenAI Codex](https://github.com/openai/codex): checkpoints that keep the user's messages next to the summary, and message anchors for chat search.
  - [OpenMausBot](https://github.com/milind-soni/OpenMausBot): group chat rounds and @mention relays.
  - [Hermes Agent](https://github.com/NousResearch/hermes-agent) and [Hermes Bot Mode](https://github.com/NousResearch/Hermes-Bot-Mode): one session per member per group chat, and handoffs that carry the earlier user messages.
  - [OpenCode](https://github.com/sst/opencode), [goose](https://github.com/block/goose), [pi](https://github.com/badlogic/pi-mono) and [Gemini CLI](https://github.com/google-gemini/gemini-cli): when to condense a long chat, and what a handoff note holds.
  - [obelisk](https://github.com/tommy0103/obelisk): chat search with a SQLite full-text index.
- Everyone who tries DS Bot, asks questions and reports bugs.

## License

[Apache License 2.0](LICENSE). Provided "as is", without any warranty. Third-party code and its license are listed in [NOTICE](NOTICE).

## Disclaimer

DS Bot is an independent community project. **It is not an official DeepSeek product**, and it is not affiliated with, endorsed by or sponsored by DeepSeek. "DeepSeek", "DeepSeek Harness" and the other names are trademarks of their owners. They are used here only to say what this plugin works with.

Bots use your own model quota, and they read and write files and run commands when you ask them to. Check important actions yourself.
