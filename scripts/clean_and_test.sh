#!/usr/bin/env bash
set -euo pipefail

# Simple script to rebuild the stack from scratch and run basic checks.
# - Stops and removes containers and named volumes
# - Recreates external network if missing
# - Builds images and starts services
# - Waits for health checks and curls key endpoints

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Prefer new Docker Compose syntax if available
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD=(docker-compose)
else
  echo "Error: docker compose or docker-compose not found in PATH" >&2
  exit 1
fi

# Load env (if present) for ports and credentials
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

NETWORK_NAME="local_colmena_devops"

echo "[1/5] Ensuring external network $NETWORK_NAME exists..."
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create "$NETWORK_NAME"
fi

echo "[2/5] Stopping stack and removing containers + named volumes..."
"${COMPOSE_CMD[@]}" down --volumes --remove-orphans || true

SKIP_APP_BUILD="${SKIP_APP_BUILD:-false}"
if [[ "$SKIP_APP_BUILD" == "true" ]]; then
  SERVICES=(postgres mail nextcloud)
  echo "[3/5] Building images (skip colmena-app)..."
  "${COMPOSE_CMD[@]}" build "${SERVICES[@]}"
else
  SERVICES=()
  echo "[3/5] Building images..."
  "${COMPOSE_CMD[@]}" build
fi

echo "[4/5] Starting stack in background..."
if [[ ${#SERVICES[@]} -gt 0 ]]; then
  "${COMPOSE_CMD[@]}" up -d "${SERVICES[@]}"
else
  "${COMPOSE_CMD[@]}" up -d
fi

wait_for_health() {
  local service="$1" timeout="${2:-180}"
  local id status start_ts now
  start_ts=$(date +%s)
  id=$("${COMPOSE_CMD[@]}" ps -q "$service" || true)
  if [[ -z "$id" ]]; then
    echo "Service $service is not running" >&2
    return 1
  fi
  while true; do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$id")
    case "$status" in
      healthy) echo "- $service is healthy"; return 0 ;;
      starting|none) ;;
      unhealthy) echo "- $service is unhealthy" >&2; return 1 ;;
      *) echo "- $service status: $status" ;;
    esac
    now=$(date +%s)
    if (( now - start_ts > timeout )); then
      echo "- Timed out waiting for $service to be healthy" >&2
      return 1
    fi
    sleep 3
  done
}

echo "[5/5] Waiting for critical services to be healthy..."
wait_for_health postgres 120 || {
  echo "Postgres failed to become healthy. Recent logs:" >&2
  "${COMPOSE_CMD[@]}" logs --no-color --tail=200 postgres || true
  exit 1
}

if [[ "$SKIP_APP_BUILD" != "true" ]]; then
  # colmena-app defines a HEALTHCHECK in the Dockerfile
  wait_for_health colmena-app 240 || {
    echo "colmena-app failed to become healthy. Recent logs:" >&2
    "${COMPOSE_CMD[@]}" logs --no-color --tail=200 colmena-app || true
    exit 1
  }
fi

# Basic HTTP checks
HTTP_PORT="${HTTP_PORT:-80}"
BACKEND_PORT="${BACKEND_PORT:-8000}"

echo "Running HTTP checks..."
if [[ "$SKIP_APP_BUILD" != "true" ]]; then
  curl -fsS --max-time 10 "http://localhost:${HTTP_PORT}/" >/div/null && echo "- Frontend OK on :${HTTP_PORT}" || {
    echo "- Frontend check failed on :${HTTP_PORT}" >&2
    "${COMPOSE_CMD[@]}" logs --no-color --tail=100 colmena-app || true
    exit 1
  }
  curl -fsS --max-time 10 "http://localhost:${BACKEND_PORT}/health/" >/dev/null && echo "- Backend OK on :${BACKEND_PORT}" || {
    echo "- Backend health check failed on :${BACKEND_PORT}" >&2
    "${COMPOSE_CMD[@]}" logs --no-color --tail=100 colmena-app || true
    exit 1
  }
else
  # In skip mode, still try to reach ancillary services
  for url in \
    "http://localhost:8003" \
    "http://localhost:1080"; do
    if curl -fsS --max-time 5 "$url" >/dev/null; then
      echo "- OK: $url"
    else
      echo "- WARN: $url not responding yet (may still be starting)"
    fi
  done
fi

# Optional quick port checks for ancillary services
echo "Optional checks:"
for url in \
  "http://localhost:5050" \
  "http://localhost:1080" \
  "http://localhost:8003"; do
  if curl -fsS --max-time 5 "$url" >/dev/null; then
    echo "- OK: $url"
  else
    echo "- WARN: $url not responding (may still be starting)"
  fi
done

echo "All checks passed. Stack is up."
