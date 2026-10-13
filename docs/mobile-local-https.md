# One-click connection to your computer

English | [中文](mobile-local-https.zh.md)

Update both DS Bot and the native mobile app. Local HTTPS requires no domain, Tailscale, OpenSSL executable, or certificate installation.

1. Connect the phone and computer to the same Wi-Fi and keep DSH running.
2. On the computer, open **Settings → Mobile devices → Enable phone connection**. The plugin creates its certificate, starts HTTPS, and shows a QR code.
3. Scan it in DS Bot Mobile. The app automatically requests pairing.
4. Click **Approve** on the computer for the phone you recognize. Later app launches reconnect automatically.

Allow private-network access if the computer's firewall asks. Camera permission and iOS local-network permission may also appear. The plugin cannot approve OS permissions for you.

The default port is `8788`; the plugin chooses an IPv4 LAN address. If several interfaces are available, choose the Wi-Fi address before enabling. Guest Wi-Fi, AP isolation, VPNs, or a firewall may prevent the phone reaching that address. If the computer changes networks or IP address, generate a new QR and pair the new address. Routine certificate renewal does not require pairing again.

## Identity and restart

The plugin creates a self-signed P-256 certificate using Node's built-in crypto. The QR contains the SHA-256 hash of the computer's SPKI public key. Dedicated native HTTP/WSS transports validate that pin, certificate validity/signature, and hostname. Global TLS validation stays enabled and the connection never falls back to HTTP.

The phone stores the pin alongside its credentials in secure storage. A different identity requires pairing again. At startup, certificates near expiry or missing a current network address are renewed with the same private key, preserving existing pairings. Enabled local access resumes after DSH restarts. A damaged key fails closed instead of silently changing identity.

Files live in the plugin's own `mobile/` directory; DSH installation and profile files are unchanged. Unix key permissions are `0600`, certificate-directory permissions `0700`; Windows retains the user's directory ACL. Keep backups private. Turning off phone connection stops the listener and active streams but retains pairing records. Revoke a device to remove its access independently.

Existing manual HTTPS configuration is preserved. Explicit `mobile.enabled: false` prevents enabling local access from the UI.

## Scope

Both devices must be directly reachable. This feature does not create an Internet tunnel or keep a powered-off computer available. For remote access, use the existing [public HTTPS deployment](mobile.md).

A browser or Expo Go cannot use this certificate-pinning transport; install the updated native app. Android background reception uses the same pin and does not require FCM/APNs while its background service runs. Existing iOS background execution limits still apply. EAS configuration is not needed for this feature. GitHub Actions can sign APKs with the project DeepSeekBot key when the password Secret is configured. Earlier test APKs used debug signing; switching certificates requires uninstalling the old App and pairing again. See [signing and releases](releasing.md).
