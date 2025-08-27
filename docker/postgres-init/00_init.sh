#!/usr/bin/env bash
set -euo pipefail

# This script runs only on first container startup (empty data dir) because it
# lives in /docker-entrypoint-initdb.d. It uses environment variables provided
# by docker-compose (env_file: .env) to ensure the requested role/database exist
# and have a password set. It is safe to re-run on a fresh volume.

echo "[init] Ensuring role and database exist (user=$POSTGRES_USER db=$POSTGRES_DB)"

# Ensure password for the primary role
if [[ -n "${POSTGRES_PASSWORD:-}" ]]; then
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    -c "ALTER USER \"$POSTGRES_USER\" WITH PASSWORD '$POSTGRES_PASSWORD';" || true
fi

# Create database if missing and assign owner
DB_EXISTS=$(psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres -tAc \
  "SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB';" || echo "")
if [[ "$DB_EXISTS" != "1" ]]; then
  echo "[init] Creating database $POSTGRES_DB owned by $POSTGRES_USER"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
    -c "CREATE DATABASE \"$POSTGRES_DB\" OWNER \"$POSTGRES_USER\";"
fi

# Basic privileges on the database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
  -c "GRANT ALL PRIVILEGES ON DATABASE \"$POSTGRES_DB\" TO \"$POSTGRES_USER\";" || true

echo "[init] Role and database setup complete."

