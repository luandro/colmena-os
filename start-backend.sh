#!/bin/sh

set -eu

SETTINGS=colmena.settings.prod
BIN=python
STATIC_ROOT=${STATIC_ROOT:-/opt/app/static}
MEDIA_ROOT=${MEDIA_ROOT:-/opt/app/media}
LOG_ROOT=${LOG_ROOT:-/opt/app/logs}

# Validate required environment variables
echo "Validating required environment variables..."
MISSING_VARS=0

check_required_var() {
    VAR_NAME=$1
    VAR_VALUE=$(eval echo \$$VAR_NAME)
    if [ -z "$VAR_VALUE" ]; then
        echo "ERROR: Required environment variable $VAR_NAME is not set"
        MISSING_VARS=$((MISSING_VARS + 1))
    elif [ "$VAR_VALUE" = "CHANGE_ME" ]; then
        echo "WARNING: Environment variable $VAR_NAME has placeholder value 'CHANGE_ME'"
        echo "  This is acceptable for testing but should be changed for production"
    fi
}

# Critical environment variables that must be set
check_required_var "SUPERADMIN_EMAIL"
check_required_var "SUPERADMIN_PASSWORD"
check_required_var "SECRET_KEY"
check_required_var "POSTGRES_PASSWORD"
check_required_var "NEXTCLOUD_ADMIN_PASSWORD"

if [ $MISSING_VARS -gt 0 ]; then
    echo ""
    echo "ERROR: $MISSING_VARS required environment variable(s) missing"
    echo "Please set all required variables in your .env file"
    exit 1
fi

echo "✓ All required environment variables are set"
echo ""

if [ "$(id -u)" -eq 0 ]; then
    mkdir -p "$STATIC_ROOT" "$MEDIA_ROOT" "$LOG_ROOT"
    chown colmena:colmena "$STATIC_ROOT" "$MEDIA_ROOT" "$LOG_ROOT"
fi

echo "Starting ColmenaOS Backend..."
echo "Using settings=$SETTINGS"

# Setup static files (always safe to run)
echo "======== Collecting static files ========"
$BIN ./manage.py collectstatic --noinput --settings=$SETTINGS

if [ "$(id -u)" -eq 0 ]; then
    chown -R colmena:colmena "$STATIC_ROOT"
fi

echo "======== Compiling translations ========"  
$BIN ./manage.py compilemessages -l en -l es -i venv

# Setup database (handle errors gracefully)
echo "======== Database Setup ========"
if ! $BIN ./bin/postgres.py CREATE; then
    echo "Database already exists, continuing..."
fi

$BIN manage.py makemigrations --settings=$SETTINGS --check --dry-run
$BIN manage.py migrate --settings=$SETTINGS

# Setup seeds (handle errors gracefully)
echo "======== Installing seeds ========"
if [ -n "$BACKEND_HOSTNAME" ] && [ -n "$FRONTEND_HOSTNAME" ]; then
    if ! $BIN manage.py load_sites_with_hostname $BACKEND_HOSTNAME $FRONTEND_HOSTNAME --settings=$SETTINGS; then
        echo "Sites already configured"
    fi
fi

if ! $BIN manage.py loaddata apps/accounts/seeds/02-groups.json --settings=$SETTINGS; then
    echo "Groups already loaded"
fi
if ! $BIN manage.py setup_group_permissions --settings=$SETTINGS; then
    echo "Permissions already configured"
fi
if ! $BIN manage.py loaddata apps/accounts/seeds/04-languages.json --settings=$SETTINGS; then
    echo "Languages already loaded"
fi
if ! $BIN manage.py loaddata apps/accounts/seeds/05-regions.json --settings=$SETTINGS; then
    echo "Regions already loaded"
fi

if [ "$(id -u)" -eq 0 ]; then
    chown -R colmena:colmena "$MEDIA_ROOT" "$LOG_ROOT"
fi

# Create superadmin (handle duplicate gracefully)
echo "======== Create Superadmin ========"
if [ -n "$SUPERADMIN_EMAIL" ] && [ -n "$SUPERADMIN_PASSWORD" ] && [ -n "$NEXTCLOUD_ADMIN_USER" ] && [ -n "$NEXTCLOUD_ADMIN_PASSWORD" ]; then
    if ! $BIN manage.py create_superadmin \
        $SUPERADMIN_EMAIL \
        $SUPERADMIN_PASSWORD \
        $NEXTCLOUD_ADMIN_USER \
        $NEXTCLOUD_ADMIN_PASSWORD; then
        echo "Superadmin already exists, continuing..."
    fi
fi

echo "======== Starting Django Server ========"
# Start gunicorn directly
WORKER_TIMEOUT=${GUNICORN_WORKER_TIMEOUT:-300}
WORKERS=${GUNICORN_WORKERS:-2}
PORT=${PORT:-8000}

CMD="$BIN -m gunicorn --timeout $WORKER_TIMEOUT --workers $WORKERS colmena.wsgi:application --bind 0.0.0.0:$PORT"

if [ "$(id -u)" -eq 0 ]; then
    exec su colmena -s /bin/sh -c "cd /opt/app && exec $CMD"
else
    exec $CMD
fi