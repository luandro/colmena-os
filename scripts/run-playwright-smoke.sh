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

# Wait for container to be healthy
wait_health() {
  local cid=$1 label=$2 timeout=${3:-300} start now status
  start=$(date +%s)
  while true; do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid") || status="unknown"
    case "$status" in
      healthy)
        echo "[playwright-smoke] $label is healthy"
        return 0
        ;;
      unhealthy)
        echo "[playwright-smoke] ERROR: $label reported unhealthy" >&2
        return 1
        ;;
    esac
    now=$(date +%s)
    if (( now - start > timeout )); then
      echo "[playwright-smoke] ERROR: $label health check timed out after ${timeout}s" >&2
      return 1
    fi
    sleep 3
  done
}

# Wait for critical services to be healthy before running tests
echo "[playwright-smoke] Waiting for postgres to be healthy..."
postgres_cid=$(docker compose "${COMPOSE_FILES[@]}" ps -q postgres || true)
if [[ -z "$postgres_cid" ]]; then
  echo "[playwright-smoke] ERROR: postgres container not found" >&2
  docker compose "${COMPOSE_FILES[@]}" ps
  exit 1
fi

if ! wait_health "$postgres_cid" postgres 180; then
  echo "[playwright-smoke] postgres health check failed. Recent logs:" >&2
  docker compose "${COMPOSE_FILES[@]}" logs --no-color --tail=100 postgres || true
  exit 1
fi

echo "[playwright-smoke] Waiting for colmena-app to be healthy..."
app_cid=$(docker compose "${COMPOSE_FILES[@]}" ps -q colmena-app || true)
if [[ -z "$app_cid" ]]; then
  echo "[playwright-smoke] ERROR: colmena-app container not found" >&2
  docker compose "${COMPOSE_FILES[@]}" ps
  exit 1
fi

if ! wait_health "$app_cid" colmena-app 300; then
  echo "[playwright-smoke] colmena-app health check failed. Recent logs:" >&2
  docker compose "${COMPOSE_FILES[@]}" logs --no-color --tail=100 colmena-app || true
  exit 1
fi

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

PLAYWRIGHT_DEPS_MARKER="$PLAYWRIGHT_DIR/.playwright-deps-installed"

if [[ -f "$PLAYWRIGHT_DEPS_MARKER" ]]; then
  echo "[playwright-smoke] Playwright deps already satisfied; refreshing browsers only."
  (cd "$PLAYWRIGHT_DIR" && npx playwright install)
else
  echo "[playwright-smoke] Running initial Playwright install with system deps (one-time)."
  (cd "$PLAYWRIGHT_DIR" && npx playwright install --with-deps)
  touch "$PLAYWRIGHT_DEPS_MARKER"
fi

echo "[playwright-smoke] Running Playwright smoke suite..."
(cd "$PLAYWRIGHT_DIR" && npm run test -- "$@")

echo "[playwright-smoke] Smoke test finished successfully."
