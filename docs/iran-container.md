# How the Iran container works (read this first)

A hand-off page: someone (or a new chat) who reads only this should understand what the
container is, what you can do with it, how each feature is switched on, and what is and
is not proven. Every address, port and secret below is a **dummy**.

Detailed per-image guides: [xui-backpack.md](xui-backpack.md), [xui-kariz.md](xui-kariz.md),
[../DEPLOY.md](../DEPLOY.md) (the SNI-spoofer image).

## 1. What it is

One container image = **3x-ui panel + one tunnel/bypass tool (+ optional nginx)**, built for a
container platform (PaaS) that runs a single container. "Iran container" means the one on
the platform, which users (or the abroad server) reach. The abroad server (e.g. Hetzner) is a
normal VPS and runs the tool natively.

| Image | Tool in it | Role names |
|---|---|---|
| `ghcr.io/litoosh13/xui-backpack` | BackPack reverse tunnel, optional nginx | `server` (Iran) / `client` (abroad) |
| `ghcr.io/litoosh13/xui-kariz` | Kariz tunnel | `entry` (Iran) / `exit` (abroad) |
| `ghcr.io/litoosh13/xui-spoof` | SNI-Spoofing-Go fake-SNI relay | n/a |

Everything is configured by **environment variables**. No config file, no wizard, no systemd.
Tags: `latest`, `vX.Y.Z`, `sha-abc1234` (pin this while testing).

## 2. What happens at start-up (the entrypoint)

The entrypoint is a shell script embedded as base64 in each Dockerfile. Read it with
`docker run --rm --entrypoint sh IMAGE -c 'cat /usr/local/bin/entrypoint.sh'`. Order:

1. `/data/entrypoint.sh` exists on a volume: it replaces everything (escape hatch).
2. Arguments given (`docker run IMAGE sh`): run them instead (debug shell).
3. If the role variable is set (`BACKPACK_ROLE` / `KARIZ_ROLE`): generate the tunnel's TOML from
   the env variables (or use `/data/backpack.toml` / `/data/kariz.toml` if present) and run
   the tool in the **background, restarted every 2 s if it exits**.
4. BackPack image only: if `NGINX_ENABLE=true`, generate an nginx config (port `NGINX_LISTEN`,
   default `8000`), validate it (`nginx -t`) and run nginx in the background, restarted on exit.
5. Panel: **off unless `XUI_ENABLE=true`**. If it is off, the container waits on whatever else was
   started; if nothing is enabled it exits with an error rather than idling.
6. `XUI_ENABLE=true`: `exec /app/x-ui`, the panel on port `2053`, stays in the foreground.

**Three independent switches, all default `false`/unset:** the tunnel (`*_ROLE` set), nginx
(`NGINX_ENABLE=true`, BackPack image) and the panel (`XUI_ENABLE=true`). A plain panel needs
`XUI_ENABLE=true` and no role. `tini` is PID 1. (The `xui-spoof` image is different: its panel
defaults to **on**, `XUI_ENABLE=false` turns it off.)

## 3. What you can do with it

| Goal | Switch it on with | Guide |
|---|---|---|
| Plain 3x-ui panel | `XUI_ENABLE=true`, no role variable | n/a |
| Tunnel only, no panel | just the role variable (panel is off by default) | both |
| Tunnel + panel | role variable + `XUI_ENABLE=true` | both |
| TCP tunnel + forwarded ports | `*_ROLE`, `*_TOKEN`, `BACKPACK_PORTS` / `KARIZ_FORWARD` | both |
| Encrypted/obfuscated tunnel | `BACKPACK_TRANSPORT=stealth`, or Kariz `tcpmux` (default, encrypted) | both |
| Carry UDP over the tunnel | `BACKPACK_ACCEPT_UDP=true`, or `/udp` / `/tcp+udp` suffix in `KARIZ_FORWARD` | both |
| UDP-friendly transports | `KARIZ_TRANSPORT=kcp` or `quic` (+ `KARIZ_KCP_*`, `KARIZ_QUIC_*`) | xui-kariz.md |
| Tunnel through the platform's HTTPS hostname | BackPack `ws` server + abroad `wss`/`simple_auth`; Kariz `ws` + `KARIZ_WS_*` | both, example B |
| Users AND tunnel through one hostname | `NGINX_ENABLE=true` + `NGINX_ROUTES` (BackPack image) | xui-backpack.md |
| Reality with the hostname as SNI | raw-port forward + abroad Reality inbound with `dest` = hostname | xui-backpack.md |
| Fake-SNI outbound relay | `CONNECT`, `FAKE_SNI`, `UTLS` (spoof image) | DEPLOY.md |

## 4. Variables

### BackPack image
| Name | Meaning |
|---|---|
| `BACKPACK_ROLE` | `server` (Iran, listens) or `client` (abroad, dials). Nothing starts without it |
| `BACKPACK_TOKEN` | Shared secret, identical on both ends |
| `BACKPACK_TRANSPORT` | Default `tcp`. Also `stealth`, `tcpmux`, `ws`, `wsmux`, `wss`, `wssmux`, `kcp`, `quic`, `udp`. `pck`/`xdi` unusable here (need `iptables`) |
| `BACKPACK_BIND` | Server tunnel listen address. Default `0.0.0.0:8443` |
| `BACKPACK_PORTS` | `2087=127.0.0.1:1004,2090=127.0.0.1:1005`: public port `=` target dialled **from the abroad side** |
| `BACKPACK_ACCEPT_UDP` | `true`: also carry UDP on every port in `BACKPACK_PORTS` |
| `BACKPACK_REMOTE` | Client only: server `IP:port` |
| `NGINX_ENABLE` | `true` starts nginx (default `false`) |
| `NGINX_LISTEN`, `NGINX_ROUTES`, `NGINX_DEFAULT` | nginx port (default `8000`), path routes, optional `/` upstream |

### Kariz image
| Name | Meaning |
|---|---|
| `KARIZ_ROLE` | `entry` (Iran) or `exit` (abroad). Nothing starts without it |
| `KARIZ_TOKEN` | Shared secret (`kariz token` makes one). Too-short values are rejected |
| `KARIZ_MODE` | `reverse` (default: exit dials entry) or `direct` |
| `KARIZ_TRANSPORT` | Default `tcpmux`. Also `tcp`, `ws`, `wss`, `kcp`, `quic`, `udp` |
| `KARIZ_LISTEN` / `KARIZ_REMOTE` | The side that listens sets `LISTEN`, the side that dials sets `REMOTE` (reverse: entry listens) |
| `KARIZ_FORWARD` | Entry only, **required** (a forward-less entry is rejected): `2087=127.0.0.1:1004/tcp,2088=127.0.0.1:1007/udp,2089=127.0.0.1:8388/tcp+udp` |
| `KARIZ_WS_PATH`, `KARIZ_WS_HOST` | For `ws`/`wss` |
| `KARIZ_QUIC_OBFS`, `KARIZ_QUIC_CONGESTION`, `KARIZ_KCP_MODE`, `KARIZ_KCP_FEC` | `quic` / `kcp` tuning (`KARIZ_KCP_FEC=10,3`) |
| `KARIZ_PROFILE` | `balanced`, `ultraspeed`, `gaming` |

### All images
`XUI_ENABLE` (default **`false`** in the BackPack and Kariz images; `true` in `xui-spoof`), `XUI_PORT` (panel port), `TZ`, `USE_VOLUME_ENTRYPOINT`.
Volumes: `/etc/x-ui` (panel DB, keep it), `/data` (optional overrides).

## 5. Dummy scenario used everywhere

| What | Dummy |
|---|---|
| Iran container public IP | `203.0.113.10` |
| Tunnel port, container `8443` (Kariz `3080`) → external | `30001` |
| User port, container `2087` → external | `30002` |
| Reality raw port, container `2090` → external | `30003` |
| Platform HTTPS hostname | `tunnel.example.com` |
| Abroad VPS | `198.51.100.7`, inbounds VLESS `1004`, Reality `1005`, xhttp `1006`, WireGuard `1007` |
| Token | `4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36` (make your own: `openssl rand -hex 24`) |

### Recipe A: raw TCP tunnel, one forwarded port (BackPack)
Iran container:
```
BACKPACK_ROLE=server
BACKPACK_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36
BACKPACK_BIND=0.0.0.0:8443
BACKPACK_PORTS=2087=127.0.0.1:1004
```
Platform: map container `8443` and `2087` as TCP. Abroad VPS `/etc/backpack/mytunnel.toml`:
```toml
[client]
remote_addr = "203.0.113.10:30001"
transport = "tcp"
token = "4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36"
```

### Recipe B: same, Stealth + UDP (WireGuard on the abroad VPS)
```
BACKPACK_TRANSPORT=stealth
BACKPACK_PORTS=2087=127.0.0.1:1007
BACKPACK_ACCEPT_UDP=true
```
Abroad: `transport = "stealth"`. Platform: a separate **UDP** mapping for container `2087`.
WireGuard clients: `Endpoint = 203.0.113.10:30002`, `PersistentKeepalive = 25`, `MTU = 1280`.

### Recipe C: Kariz, reverse, three forwards
Iran container:
```
KARIZ_ROLE=entry
KARIZ_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36
KARIZ_TRANSPORT=tcpmux
KARIZ_LISTEN=0.0.0.0:3080
KARIZ_FORWARD=2087=127.0.0.1:1004/tcp,2088=127.0.0.1:1007/udp,2089=127.0.0.1:8388/tcp+udp
```
Abroad VPS `/etc/kariz/test.toml`, run with `kariz run -c /etc/kariz/test.toml`:
```toml
role = "exit"
mode = "reverse"

[tunnel]
transport = "tcpmux"
remote = "203.0.113.10:30001"
token = "4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36"
```

### Recipe D: users AND tunnel through the single hostname (BackPack + nginx)
Full details in [xui-backpack.md](xui-backpack.md#one-hostname-for-everything-nginx-tested). Iran container, hostname mapped to
container port `8000`:
```
BACKPACK_ROLE=server
BACKPACK_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36
BACKPACK_TRANSPORT=ws
BACKPACK_BIND=127.0.0.1:8080
BACKPACK_PORTS=2087=127.0.0.1:1004,2088=127.0.0.1:1006,2090=127.0.0.1:1005
NGINX_ENABLE=true
NGINX_ROUTES=/channel=127.0.0.1:8080,/tunnel/=127.0.0.1:8080,/app/=127.0.0.1:2087,/x/=127.0.0.1:2088
```
Abroad BackPack: `transport = "wss"`, `remote_addr = "tunnel.example.com:443"`, `simple_auth = true`.
Abroad inbounds (security **none**): VLESS-WS `1004` path `/app/`, VLESS-xhttp `1006` path `/x/` `packet-up`.
Users: `vless://UUID@tunnel.example.com:443?type=ws&security=tls&path=%2Fapp%2F&encryption=none`.
Reality (raw port, hostname as SNI): abroad inbound `1005`, `dest = tunnel.example.com:443`,
`serverNames = [tunnel.example.com]`; user link points at `203.0.113.10:30003` with `sni=tunnel.example.com`.

## 6. Facts about the platform that shape every design

- Runs as **root**, has `NET_RAW`, **no** `NET_ADMIN`, no systemd, no `/dev/net/tun`. So no TUN VPNs
  (EasyTier/XRayMesh don't work), no `pck`/`xdi`, and BackPack's sysctl tuning logs harmless warnings.
- The **HTTPS hostname terminates TLS at the platform's edge** and sends **plain HTTP** to
  **one** container port. Consequences: WebSocket/xhttp work through it; Reality, XTLS Vision,
  Trojan-over-TLS and gRPC do not; the edge sees the traffic; a hostname that points at the
  tunnel no longer reaches the panel.
- **Raw TCP and UDP ports are separate mappings**, each with an external number the platform
  assigns. UDP needs its own mapping. External numbers may change after a redeploy.
- Builds happen from the Dockerfile alone with an **empty build context**: no `COPY`, no heredoc, no
  `# syntax=` line, nothing compiled. Binaries come from GitHub releases.
- A raw platform IP:port can be unreachable from some home networks even when the platform
  and tunnel are fine (seen once: instant "connection refused" from home, success from the
  abroad server). Test from both sides before blaming the tunnel.

## 7. What is proven and what is not

Proven locally (Docker on a Mac, containers on one network, nginx as an edge stand-in):
BackPack `tcp`, `stealth`, `ws`/`wss`+`simple_auth` through an edge, UDP over a TCP tunnel,
nginx path routing with VLESS-WS, VLESS-xhttp (`packet-up`) and Reality (via raw port), 8 MB transfers;
Kariz `tcpmux` and `ws` behind an edge (v1.4.0), the opt-in `XUI_ENABLE` / `NGINX_ENABLE` switches.

Reported from the real platform (by the operator, not re-verified here): a BackPack TCP tunnel to the
abroad VPS carried WireGuard fine, VLESS-xhttp only sometimes, and Shadowsocks poorly; the
hostname/nginx setups were not yet confirmed on the real edge. Kariz v2.0.0: the tunnel connected and the abroad-side to inbound path
returned the inbound's reply, but `tcpmux` dropped after ~90 s ("mux peer stopped answering pings"),
and Shadowsocks over it never connected in testing (cause not found).

Not tested: `kcp`/`quic` through the real platform, nginx routing on the real edge (idle timeouts,
xhttp behaviour), Kariz's own web panel (not in the image).

## 8. Open problems (so nobody re-derives them)

- Instagram loads badly on Android (not iPhone) over Shadowsocks, VLESS-xhttp and WireGuard tunnels.
  Hypotheses, none confirmed: QUIC/HTTP3 stalling because UDP rides inside TCP (fix to try: block UDP 443
  on the abroad side so apps fall back to TCP), MTU (set 1280), IPv6/Private DNS on Android.
- Kariz `tcpmux` instability over the raw platform port (see above). A/B idea: `wss` through the hostname.

## 9. Repo map and rules for changing things

| Path | What |
|---|---|
| `Dockerfile.3x-ui` / `-backpack` / `-kariz` | The three images (entrypoint embedded as base64) |
| `.github/workflows/image.yml` | Matrix build, pushes the three images to ghcr.io |
| `DEPLOY.md`, `docs/*.md` | Guides |

To change an entrypoint: decode the base64 block, edit, re-encode, rebuild, test. Keep the
Dockerfiles free of heredocs, `COPY` and `# syntax=`. The user commits and pushes themselves;
a push to `main` rebuilds all three images.

Testing recipe that worked: one Docker network with an nginx container as the edge
(TLS 443 to the Iran container's port), the image under test as the Iran container, a second
container running the abroad side (BackPack client + Xray), a client container with Xray
exposing SOCKS, then `curl --socks5-hostname` against a web container. Gotchas with Xray 26:
`allowInsecure` is gone (trust the test cert instead) and its `freedom` outbound blocks private
IPs unless `finalRules` allows them.
