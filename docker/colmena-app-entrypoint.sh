#!/bin/sh
# LEGACY SCRIPT: This script is available for manual management commands only.
#
# For production startup, use /opt/app/start-backend.sh instead.
# start-backend.sh provides:
#   - Non-root execution via supervisor's user directive
#   - Better error handling and privilege dropping
#   - Improved ownership management
#
# This script remains mounted for backwards compatibility with manual commands:
#   docker compose exec colmena-app /opt/app/entrypoint.sh migrate
#   docker compose exec colmena-app /opt/app/entrypoint.sh setup_db

set -eu

SETTINGS=colmena.settings.prod
BIN=python
DEFAULT_SOCKET_PATH=${GUNICORN_SOCKET_PATH:-/opt/app/app.sock}
DEFAULT_SOCKET_GROUP=${GUNICORN_SOCKET_GROUP:-colmena}

prepare_socket_path() {
  local socket_path=$1
  local socket_group=$2
  local socket_dir

  socket_dir=$(dirname "$socket_path")
  mkdir -p "$socket_dir"
  chmod 770 "$socket_dir" 2>/dev/null || true
  chgrp "$socket_group" "$socket_dir" 2>/dev/null || true
}

ensure_socket_permissions() {
  local socket_path=$1
  local socket_group=$2

  (
    attempts=0
    while [ $attempts -lt 30 ]; do
      if [ -S "$socket_path" ]; then
        chgrp "$socket_group" "$socket_path" 2>/dev/null || true
        chmod 660 "$socket_path" 2>/dev/null || true
        exit 0
      fi
      sleep 1
      attempts=$((attempts + 1))
    done
    echo "WARNING: Failed to secure socket permissions for $socket_path" >&2
  ) &
}

create_db() {
  set -e

  echo "======== Create DB ========"
  $BIN ./bin/postgres.py CREATE || true
  echo
}

create_superadmin() {
  set -e
  local superadmin_email=$1
  local superadmin_password=$2
  local nc_username=$3
  local nc_password=$4

  echo "======== Create Superadmin ========"
  $BIN manage.py create_superadmin \
    "$superadmin_email" \
    "$superadmin_password" \
    "$nc_username" \
    "$nc_password" || true
  echo
}

migrate() {
  set -e

  echo "======== Starting ecto migration ========"
  $BIN manage.py makemigrations --settings="$SETTINGS"
  $BIN manage.py migrate --settings="$SETTINGS"
  echo
}

setup_db() {
  set -e

  create_db
  migrate
}

setup_seeds() {
  set -e
  local backend_hostname=$1
  local frontend_hostname=$2

  echo "======== Installing seeds ========"
  $BIN manage.py load_sites_with_hostname "$backend_hostname" "$frontend_hostname" --settings="$SETTINGS" || true
  $BIN manage.py loaddata apps/accounts/seeds/02-groups.json --settings="$SETTINGS" || true
  $BIN manage.py setup_group_permissions --settings="$SETTINGS" || true
  $BIN manage.py loaddata apps/accounts/seeds/04-languages.json --settings="$SETTINGS" || true
  $BIN manage.py loaddata apps/accounts/seeds/05-regions.json --settings="$SETTINGS" || true
}

setup_static() {
  set -e

  echo "======== Collecting static files ========"
  $BIN manage.py collectstatic --noinput --settings="$SETTINGS"

  echo "======== Compiling translations ========"
  $BIN manage.py compilemessages -l en -l es -i venv
}

start_prod() {
  set -e

  local worker_timeout=${GUNICORN_WORKER_TIMEOUT:-120}
  local workers=${GUNICORN_WORKERS:-3}

  echo
  echo "Starting prod instance"
  echo
  echo "Using settings=$SETTINGS"
  echo

  setup_static
  setup_db
  setup_seeds "$BACKEND_HOSTNAME" "$FRONTEND_HOSTNAME"
  create_superadmin "$SUPERADMIN_EMAIL" "$SUPERADMIN_PASSWORD" "$NEXTCLOUD_ADMIN_USER" "$NEXTCLOUD_ADMIN_PASSWORD"

  echo "======== Starting colmena ========"
  exec $BIN -m gunicorn --timeout "$worker_timeout" --workers "$workers" colmena.wsgi:application --bind "0.0.0.0:${PORT:-8000}"
}

start_local() {
  set -e

  local worker_timeout=${GUNICORN_WORKER_TIMEOUT:-120}
  local workers=${GUNICORN_WORKERS:-3}
  local socket_path=${GUNICORN_SOCKET_PATH:-$DEFAULT_SOCKET_PATH}
  local socket_group=${GUNICORN_SOCKET_GROUP:-$DEFAULT_SOCKET_GROUP}

  echo
  echo "Starting local instance"
  echo
  echo "Using settings=$SETTINGS"
  echo

  setup_static
  setup_db
  setup_seeds "$BACKEND_HOSTNAME" "$FRONTEND_HOSTNAME"
  create_superadmin "$SUPERADMIN_EMAIL" "$SUPERADMIN_PASSWORD" "$NEXTCLOUD_ADMIN_USER" "$NEXTCLOUD_ADMIN_PASSWORD"

  echo "======== Starting Nginx ========"
  service nginx start
  echo
  echo "======== Starting Local colmena ========"
  prepare_socket_path "$socket_path" "$socket_group"
  ensure_socket_permissions "$socket_path" "$socket_group"
  umask 006
  exec $BIN -m gunicorn --timeout "$worker_timeout" --workers "$workers" --bind "unix:$socket_path" colmena.wsgi:application
}

case "$1" in
  create_db) shift; create_db "$@"; exit;;
  migrate) shift; migrate "$@"; exit;;
  setup_db) shift; setup_db "$@"; exit;;
  setup_seeds) shift; setup_seeds "$@"; exit;;
  start_local) shift; start_local "$@"; exit;;
  start_prod) shift; start_prod "$@"; exit;;
esac

exec "$@"
