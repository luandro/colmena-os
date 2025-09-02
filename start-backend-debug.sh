#!/bin/sh

chown -R nobody:nobody /opt/app/static
chown -R nobody:nobody /opt/app/media

SETTINGS=colmena.settings.prod
BIN=python

echo "Starting ColmenaOS Backend..."
echo "Using settings=$SETTINGS"

# Setup static files (always safe to run)
echo "======== Collecting static files ========"
$BIN ./manage.py collectstatic --noinput --settings=$SETTINGS

echo "======== Compiling translations ========"  
$BIN ./manage.py compilemessages -l en -l es -i venv

# Setup database (handle errors gracefully)
echo "======== Database Setup ========"
$BIN ./bin/postgres.py CREATE
$BIN manage.py makemigrations --settings=$SETTINGS
$BIN manage.py migrate --settings=$SETTINGS

# Setup seeds (handle errors gracefully)
echo "======== Installing seeds ========"
if [ -n "$BACKEND_HOSTNAME" ] && [ -n "$FRONTEND_HOSTNAME" ]; then
    $BIN manage.py load_sites_with_hostname $BACKEND_HOSTNAME $FRONTEND_HOSTNAME --settings=$SETTINGS
fi

$BIN manage.py loaddata apps/accounts/seeds/02-groups.json --settings=$SETTINGS
$BIN manage.py setup_group_permissions --settings=$SETTINGS
$BIN manage.py loaddata apps/accounts/seeds/04-languages.json --settings=$SETTINGS
$BIN manage.py loaddata apps/accounts/seeds/05-regions.json --settings=$SETTINGS

# Create superadmin (handle duplicate gracefully)
echo "======== Create Superadmin ========"
if [ -n "$SUPERADMIN_EMAIL" ] && [ -n "$SUPERADMIN_PASSWORD" ] && [ -n "$NEXTCLOUD_ADMIN_USER" ] && [ -n "$NEXTCLOUD_ADMIN_PASSWORD" ]; then
    $BIN manage.py create_superadmin \
        $SUPERADMIN_EMAIL \
        $SUPERADMIN_PASSWORD \
        $NEXTCLOUD_ADMIN_USER \
        $NEXTCLOUD_ADMIN_PASSWORD
fi

echo "======== Starting Django Server ========"
# Start gunicorn directly
WORKER_TIMEOUT=${GUNICORN_WORKER_TIMEOUT:-300}
WORKERS=${GUNICORN_WORKERS:-2}
PORT=${PORT:-8000}

exec python -m gunicorn --timeout $WORKER_TIMEOUT --workers $WORKERS colmena.wsgi:application --bind 0.0.0.0:$PORT
