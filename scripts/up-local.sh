#!/usr/bin/env bash
set -euo pipefail

# Bring up the local compose stack, auto-assigning free host ports if defaults are busy.
# Respects .env defaults but falls back to the next available port within a small range.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE_FILE=${COMPOSE_FILE:-docker-compose.local.yml}
# PROJECT_NAME will be decided after selecting ports to avoid collisions with prior runs
PROJECT_NAME_ENV=${PROJECT_NAME:-}

read_env() {
  local key="$1" default="$2" value
  if [[ -f .env ]]; then
    value=$(grep -E "^${key}=" .env | head -n1 | cut -d'=' -f2- || true)
    # Strip leading and trailing double quotes if present
    value=${value#\"}
    value=${value%\"}
    # Also strip single quotes if the value is wrapped in them
    value=${value#\'}
    value=${value%\'}
  fi
  printf "%s" "${value:-$default}"
}

is_port_free() {
  # Use Python to attempt bind on 127.0.0.1:PORT to avoid permission issues from ss/lsof.
  python - "$1" << 'PY'
import socket, sys
port=int(sys.argv[1])
s=socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(("127.0.0.1", port))
    s.close()
    sys.exit(0)
except OSError:
    sys.exit(1)
PY
}

pick_free_port() {
  local want="$1" maxshift="50" p="$1" i
  for ((i=0;i<=maxshift;i++)); do
    p=$((want+i))
    if is_port_free "$p"; then
      echo "$p"; return 0
    fi
  done
  echo "$want"; return 1
}

HTTP_PORT_DEF=$(read_env HTTP_PORT 7180)
BACKEND_PORT_DEF=$(read_env BACKEND_PORT 7100)
POSTGRES_HOST_PORT_DEF=$(read_env POSTGRES_HOST_PORT 7432)
PGADMIN_PORT_DEF=7050
NEXTCLOUD_HTTP_DEF=7103
NEXTCLOUD_API_DEF=7104
MAILCRAB_UI_DEF=7080
MAILCRAB_SMTP_DEF=7025

echo "Checking ports and selecting free ones if needed..."
HTTP_PORT=$(pick_free_port "$HTTP_PORT_DEF")
BACKEND_PORT=$(pick_free_port "$BACKEND_PORT_DEF")
POSTGRES_HOST_PORT=$(pick_free_port "$POSTGRES_HOST_PORT_DEF")
PGADMIN_PORT=$(pick_free_port "$PGADMIN_PORT_DEF")
NEXTCLOUD_HTTP=$(pick_free_port "$NEXTCLOUD_HTTP_DEF")
NEXTCLOUD_API=$(pick_free_port "$NEXTCLOUD_API_DEF")
MAILCRAB_UI=$(pick_free_port "$MAILCRAB_UI_DEF")
MAILCRAB_SMTP=$(pick_free_port "$MAILCRAB_SMTP_DEF")

POSTGRES_PORT=${POSTGRES_PORT:-5432}

printf "Using ports -> HTTP:%s BACKEND:%s POSTGRES:%s PGADMIN:%s NEXTCLOUD:%s/%s MAIL:%s/%s\n" \
  "$HTTP_PORT" "$BACKEND_PORT" "$POSTGRES_HOST_PORT" "$PGADMIN_PORT" "$NEXTCLOUD_HTTP" "$NEXTCLOUD_API" "$MAILCRAB_UI" "$MAILCRAB_SMTP"

NEXTCLOUD_HTTP_PORT="$NEXTCLOUD_HTTP"
NEXTCLOUD_API_HOST_PORT="$NEXTCLOUD_API"
MAILCRAB_UI_PORT="$MAILCRAB_UI"
MAILCRAB_SMTP_PORT="$MAILCRAB_SMTP"

export HTTP_PORT BACKEND_PORT POSTGRES_HOST_PORT POSTGRES_PORT \
  PGADMIN_PORT NEXTCLOUD_HTTP_PORT NEXTCLOUD_API_HOST_PORT MAILCRAB_UI_PORT MAILCRAB_SMTP_PORT

echo "Bringing up stack with selected ports..."
PROJECT_NAME_USE=${PROJECT_NAME_ENV:-colmena-${HTTP_PORT}}
docker compose -f "$COMPOSE_FILE" --project-name "$PROJECT_NAME_USE" up -d --build

echo "Done. You can now run: scripts/test-compose-local.sh"
