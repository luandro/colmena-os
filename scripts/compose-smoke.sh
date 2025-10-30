#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.yml}
PROJECT_NAME=${PROJECT_NAME:-colmena}
TEARDOWN=${TEARDOWN:-1}
PULL_IMAGES=${PULL_IMAGES:-0}
ENV_EXPORT_PATH=${ENV_EXPORT_PATH:-}

# Ensure internal database port remains the default even if the shell exported the host mapping
export POSTGRES_PORT=5432

log() {
  printf '[compose-smoke] %s\n' "$*"
}

if [[ "$PULL_IMAGES" == "1" ]]; then
  log "Pulling images defined in $COMPOSE_FILE"
  docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" pull
fi

log "Starting stack ($COMPOSE_FILE)"
docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" up -d

wait_health() {
  local cid=$1 label=$2 timeout=${3:-300} start now status
  start=$(date +%s)
  while true; do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid") || status="unknown"
    case "$status" in
      healthy)
        log "$label is healthy"
        return 0
        ;;
      unhealthy)
        log "$label reported unhealthy" >&2
        return 1
        ;;
    esac
    now=$(date +%s)
    if (( now - start > timeout )); then
      log "$label health check timed out" >&2
      return 1
    fi
    sleep 3
  done
}

SMOKE_REPORT=smoke-report.md
rm -f "$SMOKE_REPORT"
touch "$SMOKE_REPORT"

postgres_cid=$(docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" ps -q postgres || true)
app_cid=$(docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" ps -q colmena-app || true)

FAIL=0

if [[ -z "$postgres_cid" || -z "$app_cid" ]]; then
  log "Required containers are missing" >&2
  docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" ps >> "$SMOKE_REPORT"
  FAIL=1
else
  if ! wait_health "$postgres_cid" postgres 180; then
    docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" logs --no-color --tail=200 postgres >> "$SMOKE_REPORT" || true
    FAIL=1
  fi
  if ! wait_health "$app_cid" colmena-app 300; then
    docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" logs --no-color --tail=200 colmena-app >> "$SMOKE_REPORT" || true
    FAIL=1
  fi
fi

get_port() {
  local service=$1 internal_port=$2
  docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" port "$service" "$internal_port" 2>/dev/null | head -n1 | awk -F: '{print $NF}'
}

if (( FAIL == 0 )); then
  http_port=$(get_port colmena-app 80)
  api_port=$(get_port colmena-app 8000)
  if [[ -z "$http_port" || -z "$api_port" ]]; then
    log "Unable to resolve mapped ports" >&2
    FAIL=1
  else
    log "Resolved frontend port -> $http_port, backend port -> $api_port"

    if [[ -n "$ENV_EXPORT_PATH" ]]; then
      {
        echo "PLAYWRIGHT_BASE_URL=http://127.0.0.1:${http_port}"
        echo "PLAYWRIGHT_API_BASE_URL=http://127.0.0.1:${api_port}/api"
        echo "COLMENA_COMPOSE_FRONTEND_PORT=${http_port}"
        echo "COLMENA_COMPOSE_API_PORT=${api_port}"
      } > "$ENV_EXPORT_PATH"
      log "Exported environment variables to $ENV_EXPORT_PATH"
    fi

    frontend_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${http_port}/" || true)
    proxy_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${http_port}/api/" || true)
    backend_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${api_port}/api/" || true)
    schema_code=$(curl -s -o /dev/null -w "%{http_code}" -L "http://localhost:${api_port}/api/schema" || true)

    {
      echo "# Compose Smoke Test"
      echo "- Frontend / -> ${frontend_code}"
      echo "- Frontend /api/ -> ${proxy_code}"
      echo "- Backend /api/ -> ${backend_code}"
      echo "- Backend /api/schema -> ${schema_code}"
    } > "$SMOKE_REPORT"

    if [[ "$frontend_code" != "200" ]]; then FAIL=1; fi
    if [[ "$proxy_code" != "401" && "$proxy_code" != "302" ]]; then FAIL=1; fi
    if [[ "$backend_code" != "401" ]]; then FAIL=1; fi
    if [[ "$schema_code" != "200" ]]; then FAIL=1; fi
  fi
fi

if (( FAIL != 0 )); then
  log "Smoke test failed"
  docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" logs --no-color --tail=200 colmena-app >> "$SMOKE_REPORT" || true
else
  log "Smoke test passed"
fi

if [[ "$TEARDOWN" == "1" ]]; then
  log "Tearing down stack"
  docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" down --remove-orphans
fi

exit $FAIL
