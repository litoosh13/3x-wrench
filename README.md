# xui-spoof

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

```bash
docker run -d --name xui --cap-add=NET_RAW -p 2053:2053 -v xui-data:/etc/x-ui \
  ghcr.io/litoosh13/xui-kariz:latest
```

Then add the variables from the image's guide above.

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
