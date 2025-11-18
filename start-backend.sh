#!/bin/sh

set -eu

SETTINGS=colmena.settings.prod
BIN=python
STATIC_ROOT=${STATIC_ROOT:-/opt/app/static}
MEDIA_ROOT=${MEDIA_ROOT:-/opt/app/media}
LOG_ROOT=${LOG_ROOT:-/opt/app/logs}

# Provide safe defaults for optional env vars so `set -u` does not abort when they
# are intentionally omitted in local testing scenarios.
SUPERADMIN_EMAIL=${SUPERADMIN_EMAIL:-}
SUPERADMIN_PASSWORD=${SUPERADMIN_PASSWORD:-}
SECRET_KEY=${SECRET_KEY:-}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-}
NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD:-}
NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER:-}
BACKEND_HOSTNAME=${BACKEND_HOSTNAME:-}
FRONTEND_HOSTNAME=${FRONTEND_HOSTNAME:-}

# Retry configuration for database operations
MAX_RETRIES=5
INITIAL_DELAY=2  # seconds
MAX_DELAY=30     # seconds

# Ensure runtime directories exist and are owned by colmena before
# we attempt write operations (collectstatic, media sync, log files).
ensure_runtime_dirs() {
    for dir in "$@"; do
        if [ ! -d "$dir" ]; then
            if mkdir -p "$dir"; then
                echo "Created runtime directory $dir"
            else
                cat <<EOF
ERROR: Unable to create required directory $dir
This usually happens when docker volumes are mounted as root-owned paths.
Run /opt/app/start-backend.sh as root once (the script will drop to colmena
after fixing ownership) so that it can provision the runtime directories.
EOF
                exit 1
            fi
        fi

        if [ "$(id -u)" -eq 0 ]; then
            chown colmena:colmena "$dir"
        elif [ ! -w "$dir" ]; then
            cat <<EOF
ERROR: Directory $dir is not writable by user $(id -un)
The named volume was probably initialized with root:root ownership.
Please run /opt/app/start-backend.sh as root at least once so it can chown $dir.
EOF
            exit 1
        fi
    done
}

maybe_chown_recursive() {
    if [ "$(id -u)" -eq 0 ]; then
        chown -R colmena:colmena "$@"
    fi
}

# Function to run a command with retry logic
run_with_retry() {
    local cmd="$1"
    local description="$2"
    local delay=$INITIAL_DELAY

    echo "======== $description ========"

    for attempt in $(seq 1 $MAX_RETRIES); do
        if eval "$cmd"; then
            echo "✓ $description succeeded"
            return 0
        else
            if [ $attempt -lt $MAX_RETRIES ]; then
                echo "⚠ $description failed (attempt $attempt/$MAX_RETRIES)"
                echo "Retrying in $delay seconds..."
                sleep $delay
                delay=$((delay * 2))
                [ $delay -gt $MAX_DELAY ] && delay=$MAX_DELAY
            else
                echo "✗ $description failed after $MAX_RETRIES attempts"
                return 1
            fi
        fi
    done
}

create_superadmin_from_env() {
    DJANGO_SETTINGS_MODULE=$SETTINGS $BIN <<'PY'
import os
import sys

required_vars = [
    "SUPERADMIN_EMAIL",
    "SUPERADMIN_PASSWORD",
    "NEXTCLOUD_ADMIN_USER",
    "NEXTCLOUD_ADMIN_PASSWORD",
]

missing = [var for var in required_vars if not os.environ.get(var)]
if missing:
    raise SystemExit(f"Missing required environment variables: {', '.join(missing)}")

settings_module = os.environ.get("DJANGO_SETTINGS_MODULE", "colmena.settings.prod")
os.environ.setdefault("DJANGO_SETTINGS_MODULE", settings_module)

import django

django.setup()

from django.core.management import call_command
from apps.accounts.models import User

# Check if superadmin already exists - if so, skip creation and exit successfully
if User.objects.filter(email=os.environ["SUPERADMIN_EMAIL"]).exists():
    print("Superadmin already exists, skipping creation")
    sys.exit(0)

try:
    call_command(
        "create_superadmin",
        os.environ["SUPERADMIN_EMAIL"],
        os.environ["SUPERADMIN_PASSWORD"],
        os.environ["NEXTCLOUD_ADMIN_USER"],
        os.environ["NEXTCLOUD_ADMIN_PASSWORD"],
    )
    sys.exit(0)
except Exception as e:
    print(f"Failed to create superadmin: {e}", file=sys.stderr)
    sys.exit(1)
PY
}

wait_for_nextcloud_health() {
    local base_url=${NEXTCLOUD_API_WRAPPER_URL:-http://nextcloud:5001}
    base_url=${base_url%/}
    local health_url=${NEXTCLOUD_HEALTHCHECK_URL:-$base_url/api/healthcheck}

    if ! command -v curl >/dev/null 2>&1; then
        echo "WARNING: curl not available; skipping Nextcloud health verification"
        return 0
    fi

    echo "======== Waiting for Nextcloud API Wrapper ========"
    run_with_retry "curl -fsS --max-time 5 \"$health_url\" >/dev/null" "Nextcloud Healthcheck"
}

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

ensure_runtime_dirs "$STATIC_ROOT" "$MEDIA_ROOT" "$LOG_ROOT"

echo "Starting ColmenaOS Backend..."
echo "Using settings=$SETTINGS"

# Setup static files (always safe to run)
echo "======== Collecting static files ========"
$BIN ./manage.py collectstatic --noinput --settings=$SETTINGS

maybe_chown_recursive "$STATIC_ROOT"

echo "======== Compiling translations ========"
$BIN ./manage.py compilemessages -l en -l es -i venv

# Setup database (handle errors gracefully)
echo "======== Database Setup ========"
if ! run_with_retry "$BIN ./bin/postgres.py CREATE" "Database Creation"; then
    echo "Database operation failed - database may not be ready"
    echo "Continuing anyway (database might already exist)..."
fi

run_with_retry "$BIN ./manage.py migrate --settings=$SETTINGS" "Database Migration"

echo "======== Checking for pending model changes ========"
if ! $BIN ./manage.py makemigrations --settings=$SETTINGS --check --dry-run; then
    echo "WARNING: makemigrations --check detected pending model changes."
    echo "  This is usually harmless in deployed images (pre-built migrations)."
    echo "  Please run 'python manage.py makemigrations' locally and commit the results."
fi

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

maybe_chown_recursive "$MEDIA_ROOT" "$LOG_ROOT"

# Create superadmin (handle Nextcloud dependency with retry)
echo "======== Create Superadmin ========"
if [ -n "$SUPERADMIN_EMAIL" ] && [ -n "$SUPERADMIN_PASSWORD" ] && [ -n "$NEXTCLOUD_ADMIN_USER" ] && [ -n "$NEXTCLOUD_ADMIN_PASSWORD" ]; then
    if ! wait_for_nextcloud_health; then
        echo "Nextcloud API wrapper did not become healthy in time."
        exit 1
    fi

    if run_with_retry create_superadmin_from_env "Superadmin Creation"; then
        echo "✓ Superadmin user created successfully"
    else
        echo "✗ Failed to create superadmin after $MAX_RETRIES attempts"
        echo "  This may be because Nextcloud is not responding"
        echo "  Please check Nextcloud service and try again"
        exit 1
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
