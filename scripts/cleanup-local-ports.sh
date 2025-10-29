#!/usr/bin/env bash
set -euo pipefail

# Clean up processes and containers occupying local dev ports used by docker-compose.local.yml
# Usage:
#   scripts/cleanup-local-ports.sh           # dry-run (lists holders)
#   FORCE=1 scripts/cleanup-local-ports.sh   # stops compose + kills holders

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Prefer docker compose
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
  COMPOSE_CMD=(docker compose)
else
  COMPOSE_CMD=(docker-compose)
fi

# Read key from .env without sourcing (safe with URLs/spaces)
read_env() {
  local key="$1" default="$2" value
  if [[ -f .env ]]; then
    value=$(grep -E "^${key}=" .env | head -n1 | cut -d'=' -f2- || true)
    value=${value%""}
    value=${value#""}
  fi
  printf "%s" "${value:-$default}"
}

# Default ports as per docker-compose.local.yml (host side)
HTTP_PORT=$(read_env HTTP_PORT 7180)
BACKEND_PORT=$(read_env BACKEND_PORT 7100)
PGADMIN_PORT=7050
NEXTCLOUD_HTTP=7103
NEXTCLOUD_API=7104
MAILCRAB_UI=7080
MAILCRAB_SMTP=7025
POSTGRES_PORT=$(read_env POSTGRES_PORT 7432)

PORTS=(
  "$HTTP_PORT"
  "$BACKEND_PORT"
  "$PGADMIN_PORT"
  "$NEXTCLOUD_HTTP"
  "$NEXTCLOUD_API"
  "$MAILCRAB_UI"
  "$MAILCRAB_SMTP"
  "$POSTGRES_PORT"
)

echo "Stopping local compose stacks (if running)..."
"${COMPOSE_CMD[@]}" -f docker-compose.local.yml --project-name colmena down --remove-orphans 2>/dev/null || true
"${COMPOSE_CMD[@]}" -f docker-compose.yml --project-name colmena-os down --remove-orphans 2>/dev/null || true

has_lsof=0
command -v lsof >/dev/null 2>&1 && has_lsof=1

find_pids_for_port() {
  local port="$1"
  if (( has_lsof )); then
    (lsof -iTCP:"$port" -sTCP:LISTEN -Pn 2>/dev/null || true) | awk 'NR>1{print $2}' | sort -u
  else
    # Fallback to ss
    (ss -ltnp 2>/dev/null || true) | awk -v p=":$port" '$4 ~ p {print $6}' | sed 's/.*pid=\([0-9]\+\),.*/\1/' | sort -u
  fi
}

echo "Scanning for processes holding dev ports..."
declare -A offenders=()
for port in "${PORTS[@]}"; do
  pids=$(find_pids_for_port "$port" | tr '\n' ' ')
  if [[ -n "$pids" ]]; then
    offenders["$port"]="$pids"
  fi
done

# Also check Docker containers publishing these ports
declare -A docker_offenders=()
if command -v docker >/dev/null 2>&1; then
  while IFS= read -r line; do
    cid=$(echo "$line" | awk '{print $1}')
    cname=$(echo "$line" | awk '{print $2}')
    ports=$(echo "$line" | cut -d' ' -f3-)
    for port in "${PORTS[@]}"; do
      if echo "$ports" | grep -qE "0\.0\.0\.0:${port}->|\[::\]:${port}->"; then
        existing="${docker_offenders[$cid]-}"
        docker_offenders["$cid"]="$cname ${existing:+$existing }:$port"
      fi
    done
  done < <(docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' 2>/dev/null || true)
fi

if (( ${#offenders[@]} == 0 )); then
  echo "No local processes are listening on required ports."
fi

echo "Found listeners:"
for port in "${!offenders[@]}"; do
  echo "- :$port -> PIDs: ${offenders[$port]}"
done

if (( ${#docker_offenders[@]} > 0 )); then
  echo "Docker containers publishing required ports:"
  for cid in "${!docker_offenders[@]}"; do
    echo "- $cid ${docker_offenders[$cid]}"
  done
fi

if [[ "${FORCE:-0}" != "1" ]]; then
  echo "Dry-run. Set FORCE=1 to terminate these processes."
  exit 0
fi

echo "FORCE=1 set. Terminating processes..."
for port in "${!offenders[@]}"; do
  for pid in ${offenders[$port]}; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      sleep 0.3
      kill -9 "$pid" 2>/dev/null || true
      echo "Killed PID $pid on port :$port"
    fi
  done
done

# Stop Docker containers publishing conflicting ports
if (( ${#docker_offenders[@]} > 0 )); then
  echo "Stopping Docker containers occupying dev ports..."
  for cid in "${!docker_offenders[@]}"; do
    docker stop "$cid" >/dev/null 2>&1 || true
    echo "Stopped container $cid (${docker_offenders[$cid]})"
  done
fi

echo "All done. Try running: scripts/test-compose-local.sh"
