#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

read_env() {
  local key="$1"
  local default="${2:-}"
  local value
  value="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$default"
  fi
}

required_bins_csv="$(read_env OPENCLAW_REQUIRED_BINS "claude,gog,gemini,mcporter,uv,whisper,jq,rg,gh,summarize,obsidian-cli")"
required_skills_csv="$(read_env OPENCLAW_REQUIRED_SKILLS "coding-agent,gog,gemini,github,mcporter,obsidian,openai-whisper,session-logs,summarize")"

IFS=',' read -r -a required_bins <<<"$required_bins_csv"
IFS=',' read -r -a required_skills <<<"$required_skills_csv"

echo "==> Verifying required binaries in openclaw-gateway"
missing_bins=()
for bin in "${required_bins[@]}"; do
  trimmed="${bin#"${bin%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [[ -z "$trimmed" ]] && continue
  if ! docker compose exec -T openclaw-gateway sh -lc "command -v '$trimmed' >/dev/null"; then
    missing_bins+=("$trimmed")
  fi
done

if [[ ${#missing_bins[@]} -gt 0 ]]; then
  echo "Missing required binaries: ${missing_bins[*]}" >&2
  exit 1
fi

echo "==> Verifying required skills are eligible"
skills_json="$(docker compose exec -T openclaw-gateway node dist/index.js skills check --json)"
export SKILLS_JSON="$skills_json"
export REQUIRED_SKILLS_CSV="$required_skills_csv"
python3 - <<'PY'
import json
import os
import sys

data = json.loads(os.environ["SKILLS_JSON"])
required = [s.strip() for s in os.environ["REQUIRED_SKILLS_CSV"].split(",") if s.strip()]
eligible = set(data.get("eligible", []))
missing = [s for s in required if s not in eligible]
if missing:
    print("Missing required eligible skills:", ", ".join(missing), file=sys.stderr)
    sys.exit(1)
print("Required skills are eligible.")
PY

echo "==> Docker verification passed"
