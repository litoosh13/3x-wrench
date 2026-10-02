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
| `XUI_ENABLE` | no | `true` (default) runs the 3x-ui panel. `false` turns it off, and the tunnel becomes the only process (the container exits with an error if no tunnel is configured too) |
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

## Examples

### The dummy values used below

Every address, port and secret in the examples is made up. Swap in your own.

| What | Dummy value |
|---|---|
| Iran container, public IP | `203.0.113.10` |
| Tunnel port: container `8443` → platform external | `30001` |
| User port: container `2087` → platform external | `30002` |
| Platform HTTPS hostname (maps to container `8080`) | `tunnel.example.com` |
| Abroad VPS IP | `198.51.100.7` |
| VLESS inbound on the abroad VPS | port `1004` |
| Shared token (generate your own: `openssl rand -hex 24`) | `4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36` |

### A. Through raw TCP ports

```
user -> 203.0.113.10:30002 -> Iran container -> tunnel (abroad VPS dials out) -> 198.51.100.7 127.0.0.1:1004
```

**Iran container** (this image, `server`). Env variables:

```
BACKPACK_ROLE=server
BACKPACK_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36
BACKPACK_BIND=0.0.0.0:8443
BACKPACK_PORTS=2087=127.0.0.1:1004
```

On the platform expose two TCP ports: container `8443` (→ `30001`) and container `2087`
(→ `30002`). `2087=127.0.0.1:1004` means: listen on `2087` here, deliver to
`127.0.0.1:1004` on the abroad VPS. Write `BACKPACK_PORTS=1004` to use the same number
on both sides.

**Abroad VPS** (`client`). It's a normal server with systemd, so install BackPack
natively; that way `127.0.0.1:1004` is the real inbound:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/AminMGMT/BackPack/main/install.sh)
sudo backpack
```

In the wizard choose the kharej/client setup, transport `tcp`, token
`4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36`, and server `203.0.113.10:30001`. The generated file
(`/etc/backpack/mytunnel.toml`) ends up like:

```toml
[client]
remote_addr = "203.0.113.10:30001"
transport = "tcp"
token = "4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36"
```

It needs no inbound port, only outbound access to `203.0.113.10:30001`. Also check the
inbound listens on `0.0.0.0` or `127.0.0.1` (`ss -ltnp | grep 1004`), not only on its
public IP.

**Client link** (what users import). Take the abroad inbound's link and change only the
address and port:

```
vless://11111111-2222-3333-4444-555555555555@203.0.113.10:30002?type=tcp&security=reality&sni=www.example.com&fp=chrome&pbk=DUMMY_PUBLIC_KEY&sid=ab12cd34#my-vless
```

UUID, `security`, `sni`, `pbk` and `sid` stay exactly as on the abroad inbound.

**Don't** use the abroad VPS's own IP in the client link: that skips the tunnel.

### B. Through a CDN or the platform's HTTPS hostname

Use this when the container has no raw TCP port for the tunnel but the platform (or a CDN
such as Cloudflare) gives it an HTTPS hostname, `tunnel.example.com`. The edge terminates
TLS and passes **plain HTTP** to one container port, and WebSocket is HTTP, so the tunnel
can ride it. Tested with nginx standing in for the edge.

```
abroad VPS --wss/443--> edge (TLS ends) --plain ws--> Iran container :8080
```

**The two ends use different transports. This is intended:**

| Side | `transport` | Why |
|---|---|---|
| Iran container (`server`) | `ws` | The edge already removed the TLS, so the container sees plain HTTP |
| Abroad VPS (`client`) | `wss` + `simple_auth = true` | It needs TLS to reach the edge on 443 |

**Iran container** (map `tunnel.example.com` to container port `8080`):

```
BACKPACK_ROLE=server
BACKPACK_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36
BACKPACK_TRANSPORT=ws
BACKPACK_BIND=0.0.0.0:8080
BACKPACK_PORTS=2087=127.0.0.1:1004
```

**Abroad VPS** (`client`). The wizard may insist both ends use the same transport, so edit
the generated file and restart. The file says not to edit it while the service runs, so
stop it first (the tunnel name here is `mytunnel`):

```bash
systemctl stop backpack-mytunnel
nano /etc/backpack/mytunnel.toml
systemctl start backpack-mytunnel
journalctl -u backpack-mytunnel -f
```

```toml
[client]
remote_addr = "tunnel.example.com:443"
transport = "wss"
simple_auth = true
token = "4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36"
# edge_ip = "192.0.2.50"   # optional: dial this edge/CDN IP, still using the hostname
```

`simple_auth` is needed because the edge terminates TLS, which breaks BackPack's
session-bound proof. It sends the raw token to the edge, so use a long random token and
only an edge you trust. Where that matters, use
[Kariz](xui-kariz.md#b-through-the-platforms-https-hostname), whose traffic stays encrypted
end to end.

`edge_ip` makes the client connect to a specific edge IP while still sending the hostname
for TLS and routing. Use it when the hostname's own DNS answer is blocked or you want a
clean CDN address. For Cloudflare the port must be one it proxies (443, 2053, 2083, 2087,
2096, 8443) and the record must be proxied.

The user port still needs its own raw TCP mapping (container `2087` → `30002`); the client
link is the same as in example A.

**What goes wrong**

| Symptom | Cause |
|---|---|
| Client never connects, edge answers `400` | Client set to `ws` on port 443: plain WebSocket to a TLS port. Use `wss` |
| `wss` set on the Iran container | The container expects TLS that the edge already removed. Use `ws` there |
| Token rejected through the edge | `simple_auth = true` missing on the client |
| Tunnel connects, user port fails | The user port needs its own raw TCP mapping; the hostname carries HTTP only and reaches one container port |
| Panel stopped answering on the hostname | A hostname maps to one port. Mapped to the tunnel, it no longer reaches the panel |
| Drops every minute or two | The edge cuts idle connections. Keep `keepalive_period` low (e.g. `30`) |

Success looks like: client `control channel established successfully` then
`transport wss is up`; server `control channel established successfully`.

### C. Users connect to the platform hostname on port 443

Here the **tunnel** stays on raw TCP (as in example A) and the platform hostname serves
the **users**: `tunnel.example.com:443` in the VLESS link reaches the abroad inbound
through the tunnel. The platform ends TLS at its edge and passes plain HTTP to the
container.

```
user --TLS/443--> edge (TLS ends) --plain HTTP--> Iran container :2087 --tunnel--> 198.51.100.7 127.0.0.1:1004
```

1. **Tunnel:** exactly as example A (Iran container + abroad VPS over
   `203.0.113.10:30001`).
2. **Hostname:** in the platform, map `tunnel.example.com` to container port `2087`, the
   forwarded user port, not to a tunnel port.
3. **Iran container:** unchanged from example A:

```
BACKPACK_ROLE=server
BACKPACK_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36
BACKPACK_BIND=0.0.0.0:8443
BACKPACK_PORTS=2087=127.0.0.1:1004
```

4. **Abroad VPS, 3x-ui inbound.** It must speak HTTP, because TLS ends at the edge:

| Field | Value |
|---|---|
| Protocol | VLESS |
| Port | `1004` |
| Listen | `0.0.0.0` (or `127.0.0.1`) |
| Network | WebSocket |
| Path | `/ws` |
| Security | **none** (no TLS, no Reality) |
| Client UUID | `11111111-2222-3333-4444-555555555555` |

5. **Client link.** The address is the platform hostname and the port is `443`:

```
vless://11111111-2222-3333-4444-555555555555@tunnel.example.com:443?type=ws&security=tls&sni=tunnel.example.com&host=tunnel.example.com&path=%2Fws&encryption=none#via-tunnel
```

`security=tls` is the user's TLS to the edge. UUID and `path` must match the inbound.

**Works:** WebSocket, `httpupgrade` and `xhttp` inbounds. **Doesn't:** Reality, XTLS
Vision, Trojan-over-TLS or anything else that needs raw TLS end to end, because the edge
ends TLS. gRPC usually fails too, as the edge speaks HTTP/1.1 to the container.

**Trade-offs**
- The platform's edge sees your users' traffic: it ends TLS, and VLESS adds no encryption
  of its own.
- BackPack `tcp` does not encrypt the payload on the Iran-to-abroad leg. Use `stealth` or `pck` for that leg (same transport on both ends), or use [Kariz](xui-kariz.md#c-users-connect-to-the-platform-hostname-on-port-443).
- A hostname maps to **one** container port, so it is used up by the user port here. The
  tunnel has to run on its own raw TCP port (`30001`). If the platform gives you only the
  hostname, you can't also use it for users.
- Built from parts tested separately (edge to container, and the tunnel to its target);
  the whole chain was not run together.

## Check it

Client log: `control channel established successfully`. Server log:
`server started successfully, listening on address`.

The `could not set net.ipv4... — continuing` warnings are harmless: containers can't
change sysctls, and BackPack carries on.

## Not included

BackPack's interactive CLI wizard, systemd services and web panel (port 7777) don't apply
in a container; everything is set through the variables above.

## Tested

Server ↔ client with `tcp`, and with `ws` behind a TLS-terminating nginx (client dialling
`wss` with `simple_auth`), traffic through a forwarded port confirmed. Other transports
and a real platform edge were not exercised.
