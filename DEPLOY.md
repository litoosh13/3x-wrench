# Deploying the image

```
ghcr.io/litoosh13/xui-spoof:latest
```

3x-ui panel and SNI-Spoofing-Go in one container, published for `linux/amd64` and `linux/arm64` by
[.github/workflows/image.yml](.github/workflows/image.yml).

Package page: <https://github.com/litoosh13/xui-spoof/pkgs/container/xui-spoof>

Public image, so no login or pull secret is needed anywhere.

| Tag | Means |
|-----|-------|
| `latest` | Newest build from `main` |
| `v1.2.3` | Built from that git tag |
| `sha-abc1234` | One specific commit — pin this if you want reproducible deploys |

Both bundled binaries track their upstream **latest release at build time**. There is
no build cache in CI on purpose, so re-running the workflow really does pick up new
3x-ui and sni-spoofing versions. Pin them instead with `--build-arg XUI_REF=v2.8.0` /
`REF=v1.0.0` if you build it yourself.

---

## Volume

One mount. Name it whatever the provider's UI wants — the path is what matters.

| Mount path | Holds | Size |
|---|---|---|
| `/etc/x-ui` | Panel database (`x-ui.db`): login, inbounds, Xray config | 1Gi is plenty |

Skip it and every redeploy resets you to `admin`/`admin` with no inbounds.

`/data` also exists but is optional — it is only the entrypoint-override hook.

## Ports

| Port | Expose? | What |
|---|---|---|
| `2053` | yes | Panel web UI |
| your inbound ports | yes | The VLESS/VMess/etc. inbounds you create in the panel |
| `2020` | **no** | The spoofer. Loopback-only, consumed by Xray inside the same container |

2020 must never be published. It is an unauthenticated TCP relay to your foreign
server — anyone who reaches it gets a free tunnel. Nothing outside the container needs
it, and the spoofing itself is an *outbound* connection, which needs no open port.

Inbounds need **raw TCP**. An HTTP-only ingress works for the panel and breaks
everything else.

## Environment variables

### Set these three

| Name | Example | Notes |
|---|---|---|
| `CONNECT` | `203.0.113.10:443` | Your foreign server, as `IP:port` |
| `FAKE_SNI` | `hcaptcha.com` | Decoy hostname the DPI sees. Must **not** be blocked |
| `UTLS` | `firefox` | `chrome`, `edge`, `safari`, `ios`, `qq`, `360browser`, `none` |

Leave `CONNECT` unset and you get a plain 3x-ui with no spoofing — the quickest way to
tell a broken panel from a broken spoof.

### Tuning, after `TEST_MODE`

Set `TEST_MODE=true`, start once, read the log: it prints a NAT preflight (external vs
internal IP) and ~24 fingerprint/fragment rows. Copy a passing row into these, then
**remove `TEST_MODE`** or the panel never starts.

`FAKE_REPEAT` · `FAKE_DELAY` · `ENABLE_FRAGMENT` · `FRAGMENT_DELAY` · `SNI_CHUNK` ·
`ACK_TIMEOUT` · `INJECTOR` · `EXTRA_ARGS`

### Optional

| Name | Default | When |
|---|---|---|
| `SPOOF_PORT` | `2020` | Changing the spoofer's loopback port |
| `XUI_PORT` | `2053` | The provider already uses 2053 |
| `TZ` | UTC | `Asia/Tehran` for local timestamps in panel logs |

### Do not set

`LISTEN` and `PORT` both make the relay listen on `0.0.0.0`. They still work, for the
sni-only image, but in this one they turn the loopback relay into a public open proxy.

Already baked into the image: `XUI_IN_DOCKER`, `XUI_MAIN_FOLDER`,
`XUI_ENABLE_FAIL2BAN=false`, `XRAY_VMESS_AEAD_FORCED=false`.

---

## What the host must allow

| Needed | Why |
|---|---|
| Run as **root** | sni-spoofing refuses to start otherwise |
| **`CAP_NET_RAW`** | Packet injection. In Docker's default capability set |
| Real network stack | gVisor/tun sandboxes cannot do `AF_PACKET` |
| Raw TCP ports | For the inbounds, not the panel |

`CAP_NET_ADMIN` is optional — it unlocks the `active` injector. Without it `passive` is
selected automatically, which is often faster anyway.

Check a platform before debugging anything else:

```bash
docker exec <name> capsh --print | head -n1
```

No `cap_net_raw` there means the platform stripped it and no tuning will help. Fall
back to running the panel alone (`CONNECT` unset) with Xray's built-in `freedom`
fragmentation, which needs no capabilities.

**Placement beats every setting.** The fake ClientHello is injected by whoever runs this
container, so the DPI must sit *between the container and `CONNECT`*. Deployed abroad it
spoofs nothing.

---

## Quick start

```bash
docker run -d --name xui-spoof \
  --cap-add=NET_RAW \
  -p 2053:2053 -p 8443:8443 \
  -v xui-data:/etc/x-ui \
  -e CONNECT=203.0.113.10:443 \
  -e FAKE_SNI=hcaptcha.com \
  -e UTLS=firefox \
  ghcr.io/litoosh13/xui-spoof:latest
```

Panel on `:2053`, `admin`/`admin` — change it immediately.

Or as compose, which is what most providers' forms expect:

```yaml
services:
  xui-spoof:
    image: ghcr.io/litoosh13/xui-spoof:latest
    cap_add: [NET_RAW]
    ports:
      - "2053:2053"     # panel
      - "8443:8443"     # your inbound(s)
    volumes:
      - xui-data:/etc/x-ui
    environment:
      CONNECT: "203.0.113.10:443"
      FAKE_SNI: "hcaptcha.com"
      UTLS: "firefox"
    restart: unless-stopped

volumes:
  xui-data:
```

## Wiring the panel

Add a VLESS **outbound** pointing at `127.0.0.1:2020`, then route your inbounds to it:

```json
{
  "tag": "spoof",
  "protocol": "vless",
  "settings": {
    "vnext": [{
      "address": "127.0.0.1",
      "port": 2020,
      "users": [{ "id": "YOUR-UUID", "encryption": "none", "flow": "xtls-rprx-vision" }]
    }]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "tls",
    "tlsSettings": { "serverName": "your.real.domain", "fingerprint": "chrome" }
  }
}
```

`serverName` must be the real hostname of the foreign server, **not** the loopback
address — Xray otherwise derives the SNI from the dial address and the handshake dies.
The real SNI stays in the real ClientHello; the decoy is only what the DPI sees first.

## Limits

- **One upstream per container.** A second foreign server needs a second deployment.
- **TCP only.** No QUIC, no XHTTP-over-UDP, no Hysteria on this path.
- **One replica.** SQLite on a ReadWriteOnce volume, and two spoofers would fight over it.
