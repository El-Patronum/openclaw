FROM node:22-bookworm

# Install Bun (required for build scripts)
ARG BUN_INSTALL_DIR=/opt/bun
ENV BUN_INSTALL=${BUN_INSTALL_DIR}
ENV PATH="${BUN_INSTALL_DIR}/bin:${PATH}"
RUN curl -fsSL https://bun.sh/install | bash \
  && ln -sf "${BUN_INSTALL_DIR}/bin/bun" /usr/local/bin/bun \
  && bun --version

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

ARG OPENCLAW_INSTALL_CLAUDE=0
ARG OPENCLAW_CLAUDE_NPM_PACKAGE=@anthropic-ai/claude-code
RUN if [ "$OPENCLAW_INSTALL_CLAUDE" = "1" ]; then \
      npm install -g "$OPENCLAW_CLAUDE_NPM_PACKAGE" && \
      claude --version; \
    fi

ARG OPENCLAW_INSTALL_GEMINI=0
ARG OPENCLAW_GEMINI_NPM_PACKAGE=@google/gemini-cli
RUN if [ "$OPENCLAW_INSTALL_GEMINI" = "1" ]; then \
      npm install -g "$OPENCLAW_GEMINI_NPM_PACKAGE" && \
      gemini --version; \
    fi

ARG OPENCLAW_DOCKER_NPM_GLOBAL_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_NPM_GLOBAL_PACKAGES" ]; then \
      npm install -g $OPENCLAW_DOCKER_NPM_GLOBAL_PACKAGES; \
    fi

ARG OPENCLAW_DOCKER_GO_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_GO_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends golang-go && \
      rm -rf /var/lib/apt/lists/* && \
      export GOPATH=/usr/local/go-work && \
      export GOBIN=/usr/local/bin && \
      mkdir -p "$GOPATH" && \
      for pkg in $OPENCLAW_DOCKER_GO_PACKAGES; do \
        GO111MODULE=on go install "$pkg"; \
      done; \
    fi

ARG OPENCLAW_INSTALL_WHISPER=0
RUN if [ "$OPENCLAW_INSTALL_WHISPER" = "1" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3 python3-pip ffmpeg && \
      rm -rf /var/lib/apt/lists/* && \
      pip3 install --no-cache-dir --break-system-packages openai-whisper && \
      whisper --help >/dev/null; \
    fi

ARG OPENCLAW_INSTALL_UV=0
RUN if [ "$OPENCLAW_INSTALL_UV" = "1" ]; then \
      curl -LsSf https://astral.sh/uv/install.sh | sh && \
      install -m 0755 /root/.local/bin/uv /usr/local/bin/uv && \
      install -m 0755 /root/.local/bin/uvx /usr/local/bin/uvx && \
      uv --version >/dev/null; \
    fi

ARG OPENCLAW_INSTALL_BREW=0
ARG BREW_INSTALL_DIR=/home/linuxbrew/.linuxbrew
ARG OPENCLAW_BREW_TAPS=""
ARG OPENCLAW_BREW_FORMULAS=""
ENV HOMEBREW_PREFIX=${BREW_INSTALL_DIR}
ENV HOMEBREW_CELLAR=${BREW_INSTALL_DIR}/Cellar
ENV HOMEBREW_REPOSITORY=${BREW_INSTALL_DIR}/Homebrew
ENV PATH="${BREW_INSTALL_DIR}/bin:${BREW_INSTALL_DIR}/sbin:${PATH}"
RUN if [ "$OPENCLAW_INSTALL_BREW" = "1" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git \
        file \
        procps \
        build-essential && \
      rm -rf /var/lib/apt/lists/* && \
      if ! id -u linuxbrew >/dev/null 2>&1; then useradd -m -s /bin/bash linuxbrew; fi && \
      mkdir -p "$BREW_INSTALL_DIR" && \
      chown -R linuxbrew:linuxbrew "$(dirname "$BREW_INSTALL_DIR")" && \
      su - linuxbrew -c "NONINTERACTIVE=1 CI=1 /bin/bash -c '$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)'" && \
      if [ ! -x "$BREW_INSTALL_DIR/bin/brew" ]; then echo \"brew install failed\" >&2; exit 1; fi && \
      mkdir -p "$BREW_INSTALL_DIR/Library" && \
      ln -sfn "$BREW_INSTALL_DIR/Homebrew/Library/Homebrew" "$BREW_INSTALL_DIR/Library/Homebrew" && \
      ln -sf "$BREW_INSTALL_DIR/bin/brew" /usr/local/bin/brew && \
      if [ -n "$OPENCLAW_BREW_TAPS" ]; then \
        for tap in $OPENCLAW_BREW_TAPS; do \
          su - linuxbrew -c "$BREW_INSTALL_DIR/bin/brew tap $tap"; \
        done; \
      fi && \
      if [ -n "$OPENCLAW_BREW_FORMULAS" ]; then \
        for formula in $OPENCLAW_BREW_FORMULAS; do \
          su - linuxbrew -c "$BREW_INSTALL_DIR/bin/brew install $formula"; \
        done; \
      fi && \
      for tool in summarize obsidian-cli; do \
        if [ -x "$BREW_INSTALL_DIR/bin/$tool" ]; then \
          ln -sf "$BREW_INSTALL_DIR/bin/$tool" "/usr/local/bin/$tool"; \
        fi; \
      done && \
      brew --version; \
    fi

ARG OPENCLAW_INSTALL_GOG=0
ARG OPENCLAW_GOG_DOWNLOAD_URL=""
RUN if [ "$OPENCLAW_INSTALL_GOG" = "1" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates tar && \
      rm -rf /var/lib/apt/lists/* && \
      url="$OPENCLAW_GOG_DOWNLOAD_URL"; \
      if [ -x "$BREW_INSTALL_DIR/bin/brew" ]; then \
        su - linuxbrew -c "$BREW_INSTALL_DIR/bin/brew install gogcli || $BREW_INSTALL_DIR/bin/brew install gog || true"; \
        if [ -x "$BREW_INSTALL_DIR/bin/gog" ]; then \
          ln -sf "$BREW_INSTALL_DIR/bin/gog" /usr/local/bin/gog; \
          gog --version; \
          exit 0; \
        fi; \
      fi; \
      if [ -z "$url" ]; then \
        arch="$(uname -m)"; \
        case "$arch" in \
          x86_64|amd64) gog_arch="x86_64" ;; \
          aarch64|arm64) gog_arch="arm64" ;; \
          *) echo "unsupported architecture for gog: $arch" >&2; exit 1 ;; \
        esac; \
        release_json="$(curl -fsSL https://api.github.com/repos/steipete/gog/releases/latest || true)"; \
        release_assets="$(printf '%s' "$release_json" | grep '"browser_download_url"' | sed -E 's/.*"browser_download_url":[[:space:]]*"([^"]+)".*/\1/')"; \
        if [ "$gog_arch" = "arm64" ]; then \
          url="$(printf '%s' "$release_assets" | grep -Ei 'linux' | grep -Ei '(aarch64|arm64)' | grep -Ei '\\.tar\\.gz$' | head -n1 || true)"; \
        else \
          url="$(printf '%s' "$release_assets" | grep -Ei 'linux' | grep -Ei '(x86_64|amd64)' | grep -Ei '\\.tar\\.gz$' | head -n1 || true)"; \
        fi; \
      fi; \
      if [ -z "$url" ]; then echo "could not install gog automatically; set OPENCLAW_GOG_DOWNLOAD_URL or ensure brew formula exists" >&2; exit 1; fi; \
      curl -fL "$url" | tar -xz -C /usr/local/bin gog; \
      chmod +x /usr/local/bin/gog && \
      gog --version; \
    fi

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile
ARG OPENCLAW_PREBUILD_NODE_LLAMA=0
RUN if [ "$OPENCLAW_PREBUILD_NODE_LLAMA" = "1" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends cmake && \
      rm -rf /var/lib/apt/lists/* && \
      node --input-type=module -e "const { getLlama } = await import('node-llama-cpp'); await getLlama(); console.log('node-llama-cpp ready');"; \
    fi

COPY . .
RUN pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Allow non-root user to write temp files during runtime/tests.
RUN chown -R node:node /app

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
USER node

# Start gateway server with default config.
# Binds to loopback (127.0.0.1) by default for security.
#
# For container platforms requiring external health checks:
#   1. Set OPENCLAW_GATEWAY_TOKEN or OPENCLAW_GATEWAY_PASSWORD env var
#   2. Override CMD: ["node","openclaw.mjs","gateway","--allow-unconfigured","--bind","lan"]
CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
