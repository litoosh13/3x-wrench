# xui-kariz

3x-ui panel + [Kariz](https://github.com/Erfan-XRay/Kariz) in one container.
Image: `ghcr.io/litoosh13/xui-kariz:latest` (build file: [`Dockerfile.3x-ui-kariz`](../Dockerfile.3x-ui-kariz)).

Kariz links two servers with an encrypted tunnel. Users connect to the **entry**; Kariz
carries their TCP/UDP traffic to the **exit**, which reaches the real target. You run one
container per side.

## Volume

| Mount path | Holds |
|---|---|
| `/etc/x-ui` | Panel database. Add it, or every redeploy resets to `admin`/`admin` |

The tunnel config is regenerated from env on every start, so it needs no volume.

## Environment variables

Nothing starts until `KARIZ_ROLE` is set.

| Name | Required | Notes |
|---|---|---|
| `KARIZ_ROLE` | yes | `entry` or `exit` |
| `KARIZ_TOKEN` | yes | Same value on both sides. Make one: `docker run --rm --entrypoint kariz IMAGE token` |
| `KARIZ_MODE` | no | `reverse` (default) or `direct`. See below |
| `KARIZ_TRANSPORT` | no | Default `tcpmux`. Also `tcp`, `ws`, `wss` (direct), `kcp`, `quic`, `udp` |
| `KARIZ_LISTEN` | one of | The side that **listens** sets this, e.g. `0.0.0.0:3080` |
| `KARIZ_REMOTE` | one of | The side that **dials** sets this, e.g. `203.0.113.5:3080` |
| `KARIZ_FORWARD` | entry only | `443=127.0.0.1:443,8080=127.0.0.1:80`: public port on the entry `=` target dialled from the exit. A bare port listens on `0.0.0.0` |
| `KARIZ_WS_PATH` | ws/wss | WebSocket path, e.g. `/api/v1/stream`. Must match on both sides |
| `KARIZ_WS_HOST` | ws/wss | Host header (and TLS name on the dialer). Set it to your hostname |
| `KARIZ_PROFILE` | no | `balanced` (default), `ultraspeed`, `gaming` |

Who listens depends on the mode:

| Mode | Entry | Exit |
|---|---|---|
| `reverse` (default) | `KARIZ_LISTEN` | `KARIZ_REMOTE` |
| `direct` | `KARIZ_REMOTE` | `KARIZ_LISTEN` |

Reverse is the one to use when the exit sits behind NAT or a platform that gives you no
inbound port: the exit only dials out.

`UDP`-based transports (`kcp`, `quic`, `udp`) need the platform to forward **UDP** on the
tunnel port. Stay on `tcpmux` if you are unsure.

For anything the variables don't cover, put a complete config at `/data/kariz.toml`
(mount a volume at `/data`); it is used instead. Format: the
[Kariz README](https://github.com/Erfan-XRay/Kariz) and its `configs/` samples.

## Ports to open on the platform

| Port | Where | Protocol |
|---|---|---|
| `2053` | both | TCP: panel |
| The tunnel port (`3080` in the examples) | whichever side **listens** | TCP (UDP for kcp/quic/udp) |
| Each public port in `KARIZ_FORWARD` | entry | TCP, **raw TCP**, not HTTP-only ingress |

The side that only dials opens nothing for the tunnel.

## Example: reverse tunnel

Entry (the server users reach):

```
KARIZ_ROLE=entry
KARIZ_TOKEN=<token>
KARIZ_LISTEN=0.0.0.0:3080
KARIZ_FORWARD=443=127.0.0.1:443
```

Exit (where the 3x-ui inbound on `:443` lives):

```
KARIZ_ROLE=exit
KARIZ_TOKEN=<same token>
KARIZ_REMOTE=<entry public host>:<entry tunnel port>
```

Users hit `entry:443`, which arrives at `127.0.0.1:443` on the exit.

## Behind the platform's HTTPS hostname

Many platforms give the container a hostname like `tunnel.example.com` and map it to one
container port. The platform terminates TLS and passes **plain HTTP** to the container.
WebSocket is HTTP, so the tunnel can ride it, and the container (the Iran side) never
needs a raw TCP port for the tunnel.

Iran container (`entry`; map the hostname to port `8080` in the platform):

```
KARIZ_ROLE=entry
KARIZ_TOKEN=<token>
KARIZ_TRANSPORT=ws
KARIZ_LISTEN=0.0.0.0:8080
KARIZ_WS_PATH=/api/v1/stream
KARIZ_WS_HOST=tunnel.example.com
KARIZ_FORWARD=2087=127.0.0.1:1004
```

Abroad VPS (`exit`), which dials the hostname over `wss`:

```toml
role = "exit"
mode = "reverse"

[tunnel]
transport = "wss"
remote = "tunnel.example.com:443"
token = "<same token>"

[tunnel.ws]
path = "/api/v1/stream"
host = "tunnel.example.com"
```

Notes:
- The container side is plain `ws`; only the dialing side says `wss`. That is intended.
- A hostname maps to **one** container port. Point it at the tunnel port; it then no
  longer reaches the panel.
- The hostname carries HTTP only. The forwarded user port (`2087`) still needs its own
  raw TCP mapping.
- Mux stays on (the default), because its pings stop the edge cutting the connection as
  idle. Keep `keepalive` at or below ~90 s.

## Check it

Container logs should show `mux session ... established`. Or in the container:

```bash
kariz status -c /etc/kariz/config.toml
```

`exit side ● connected` means the tunnel is up. `1 failed` on a forward means the target
on the exit isn't listening.

## Tested

Entry ↔ exit with `reverse` + `tcpmux`, and with `ws` behind a TLS-terminating nginx
(exit dialling `wss`), traffic through a forwarded port confirmed. Other transports,
`direct`, and a real platform edge were not exercised.
