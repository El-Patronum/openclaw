#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
EXTRA_COMPOSE_FILE="$ROOT_DIR/docker-compose.extra.yml"
ENV_FILE="$ROOT_DIR/.env"

load_env_defaults() {
  local file="$1"
  local line key value
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    if [[ -z "${!key+x}" ]]; then
      export "$key=$value"
    fi
  done <"$file"
}

load_env_defaults "$ENV_FILE"

IMAGE_NAME="${OPENCLAW_IMAGE:-openclaw:local}"
EXTRA_MOUNTS="${OPENCLAW_EXTRA_MOUNTS:-}"
HOME_VOLUME_NAME="${OPENCLAW_HOME_VOLUME:-}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing dependency: $1" >&2
    exit 1
  fi
}

require_cmd docker
if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose not available (try: docker compose version)" >&2
  exit 1
fi

OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-$HOME/.openclaw/workspace}"

mkdir -p "$OPENCLAW_CONFIG_DIR"
mkdir -p "$OPENCLAW_WORKSPACE_DIR"

export OPENCLAW_CONFIG_DIR
export OPENCLAW_WORKSPACE_DIR
export OPENCLAW_GATEWAY_HOST="${OPENCLAW_GATEWAY_HOST:-127.0.0.1}"
export OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
export OPENCLAW_BRIDGE_PORT="${OPENCLAW_BRIDGE_PORT:-18790}"
export OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-lan}"
export OPENCLAW_IMAGE="$IMAGE_NAME"
export OPENCLAW_DOCKER_APT_PACKAGES="${OPENCLAW_DOCKER_APT_PACKAGES:-}"
export OPENCLAW_PREBUILD_NODE_LLAMA="${OPENCLAW_PREBUILD_NODE_LLAMA:-0}"
export OPENCLAW_INSTALL_CLAUDE="${OPENCLAW_INSTALL_CLAUDE:-0}"
export OPENCLAW_CLAUDE_NPM_PACKAGE="${OPENCLAW_CLAUDE_NPM_PACKAGE:-@anthropic-ai/claude-code}"
export OPENCLAW_INSTALL_GEMINI="${OPENCLAW_INSTALL_GEMINI:-0}"
export OPENCLAW_GEMINI_NPM_PACKAGE="${OPENCLAW_GEMINI_NPM_PACKAGE:-@google/gemini-cli}"
export OPENCLAW_DOCKER_NPM_GLOBAL_PACKAGES="${OPENCLAW_DOCKER_NPM_GLOBAL_PACKAGES:-}"
export OPENCLAW_DOCKER_GO_PACKAGES="${OPENCLAW_DOCKER_GO_PACKAGES:-}"
export OPENCLAW_INSTALL_WHISPER="${OPENCLAW_INSTALL_WHISPER:-0}"
export OPENCLAW_INSTALL_UV="${OPENCLAW_INSTALL_UV:-0}"
export OPENCLAW_INSTALL_GOG="${OPENCLAW_INSTALL_GOG:-0}"
export OPENCLAW_GOG_DOWNLOAD_URL="${OPENCLAW_GOG_DOWNLOAD_URL:-}"
export OPENCLAW_INSTALL_BREW="${OPENCLAW_INSTALL_BREW:-0}"
export OPENCLAW_BREW_TAPS="${OPENCLAW_BREW_TAPS:-}"
export OPENCLAW_BREW_FORMULAS="${OPENCLAW_BREW_FORMULAS:-}"
export OPENCLAW_SKIP_ONBOARD="${OPENCLAW_SKIP_ONBOARD:-0}"
export OPENCLAW_REQUIRED_BINS="${OPENCLAW_REQUIRED_BINS:-}"
export OPENCLAW_REQUIRED_SKILLS="${OPENCLAW_REQUIRED_SKILLS:-}"
export OPENCLAW_EXTRA_MOUNTS="$EXTRA_MOUNTS"
export OPENCLAW_HOME_VOLUME="$HOME_VOLUME_NAME"

if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"
  else
    OPENCLAW_GATEWAY_TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"
  fi
fi
export OPENCLAW_GATEWAY_TOKEN

COMPOSE_FILES=("$COMPOSE_FILE")
COMPOSE_ARGS=()

write_extra_compose() {
  local home_volume="$1"
  shift
  local mount

  cat >"$EXTRA_COMPOSE_FILE" <<'YAML'
services:
  openclaw-gateway:
    volumes:
YAML

  if [[ -n "$home_volume" ]]; then
    printf '      - %s:/home/node\n' "$home_volume" >>"$EXTRA_COMPOSE_FILE"
    printf '      - %s:/home/node/.openclaw\n' "$OPENCLAW_CONFIG_DIR" >>"$EXTRA_COMPOSE_FILE"
    printf '      - %s:/home/node/.openclaw/workspace\n' "$OPENCLAW_WORKSPACE_DIR" >>"$EXTRA_COMPOSE_FILE"
  fi

  for mount in "$@"; do
    printf '      - %s\n' "$mount" >>"$EXTRA_COMPOSE_FILE"
  done

  cat >>"$EXTRA_COMPOSE_FILE" <<'YAML'
  openclaw-cli:
    volumes:
YAML

  if [[ -n "$home_volume" ]]; then
    printf '      - %s:/home/node\n' "$home_volume" >>"$EXTRA_COMPOSE_FILE"
    printf '      - %s:/home/node/.openclaw\n' "$OPENCLAW_CONFIG_DIR" >>"$EXTRA_COMPOSE_FILE"
    printf '      - %s:/home/node/.openclaw/workspace\n' "$OPENCLAW_WORKSPACE_DIR" >>"$EXTRA_COMPOSE_FILE"
  fi

  for mount in "$@"; do
    printf '      - %s\n' "$mount" >>"$EXTRA_COMPOSE_FILE"
  done

  if [[ -n "$home_volume" && "$home_volume" != *"/"* ]]; then
    cat >>"$EXTRA_COMPOSE_FILE" <<YAML
volumes:
  ${home_volume}:
YAML
  fi
}

VALID_MOUNTS=()
if [[ -n "$EXTRA_MOUNTS" ]]; then
  IFS=',' read -r -a mounts <<<"$EXTRA_MOUNTS"
  for mount in "${mounts[@]}"; do
    mount="${mount#"${mount%%[![:space:]]*}"}"
    mount="${mount%"${mount##*[![:space:]]}"}"
    if [[ -n "$mount" ]]; then
      VALID_MOUNTS+=("$mount")
    fi
  done
fi

if [[ -n "$HOME_VOLUME_NAME" || ${#VALID_MOUNTS[@]} -gt 0 ]]; then
  # Bash 3.2 + nounset treats "${array[@]}" on an empty array as unbound.
  if [[ ${#VALID_MOUNTS[@]} -gt 0 ]]; then
    write_extra_compose "$HOME_VOLUME_NAME" "${VALID_MOUNTS[@]}"
  else
    write_extra_compose "$HOME_VOLUME_NAME"
  fi
  COMPOSE_FILES+=("$EXTRA_COMPOSE_FILE")
fi
for compose_file in "${COMPOSE_FILES[@]}"; do
  COMPOSE_ARGS+=("-f" "$compose_file")
done
COMPOSE_HINT="docker compose"
for compose_file in "${COMPOSE_FILES[@]}"; do
  COMPOSE_HINT+=" -f ${compose_file}"
done

upsert_env() {
  local file="$1"
  shift
  local -a keys=("$@")
  local tmp
  tmp="$(mktemp)"
  # Use a delimited string instead of an associative array so the script
  # works with Bash 3.2 (macOS default) which lacks `declare -A`.
  local seen=" "

  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      local key="${line%%=*}"
      local replaced=false
      for k in "${keys[@]}"; do
        if [[ "$key" == "$k" ]]; then
          printf '%s=%s\n' "$k" "${!k-}" >>"$tmp"
          seen="$seen$k "
          replaced=true
          break
        fi
      done
      if [[ "$replaced" == false ]]; then
        printf '%s\n' "$line" >>"$tmp"
      fi
    done <"$file"
  fi

  for k in "${keys[@]}"; do
    if [[ "$seen" != *" $k "* ]]; then
      printf '%s=%s\n' "$k" "${!k-}" >>"$tmp"
    fi
  done

  mv "$tmp" "$file"
}

upsert_env "$ENV_FILE" \
  OPENCLAW_CONFIG_DIR \
  OPENCLAW_WORKSPACE_DIR \
  OPENCLAW_GATEWAY_HOST \
  OPENCLAW_GATEWAY_PORT \
  OPENCLAW_BRIDGE_PORT \
  OPENCLAW_GATEWAY_BIND \
  OPENCLAW_GATEWAY_TOKEN \
  OPENCLAW_IMAGE \
  OPENCLAW_EXTRA_MOUNTS \
  OPENCLAW_HOME_VOLUME \
  OPENCLAW_DOCKER_APT_PACKAGES \
  OPENCLAW_PREBUILD_NODE_LLAMA \
  OPENCLAW_INSTALL_CLAUDE \
  OPENCLAW_CLAUDE_NPM_PACKAGE \
  OPENCLAW_INSTALL_GEMINI \
  OPENCLAW_GEMINI_NPM_PACKAGE \
  OPENCLAW_DOCKER_NPM_GLOBAL_PACKAGES \
  OPENCLAW_DOCKER_GO_PACKAGES \
  OPENCLAW_INSTALL_WHISPER \
  OPENCLAW_INSTALL_UV \
  OPENCLAW_INSTALL_GOG \
  OPENCLAW_GOG_DOWNLOAD_URL \
  OPENCLAW_INSTALL_BREW \
  OPENCLAW_BREW_TAPS \
  OPENCLAW_BREW_FORMULAS \
  OPENCLAW_SKIP_ONBOARD \
  OPENCLAW_REQUIRED_BINS \
  OPENCLAW_REQUIRED_SKILLS

echo "==> Building Docker image: $IMAGE_NAME"
docker build \
  --build-arg "OPENCLAW_DOCKER_APT_PACKAGES=${OPENCLAW_DOCKER_APT_PACKAGES}" \
  --build-arg "OPENCLAW_PREBUILD_NODE_LLAMA=${OPENCLAW_PREBUILD_NODE_LLAMA}" \
  --build-arg "OPENCLAW_INSTALL_CLAUDE=${OPENCLAW_INSTALL_CLAUDE}" \
  --build-arg "OPENCLAW_CLAUDE_NPM_PACKAGE=${OPENCLAW_CLAUDE_NPM_PACKAGE}" \
  --build-arg "OPENCLAW_INSTALL_GEMINI=${OPENCLAW_INSTALL_GEMINI}" \
  --build-arg "OPENCLAW_GEMINI_NPM_PACKAGE=${OPENCLAW_GEMINI_NPM_PACKAGE}" \
  --build-arg "OPENCLAW_DOCKER_NPM_GLOBAL_PACKAGES=${OPENCLAW_DOCKER_NPM_GLOBAL_PACKAGES}" \
  --build-arg "OPENCLAW_DOCKER_GO_PACKAGES=${OPENCLAW_DOCKER_GO_PACKAGES}" \
  --build-arg "OPENCLAW_INSTALL_WHISPER=${OPENCLAW_INSTALL_WHISPER}" \
  --build-arg "OPENCLAW_INSTALL_UV=${OPENCLAW_INSTALL_UV}" \
  --build-arg "OPENCLAW_INSTALL_GOG=${OPENCLAW_INSTALL_GOG}" \
  --build-arg "OPENCLAW_GOG_DOWNLOAD_URL=${OPENCLAW_GOG_DOWNLOAD_URL}" \
  --build-arg "OPENCLAW_INSTALL_BREW=${OPENCLAW_INSTALL_BREW}" \
  --build-arg "OPENCLAW_BREW_TAPS=${OPENCLAW_BREW_TAPS}" \
  --build-arg "OPENCLAW_BREW_FORMULAS=${OPENCLAW_BREW_FORMULAS}" \
  -t "$IMAGE_NAME" \
  -f "$ROOT_DIR/Dockerfile" \
  "$ROOT_DIR"

if [[ "$OPENCLAW_SKIP_ONBOARD" != "1" ]]; then
  echo ""
  echo "==> Onboarding (interactive)"
  echo "When prompted:"
  echo "  - Gateway bind: lan"
  echo "  - Gateway auth: token"
  echo "  - Gateway token: $OPENCLAW_GATEWAY_TOKEN"
  echo "  - Tailscale exposure: Off"
  echo "  - Install Gateway daemon: No"
  echo ""
  docker compose "${COMPOSE_ARGS[@]}" run --rm openclaw-cli onboard --no-install-daemon
fi

echo ""
echo "==> Provider setup (optional)"
echo "WhatsApp (QR):"
echo "  ${COMPOSE_HINT} run --rm openclaw-cli channels login"
echo "Telegram (bot token):"
echo "  ${COMPOSE_HINT} run --rm openclaw-cli channels add --channel telegram --token <token>"
echo "Discord (bot token):"
echo "  ${COMPOSE_HINT} run --rm openclaw-cli channels add --channel discord --token <token>"
echo "Docs: https://docs.openclaw.ai/channels"

echo ""
echo "==> Starting gateway"
docker compose "${COMPOSE_ARGS[@]}" up -d --remove-orphans openclaw-gateway

echo ""
echo "Gateway running with host port mapping."
echo "Access from tailnet devices via the host's tailnet IP."
echo "Config: $OPENCLAW_CONFIG_DIR"
echo "Workspace: $OPENCLAW_WORKSPACE_DIR"
echo "Token: $OPENCLAW_GATEWAY_TOKEN"
echo ""
echo "Commands:"
echo "  ${COMPOSE_HINT} logs -f openclaw-gateway"
echo "  ${COMPOSE_HINT} exec openclaw-gateway node dist/index.js health --token \"$OPENCLAW_GATEWAY_TOKEN\""
