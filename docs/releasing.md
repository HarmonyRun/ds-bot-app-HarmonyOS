# GitHub Actions, Android signing and releases

English | [中文](releasing.zh.md)

## Signing identity

`apps/mobile/signing/` contains the password-encrypted `DeepSeekBot.p12`, its public DER certificate and SHA-256 fingerprint. Identity: `CN=DeepSeekBot, O=DeepSeekBot, C=CN`; alias `deepseekbot`; RSA 4096; validity 10,000 days.

The password is not in Git. The owner's private backup ZIP contains the key and the file `ANDROID_KEYSTORE_PASSWORD`. Keep it offline; never upload the ZIP/password to GitHub, build artifacts or Releases. A person holding both the encrypted key and password can sign updates.

The current GitHub app cannot manage repository Secrets. The maintainer must open **Settings → Secrets and variables → Actions → New repository secret**, name it `ANDROID_KEYSTORE_PASSWORD`, and paste the full contents of the private backup's password file (no quotes). Use a Secret, not a Variable. Then run **Actions → Build plugin and Android → Run workflow → main**. Enable Actions first if GitHub prompts. Do not expose the signing password to external-fork PR workflows.

## Pipeline

The build workflow runs on main pushes, PRs, manual dispatch and `mobile-v*` tags. It installs locked dependencies; checks plugin tests/generated bundle/lint, SDK tests, App TypeScript/tests and the Python device helper; packs the plugin; and builds standalone ARM64 and x86_64 APKs using Node 24, Java 17, Expo prebuild and Gradle.

With the Secret, it signs APKs using the encrypted key and verifies the resulting certificate against the committed fingerprint. Without it, the artifact is explicitly named `-unsigned.apk`, emits a warning and **cannot be installed**. A successful unsigned build does not establish signing readiness. APK artifacts include checksums and, when signed, the public certificate. Android `versionCode` uses the workflow run number; retries of the same run retain it.

The separate Test workflow checks Linux/Windows, Node 22/24 and two DSH versions. These workflows do not compile iOS; iOS needs macOS/Xcode and Apple signing. Android needs no EAS project.

## Download and publish

From the successful run's Artifacts, download and extract `dsbot-plugin` plus `dsbot-android-arm64` for phones or `dsbot-android-x86_64` for emulators. Install matching host/plugin files. Main builds upload artifacts only.

To publish, first verify the password Secret, checks and both signed APKs. Update plugin/App versions, lockfiles and bilingual release notes as appropriate, then push a unique tag:

```sh
git tag mobile-v0.1.0
git push origin mobile-v0.1.0
```

The tag pipeline creates a prerelease with the plugin tarball, signed APKs, public certificate and combined checksums. Missing signing credentials fail the release job; unsigned APKs are not published as installable releases. It uploads no signing password, private backup or DSH data. Artifacts expire according to GitHub retention; Releases are intended for versions kept longer. Release checksums use flat filenames: run `sha256sum -c SHA256SUMS` in the download directory, or `shasum -a 256 -c SHA256SUMS` on macOS.

## Local builds

Install Node 24, Java 17, Android SDK/Build Tools 36, NDK `27.1.12297006` and CMake. Expo/Gradle download pinned components. From `apps/mobile`:

```sh
npm ci
npm run typecheck
npm test
DS_BOT_ANDROID_VERSION_CODE=100 npx --no-install expo prebuild --platform android --no-install
cd android
./gradlew assembleRelease --no-daemon --max-workers=2 -PreactNativeArchitectures=arm64-v8a
cd ..
```

Choose a `versionCode` above the installed version. Keep CI run numbers above any locally distributed version; avoid arbitrary high local release numbers. Load the password privately into `ANDROID_KEYSTORE_PASSWORD` without printing it, set `ANDROID_HOME`, and run:

```sh
bash scripts/sign-android.sh android/app/build/outputs/apk/release/app-release-unsigned.apk dsbot-android-arm64.apk
```

The script passes the password through the environment, checks the certificate fingerprint and does not accept a plaintext password argument. Release builds do not use Expo's public debug signing key. Switching from old debug APKs requires uninstalling/reinstalling and pairing again; host data remains. Preserve this key for future updates. Fork owners should generate their own identity/certificate/fingerprint and use a different application ID.

Plugin packaging from `ds-bot`:

```sh
npm ci
npm run harness
npm run build
npm test -- --test-concurrency=2
npm run lint
npm pack
```
