#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
OPENCLAW_SKIP_ONBOARD=1 ./docker-setup.sh
docker compose up -d --force-recreate --remove-orphans openclaw-gateway
./scripts/docker-verify.sh
