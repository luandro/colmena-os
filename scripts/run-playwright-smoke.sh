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

PLAYWRIGHT_DIR="$ROOT_DIR/tests/playwright"
export PLAYWRIGHT_BROWSERS_PATH="${PLAYWRIGHT_BROWSERS_PATH:-$PLAYWRIGHT_DIR/ms-playwright}"

echo "[playwright-smoke] Installing Playwright dependencies..."
(cd "$PLAYWRIGHT_DIR" && npm ci --no-audit --no-fund --prefer-offline)

echo "[playwright-smoke] Ensuring Playwright browsers are installed..."
(cd "$PLAYWRIGHT_DIR" && npx playwright install --with-deps)

echo "[playwright-smoke] Running Playwright smoke suite..."
(cd "$PLAYWRIGHT_DIR" && npm run test -- "$@")

echo "[playwright-smoke] Smoke test finished successfully."
