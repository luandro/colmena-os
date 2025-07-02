#!/bin/bash

# Local Testing Script for ColmenaOS CI/CD Pipeline
# Tests GitHub Actions workflows locally using act before running on GitHub

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SECRETS_FILE="$PROJECT_ROOT/.secrets"
ACT_CONFIG="$PROJECT_ROOT/.actrc"

# Functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if act is installed
    if ! command -v act &> /dev/null; then
        log_error "act is not installed. Installing..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install act
            else
                log_error "Please install act manually or install Homebrew"
                exit 1
            fi
        else
            log_error "Unsupported OS. Please install act manually."
            exit 1
        fi
    fi
    
    # Check if Docker is running
    if ! docker info &> /dev/null; then
        log_error "Docker is not running. Please start Docker."
        exit 1
    fi
    
    # Check if secrets file exists
    if [[ ! -f "$SECRETS_FILE" ]]; then
        log_warning "Secrets file not found. Creating from example..."
        cp "$PROJECT_ROOT/.secrets.example" "$SECRETS_FILE"
        log_warning "Please edit $SECRETS_FILE with your actual credentials"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

setup_docker_buildx() {
    log_info "Setting up Docker Buildx for multi-arch testing..."
    
    # Create buildx instance if it doesn't exist
    if ! docker buildx inspect act-builder &> /dev/null; then
        docker buildx create --name act-builder --use
    else
        docker buildx use act-builder
    fi
    
    # Enable QEMU for multi-arch builds
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    
    log_success "Docker Buildx setup complete"
}

test_workflow() {
    local workflow_name="$1"
    local job_name="${2:-}"
    local event="${3:-push}"
    
    log_info "Testing workflow: $workflow_name"
    
    local act_cmd="act $event"
    
    if [[ -n "$job_name" ]]; then
        act_cmd="$act_cmd -j $job_name"
    fi
    
    if [[ -f "$SECRETS_FILE" ]]; then
        act_cmd="$act_cmd --secret-file $SECRETS_FILE"
    fi
    
    if [[ -f "$ACT_CONFIG" ]]; then
        act_cmd="$act_cmd --config $ACT_CONFIG"
    fi
    
    # Add workflow file if specified
    if [[ -f "$PROJECT_ROOT/.github/workflows/$workflow_name.yml" ]]; then
        act_cmd="$act_cmd --workflows $PROJECT_ROOT/.github/workflows/$workflow_name.yml"
    fi
    
    log_info "Running: $act_cmd"
    
    if eval "$act_cmd"; then
        log_success "Workflow $workflow_name passed"
        return 0
    else
        log_error "Workflow $workflow_name failed"
        return 1
    fi
}

test_all_workflows() {
    log_info "Testing all ColmenaOS workflows..."
    
    local failed_tests=0
    
    # Test daily update checker (dry run)
    log_info "Testing daily update checker workflow..."
    if test_workflow "daily-update-checker" "" "schedule"; then
        log_success "Daily update checker test passed"
    else
        log_error "Daily update checker test failed"
        ((failed_tests++))
    fi
    
    # Test build and push workflow
    log_info "Testing build and push workflow..."
    if test_workflow "build-and-push" "prepare" "push"; then
        log_success "Build and push test passed"
    else
        log_error "Build and push test failed"
        ((failed_tests++))
    fi
    
    # Test Balena draft deployment (dry run)
    log_info "Testing Balena draft deployment workflow..."
    if ACT_DRY_RUN=true test_workflow "deploy-balena-draft" "" "repository_dispatch"; then
        log_success "Balena draft deployment test passed"
    else
        log_error "Balena draft deployment test failed"
        ((failed_tests++))
    fi
    
    if [[ $failed_tests -eq 0 ]]; then
        log_success "All workflow tests passed! 🎉"
        return 0
    else
        log_error "$failed_tests workflow test(s) failed"
        return 1
    fi
}

test_specific_service() {
    local service="$1"
    
    log_info "Testing specific service: $service"
    
    # Set environment variables for service-specific testing
    export INPUT_SERVICES="$service"
    export INPUT_PLATFORMS="linux/amd64"  # Test single arch for speed
    
    if test_workflow "build-and-push" "build" "workflow_dispatch"; then
        log_success "Service $service test passed"
        return 0
    else
        log_error "Service $service test failed"
        return 1
    fi
}

clean_up() {
    log_info "Cleaning up test artifacts..."
    
    # Remove act artifacts
    if [[ -d "/tmp/act-artifacts" ]]; then
        rm -rf /tmp/act-artifacts
    fi
    
    # Clean up Docker containers and images created by act
    docker container prune -f --filter "label=act"
    docker image prune -f --filter "label=act"
    
    log_success "Cleanup complete"
}

show_help() {
    cat << EOF
Local Testing Script for ColmenaOS CI/CD Pipeline

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    check           Check prerequisites and setup
    test-all        Test all workflows
    test-service    Test specific service (frontend|backend|devops)
    test-workflow   Test specific workflow by name
    setup           Setup Docker Buildx for multi-arch testing
    clean           Clean up test artifacts
    help            Show this help message

Examples:
    $0 check                           # Check prerequisites
    $0 test-all                        # Test all workflows
    $0 test-service frontend           # Test frontend service only
    $0 test-workflow build-and-push    # Test specific workflow
    $0 clean                           # Clean up after testing

Environment Variables:
    ACT_DRY_RUN=true                   # Run act in dry-run mode
    ACT_VERBOSE=true                   # Enable verbose output
    SKIP_DOCKER_SETUP=true             # Skip Docker Buildx setup

EOF
}

main() {
    local command="${1:-help}"
    
    case "$command" in
        "check")
            check_prerequisites
            ;;
        "setup")
            check_prerequisites
            setup_docker_buildx
            ;;
        "test-all")
            check_prerequisites
            setup_docker_buildx
            test_all_workflows
            ;;
        "test-service")
            local service="${2:-}"
            if [[ -z "$service" ]]; then
                log_error "Please specify a service: frontend, backend, or devops"
                exit 1
            fi
            check_prerequisites
            setup_docker_buildx
            test_specific_service "$service"
            ;;
        "test-workflow")
            local workflow="${2:-}"
            if [[ -z "$workflow" ]]; then
                log_error "Please specify a workflow name"
                exit 1
            fi
            check_prerequisites
            test_workflow "$workflow"
            ;;
        "clean")
            clean_up
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Trap to ensure cleanup on exit
trap clean_up EXIT

# Run main function
main "$@"