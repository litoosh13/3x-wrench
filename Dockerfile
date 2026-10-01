# ===========================================================================
# SNI-Spoofing-Go — container image. See docs/sni-spoofing-only.md.
#
# Configured entirely by environment variables (no config.ini):
#   CONNECT=104.19.229.21:443  FAKE_SNI=hcaptcha.com  UTLS=firefox  PORT=40443
#
# Deliberately built to survive restricted networks — do not "modernise" these:
#   * no `# syntax=` line  -> never pulls the docker/dockerfile frontend image,
#                             which registry mirrors usually do not carry
#   * no heredoc           -> works on old builders and behind such mirrors
#   * no Go build          -> never contacts proxy.golang.org (403 in Iran etc.)
# Only debian:bookworm-slim and github.com are needed to build this.
#
#   Repo: https://github.com/aleskxyz/SNI-Spoofing-Go   (GPL-3.0)
# ===========================================================================

# --------------------------- download stage -------------------------------
FROM debian:bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl && rm -rf /var/lib/apt/lists/*

# REF=latest -> newest release. Pin a tag instead, e.g. --build-arg REF=v1.0.0
ARG REF=latest
ARG TARGETARCH
ARG TARGETVARIANT

RUN set -eu; \
    case "${TARGETARCH:-amd64}${TARGETVARIANT:-}" in \
      amd64)  ASSET=sni-spoofing-linux-amd64 ;; \
      arm64)  ASSET=sni-spoofing-linux-arm64 ;; \
      armv7)  ASSET=sni-spoofing-linux-armv7 ;; \
      *) echo "unsupported arch: ${TARGETARCH:-}${TARGETVARIANT:-}" >&2; exit 1 ;; \
    esac; \
    if [ "$REF" = "latest" ]; then \
      URL="https://github.com/aleskxyz/SNI-Spoofing-Go/releases/latest/download/${ASSET}"; \
    else \
      URL="https://github.com/aleskxyz/SNI-Spoofing-Go/releases/download/${REF}/${ASSET}"; \
    fi; \
    echo "downloading ${URL}"; \
    mkdir -p /out; \
    curl -fL --retry 3 -o /out/sni-spoofing "$URL"; \
    chmod +x /out/sni-spoofing; \
    /out/sni-spoofing -h >/dev/null 2>&1 || true

# ---------------------------- runtime stage -------------------------------
FROM debian:bookworm-slim

# iptables AND iproute2 are both needed by the "active" (nfqueue) injector:
# it runs `ip route get` / `ip rule`, and upstream's image ships iptables only.
# The second line is the network-debugging toolbox: ping, nslookup/dig, nc,
# traceroute, netstat/ifconfig, tcpdump. The third is editing/quality-of-life.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates iptables iproute2 libcap2-bin tini \
        iputils-ping dnsutils netcat-openbsd traceroute net-tools tcpdump \
        procps curl wget nano vim-tiny less \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/sni-spoofing /usr/local/bin/sni-spoofing

# WORKDIR is deliberately NOT /data: the binary auto-loads ./config.ini when
# one happens to be present, and we want a pure flags-only run.
RUN mkdir -p /data
WORKDIR /app

# entrypoint.sh, base64-encoded so this Dockerfile needs no heredoc support
# and no external frontend. Decode it to read/edit:
#   docker run --rm --entrypoint sh IMAGE -c 'cat /usr/local/bin/entrypoint.sh'
RUN set -eu; printf '%s' \
    IyEvYmluL3NoCiMgQnVpbGRzIHNuaS1zcG9vZmluZyBDTEkgZmxhZ3MgZnJvbSBlbnZpcm9ubWVudCB2YXJpYWJsZXMuIE9ubHkg \
    dmFyaWFibGVzIHlvdQojIGFjdHVhbGx5IHNldCBhcmUgcGFzc2VkLCBzbyBhbnl0aGluZyBsZWZ0IHVuc2V0IGtlZXBzIHRoZSBi \
    aW5hcnkncyBvd24gZGVmYXVsdC4Kc2V0IC1ldQoKbG9nKCkgeyBwcmludGYgJ1tlbnRyeXBvaW50XSAlc1xuJyAiJCoiID4mMjsg \
    fQoKIyAtLS0gb3ZlcnJpZGUgaG9vazogeW91ciBvd24gc2NyaXB0IG9uIHRoZSB2b2x1bWUgd2lucyAtLS0tLS0tLS0tLS0tLS0t \
    LS0tLS0KaWYgWyAtZiAvZGF0YS9lbnRyeXBvaW50LnNoIF0gJiYgWyAiJHtVU0VfVk9MVU1FX0VOVFJZUE9JTlQ6LXRydWV9IiA9 \
    ICJ0cnVlIiBdOyB0aGVuCiAgICBsb2cgInJ1bm5pbmcgL2RhdGEvZW50cnlwb2ludC5zaCBmcm9tIHRoZSB2b2x1bWUiCiAgICBl \
    eGVjIC9iaW4vc2ggL2RhdGEvZW50cnlwb2ludC5zaCAiJEAiCmZpCgojIC0tLSByYXcgcGFzcy10aHJvdWdoOiBhbnkgYXJncyBn \
    byBzdHJhaWdodCB0byB0aGUgYmluYXJ5IC0tLS0tLS0tLS0tLS0tLS0tLQppZiBbICIkIyIgLWd0IDAgXTsgdGhlbgogICAgY2Fz \
    ZSAiJDEiIGluCiAgICAgICAgc2h8YmFzaHwvYmluL3NofC9iaW4vYmFzaCkgZXhlYyAiJEAiIDs7CiAgICBlc2FjCiAgICBleGVj \
    IC91c3IvbG9jYWwvYmluL3NuaS1zcG9vZmluZyAiJEAiCmZpCgojIC0tLSBwcml2aWxlZ2UgLyBjYXBhYmlsaXR5IHNhbml0eSBj \
    aGVjayAtLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLQppZiBbICIkKGlkIC11KSIgLW5lIDAgXTsgdGhlbgogICAg \
    bG9nICJFUlJPUjogbm90IHJvb3QgaW5zaWRlIHRoZSBjb250YWluZXI7IHNuaS1zcG9vZmluZyBuZWVkcyByb290LiIKICAgIGV4 \
    aXQgMQpmaQpIQVZFX05FVF9BRE1JTj11bmtub3duCmlmIGNvbW1hbmQgLXYgY2Fwc2ggPi9kZXYvbnVsbCAyPiYxOyB0aGVuCiAg \
    ICBDQVBTPSIkKGNhcHNoIC0tcHJpbnQgMj4vZGV2L251bGwgfCBzZWQgLW4gJ3MvXkN1cnJlbnQ6IC8vcCcgfCBoZWFkIC1uMSki \
    CiAgICBsb2cgImNhcGFiaWxpdGllczogJHtDQVBTOi11bmtub3dufSIKICAgIGNhc2UgIiRDQVBTIiBpbgogICAgICAgICpjYXBf \
    bmV0X2FkbWluKnwiPWVwIiopIEhBVkVfTkVUX0FETUlOPXllcyA7OwogICAgICAgICopIEhBVkVfTkVUX0FETUlOPW5vIDs7CiAg \
    ICBlc2FjCiAgICBjYXNlICIkQ0FQUyIgaW4KICAgICAgICAqY2FwX25ldF9yYXcqfCI9ZXAiKikgOzsKICAgICAgICAqKSBsb2cg \
    IldBUk5JTkc6IGNhcF9uZXRfcmF3IG1pc3NpbmcgLT4gbm8gcGFja2V0IGluamVjdGlvbiBpcyBwb3NzaWJsZSBhdCBhbGwuIiA7 \
    OwogICAgZXNhYwpmaQoKIyBUaGUgYWN0aXZlIGluamVjdG9yIG5lZWRzIENBUF9ORVRfQURNSU4gKG5mcXVldWUgKyBpcHRhYmxl \
    cyArIGlwIHJ1bGUpLgojIFRoZSBwYXNzaXZlIG9uZSBvbmx5IG5lZWRzIENBUF9ORVRfUkFXIChBRl9QQUNLRVQgc29ja2V0ICsg \
    bGluay1sYXllciBzZW5kKSwKIyB3aGljaCBpcyBpbiBEb2NrZXIncyBkZWZhdWx0IGNhcGFiaWxpdHkgc2V0IC0+IGF1dG8tc2Vs \
    ZWN0IGl0IHdoZW4gTkVUX0FETUlOCiMgaXMgYWJzZW50IGFuZCB0aGUgdXNlciBoYXMgbm90IGNob3NlbiBhIG1vZGUgZXhwbGlj \
    aXRseS4KaWYgWyAteiAiJHtJTkpFQ1RPUjotfSIgXSAmJiBbICIkSEFWRV9ORVRfQURNSU4iID0gIm5vIiBdOyB0aGVuCiAgICBJ \
    TkpFQ1RPUj1wYXNzaXZlCiAgICBsb2cgImNhcF9uZXRfYWRtaW4gbWlzc2luZyAtPiBhdXRvLXNlbGVjdGluZyBJTkpFQ1RPUj1w \
    YXNzaXZlIChzZXQgSU5KRUNUT1I9YWN0aXZlIHRvIGZvcmNlKS4iCmVsaWYgWyAiJHtJTkpFQ1RPUjotfSIgPSAiYWN0aXZlIiBd \
    ICYmIFsgIiRIQVZFX05FVF9BRE1JTiIgPSAibm8iIF07IHRoZW4KICAgIGxvZyAiV0FSTklORzogSU5KRUNUT1I9YWN0aXZlIGJ1 \
    dCBjYXBfbmV0X2FkbWluIGlzIG1pc3Npbmc7IHRoaXMgd2lsbCBmYWlsLiBUcnkgSU5KRUNUT1I9cGFzc2l2ZS4iCmZpCgojIC0t \
    LSBidWlsZCB0aGUgZmxhZyBsaXN0IC0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLS0tLQpz \
    ZXQgLS0KCmlmIFsgLW4gIiR7TElTVEVOOi19IiBdOyB0aGVuCiAgICBzZXQgLS0gIiRAIiAtbGlzdGVuICIkTElTVEVOIgplbGlm \
    IFsgLW4gIiR7UE9SVDotfSIgXTsgdGhlbgogICAgc2V0IC0tICIkQCIgLWxpc3RlbiAiMC4wLjAuMDoke1BPUlR9IgplbHNlCiAg \
    ICBsb2cgIkVSUk9SOiBzZXQgTElTVEVOIChlLmcuIDAuMC4wLjA6NDA0NDMpIG9yIFBPUlQuIgogICAgZXhpdCAxCmZpCgppZiBb \
    IC16ICIke0NPTk5FQ1Q6LX0iIF07IHRoZW4KICAgIGxvZyAiRVJST1I6IHNldCBDT05ORUNUICh1cHN0cmVhbSBJUDpwb3J0LCBl \
    LmcuIDEwNC4xOS4yMjkuMjE6NDQzKS4iCiAgICBleGl0IDEKZmkKc2V0IC0tICIkQCIgLWNvbm5lY3QgIiRDT05ORUNUIgoKWyAt \
    biAiJHtGQUtFX1NOSTotfSIgXSAgICAgICAmJiBzZXQgLS0gIiRAIiAtZmFrZS1zbmkgIiRGQUtFX1NOSSIKWyAtbiAiJHtVVExT \
    Oi19IiBdICAgICAgICAgICAmJiBzZXQgLS0gIiRAIiAtdXRscyAiJFVUTFMiClsgLW4gIiR7SU5KRUNUT1I6LX0iIF0gICAgICAg \
    JiYgc2V0IC0tICIkQCIgLWluamVjdG9yICIkSU5KRUNUT1IiClsgLW4gIiR7RkFLRV9SRVBFQVQ6LX0iIF0gICAgJiYgc2V0IC0t \
    ICIkQCIgLWZha2UtcmVwZWF0ICIkRkFLRV9SRVBFQVQiClsgLW4gIiR7RkFLRV9ERUxBWTotfSIgXSAgICAgJiYgc2V0IC0tICIk \
    QCIgLWZha2UtZGVsYXkgIiRGQUtFX0RFTEFZIgpbIC1uICIke0FDS19USU1FT1VUOi19IiBdICAgICYmIHNldCAtLSAiJEAiIC1h \
    Y2stdGltZW91dCAiJEFDS19USU1FT1VUIgpbIC1uICIke0ZSQUdNRU5UX0RFTEFZOi19IiBdICYmIHNldCAtLSAiJEAiIC1mcmFn \
    bWVudC1kZWxheSAiJEZSQUdNRU5UX0RFTEFZIgpbIC1uICIke1NOSV9DSFVOSzotfSIgXSAgICAgICYmIHNldCAtLSAiJEAiIC1z \
    bmktY2h1bmsgIiRTTklfQ0hVTksiCgojIEdvIGJvb2wgZmxhZ3MgbmVlZCB0aGUgPXZhbHVlIGZvcm07ICItZW5hYmxlLWZyYWdt \
    ZW50IHRydWUiIHdvdWxkIG5vdCB3b3JrLgpbIC1uICIke0VOQUJMRV9GUkFHTUVOVDotfSIgXSAmJiBzZXQgLS0gIiRAIiAiLWVu \
    YWJsZS1mcmFnbWVudD0ke0VOQUJMRV9GUkFHTUVOVH0iClsgIiR7VEVTVF9NT0RFOi1mYWxzZX0iID0gInRydWUiIF0gJiYgc2V0 \
    IC0tICIkQCIgLXRlc3QKCmxvZyAiZXhlYzogc25pLXNwb29maW5nICQqICR7RVhUUkFfQVJHUzotfSIKIyBFWFRSQV9BUkdTIGlz \
    IGludGVudGlvbmFsbHkgdW5xdW90ZWQgc28gaXQgY2FuIGNhcnJ5IHNldmVyYWwgZmxhZ3MuCiMgc2hlbGxjaGVjayBkaXNhYmxl \
    PVNDMjA4NgpleGVjIC91c3IvbG9jYWwvYmluL3NuaS1zcG9vZmluZyAiJEAiICR7RVhUUkFfQVJHUzotfQo= \
    | base64 -d > /usr/local/bin/entrypoint.sh; \
    chmod +x /usr/local/bin/entrypoint.sh

# No ENV defaults on purpose: an unset variable = the binary's own default.
# Set what you need in your provider's environment panel.
EXPOSE 40443

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
