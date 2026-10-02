# 3x-wrench

[3x-ui](https://github.com/MHSanaei/3x-ui) panel plus one censorship-bypass tool per image,
built for container platforms (PaaS) that give you a single container. `linux/amd64` and
`linux/arm64`, rebuilt weekly so `latest` tracks upstream. Public images, no login needed.

| Image | Adds | Setup guide |
|---|---|---|
| `ghcr.io/litoosh13/xui-spoof` | [SNI-Spoofing-Go](https://github.com/aleskxyz/SNI-Spoofing-Go): fake-SNI relay for outbound traffic | [DEPLOY.md](DEPLOY.md) |
| `ghcr.io/litoosh13/xui-backpack` | [BackPack](https://github.com/AminMGMT/BackPack): Iran ⇄ abroad reverse tunnel | [docs/xui-backpack.md](docs/xui-backpack.md) |
| `ghcr.io/litoosh13/xui-kariz` | [Kariz](https://github.com/Erfan-XRay/Kariz): encrypted entry/exit tunnel | [docs/xui-kariz.md](docs/xui-kariz.md) |

Tags: `latest` (newest `main`), `vX.Y.Z` (git tag), `sha-abc1234` (pin for reproducible deploys).

## Same in all three

| | |
|---|---|
| Panel | port `2053`, login `admin` / `admin` (change it) |
| Volume | `/etc/x-ui` holds the panel database. Without it every redeploy resets the panel |
| Tunnel/spoofer | Starts only when its role/`CONNECT` variable is set. Leave it unset for a plain panel |
| Override | A script at `/data/entrypoint.sh` replaces the built-in start-up |
| Needs | Root. `NET_RAW` for the spoofer (Docker default). Raw TCP ports for inbounds |

## Quick start

Dummy example: an Iran-side Kariz entry that publishes port `2087` and delivers it to
`127.0.0.1:1004` on the abroad server. Every value here is made up.

```bash
docker run -d --name xui --cap-add=NET_RAW \
  -p 2053:2053 -p 3080:3080 -p 2087:2087 \
  -v xui-data:/etc/x-ui \
  -e KARIZ_ROLE=entry \
  -e KARIZ_TOKEN=4f9d2a7c18e35b60a1d4c7e92f0b83d65a1c9e47b20f8d36 \
  -e KARIZ_LISTEN=0.0.0.0:3080 \
  -e KARIZ_FORWARD=2087=127.0.0.1:1004 \
  ghcr.io/litoosh13/xui-kariz:latest
```

Panel on `:2053` (`admin` / `admin`, change it). The matching abroad side and the same
example for BackPack and the spoofer are in each image's guide above.

## Building

Each image is one self-contained Dockerfile, so a provider that only takes a Dockerfile
can paste it in: [`Dockerfile.3x-ui`](Dockerfile.3x-ui),
[`Dockerfile.3x-ui-backpack`](Dockerfile.3x-ui-backpack),
[`Dockerfile.3x-ui-kariz`](Dockerfile.3x-ui-kariz). Pin versions with the build args
`REF` (the tool) and `XUI_REF` (3x-ui). They build only from GitHub releases and the
Debian mirrors, and have no `# syntax=` line, heredoc, `COPY` or compile step. Keep it
that way: it is what lets them build behind registry mirrors and from Iran.

The SNI-spoofer alone, without the panel, is [`Dockerfile`](Dockerfile); its full manual is
[docs/sni-spoofing-only.md](docs/sni-spoofing-only.md).
