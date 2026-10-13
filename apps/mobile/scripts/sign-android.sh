#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
input=${1:?usage: sign-android.sh unsigned.apk signed.apk}
output=${2:?usage: sign-android.sh unsigned.apk signed.apk}
: "${ANDROID_KEYSTORE_PASSWORD:?Set ANDROID_KEYSTORE_PASSWORD from your private signing backup or GitHub Secret}"
: "${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK}"
tools=$(find "$ANDROID_HOME/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
"$tools/apksigner" sign --ks signing/DeepSeekBot.p12 --ks-key-alias deepseekbot \
  --ks-pass env:ANDROID_KEYSTORE_PASSWORD --key-pass env:ANDROID_KEYSTORE_PASSWORD \
  --out "$output" "$input"
"$tools/apksigner" verify --verbose --print-certs "$output"
# Build Tools 36 names scheme signers "V3.0 Signer:"; older tools use "Signer #1".
# Every reported signer must have the project's certificate.
actual=$("$tools/apksigner" verify --print-certs "$output" | sed -nE 's/^(Signer #[0-9]+|V[0-9.]+ Signer):? certificate SHA-256 digest: //p' | sort -u)
expected=$(tr -d '[:space:]' < signing/certificate.sha256)
if [[ "$actual" != "$expected" ]]; then
  echo 'APK certificate does not match the committed DeepSeekBot certificate' >&2
  exit 1
fi
