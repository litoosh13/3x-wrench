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

## Example

Server (Iran side, the one users reach):

```
BACKPACK_ROLE=server
BACKPACK_TOKEN=<secret>
BACKPACK_BIND=0.0.0.0:8443
BACKPACK_PORTS=443
```

Client (kharej side, where the 3x-ui inbound on `:443` lives):

```
BACKPACK_ROLE=client
BACKPACK_TOKEN=<same secret>
BACKPACK_REMOTE=<server public host>:<server tunnel port>
```

Users hit `server:443`, which arrives at `127.0.0.1:443` on the client.

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
