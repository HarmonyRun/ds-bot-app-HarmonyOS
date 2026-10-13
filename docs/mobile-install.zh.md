# 手机端部署安装

先连接自己的电脑时，推荐[一键本地 HTTPS](mobile-local-https.zh.md)：无需域名、额外 App 或手动安装证书。需要外出访问时可部署到 **VPS**，或选择下面的其他方式：

| 方式 | 需要什么 | 使用范围 |
| --- | --- | --- |
| **VPS（推荐）** | 云服务器、域名 | 手机有网络就能连接 |
| 局域网（一键） | 更新插件与原生 App，电脑保持开机 | 同一局域网内，无需域名 |
| HTTPS 隧道 | 保持开机的电脑、隧道服务 | 外出可连接，无需主机公网 IP |
| Tailscale | 主机和手机安装 Tailscale | 两端加入同一私网后可连接 |

先完成主机部署，再安装手机 App 并配对。模型 API Key 配在 DSH 主机上，手机不需要填写。

## 1. VPS 部署（推荐）

以下以 Ubuntu VPS 为例。准备 Node.js 24 LTS、pnpm、Caddy，以及一个域名。将域名（例如 `bot.example.com`）的 DNS 指向 VPS 公网 IP，在安全组和防火墙放行 TCP 80、443。

### 安装 DSH 和插件

安装 [Node.js](https://nodejs.org/)，然后安装 pnpm：

```sh
npm install -g pnpm
```

把本仓库放到 VPS。在仓库根目录执行：

```sh
cd ds-bot
npm ci
npm run build
npm pack
npx @deepseek-ai/dsh@0.2.1-alpha.1 plugin --profile web add "$PWD/ds-bot-0.1.2.tgz"
```

如果已有从本仓库构建的插件包，直接用它的绝对路径执行最后一条命令即可。

### 开启手机连接

创建 `~/mobile.patch.yml`，填入下面内容，把域名换成自己的：

```yaml
- id: bot
  config:
    mobile:
      enabled: true
      host: 127.0.0.1
      port: 8788
      publicUrl: https://bot.example.com
```

已有 `bot.config` 配置时，把原有字段一起保留：DSH patch 会替换整段配置，不会递归合并。

安装 Caddy 和 tmux：

```sh
sudo apt update
sudo apt install -y caddy tmux
```

在 `/etc/caddy/Caddyfile` 中添加下面内容，使用自己的域名，保留文件中仍需使用的其他站点：

```caddyfile
bot.example.com {
    reverse_proxy 127.0.0.1:8788
}
```

应用配置：

```sh
sudo systemctl reload caddy
```

### 启动并配置模型

创建 Bot 工作目录，在 tmux 中启动 DSH：

```sh
mkdir -p ~/dsbot-workspace
cd ~/dsbot-workspace
tmux new -s dsbot
npx @deepseek-ai/dsh@0.2.1-alpha.1 web --patch "$HOME/mobile.patch.yml" --port 3080 --no-open
```

在自己的电脑另开终端，连接管理页面：

```sh
ssh -N -L 3080:127.0.0.1:3080 用户名@VPS地址
```

保持 SSH 转发运行，在电脑浏览器打开 DSH 启动输出中的本机登录链接（端口 `3080`）。在 Harness 设置中添加模型提供方、配置凭据，再为 DS Bot 的 Chief 选择模型，发送一条消息确认回复正常。

DSH 终端按 `Ctrl+B`，松开后按 `D`，即可退出 tmux 界面并保持服务运行。以后用 `tmux attach -t dsbot` 返回。VPS 重启后需要重新启动 DSH；需要开机自启时再配置系统服务。

手机浏览器打开 `https://bot.example.com/mobile/v1/info`，能看到 JSON 就可以继续配对。手机入口是 HTTPS 域名，`3080` 只用于电脑管理，无需公网开放。

## 2. 局域网部署

适合在家使用。电脑安装 [DSH Desktop](https://github.com/deepseek-ai/deepseek-harness/releases)，在 **插件 → 添加插件** 中安装从本仓库构建的 `.tgz`，启用并配置模型。也可以使用上面的 DSH Web 安装方式。

**HTTPS 仍然需要，但插件可以自动配置。**更新插件与原生 App，在电脑「设置 → 手机设备」点击「启用手机连接」，手机在同一 Wi-Fi 扫码，然后在电脑批准。插件生成证书，App 根据二维码的公钥指纹验证电脑。无需改 profile、配置域名或安装证书。详见[一键操作说明](mobile-local-https.zh.md)。

下面是已有域名与受信任证书时的手动配置，属于可选高级部署：

编辑 DSH 数据目录下的 `profiles/desktop/cordis.patch.yml`（Web 使用 `profiles/web/cordis.patch.yml`），添加手机配置：

```yaml
- id: bot
  config:
    mobile:
      enabled: true
      host: 0.0.0.0
      port: 8788
      publicUrl: https://bot.example.com:8788
      certPath: /实际路径/fullchain.pem
      keyPath: /实际路径/privkey.pem
```

默认 DSH 数据目录是用户目录下的 `.dsh`。使用实际域名和证书路径，保留已有 `bot.config` 字段，重启 DSH；电脑防火墙仅允许局域网访问 TCP `8788`。

手机连同一 Wi-Fi，打开 `https://bot.example.com:8788/mobile/v1/info` 确认可达，再配对。手动配置的证书需要被手机系统信任；一键方案通过配对公钥验证自动生成的自签证书。离开可直达的局域网后，需要改用下面的隧道或私网方案。

## 3. HTTPS 隧道

适合电脑没有公网 IP、又希望外出连接的情况。

1. 按局域网部分安装 DSH 和插件。
2. 在主机安装 Cloudflare Tunnel 等隧道客户端，配置一个固定 HTTPS 域名，转发到 `http://127.0.0.1:8788`。Cloudflare 的固定域名方案需要将自己的域名接入它的 DNS。
3. 使用 VPS 部分的 `mobile` 配置：`host: 127.0.0.1`、`port: 8788`、`publicUrl` 填隧道 HTTPS 域名；无需填写 `certPath` 和 `keyPath`。
4. 重启 DSH，保持隧道运行，检查 `https://你的域名/mobile/v1/info`，然后配对。

隧道需支持 WebSocket。不要在这个入口加要求先登录网页的访问页面，当前 App 无法完成该登录流程。使用隧道服务供应商的安装指南配置客户端常驻运行。

## 4. Tailscale

适合不想购买域名、愿意在手机保持 VPN 连接的情况。

1. 主机和手机安装 [Tailscale](https://tailscale.com/download)，登录同一个账号并连接。
2. 按局域网部分安装 DSH 和插件。
3. 主机执行：

```sh
tailscale serve --bg http://127.0.0.1:8788
tailscale serve status
```

首次使用若提示启用 HTTPS，按提示完成设置。记录输出中的 `https://主机名.私网名.ts.net` 地址。

4. 使用 VPS 部分的 `mobile` 配置：监听 `127.0.0.1:8788`，把 `publicUrl` 换成上述 HTTPS 地址；无需填写证书路径。
5. 重启 DSH，手机保持 Tailscale 连接，检查该地址下的 `/mobile/v1/info`，然后配对。

使用 Tailscale Serve 即可，无需启用公网 Funnel。

## 5. 安装手机 App 并配对

1. Android 安装与主机插件配套的 **ARM64 APK**。需要自行构建时，见[Android APK 构建说明](mobile.zh.md#构建个人测试用-android-apk)。
2. 主机打开 **DS Bot → Settings → Mobile devices → Create pairing code**。
3. 手机 App 扫描二维码，或粘贴完整的 **Manual pairing data** JSON，填写设备名称。
4. 回到主机，在待配对设备旁点击 **Approve**。
5. 手机打开 Chief，发送消息确认连接成功。

配对码约两分钟后过期，过期就重新生成。`publicUrl` 只填 HTTPS 域名和必要的端口，不加 `/mobile/v1` 等路径。已有 DSH 的用户沿用原来的数据目录，不要同时启动两个进程读写同一份数据。

## 6. 后台通知

Android 打开 **设置 → 通知中心 → 开启后台运行提醒**，允许系统通知权限。通知栏出现常驻提醒后，按 Home 切到其他 App，检查任务完成通知。

这条方式无需 FCM/APNs，但主机必须运行、手机必须能连接；Tailscale 方案还需保持 VPN。强制停止或划掉 App 会停止接收。收不到提醒时，检查手机对 DS Bot 和 VPN 的后台、电池限制。主机重启后，回到 App 重连。

## 连接失败时

- **打不开 `/mobile/v1/info`**：先检查域名、证书、代理或 VPN，确认 DSH 已运行。
- **返回 502**：检查 Bridge 是否启用、代理是否指向 `8788`。
- **提示 Mobile access is off**：检查插件包、对应 profile 的配置，并重启 DSH。
- **配对后没有模型回复**：先在主机确认模型和凭据可用。
