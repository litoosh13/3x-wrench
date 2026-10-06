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

## 5. Both at once in one container

```
BACKPACK_ROLE=server
BACKPACK_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36
BACKPACK_TRANSPORT=ws
BACKPACK_BIND=127.0.0.1:8080
BACKPACK_PORTS=2087=127.0.0.1:1004,2088=127.0.0.1:1006,2090=127.0.0.1:1005
NGINX_ENABLE=true
NGINX_ROUTES=/channel=127.0.0.1:8080,/tunnel=127.0.0.1:8080,/b/=127.0.0.1:2088
NGINX_DEFAULT=127.0.0.1:2087
```
- Hostname → container `8000`: the tunnel (`wss` from the abroad VPS), xhttp `/` → `1004`, xhttp `/b/` → `1006`.
- Container `2090` as a raw TCP port: Reality → `1005`, reached by IP.
- The tunnel itself runs over the hostname here, so no raw port is needed for it.

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

Not verified on a real platform: Reality through the raw-port way, Shadowsocks, WireGuard
through this setup, and multiple paths (section 3b). They are tested only in the local rig.

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
