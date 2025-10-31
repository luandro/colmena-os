#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

KEEP_UP="false"
if [[ "${1:-}" == "--keep-up" ]]; then
  KEEP_UP="true"
  shift
fi

echo "[playwright-smoke] Starting ColmenaOS stack via docker compose..."
COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.local.yml)
docker compose "${COMPOSE_FILES[@]}" build colmena-app >/dev/null
docker compose "${COMPOSE_FILES[@]}" up -d

cleanup() {
  local status=$?
  if [[ "$KEEP_UP" == "false" ]]; then
    echo "[playwright-smoke] Stopping docker compose stack..."
    docker compose "${COMPOSE_FILES[@]}" down >/dev/null || true
  else
    echo "[playwright-smoke] Leaving docker compose stack running (--keep-up)."
  fi
  return $status
}
trap cleanup EXIT

echo "[playwright-smoke] Installing Playwright dependencies..."
(cd tests/playwright && npm install --silent)

echo "[playwright-smoke] Running Playwright smoke suite..."
(cd tests/playwright && npm run test -- "$@")

echo "[playwright-smoke] Smoke test finished successfully."
