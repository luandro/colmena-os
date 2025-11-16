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

read_env() {
  local key="$1" default="$2" value
  if [[ -f .env ]]; then
    value=$(grep -E "^${key}=" .env | head -n1 | cut -d'=' -f2- || true)
    value=${value#\"}
    value=${value%\"}
  fi
  printf "%s" "${value:-$default}"
}

PLAYWRIGHT_SUPERADMIN_EMAIL=${PLAYWRIGHT_SUPERADMIN_EMAIL:-$(read_env SUPERADMIN_EMAIL "admin@example.com")}
PLAYWRIGHT_SUPERADMIN_PASSWORD=${PLAYWRIGHT_SUPERADMIN_PASSWORD:-$(read_env SUPERADMIN_PASSWORD "")}

if [[ -z "$PLAYWRIGHT_SUPERADMIN_PASSWORD" ]]; then
  echo "[playwright-smoke] ERROR: SUPERADMIN_PASSWORD not set in environment or .env" >&2
  echo "Set PLAYWRIGHT_SUPERADMIN_PASSWORD or SUPERADMIN_PASSWORD before running." >&2
  exit 1
fi

export PLAYWRIGHT_SUPERADMIN_EMAIL PLAYWRIGHT_SUPERADMIN_PASSWORD

echo "[playwright-smoke] Installing Playwright dependencies..."
(cd "$PLAYWRIGHT_DIR" && npm ci --no-audit --no-fund --prefer-offline)

echo "[playwright-smoke] Ensuring Playwright browsers are installed..."
(cd "$PLAYWRIGHT_DIR" && npx playwright install --with-deps)

echo "[playwright-smoke] Running Playwright smoke suite..."
(cd "$PLAYWRIGHT_DIR" && npm run test -- "$@")

echo "[playwright-smoke] Smoke test finished successfully."
