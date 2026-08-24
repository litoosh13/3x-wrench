# SNI-Spoofing-Go in a container

One Dockerfile, no config file, everything set through environment variables.
Built for providers that only accept a Dockerfile.

Upstream: [aleskxyz/SNI-Spoofing-Go](https://github.com/aleskxyz/SNI-Spoofing-Go) (GPL-3.0)

---

## Prerequisites — what the provider must give you

| Needed | Why |
|--------|-----|
| Build from a Dockerfile | The image is built from `Dockerfile` alone; nothing else is uploaded |
| Container runs as **root** | The tool refuses to start otherwise |
| **`CAP_NET_RAW`** | Required for packet injection. It is in Docker's default capability set, so you normally have it already |
| A **raw TCP** public port | This is a plain TCP proxy — not HTTP, not SOCKS. An HTTP-only ingress will break it |
| Real network stack | A gVisor/tun-style sandbox can't do `AF_PACKET`; you'd see `supports Ethernet-like interfaces only` |
| Outbound to `github.com` and the Debian mirrors **at build time** | That's where the binary and packages come from |

Optional: `CAP_NET_ADMIN` unlocks the `active` injector. Without it the `passive`
injector is used automatically, which is fine — often faster, in fact.

**Placement matters more than any setting.** The fake ClientHello is injected by
whoever runs this proxy, so the DPI must sit **between the container and `CONNECT`**.
A container hosted abroad spoofs nothing for a client that is itself behind the DPI.

---

## 1. Build

Point the service at `Dockerfile` and deploy. To pin a version instead of the
newest release, set the build argument `REF` to a tag, e.g. `v1.0.0`.

## 2. Set these four variables

| Name | Value |
|------|-------|
| `CONNECT` | `104.19.229.21:443` — your real destination, as `IP:port` |
| `FAKE_SNI` | `hcaptcha.com` — decoy hostname the DPI sees; must be a domain that is **not** blocked |
| `UTLS` | `firefox` |
| `PORT` | `40443` |

That's the minimum. It produces:

```
sni-spoofing -listen 0.0.0.0:40443 -connect 104.19.229.21:443 -fake-sni hcaptcha.com -utls firefox -injector passive
```

Use `PORT` (which listens on `0.0.0.0`), not `127.0.0.1` — localhost-only would be
unreachable from outside the container.

## 3. Publish the port

Expose the same port in the provider's networking panel as a **raw TCP** port, and open
it in any firewall/security group.

## 4. Check it works

Add `TEST_MODE` = `true`, start the service once, read the logs, then remove the
variable and restart.

The log prints a preflight (external vs internal IP — the NAT check) and a matrix of
~24 fingerprint/fragment combinations. Set `UTLS` / `FAKE_REPEAT` / `ENABLE_FRAGMENT`
to a row that passed.

Then, end to end from your own machine:

```bash
curl -sSLf --resolve one.one.one.one:40443:<PUBLIC_IP> https://one.one.one.one:40443/ | head
```

The client keeps sending the real hostname; only the DPI sees the decoy.

---

## All variables

Set one and it becomes a flag; leave it unset and the binary's own default applies.

| Name | Flag | Notes |
|------|------|-------|
| `CONNECT` | `-connect` | **Required.** Upstream `IP:port` |
| `PORT` | `-listen 0.0.0.0:$PORT` | **Required** (or `LISTEN`) |
| `LISTEN` | `-listen` | Full address; overrides `PORT` |
| `FAKE_SNI` | `-fake-sni` | Required when `CONNECT` is an IP |
| `UTLS` | `-utls` | `firefox`, `chrome`, `edge`, `safari`, `ios`, `qq`, `360browser`, `none` |
| `INJECTOR` | `-injector` | `passive` or `active`. Auto-selected if unset — see below |
| `FAKE_REPEAT` | `-fake-repeat` | Number of fake ClientHello packets |
| `FAKE_DELAY` | `-fake-delay` | e.g. `2ms` |
| `ACK_TIMEOUT` | `-ack-timeout` | e.g. `2s` |
| `ENABLE_FRAGMENT` | `-enable-fragment=` | `true` / `false` |
| `FRAGMENT_DELAY` | `-fragment-delay` | e.g. `500ms` |
| `SNI_CHUNK` | `-sni-chunk` | SNI bytes per write when fragmenting |
| `TEST_MODE` | `-test` | `true` runs the test matrix once and exits |
| `EXTRA_ARGS` | *(appended raw)* | Any flag without its own variable |
| `USE_VOLUME_ENTRYPOINT` | — | `false` disables the `/data/entrypoint.sh` hook |

### active vs passive

|  | active | passive |
|---|---|---|
| Mechanism | nfqueue + `iptables` + `ip rule` | `AF_PACKET` + link-layer write |
| Needs | `CAP_NET_ADMIN` **and** `CAP_NET_RAW` | `CAP_NET_RAW` only |
| Default container | fails | **works** |

The entrypoint prints the container's capabilities at startup and picks passive
automatically when `CAP_NET_ADMIN` is missing and you haven't set `INJECTOR` yourself.

### Volume (optional)

Mount at `/data`. Nothing is required there; it exists so you can override start-up
without rebuilding. If `/data/entrypoint.sh` exists it runs instead of the built-in one:

```sh
#!/bin/sh
set -eu
exec /usr/local/bin/sni-spoofing \
  -listen 0.0.0.0:40443 \
  -connect 104.19.229.21:443 \
  -fake-sni hcaptcha.com \
  -utls firefox
```

It's invoked as `/bin/sh /data/entrypoint.sh`, so a missing executable bit is fine.
Keep the `exec` so signals reach the binary.

Only `/data` survives a redeploy. Changes anywhere else in the container are lost.

---

## Bundled with the 3x-ui panel (`Dockerfile.3x-ui`)

> Deploying the prebuilt image rather than building it? Everything you need — env vars,
> the volume path, which ports to publish — is in **[DEPLOY.md](DEPLOY.md)**.


Two containers cannot share `127.0.0.1`, and a provider that only builds a Dockerfile
gives you exactly one. So [`Dockerfile.3x-ui`](Dockerfile.3x-ui) puts both in one image:

| | Listens on | Exposed? |
|---|---|---|
| `sni-spoofing` | `127.0.0.1:2020` | no — loopback only |
| 3x-ui panel | `0.0.0.0:2053` | yes — map this port |

Build it exactly like `Dockerfile` (paste it into the provider's form if it insists on
that name), then set the same `CONNECT` / `FAKE_SNI` / `UTLS` variables. Extra ones:

| Name | Notes |
|------|-------|
| `SPOOF_PORT` | Loopback port for the spoofer. Default `2020` |
| `XUI_PORT` | Panel port. Default `2053` |
| `XUI_ENABLE_FAIL2BAN` | `false` here (no fail2ban package). Set `true` only if you add it |

`LISTEN` and `PORT` still work and still win over `SPOOF_PORT` — use them only if you
deliberately want the relay reachable from outside, which is a bad idea in this image.
**Leave `CONNECT` unset and you get a plain panel with no spoofing**, which is the easy
way to check the panel half before debugging the spoof half.

Mount the volume at **`/etc/x-ui`** (the panel database). Nothing else is stateful.

In the panel, add a VLESS **outbound** pointing at `127.0.0.1:2020` and route your
inbounds to it. The one line people get wrong: `serverName` must be the real hostname
of the foreign server, not the loopback address — Xray otherwise derives SNI from the
dial address and the handshake dies. The real SNI stays in the real ClientHello; the
decoy is only what the DPI sees first.

Constraints that follow from the design, not from this image:

- One upstream per spoofer. A second server needs a second `SPOOF_PORT`, which this
  image does not do — run a second container for it.
- **TCP only.** No QUIC, no XHTTP-over-UDP, no Hysteria through this path.
- `TEST_MODE=true` runs the matrix and **skips the panel**, since you are there to read
  the log. Unset it to get the panel back.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ERROR: set LISTEN … or PORT` | No env vars set — see the four above |
| `WARNING: cap_net_admin missing` | Expected; passive is auto-selected. Only a problem if you forced `INJECTOR=active` |
| `cap_net_raw missing` | Provider strips default capabilities — nothing will work; ask them for `NET_RAW` |
| `supports Ethernet-like interfaces only` | Sandboxed network stack (gVisor/tun). Passive can't run there |
| Starts fine but the bypass doesn't work | Either NAT is dropping the wrong-seq packet, or the DPI isn't between this container and `CONNECT`. Run `TEST_MODE=true` |
| `docker/dockerfile:1 … 403` | A `# syntax=` line crept into `Dockerfile`. It must not be there — registry mirrors don't carry that image |
| `proxy.golang.org … 403` | You're using a Dockerfile that compiles from source. This one doesn't |

**NAT can silently break it.** The injected packet carries a deliberately wrong TCP
sequence number, and a NAT gateway's conntrack often drops it as INVALID. `TEST_MODE`'s
preflight compares external and internal IP, which is exactly this check.

**The listener is an unauthenticated TCP relay** to whatever `CONNECT` points at. Anyone
who finds the public port can use it. Firewall it to your own IP if you can.

### Debugging from inside the container

The image ships a network toolbox so you can check what the container's own network can
reach. Open a shell in it (`docker exec -it <name> sh`, or the provider's web console):

```bash
ping -c3 104.19.229.21              # is the host reachable at all
nslookup example.com                # DNS from inside the container
dig +short example.com              # same, more detail
nc -vz 104.19.229.21 443            # is the TCP port open from here
traceroute 104.19.229.21            # where the path dies
curl -sS -o /dev/null -w '%{http_code}\n' https://example.com
ip addr ; ip route                  # the container's own addressing
netstat -tlnp                       # is the proxy actually listening
tcpdump -ni any host 104.19.229.21  # watch the real + injected packets
```

`tcpdump` is the one that settles arguments: if you see the fake ClientHello leave but
never get a response, the packet is being dropped upstream (NAT/conntrack), not
mis-generated. `ping` and `tcpdump` both need `CAP_NET_RAW`, which you already have.

### Reading the entrypoint

The start-up script is base64-embedded in the Dockerfile — that's what keeps it building
behind registry mirrors. To read it inside a running container:

```bash
cat /usr/local/bin/entrypoint.sh
```

---

## The Dockerfile

It's [`Dockerfile`](Dockerfile) in this repo. For a provider that wants the file pasted
into a web form, open it and copy the whole thing.

```bash
git clone <this repo> && cd sni
docker build -t sni-spoof .
```

Deliberately built to survive restricted networks — three things in it look like
omissions but are not, so don't "fix" them:

- **no `# syntax=` line** — that would pull the `docker/dockerfile` frontend image from
  Docker Hub, which registry mirrors don't carry (403)
- **no heredoc** — the entrypoint is base64-embedded so old builders and mirrored
  registries can still build it
- **no Go build** — compiling would hit `proxy.golang.org`, which is blocked from Iran;
  it downloads the released binary from GitHub instead
