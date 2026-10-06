# Two ways in: the container's IP, or the platform's hostname

Users (and the abroad server) can reach the Iran container in two different ways. They do
not support the same protocols. This page lists both with dummy examples, says what breaks
on each, and records what was actually verified on a real platform. All addresses, ports,
UUIDs and tokens below are **dummies**.

Related: [iran-container.md](iran-container.md) (how the container works),
[xui-backpack.md](xui-backpack.md) (variables and the nginx feature).

## 1. The two ways

| | **IP + raw port** | **Platform hostname** |
|---|---|---|
| Address in the client link | the container's public IP + the external port | `tunnel.example.com`, port `443` |
| What the platform does | maps an external TCP/UDP port to a container port, bytes pass untouched | its **edge ends TLS** and sends **plain HTTP** to one container port |
| Needs on the platform | one mapping per forwarded port (TCP, and a separate one for UDP) | one hostname mapping, to nginx's port (`8000`) |
| Works | Reality, XTLS Vision, Shadowsocks, WireGuard/UDP, VLESS over TCP, anything | only HTTP-based protocols: **xhttp, WebSocket** (security none on the abroad inbound) |
| Does **not** work | nothing is blocked by the platform (but see "raw ports can be blocked" below) | **Reality**, XTLS Vision, Trojan/TLS, gRPC, Shadowsocks, WireGuard, any raw TLS |
| The edge sees | only encrypted bytes | the user's traffic in clear (it ends TLS) |
| Several services | one port per service | one hostname, **one path per service** |

Both can be used at the same time by one container (section 5).

## 2. Way 1: IP + raw ports

The container forwards each public port through the tunnel to a port on the abroad VPS.
Add one forward per service; each needs a **TCP mapping** on the platform (container port
→ external port), and UDP services need a separate **UDP mapping**.

Dummy scenario: container `203.0.113.10`; tunnel over raw TCP; abroad VPS runs Reality
`1005`, Shadowsocks `1006`, WireGuard `1007`.

Iran container:
```
BACKPACK_ROLE=server
BACKPACK_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36
BACKPACK_BIND=0.0.0.0:8443
BACKPACK_PORTS=2090=127.0.0.1:1005,2091=127.0.0.1:1006,2092=127.0.0.1:1007
BACKPACK_ACCEPT_UDP=true
```
Platform mappings (external numbers are examples): container `8443` TCP → `30001` (the tunnel),
`2090` TCP → `30003` (Reality), `2091` TCP **and** UDP → `30004` (Shadowsocks), `2092` UDP →
`30005` (WireGuard).

Abroad VPS BackPack client (`/etc/backpack/mytunnel.toml`):
```toml
[client]
remote_addr = "203.0.113.10:30001"
transport = "tcp"
token = "4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36"
```
Client links point at the **IP and the external port**:
```
vless://11111111-2222-3333-4444-555555555555@203.0.113.10:30003?type=tcp&security=reality&sni=tunnel.example.com&fp=chrome&pbk=DUMMY_PUBLIC_KEY&sid=ab12cd34&flow=xtls-rprx-vision&encryption=none#reality
ss://BASE64(method:password)@203.0.113.10:30004#shadowsocks
WireGuard peer:  Endpoint = 203.0.113.10:30005
```
Reality's inbound uses `dest = tunnel.example.com:443` and `serverNames = [tunnel.example.com]`,
so the hostname is only the camouflage name (the `sni`), never the address.

Caveat: a raw platform IP:port can be unreachable from some home networks even when the
platform is fine (seen once: instant "connection refused" from home, success from the
abroad server). Test the raw port from the network the users are on.

## 3. Way 2: the hostname (nginx path routing)

With `NGINX_ENABLE=true`, nginx listens on one port (default `8000`) and routes by URL path.
The hostname is mapped to **that port**, not to `8080`: `8080` is BackPack's own WebSocket
server, bound to `127.0.0.1` and reachable only by nginx.

```
users   --TLS/443--> edge --plain HTTP--> nginx :8000 --path--> BackPack forward --tunnel--> abroad inbound
abroad  --wss/443--> edge --plain HTTP--> nginx :8000 --/channel, /tunnel--> BackPack ws server
```
BackPack's WebSocket tunnel uses two paths, `/channel` (control) and `/tunnel/<id>` (data).
Both must be routed, and **no user path may start with `/channel` or `/tunnel`**.

### 3a. One service (xhttp), the tested setup
The abroad inbound (VLESS, xhttp, **security none**, port `1004`) uses path `/`. nginx sends
everything that is not the tunnel to the forward for `1004`:

```
BACKPACK_ROLE=server
BACKPACK_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36
BACKPACK_TRANSPORT=ws
BACKPACK_BIND=127.0.0.1:8080
BACKPACK_PORTS=2087=127.0.0.1:1004
NGINX_ENABLE=true
NGINX_ROUTES=/channel=127.0.0.1:8080,/tunnel=127.0.0.1:8080
NGINX_DEFAULT=127.0.0.1:2087
```
Hostname mapped to container port `8000`. Abroad BackPack client:
```toml
[client]
remote_addr = "tunnel.example.com:443"
transport = "wss"
simple_auth = true
token = "4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36"
```
Client link (**keep `h2` in `alpn`**, see section 6):
```
vless://11111111-2222-3333-4444-555555555555@tunnel.example.com:443?encryption=none&security=tls&sni=tunnel.example.com&fp=chrome&alpn=h2%2Chttp%2F1.1&type=xhttp&host=tunnel.example.com&path=%2F&mode=packet-up#hostname-xhttp
```

### 3b. Several services: one path each
Every extra abroad inbound gets its own path, its own container forward port and its own
route. The path must be identical in three places: the abroad inbound, `NGINX_ROUTES`, and
the client link. Add an xhttp inbound on `1006` with path `/b/` and a WebSocket inbound on
`1008` with path `/ws/`:

```
BACKPACK_PORTS=2087=127.0.0.1:1004,2088=127.0.0.1:1006,2089=127.0.0.1:1008
NGINX_ROUTES=/channel=127.0.0.1:8080,/tunnel=127.0.0.1:8080,/b/=127.0.0.1:2088,/ws/=127.0.0.1:2089
NGINX_DEFAULT=127.0.0.1:2087
```
Client links (only the path, and `type` for WebSocket, change):
```
…@tunnel.example.com:443?…&alpn=h2%2Chttp%2F1.1&type=xhttp&host=tunnel.example.com&path=%2Fb%2F&mode=packet-up
…@tunnel.example.com:443?…&alpn=h2%2Chttp%2F1.1&type=ws&host=tunnel.example.com&path=%2Fws%2F
```
Rules: forward container ports (`2087`, `2088`, …) and abroad ports must all differ; end
user paths with a slash; the path `/` (the default) can serve only **one** inbound.
Everything that must stay raw (Reality, Shadowsocks, UDP) goes through Way 1 instead.

## 4. The problem with Reality (and the other raw-TLS protocols) on the hostname

Reality performs a TLS handshake directly with the abroad inbound. The platform's edge ends
TLS at the hostname, so the handshake never reaches the abroad server and the client gets
no ping and no connection. This is a property of the platform, not of the image, and no
setting changes it. The same holds for XTLS Vision, Trojan over TLS, and gRPC.

What to do instead:

| Wish | Do this |
|---|---|
| Reality | Way 1: the link's address is the container's **IP + external port**; use the hostname only as `sni` / Reality `dest` |
| One hostname for everything | Use xhttp or WebSocket (security none on the abroad inbound); give up Reality |
| Both | Run both at once (section 5) |

Test whether Reality can work from a given network before relying on it: the raw port may
be blocked (section 2), and then only the hostname way is left.

## 5. Worked example: one clean container, four services (step by step)

This is the exact order used to build a clean setup, with dummy values. One Iran container
and one abroad VPS carry four services, each through the way that suits it:

| Service on the abroad VPS | Port | Reaches users through | Why |
|---|---|---|---|
| VLESS xhttp, security **none**, path `/` | `1004` | the **hostname** (nginx) | HTTP-based, so the edge can carry it |
| Shadowsocks (TCP) | `1006` | **IP + raw TCP port** | not HTTP |
| WireGuard (UDP) | `1007` | **IP + raw UDP port** | UDP |
| VLESS xhttp over **Reality** | `1008` | **IP + raw TCP port** | Reality needs raw TLS end to end |

The tunnel itself runs over the hostname, so it needs no raw port of its own.

Dummy values: hostname `tunnel.example.com`, container IP `203.0.113.10`, token
`4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36`, user UUID `11111111-2222-3333-4444-555555555555`, abroad VPS tunnel service
named `mytunnel`.

Do the steps in order and test each one before the next. If a step fails, the cause is in
that step.

### Step 1: the container, tunnel only
Env (the panel is off by default, so nothing else is needed):
```
BACKPACK_ROLE=server
BACKPACK_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36
BACKPACK_TRANSPORT=ws
BACKPACK_BIND=127.0.0.1:8080
NGINX_ENABLE=true
NGINX_ROUTES=/channel=127.0.0.1:8080,/tunnel=127.0.0.1:8080
```
Platform: map the hostname to container port **`8000`** (nginx), not `8080`. The log shows
`nginx on 8000` and `waiting for ws control channel connection`. Check from outside:

```bash
curl -si https://tunnel.example.com/ | head -3     # expect: HTTP/2 404
```
Pitfalls seen: `curl` without `https://` shows a `301` (the edge's redirect, not your
container); a `502` with `server: nginx` and no version means the hostname is mapped to the
wrong container port (check it says `8000`); `ss -ltn | grep 8000` and
`curl -si http://127.0.0.1:8000/` in the container prove nginx itself is fine.

### Step 2: the abroad VPS dials the hostname
`/etc/backpack/mytunnel.toml` (stop the service first, start it after):
```toml
[client]
remote_addr = "tunnel.example.com:443"
transport = "wss"
simple_auth = true
token = "4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36"
```
No `edge_ip` line (a stale one pins the connection to an edge IP that may not serve the new
hostname and gives `tls: unrecognized name`). Success: `control channel established
successfully`, `transport wss is up`.

### Step 3: VLESS xhttp on 1004, through the hostname
Container: add the forward and route everything that is not the tunnel to it:
```
BACKPACK_PORTS=2087=127.0.0.1:1004
NGINX_DEFAULT=127.0.0.1:2087
```
Abroad inbound: VLESS, xhttp, port `1004`, security **none**, path `/`, mode `packet-up`,
`host` empty. Test inside out (each should return `400` with an `X-Padding` header, which
proves the request reached Xray): `curl -si http://127.0.0.1:1004/` on the VPS, then in the
container `printf 'GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n' | nc -w3 127.0.0.1 2087` and
`curl -si http://127.0.0.1:8000/`, then `curl -si https://tunnel.example.com/` from outside.

Client link: the address is the hostname, and `alpn` **must contain `h2`**:
```
vless://11111111-2222-3333-4444-555555555555@tunnel.example.com:443?encryption=none&security=tls&sni=tunnel.example.com&fp=chrome&alpn=h2%2Chttp%2F1.1&type=xhttp&host=tunnel.example.com&path=%2F&mode=packet-up#hostname-xhttp
```

### Step 4: Shadowsocks on 1006, through a raw TCP port
Container: add a forward (TCP only to start):
```
BACKPACK_PORTS=2087=127.0.0.1:1004,2091=127.0.0.1:1006
```
Platform: map container `2091` as a **raw TCP** port, for example external `30004`. On the VPS,
`ss -ltnp | grep 1006` must show `0.0.0.0:1006` or `127.0.0.1:1006` (not only the public IP).
Checks: `nc -vz 127.0.0.1 2091` in the container, then `nc -vz 203.0.113.10 30004` from the
network the users are on. The client link is the existing Shadowsocks link with only the address and
port changed to `203.0.113.10:30004`.

### Step 5: WireGuard on 1007, through a raw UDP port
Container: add the forward and switch UDP on:
```
BACKPACK_PORTS=2087=127.0.0.1:1004,2091=127.0.0.1:1006,2092=127.0.0.1:1007
BACKPACK_ACCEPT_UDP=true
```
`BACKPACK_ACCEPT_UDP` gives every forwarded port a UDP listener, which is harmless where the
platform has no UDP mapping. Platform: map container `2092` as a **UDP** port, for example external
`30005` (a UDP mapping is separate from a TCP one). On the VPS `ss -ulnp | grep 1007` shows
WireGuard. Client config: only the endpoint changes, plus two helpful lines:
```ini
[Interface]
MTU = 1280

[Peer]
Endpoint = 203.0.113.10:30005
PersistentKeepalive = 25
```
`PersistentKeepalive = 25` keeps the UDP flow alive (BackPack drops a flow after 60 s of silence). On the VPS,
`tcpdump -ni any udp port 1007` shows packets from `127.0.0.1`, which is expected.

### Step 6: Reality xhttp on 1008, through a raw TCP port
Container: add the last forward:
```
BACKPACK_PORTS=2087=127.0.0.1:1004,2091=127.0.0.1:1006,2092=127.0.0.1:1007,2093=127.0.0.1:1008
```
Platform: map container `2093` as a **raw TCP** port, for example external `30006`. Abroad inbound: VLESS,
xhttp, security **Reality**, port `1008`; its `serverNames` must contain the link's `sni`, and `dest` is a
site that supports TLS 1.3 and HTTP/2. Check Reality's camouflage (a normal TLS client must get the
destination site's page):
```bash
curl -vk --resolve tunnel.example.com:30006:203.0.113.10 https://tunnel.example.com:30006/ 2>&1 | grep -E 'HTTP/|alert|refused'
```
Client link: take the Reality link, change only the address and port to `203.0.113.10:30006`:
```
vless://11111111-2222-3333-4444-555555555555@203.0.113.10:30006?encryption=none&security=reality&sni=tunnel.example.com&fp=chrome&pbk=DUMMY_PUBLIC_KEY&sid=ab12cd34&type=xhttp&path=%2Fr%2F&mode=auto#reality-xhttp
```
(The path and mode follow the inbound's own xhttp settings; Reality over xhttp needs no `flow`.)

### Final container environment, all steps together
```
BACKPACK_ROLE=server
BACKPACK_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36
BACKPACK_TRANSPORT=ws
BACKPACK_BIND=127.0.0.1:8080
BACKPACK_PORTS=2087=127.0.0.1:1004,2091=127.0.0.1:1006,2092=127.0.0.1:1007,2093=127.0.0.1:1008
BACKPACK_ACCEPT_UDP=true
NGINX_ENABLE=true
NGINX_ROUTES=/channel=127.0.0.1:8080,/tunnel=127.0.0.1:8080
NGINX_DEFAULT=127.0.0.1:2087
```

### Platform mappings, all steps together
| Container port | Type | Example external | Used by |
|---|---|---|---|
| `8000` | hostname (HTTP) | `tunnel.example.com` | the tunnel and VLESS xhttp (`1004`) |
| `2091` | raw TCP | `30004` | Shadowsocks (`1006`) |
| `2092` | raw **UDP** | `30005` | WireGuard (`1007`) |
| `2093` | raw TCP | `30006` | Reality xhttp (`1008`) |

Status on the real platform: **all six steps were confirmed working there**, in this order, with the
hostname carrying the tunnel and VLESS xhttp, and raw ports carrying Shadowsocks (TCP), WireGuard (UDP)
and Reality xhttp. Shadowsocks UDP was not enabled.

## 6. What was verified, and the pitfalls found

On a real platform (hostname + nginx + BackPack `ws`, abroad VPS dialling `wss`):
- The tunnel came up over the hostname, and a VLESS **xhttp** inbound on path `/` carried real
  traffic. Instagram loaded well through it.
- **ALPN must include `h2`.** Tested with a real Xray client on the same chain: path `/` with
  `alpn=h2,http/1.1` (or `h2` alone) worked; `alpn=http/1.1` only failed at once, and the
  requests never reached nginx. The padding option (`extra`) and the fingerprint did not matter.
- The abroad inbound's path must be the path in the link. The inbound used `/`; a link with
  `/x` gave a 400 on every request.
- A 5 MB download through the path took about 12 s (~0.4 MB/s) from a laptop. That is one
  measurement from one network, not a benchmark.

Not verified on a real platform: several paths at once (section 3b), Shadowsocks UDP, and long idle
periods on the edge. They are tested only in the local rig, or not at all. The whole clean setup in
section 5 (tunnel, VLESS xhttp, Shadowsocks TCP, WireGuard, Reality xhttp) was confirmed there.

## 7. Diagnosing a hostname setup (inside out)

Stop at the first layer that fails. A healthy Xray xhttp inbound answers a plain GET with
`400` and an `X-Padding` header, so that header proves the request reached Xray.

| Layer | Run | Healthy |
|---|---|---|
| Abroad inbound | `curl -si http://127.0.0.1:1004/ \| head` on the VPS | `400` + `X-Padding`; also `ss -ltnp \| grep 1004` |
| Forward / tunnel | in the container: `printf 'GET / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n' \| nc -w3 127.0.0.1 2087` | same `400` + `X-Padding` |
| nginx | in the container: `curl -si http://127.0.0.1:8000/` | same |
| Hostname | `curl -si https://tunnel.example.com/` from outside | same |
| Real client | an Xray client with the link's settings, `curl --socks5-hostname` through it | an HTTP response |
| Where requests stop | `tcpdump -nA -i any tcp port 8000 -c 60 \| grep -E 'GET \|POST \|HTTP/'` in the container while the client tries | `GET /<session>` and `POST /<session>/<n>` lines |

Reading the failures:

| You see | Meaning |
|---|---|
| `tls: unrecognized name` (curl or the BackPack log) | The edge has no route for that hostname. Wrong or old hostname, hostname not mapped to the container, or a stale `edge_ip`. Check each of the edge's IPs with `curl --resolve host:443:IP` |
| `websocket: bad handshake` | nginx has no route for BackPack's `/channel` or `/tunnel/` |
| nginx page "plain HTTP request was sent to HTTPS port" | The abroad port speaks TLS. The inbound must be security **none** |
| `400` **without** `X-Padding` | The reply came from nginx or the edge, not Xray |
| `400` with `X-Padding` on every real request | The path or host in the link does not match the inbound |
| nginx `502` | The route points at a port that has no forward |
| Nothing at all on the container tap | The client never reaches nginx: wrong hostname, `alpn` without `h2`, or a network block |
| Hostname mapped to `8080` | Wrong. Map it to nginx's `8000` (`8080` is loopback-only) |

A leftover `edge_ip` in an abroad BackPack config pins its connection to one edge IP, and
that IP may not serve the new hostname. Remove it, or set it to an IP that answers.
