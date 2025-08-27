#!/usr/bin/env bash
set -euo pipefail

# Reset only the Postgres data volume used by docker-compose in this project,
# then bring the stack back up so init scripts re-run.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Pick compose command
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose &>/dev/null; then
  COMPOSE_CMD=(docker-compose)
else
  echo "Error: docker compose or docker-compose not found in PATH" >&2
  exit 1
fi

# Compute default project name (dir basename); docker-compose v2 uses this by default
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}" 

echo "[1/4] Bringing stack down..."
"${COMPOSE_CMD[@]}" down || true

echo "[2/4] Locating Postgres data volume for project '$PROJECT_NAME'..."
VOLUME=""

# Prefer exact match by compose labels (requires docker with labels support)
while IFS= read -r vol; do
  if docker volume inspect "$vol" >/dev/null 2>&1; then
    proj=$(docker volume inspect -f '{{ index .Labels "com.docker.compose.project"}}' "$vol" 2>/dev/null || echo "")
    name=$(docker volume inspect -f '{{ index .Labels "com.docker.compose.volume"}}' "$vol" 2>/dev/null || echo "")
    if [[ "$proj" == "$PROJECT_NAME" && "$name" == "pg_data" ]]; then
      VOLUME="$vol"
      break
    fi
  fi
done < <(docker volume ls -q)

# Fallback to common naming convention
if [[ -z "$VOLUME" ]]; then
  candidate1="${PROJECT_NAME}_pg_data"
  if docker volume inspect "$candidate1" >/dev/null 2>&1; then
    VOLUME="$candidate1"
  fi
fi

# Last fallback: first volume ending with _pg_data
if [[ -z "$VOLUME" ]]; then
  for vol in $(docker volume ls -q | grep -E '(^|_)pg_data$' || true); do
    VOLUME="$vol"; break
  done
fi

if [[ -z "$VOLUME" ]]; then
  echo "WARN: Could not find a pg_data volume to remove (maybe not created yet)." >&2
else
  echo "[3/4] Removing Postgres volume: $VOLUME"
  docker volume rm -f "$VOLUME" || true
fi

echo "[4/4] Starting stack..."
"${COMPOSE_CMD[@]}" up -d

echo "Waiting a few seconds for postgres to start..."
sleep 5

if docker ps --format '{{.Names}}' | grep -q '^colmena_postgres$'; then
  echo "--- Postgres logs (last 80 lines) ---"
  docker logs --tail 80 colmena_postgres || true
fi

echo "Done. Postgres should be re-initialized with init scripts."

