#!/usr/bin/env bash
set -euo pipefail

# Smoke-test docker-compose.local.yml for frontend and backend
# - Builds and starts the stack
# - Waits for health
# - Runs curl checks for frontend, backend, and proxy
# - Writes REPORT.md on failure
#
# Usage:
#   scripts/test-compose-local.sh             # bring up, test, leave running
#   TEARDOWN=1 scripts/test-compose-local.sh  # bring up, test, then down

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Choose compose command
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD=(docker-compose)
else
  echo "Error: docker compose or docker-compose not found" >&2
  exit 1
fi

PROJECT_NAME=${PROJECT_NAME:-colmena}
COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.local.yml}

# Read simple KEY=VALUE from .env without sourcing (values may contain spaces)
read_env() {
  local key="$1" default="$2" value
  if [[ -f .env ]]; then
    value=$(grep -E "^${key}=" .env | head -n1 | cut -d'=' -f2- || true)
    # Trim surrounding double quotes
    value=${value#\"}
    value=${value%\"}
  fi
  printf "%s" "${value:-$default}"
}

# Preflight: optional port cleanup
# - Always show a dry-run list of listeners
# - If CLEAN_PORTS=1, also kill listeners before starting
if [[ -x scripts/cleanup-local-ports.sh ]]; then
  echo "==> Preflight: checking ports..."
  bash scripts/cleanup-local-ports.sh || true
  if [[ "${CLEAN_PORTS:-0}" == "1" ]]; then
    echo "==> Preflight: killing listeners on dev ports (CLEAN_PORTS=1)"
    FORCE=1 bash scripts/cleanup-local-ports.sh || true
  fi
fi

# Defaults match docker-compose.local.yml (host ports)
HTTP_PORT_HOST=$(read_env HTTP_PORT 7180)
BACKEND_PORT_HOST=$(read_env BACKEND_PORT 7100)

echo "==> Building and starting stack (${COMPOSE_FILE})..."
"${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" up -d --build

echo "==> Waiting for postgres health..."
POSTGRES_ID=$("${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" ps -q postgres || true)
if [[ -z "$POSTGRES_ID" ]]; then
  echo "postgres container not found" >&2; exit 1
fi

wait_health() {
  local cid="$1" label="$2" timeout="${3:-240}" start now status
  start=$(date +%s)
  while true; do
    status=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cid") || status="unknown"
    if [[ "$status" == "healthy" ]]; then
      echo "- $label is healthy"; return 0
    elif [[ "$status" == "unhealthy" ]]; then
      echo "- $label is unhealthy" >&2; return 1
    fi
    now=$(date +%s); (( now - start > timeout )) && { echo "- $label health timeout" >&2; return 1; }
    sleep 3
  done
}

wait_health "$POSTGRES_ID" postgres 180 || {
  "${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" logs --no-color --tail=200 postgres || true
  exit 1
}

APP_ID=$("${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" ps -q colmena-app || true)
if [[ -z "$APP_ID" ]]; then
  echo "colmena-app container not found" >&2; exit 1
fi

echo "==> Waiting for colmena-app health..."
if ! wait_health "$APP_ID" colmena-app 300; then
  echo "Recent colmena-app logs:" >&2
  "${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" logs --no-color --tail=200 colmena-app || true
fi

echo "==> Running HTTP checks..."
FAIL=0

code_front=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${HTTP_PORT_HOST}/" || true)
code_proxy=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${HTTP_PORT_HOST}/api/" || true)
code_schema_follow=$(curl -s -o /dev/null -w "%{http_code}" -L "http://localhost:${BACKEND_PORT_HOST}/api/schema" || true)
code_api_root=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${BACKEND_PORT_HOST}/api/" || true)

printf "Frontend /       -> %s\n" "$code_front"
printf "Frontend /api/   -> %s\n" "$code_proxy"
printf "Backend /api/    -> %s\n" "$code_api_root"
printf "Backend /schema  -> %s\n" "$code_schema_follow"

[[ "$code_front" == "200" ]] || FAIL=1
if [[ "$code_proxy" != "401" && "$code_proxy" != "302" ]]; then
  FAIL=1
fi
[[ "$code_api_root" == "401" ]] || FAIL=1
[[ "$code_schema_follow" == "200" ]] || FAIL=1

if (( FAIL )); then
  echo "==> One or more checks FAILED"
  {
    echo "# Test Failure Report - $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo "Environment: ${COMPOSE_FILE} (project ${PROJECT_NAME})"
    echo
    echo "## Results"
    echo "- Frontend /        -> ${code_front} (expect 200)"
    echo "- Frontend /api/    -> ${code_proxy} (expect 401 or 302)"
    echo "- Backend /api/     -> ${code_api_root} (expect 401)"
    echo "- Backend /schema   -> ${code_schema_follow} (expect 200)"
    echo
    echo "## docker compose ps"
    "${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" ps
    echo
    echo "## colmena-app logs (tail)"
    "${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" logs --no-color --tail=200 colmena-app || true
  } >> REPORT.md
  echo "Report appended to REPORT.md"
  exit 1
else
  echo "==> All checks passed"
fi

if [[ "${TEARDOWN:-0}" == "1" ]]; then
  echo "==> Tearing down stack..."
  "${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME" down --remove-orphans
fi

echo "Done."
