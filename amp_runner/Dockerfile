# Debian (glibc) base: the Amp CLI is a Bun-compiled glibc binary and does not run on Alpine/musl.
FROM ghcr.io/home-assistant/base-debian:trixie

ARG BUILD_VERSION

# Tools the agent uses inside threads: curl + jq for the HA REST API, python3-websockets
# for the HA WebSocket API, git so the Changes pane works in the workspace.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        gzip \
        jq \
        procps \
        python3 \
        python3-websockets \
    && rm -rf /var/lib/apt/lists/*

# Install the Amp CLI into the image. run.sh copies it to /data on first start so the
# runner's self-updates land on persistent storage.
RUN set -eu; \
    case "$(uname -m)" in \
        aarch64|arm64) target=linux-arm64 ;; \
        x86_64) if grep -q avx2 /proc/cpuinfo 2>/dev/null; then target=linux-x64; else target=linux-x64-baseline; fi ;; \
        *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
    esac; \
    version="$(curl -fsSL https://static.ampcode.com/cli/cli-version.txt)"; \
    echo "Installing Amp CLI ${version} (${target})"; \
    mkdir -p /opt/amp/bin; \
    curl -fsSL "https://static.ampcode.com/cli/${version}/amp-${target}.gz" | gzip -dc > /opt/amp/bin/amp; \
    expected="$(curl -fsSL "https://static.ampcode.com/cli/${version}/${target}-amp.sha256")"; \
    actual="$(sha256sum /opt/amp/bin/amp | cut -d' ' -f1)"; \
    [ "$expected" = "$actual" ] || { echo "checksum mismatch: expected $expected got $actual" >&2; exit 1; }; \
    chmod 0755 /opt/amp/bin/amp; \
    echo "$version" > /opt/amp/version

COPY rootfs /
RUN chmod a+x /run.sh /opt/workspace/bin/*

LABEL \
    io.hass.version="${BUILD_VERSION}" \
    io.hass.type="app" \
    io.hass.arch="aarch64|amd64" \
    org.opencontainers.image.source="https://github.com/nclandrei/HAmp"

CMD [ "/run.sh" ]
