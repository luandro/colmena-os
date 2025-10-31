#!/bin/sh

set -eu

SETTINGS=colmena.settings.prod
BIN=python

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
  exec $BIN -m gunicorn --timeout "$worker_timeout" --workers "$workers" --bind unix:/opt/app/app.sock -m 777 colmena.wsgi:application
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
