# xui-backpack

3x-ui panel + [BackPack](https://github.com/AminMGMT/BackPack) in one container.
Image: `ghcr.io/litoosh13/xui-backpack:latest` (build file: [`Dockerfile.3x-ui-backpack`](../Dockerfile.3x-ui-backpack)).

BackPack is a reverse tunnel between an Iran server and a kharej (abroad) server. The
**server** end exposes the public ports; the **client** end dials it and delivers each
connection to the service behind it. You run one container per side.

## Volume

| Mount path | Holds |
|---|---|
| `/etc/x-ui` | Panel database. Add it, or every redeploy resets to `admin`/`admin` |

The tunnel config is regenerated from env on every start, so it needs no volume.

## Environment variables

Nothing starts until `BACKPACK_ROLE` is set.

| Name | Required | Notes |
|---|---|---|
| `BACKPACK_ROLE` | yes | `server` (Iran end, listens) or `client` (kharej end, dials) |
| `BACKPACK_TOKEN` | yes | Same value on both ends |
| `BACKPACK_TRANSPORT` | no | Default `tcp`. Must match on both ends. Others: `tcpmux`, `ws`, `wsmux`, `wss`, `wssmux`, `stealth`, `pck`, `kcp`, `quic`, `udp`, `xdi` |
| `BACKPACK_BIND` | server | Tunnel listen address. Default `0.0.0.0:8443` |
| `BACKPACK_PORTS` | server | Public ports to expose: `443,8080=127.0.0.1:2096`. `443` means the client hands it to its own `127.0.0.1:443`; `A=host:B` sends it to `host:B` |
| `BACKPACK_REMOTE` | client | Server address, `IP:port`. The port must match the server's `BACKPACK_BIND` |

For anything else (fallback transports, TLS certificates, tuning, UDP forwarding, `wss`
domains), put a complete config at `/data/backpack.toml` (mount a volume at `/data`); it
is used instead of the generated one. Keys:
[config reference](https://github.com/AminMGMT/BackPack/blob/main/docs/config-reference.md).
Its files have a `[server]` or `[client]` table.

Transport notes: `pck` and `xdi` need root + `NET_RAW` (the image runs as root, and Docker
gives `NET_RAW` by default). `kcp`, `quic` and `udp` need the platform to forward **UDP**.
`wss` needs a certificate. `tcp` sends the token in the clear, so use `stealth` or `pck`
on a filtered link.

## Ports to open on the platform

| Port | Where | Protocol |
|---|---|---|
| `2053` | both | TCP: panel |
| `BACKPACK_BIND` port (`8443`) | server | TCP (UDP for kcp/quic/udp). The client dials this |
| Each public port in `BACKPACK_PORTS` | server | TCP, **raw TCP**, not HTTP-only ingress |

The client opens nothing for the tunnel.

## Example: reach a VLESS inbound on your abroad server

You have a VPS abroad (Hetzner, say) with a VLESS inbound on port `1004`, and you want
users to reach it through the Iran container. All addresses and ports below are dummies.

```
user -> Iran container :2087 -> tunnel (the abroad VPS dials out) -> abroad VPS 127.0.0.1:1004
```

**1. Iran container** (this image, the `server` role):

```
BACKPACK_ROLE=server
BACKPACK_TOKEN=<long random secret>
BACKPACK_BIND=0.0.0.0:8443
BACKPACK_PORTS=2087=127.0.0.1:1004
```

`2087=127.0.0.1:1004` means: listen on `2087` here, deliver to `127.0.0.1:1004` on the
abroad VPS. Write `BACKPACK_PORTS=1004` to use the same number on both sides.

**2. Platform ports.** Expose two TCP ports and note the external number the platform
assigns to each. A tunnel port and a user port can't be the same one.

| Container port | Example external | Used for |
|---|---|---|
| `8443` | `203.0.113.10:30001` | the tunnel, dialled by the abroad VPS |
| `2087` | `203.0.113.10:30002` | users |

**3. Abroad VPS** (the `client` role). It's a normal server with systemd, so install
BackPack natively rather than in a container, so `127.0.0.1:1004` is the real inbound:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AminMGMT/BackPack/main/install.sh)
sudo backpack
```

In the wizard choose the kharej/client setup, the same transport (`tcp`), the same
token, and the Iran **external** tunnel address: `203.0.113.10:30001`. It needs no
inbound port, only outbound access to that address.

**4. Client link.** Take the VLESS link from the abroad inbound and change only the
address and port to `203.0.113.10:30002`. UUID, Reality/TLS settings and SNI stay the
same; the traffic passes through as raw TCP.

Also check on the abroad VPS that the inbound listens on `0.0.0.0` or `127.0.0.1`
(`ss -ltnp | grep 1004`), not only on its public IP.

**Don't** use the abroad VPS's own IP in the client link: that skips the tunnel.

## Check it

Client log: `control channel established successfully`. Server log:
`server started successfully, listening on address`.

The `could not set net.ipv4... — continuing` warnings are harmless: containers can't
change sysctls, and BackPack carries on.

## Not included

BackPack's interactive CLI wizard, systemd services and web panel (port 7777) don't apply
in a container; everything is set through the variables above.

## Tested

Server ↔ client with `tcp`, traffic through a forwarded port confirmed. Other transports
were not exercised.
