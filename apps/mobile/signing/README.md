# Android release identity

`DeepSeekBot.p12` is the password-encrypted PKCS#12 release signing key, committed at the owner's request. `DeepSeekBot.cer` is its public DER certificate; `certificate.sha256` is the certificate fingerprint verified after signing. Identity: `CN=DeepSeekBot, O=DeepSeekBot, C=CN`; alias `deepseekbot`; RSA 4096 / SHA-256; valid for 10,000 days.

The password is **not** in this repository. Set the repository Actions Secret `ANDROID_KEYSTORE_PASSWORD` from the private backup. The key password is the same as the store password. Keep the backup offline and never upload its password or ZIP to Git, artifacts, issues or Releases. Anyone with both the key and its password can sign app updates.

Release builds are unsigned until `scripts/sign-android.sh` signs them. That script checks the APK's certificate against this fingerprint. Never regenerate this key for an ordinary update: Android requires the same signing certificate. Fork owners should use their own key and application ID.

See [English release guide](../../../docs/releasing.md) / [中文签名与发布教程](../../../docs/releasing.zh.md).
