#!/usr/bin/env bash

###############################################################################
# ColmenaOS Run-in-Environment Script
#
# This script allows you to run arbitrary code (backend/frontend/infra)
# against the actual ColmenaOS infrastructure (docker-compose stack).
#
# Usage:
#   ./scripts/run-in-environment.sh [command] [options]
#
# Examples:
#   # Start the stack and run a Django management command
#   ./scripts/run-in-environment.sh backend manage.py showmigrations
#
#   # Run a Python script against the live database
#   ./scripts/run-in-environment.sh backend scripts/test_db.py
#
#   # Show frontend development instructions (must run on host)
#   ./scripts/run-in-environment.sh frontend dev
#
#   # Execute backend tests
#   ./scripts/run-in-environment.sh test backend
#
#   # Run infrastructure tests
#   ./scripts/run-in-environment.sh test infra
#
#   # Drop into a shell in the running app container
#   ./scripts/run-in-environment.sh shell
#
#   # Execute arbitrary command in the app container
#   ./scripts/run-in-environment.sh exec "python -c 'print(\"Hello from container\")'"
#
#   # Bring up the stack and keep it running
#   ./scripts/run-in-environment.sh up --keep-up
#
#   # Run a complete smoke test
#   ./scripts/run-in-environment.sh test smoke
###############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
COMPOSE_FILES=(-f docker-compose.yml -f docker-compose.local.yml)
DEFAULT_HTTP_PORT=7180
DEFAULT_BACKEND_PORT=7100
DEFAULT_POSTGRES_PORT=7432
STACK_STARTED_BY_SCRIPT=false
KEEP_UP=${KEEP_UP:-false}

###############################################################################
# Helper Functions
###############################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if a port is in use (with fallback for systems without lsof)
port_is_in_use() {
    local port=$1

    # Try lsof first if available
    if command -v lsof >/dev/null 2>&1; then
        lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1
        return $?
    fi

    # Fallback to ss (available on most Linux systems)
    if command -v ss >/dev/null 2>&1; then
        ss -ltnp 2>/dev/null | grep -qE ":$port\s"
        return $?
    fi

    # If neither tool is available, assume port is free (best effort)
    log_warning "Neither lsof nor ss available; skipping port availability check"
    return 1
}

# Check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker first."
        exit 1
    fi
}

# Check if required ports are available
check_ports() {
    local http_port=${HTTP_PORT:-$DEFAULT_HTTP_PORT}
    local backend_port=${BACKEND_PORT:-$DEFAULT_BACKEND_PORT}
    local postgres_port=${POSTGRES_HOST_PORT:-$DEFAULT_POSTGRES_PORT}
    local conflict_found=false

    log_info "Checking if ports are available..."

    if port_is_in_use "$http_port"; then
        log_warning "HTTP port $http_port is already in use"
        conflict_found=true
    fi

    if port_is_in_use "$backend_port"; then
        log_warning "Backend port $backend_port is already in use"
        conflict_found=true
    fi

    if port_is_in_use "$postgres_port"; then
        log_warning "Postgres port $postgres_port is already in use"
        conflict_found=true
    fi

    if [[ "$conflict_found" == true ]]; then
        read -p "  Try to use different ports? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            auto_assign_ports
        else
            log_warning "Proceeding with potentially conflicting ports"
        fi
    fi
}

# Determine if any compose services are already running
stack_is_running() {
    local services
    services=$(docker compose "${COMPOSE_FILES[@]}" ps --services --status running 2>/dev/null || true)
    services=${services//[$'\n''\r'' ']}
    [[ -n "$services" ]]
}

# Auto-assign free ports
auto_assign_ports() {
    local http_port=$DEFAULT_HTTP_PORT
    local backend_port=$DEFAULT_BACKEND_PORT
    local postgres_port=$DEFAULT_POSTGRES_PORT

    # Find free ports
    while port_is_in_use "$http_port"; do
        http_port=$((http_port + 1))
    done

    while port_is_in_use "$backend_port"; do
        backend_port=$((backend_port + 1))
    done

    while port_is_in_use "$postgres_port"; do
        postgres_port=$((postgres_port + 1))
    done

    export HTTP_PORT=$http_port
    export BACKEND_PORT=$backend_port
    export POSTGRES_HOST_PORT=$postgres_port

    log_info "Auto-assigned ports:"
    log_info "  HTTP (Frontend): $http_port"
    log_info "  Backend API: $backend_port"
    log_info "  Postgres: $postgres_port"
}

# Ensure environment is set up
ensure_env() {
    if [[ ! -f "$ROOT_DIR/.env" ]]; then
        log_info "No .env file found. Creating from .env.example..."
        cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
        log_warning "Please edit .env file and replace CHANGE_ME values"
        log_warning "  Required: POSTGRES_PASSWORD, SECRET_KEY, COLMENA_SECRET_KEY, SUPERADMIN_PASSWORD"
        read -p "Press enter when you've updated .env file..."
    fi

    # Source the environment
    set -a
    source "$ROOT_DIR/.env"
    set +a
}

# Wait for service to be healthy
wait_for_service() {
    local service=$1
    local timeout=${2:-60}
    local interval=${3:-2}

    log_info "Waiting for $service to be healthy (timeout: ${timeout}s)..."

    local count=0
    while [ $count -lt $timeout ]; do
        if docker compose "${COMPOSE_FILES[@]}" ps --services --status running | grep -q "^$service$"; then
            log_success "$service is running"
            return 0
        fi
        sleep $interval
        count=$((count + interval))
        echo -n "."
    done

    echo
    log_error "$service failed to start within ${timeout} seconds"
    return 1
}

# Bring up the stack
bring_up_stack() {
    local build=${1:-""}
    local keep_up=${2:-"false"}

    log_info "Bringing up ColmenaOS stack..."

    check_docker
    ensure_env
    local already_running=false

    if stack_is_running; then
        already_running=true
        log_info "Stack already running; ensuring services stay up"
    else
        check_ports
    fi

    local compose_args="${COMPOSE_FILES[@]}"
    local cmd="up -d"

    if [[ "$build" == "--build" ]]; then
        cmd="up -d --build"
        log_info "Building images before starting..."
    fi

    docker compose $compose_args $cmd

    if [[ "$already_running" == false ]]; then
        STACK_STARTED_BY_SCRIPT=true
    fi

    # Wait for critical services
    wait_for_service "postgres" 60
    wait_for_service "colmena-app" 120

    log_success "Stack is up and running!"

    if [[ "$keep_up" == "--keep-up" || "$keep_up" == "true" ]]; then
        KEEP_UP=true
    fi

    if [[ "$already_running" == true ]]; then
        log_info "Existing stack will remain untouched after this command."
    elif [[ "${KEEP_UP}" == "true" ]]; then
        log_info "Stack will remain running after script exits (--keep-up enabled)."
    else
        log_info "Stack will be stopped when script exits (use --keep-up to keep it running)."
    fi
}

# Tear down the stack
tear_down_stack() {
    log_info "Tearing down ColmenaOS stack..."
    docker compose "${COMPOSE_FILES[@]}" down 2>/dev/null || true
    log_success "Stack stopped"
}

# Run backend command
run_backend() {
    shift # Remove 'backend' from arguments

    log_info "Running backend command: $*"

    # Ensure stack is up
    bring_up_stack "" "--keep-up"

    if [[ $# -eq 0 ]]; then
        log_error "No backend command provided"
        exit 1
    fi

    local cmd=("$@")

    # Automatically run manage.py via python for convenience (matches docs)
    if [[ ${cmd[0]} == "manage.py" ]]; then
        cmd=(python manage.py "${cmd[@]:1}")
    fi

    # Run command inside /opt/app so relative paths (scripts/, etc.) resolve
    local quoted_cmd
    quoted_cmd=$(printf ' %q' "${cmd[@]}")
    docker compose "${COMPOSE_FILES[@]}" exec -T colmena-app sh -c "cd /opt/app &&${quoted_cmd}"
}

# Run frontend command
run_frontend() {
    local cmd=$1
    shift

    log_info "Running frontend command: $cmd"

    case "$cmd" in
        "dev"|"build"|"test"|"lint")
            log_warning "Frontend commands (dev, build, test, lint) must be run on the host"
            log_info "The runtime container only includes Python, nginx, and supervisor."
            log_info "Node.js/npm are only available in the build stage."
            echo
            log_info "To run frontend commands, execute from your host machine:"
            echo "  cd $ROOT_DIR/frontend"
            echo "  npm run $cmd $*"
            echo

            if [[ "$cmd" == "dev" ]]; then
                log_info "For development server specifically:"
                echo "  npm run dev -- --host 0.0.0.0 --port 3000"
                echo
                log_info "Frontend will be accessible at http://localhost:3000"
                log_info "Backend API is at http://localhost:${BACKEND_PORT:-7100}"
                log_info "Make sure the stack is running: $0 up --keep-up"
            fi
            ;;

        *)
            log_error "Unknown frontend command: $cmd"
            log_info "Available commands: dev, build, test, lint"
            echo
            log_info "Note: All frontend commands must be run on the host (see above)"
            exit 1
            ;;
    esac
}

# Run tests
run_tests() {
    local test_type=$1
    shift

    case "$test_type" in
        "backend")
            log_info "Running backend tests..."
            bring_up_stack "" "--keep-up"

            docker compose "${COMPOSE_FILES[@]}" exec -T colmena-app python manage.py test "$@"
            ;;

        "frontend")
            log_info "Running frontend tests..."
            run_frontend test "$@"
            ;;

        "smoke")
            log_info "Running smoke tests..."
            # Use the existing smoke test script
            ./scripts/run-playwright-smoke.sh "$@"
            ;;

        "infra")
            log_info "Running infrastructure tests..."
            bring_up_stack "" "--keep-up"

            # Check all services are running
            local services=("postgres" "colmena-app" "nextcloud" "mail")
            for service in "${services[@]}"; do
                if docker compose "${COMPOSE_FILES[@]}" ps --services --status running | grep -q "^$service$"; then
                    log_success "✓ $service is running"
                else
                    log_error "✗ $service is not running"
                    exit 1
                fi
            done

            # Check database connectivity
            log_info "Testing database connectivity..."
            docker compose "${COMPOSE_FILES[@]}" exec -T postgres pg_isready -U "${POSTGRES_USER:-colmena}" -d "${POSTGRES_DB:-colmena}" || {
                log_error "Database is not ready"
                exit 1
            }
            log_success "Database is ready"

            # Check backend API
            log_info "Testing backend API..."
            if curl -sf http://localhost:${HTTP_PORT:-7180}/api/health/ >/dev/null; then
                log_success "Backend API is responding"
            else
                log_error "✗ Backend API health check failed"
                exit 1
            fi

            log_success "All infrastructure tests passed!"
            ;;

        *)
            log_error "Unknown test type: $test_type"
            log_info "Available test types: backend, frontend, smoke, infra"
            exit 1
            ;;
    esac
}

# Drop into a shell
open_shell() {
    log_info "Opening shell in colmena-app container..."
    bring_up_stack "" "--keep-up"

    docker compose "${COMPOSE_FILES[@]}" exec colmena-app sh
}

# Execute arbitrary command
execute_command() {
    log_info "Executing command in colmena-app container: $*"
    bring_up_stack "" "--keep-up"

    docker compose "${COMPOSE_FILES[@]}" exec -T colmena-app "$@"
}

# Show help
show_help() {
    cat << EOF
ColmenaOS Run-in-Environment Script

Usage: $0 <command> [options]

Commands:
  backend <command...>       Run backend command in the container
                             Example: $0 backend manage.py showmigrations

  frontend <cmd> [args...]   Frontend helper (shows instructions)
                             Note: All frontend commands must be run on the host
                             Available commands:
                               dev     - Start development server
                               build   - Build for production
                               test    - Run tests
                               lint    - Lint code

  test <type> [args...]      Run tests
                             Available types:
                               backend - Django tests
                               frontend - React tests
                               smoke   - Playwright smoke tests
                               infra   - Infrastructure tests

  shell                      Drop into shell in the container

  exec <command...>          Execute arbitrary command in container
                             Example: $0 exec "python -c 'print(\"Hello\")'"

  up [--build] [--keep-up]   Bring up the stack
                             --build: Build images before starting
                             --keep-up: Don't stop stack on exit

  down                       Stop the stack

  status                     Show stack status

  logs [service]             Show logs
                             Example: $0 logs colmena-app

  help                       Show this help message

Examples:
  # Run Django management command
  $0 backend manage.py migrate

  # Run a Python script
  $0 backend scripts/test_db.py

  # Run backend tests
  $0 test backend

  # Run smoke tests
  $0 test smoke

  # Execute arbitrary Python code
  $0 exec python -c "from django.conf import settings; print(settings.DEBUG)"

EOF
}

###############################################################################
# Main Script
###############################################################################

# Set up cleanup trap
cleanup() {
    if [[ "$STACK_STARTED_BY_SCRIPT" != "true" ]]; then
        return
    fi

    if [[ "${KEEP_UP:-false}" == "true" ]]; then
        return
    fi

    tear_down_stack
}
trap cleanup EXIT

# Parse command line arguments
COMMAND=${1:-}
case "${COMMAND}" in
    "backend"|"be")
        shift
        run_backend "$@"
        ;;

    "frontend"|"fe")
        shift
        if [[ $# -eq 0 ]]; then
            log_error "Missing frontend command"
            show_help
            exit 1
        fi
        run_frontend "$@"
        ;;

    "test")
        shift
        if [[ $# -eq 0 ]]; then
            log_error "Missing test type"
            show_help
            exit 1
        fi
        run_tests "$@"
        ;;

    "shell")
        open_shell
        ;;

    "exec")
        shift
        if [[ $# -eq 0 ]]; then
            log_error "Missing command to execute"
            exit 1
        fi
        execute_command "$@"
        ;;

    "up")
        shift
        KEEP_UP=false
        BUILD=""

        # Parse arguments
        for arg in "$@"; do
            case "$arg" in
                "--keep-up")
                    KEEP_UP=true
                    ;;
                "--build")
                    BUILD="--build"
                    ;;
            esac
        done

        bring_up_stack "$BUILD" "$KEEP_UP"
        ;;

    "down")
        tear_down_stack
        ;;

    "status")
        check_docker
        docker compose "${COMPOSE_FILES[@]}" ps
        ;;

    "logs")
        shift
        check_docker
        if [[ -n "${1:-}" ]]; then
            docker compose "${COMPOSE_FILES[@]}" logs -f "$1"
        else
            docker compose "${COMPOSE_FILES[@]}" logs -f
        fi
        ;;

    "help"|"-h"|"--help"|"")
        show_help
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        echo
        show_help
        exit 1
        ;;
esac

exit 0
