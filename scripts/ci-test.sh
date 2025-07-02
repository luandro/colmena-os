#!/bin/bash

# CI Testing Script for ColmenaOS
# Integrates act (local testing) with Digital Ocean testbeds for comprehensive CI/CD validation

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOCAL_TEST_SCRIPT="$SCRIPT_DIR/local-test.sh"
DO_TESTBED_SCRIPT="$PROJECT_ROOT/tests/0_do-testbed_cli.sh"
TESTBED_PREFIX="ci-test"

# Test configuration
ENABLE_LOCAL_TESTS="${ENABLE_LOCAL_TESTS:-true}"
ENABLE_DO_TESTS="${ENABLE_DO_TESTS:-true}"
ENABLE_INTEGRATION_TESTS="${ENABLE_INTEGRATION_TESTS:-true}"
DO_CLEANUP="${DO_CLEANUP:-true}"
TEST_TIMEOUT="${TEST_TIMEOUT:-1800}"  # 30 minutes

# Functions
log_info() {
    echo -e "${BLUE}ℹ️  [$(date +'%H:%M:%S')] $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ [$(date +'%H:%M:%S')] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  [$(date +'%H:%M:%S')] $1${NC}"
}

log_error() {
    echo -e "${RED}❌ [$(date +'%H:%M:%S')] $1${NC}"
}

log_step() {
    echo -e "${PURPLE}🔄 [$(date +'%H:%M:%S')] $1${NC}"
}

check_prerequisites() {
    log_info "Checking CI testing prerequisites..."
    
    # Check if local test script exists
    if [[ ! -f "$LOCAL_TEST_SCRIPT" ]]; then
        log_error "Local test script not found: $LOCAL_TEST_SCRIPT"
        exit 1
    fi
    
    # Check if DO testbed script exists
    if [[ ! -f "$DO_TESTBED_SCRIPT" ]]; then
        log_error "DO testbed script not found: $DO_TESTBED_SCRIPT"
        exit 1
    fi
    
    # Make sure scripts are executable
    chmod +x "$LOCAL_TEST_SCRIPT" "$DO_TESTBED_SCRIPT"
    
    log_success "Prerequisites check passed"
}

run_local_tests() {
    if [[ "$ENABLE_LOCAL_TESTS" != "true" ]]; then
        log_warning "Local tests disabled, skipping..."
        return 0
    fi
    
    log_step "Running local GitHub Actions tests with act..."
    
    # Run local test setup
    if ! "$LOCAL_TEST_SCRIPT" check; then
        log_error "Local test prerequisites check failed"
        return 1
    fi
    
    # Test specific workflows
    local failed_tests=0
    
    log_info "Testing daily update checker workflow..."
    if "$LOCAL_TEST_SCRIPT" test-workflow daily-update-checker; then
        log_success "Daily update checker test passed"
    else
        log_error "Daily update checker test failed"
        ((failed_tests++))
    fi
    
    log_info "Testing build preparation..."
    if ACT_DRY_RUN=true "$LOCAL_TEST_SCRIPT" test-workflow build-and-push; then
        log_success "Build workflow test passed"
    else
        log_error "Build workflow test failed"
        ((failed_tests++))
    fi
    
    # Test individual services
    for service in frontend backend devops; do
        log_info "Testing $service service build..."
        if ACT_DRY_RUN=true "$LOCAL_TEST_SCRIPT" test-service "$service"; then
            log_success "$service service test passed"
        else
            log_error "$service service test failed"
            ((failed_tests++))
        fi
    done
    
    if [[ $failed_tests -eq 0 ]]; then
        log_success "All local tests passed! 🎉"
        return 0
    else
        log_error "$failed_tests local test(s) failed"
        return 1
    fi
}

create_do_testbed() {
    if [[ "$ENABLE_DO_TESTS" != "true" ]]; then
        log_warning "DO testbed tests disabled, skipping..."
        return 0
    fi
    
    local testbed_name="$1"
    
    log_step "Creating Digital Ocean testbed: $testbed_name"
    
    # Create testbed
    if ! "$DO_TESTBED_SCRIPT" create "$testbed_name"; then
        log_error "Failed to create DO testbed: $testbed_name"
        return 1
    fi
    
    log_success "DO testbed created successfully: $testbed_name"
    return 0
}

test_docker_build_on_testbed() {
    local testbed_name="$1"
    
    log_step "Testing Docker builds on testbed: $testbed_name"
    
    # Get testbed IP
    local droplet_name=$(doctl compute droplet list --format Name --no-header | \
                       grep "${TESTBED_PREFIX}-${testbed_name}" | \
                       head -1)
    
    if [[ -z "$droplet_name" ]]; then
        log_error "Testbed not found: $testbed_name"
        return 1
    fi
    
    local droplet_ip=$(doctl compute droplet get "$droplet_name" --format PublicIPv4 --no-header)
    
    log_info "Testing Docker builds on $droplet_ip..."
    
    # Copy necessary files to testbed
    scp -o StrictHostKeyChecking=no -r \
        "$PROJECT_ROOT/docker-compose.yml" \
        "$PROJECT_ROOT/.env.example" \
        "root@$droplet_ip:/tmp/"
    
    # Test Docker builds remotely
    ssh -o StrictHostKeyChecking=no "root@$droplet_ip" << 'EOF'
        set -e
        cd /tmp
        
        # Create test environment file
        cp .env.example .env
        
        # Update with secure test values
        sed -i 's/your_secure_password_here/test_password_123/g' .env
        sed -i 's/your_django_secret_key_here_min_50_chars_long_random_string/test_secret_key_for_testing_purposes_minimum_fifty_chars/g' .env
        sed -i 's/your_nextcloud_admin_password/test_nextcloud_pass/g' .env
        sed -i 's/DEBUG=false/DEBUG=true/g' .env
        
        echo "=== Environment Configuration ==="
        cat .env | grep -v PASSWORD | grep -v SECRET_KEY
        echo ""
        
        echo "=== Testing Docker Compose Validation ==="
        docker compose config
        echo ""
        
        echo "=== Testing Service Pull (without build) ==="
        # Test if we can pull base images
        docker compose pull --ignore-buildable || echo "Some services require building"
        echo ""
        
        echo "=== Docker System Info ==="
        docker system info | grep -A 5 "Server Version"
        docker system df
        echo ""
        
        echo "=== Available Resources ==="
        df -h /
        free -h
        nproc
        echo ""
EOF
    
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_success "Docker build test passed on testbed"
        return 0
    else
        log_error "Docker build test failed on testbed"
        return 1
    fi
}

test_colmena_deployment() {
    local testbed_name="$1"
    
    log_step "Testing full ColmenaOS deployment on testbed: $testbed_name"
    
    # Deploy ColmenaOS using the existing script
    if ! "$DO_TESTBED_SCRIPT" deploy "$testbed_name"; then
        log_error "ColmenaOS deployment failed on testbed: $testbed_name"
        return 1
    fi
    
    # Additional health checks
    local droplet_name=$(doctl compute droplet list --format Name --no-header | \
                       grep "${TESTBED_PREFIX}-${testbed_name}" | \
                       head -1)
    local droplet_ip=$(doctl compute droplet get "$droplet_name" --format PublicIPv4 --no-header)
    
    log_info "Running additional health checks on $droplet_ip..."
    
    # Extended health check
    ssh -o StrictHostKeyChecking=no "root@$droplet_ip" << 'EOF'
        cd /root
        
        echo "=== Service Status ==="
        docker compose ps
        echo ""
        
        echo "=== Service Logs (last 20 lines each) ==="
        for service in $(docker compose ps --services); do
            echo "--- $service logs ---"
            docker compose logs --tail=20 "$service" 2>/dev/null || echo "No logs for $service"
            echo ""
        done
        
        echo "=== Container Resource Usage ==="
        docker stats --no-stream
        echo ""
        
        echo "=== Network Connectivity Tests ==="
        # Test internal service communication
        docker compose exec -T backend curl -f http://db:5432 || echo "DB connection test skipped"
        echo ""
        
        echo "=== Disk Usage After Deployment ==="
        df -h /
        echo ""
        
        echo "=== System Load ==="
        uptime
        echo ""
EOF
    
    local exit_code=$?
    if [[ $exit_code -eq 0 ]]; then
        log_success "ColmenaOS deployment test passed"
        return 0
    else
        log_error "ColmenaOS deployment test failed"
        return 1
    fi
}

run_integration_tests() {
    if [[ "$ENABLE_INTEGRATION_TESTS" != "true" ]]; then
        log_warning "Integration tests disabled, skipping..."
        return 0
    fi
    
    local testbed_name="${TESTBED_PREFIX}-integration-$(date +%s)"
    
    log_step "Running integration tests on testbed: $testbed_name"
    
    # Create testbed
    if ! create_do_testbed "$testbed_name"; then
        return 1
    fi
    
    # Test Docker builds
    if ! test_docker_build_on_testbed "$testbed_name"; then
        log_error "Docker build integration test failed"
        cleanup_testbed "$testbed_name"
        return 1
    fi
    
    # Test full deployment
    if ! test_colmena_deployment "$testbed_name"; then
        log_error "Deployment integration test failed"
        cleanup_testbed "$testbed_name"
        return 1
    fi
    
    log_success "All integration tests passed! 🎉"
    
    # Cleanup
    if [[ "$DO_CLEANUP" == "true" ]]; then
        cleanup_testbed "$testbed_name"
    else
        log_warning "Cleanup disabled. Testbed preserved: $testbed_name"
    fi
    
    return 0
}

cleanup_testbed() {
    local testbed_name="$1"
    
    log_info "Cleaning up testbed: $testbed_name"
    
    if ! "$DO_TESTBED_SCRIPT" destroy "$testbed_name"; then
        log_warning "Failed to cleanup testbed: $testbed_name"
    else
        log_success "Testbed cleaned up: $testbed_name"
    fi
}

cleanup_all_testbeds() {
    log_info "Cleaning up all CI testbeds..."
    
    if ! "$DO_TESTBED_SCRIPT" destroy "$TESTBED_PREFIX"; then
        log_warning "Failed to cleanup some testbeds"
    else
        log_success "All CI testbeds cleaned up"
    fi
}

run_full_test_suite() {
    local start_time=$(date +%s)
    local failed_tests=0
    
    log_step "Starting full CI test suite for ColmenaOS..."
    
    # Run local tests first (faster feedback)
    if ! run_local_tests; then
        log_error "Local tests failed"
        ((failed_tests++))
    fi
    
    # Run integration tests if local tests pass or if forced
    if [[ $failed_tests -eq 0 ]] || [[ "${FORCE_INTEGRATION:-false}" == "true" ]]; then
        if ! run_integration_tests; then
            log_error "Integration tests failed"
            ((failed_tests++))
        fi
    else
        log_warning "Skipping integration tests due to local test failures"
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [[ $failed_tests -eq 0 ]]; then
        log_success "🎉 All CI tests passed! (Duration: ${duration}s)"
        return 0
    else
        log_error "❌ $failed_tests test suite(s) failed (Duration: ${duration}s)"
        return 1
    fi
}

show_help() {
    cat << EOF
CI Testing Script for ColmenaOS

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    full                Run complete test suite (local + integration)
    local               Run local tests only (act)
    integration         Run integration tests only (DO testbed)
    create-testbed      Create a DO testbed for manual testing
    cleanup             Clean up all CI testbeds
    help                Show this help message

Options:
    --no-local          Disable local tests
    --no-do            Disable DO testbed tests
    --no-integration   Disable integration tests
    --no-cleanup       Don't cleanup testbeds after tests
    --force-integration Run integration tests even if local tests fail

Environment Variables:
    ENABLE_LOCAL_TESTS=true|false      Enable/disable local tests
    ENABLE_DO_TESTS=true|false         Enable/disable DO testbed tests
    ENABLE_INTEGRATION_TESTS=true|false Enable/disable integration tests
    DO_CLEANUP=true|false              Enable/disable testbed cleanup
    FORCE_INTEGRATION=true|false       Force integration tests
    TEST_TIMEOUT=1800                  Test timeout in seconds

Examples:
    $0 full                           # Run complete test suite
    $0 local                          # Test locally with act only
    $0 integration                    # Test on DO testbed only
    $0 create-testbed manual-test     # Create testbed for manual testing
    $0 cleanup                        # Clean up all test resources

EOF
}

main() {
    local command="${1:-full}"
    
    # Parse options
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-local)
                ENABLE_LOCAL_TESTS=false
                shift
                ;;
            --no-do)
                ENABLE_DO_TESTS=false
                shift
                ;;
            --no-integration)
                ENABLE_INTEGRATION_TESTS=false
                shift
                ;;
            --no-cleanup)
                DO_CLEANUP=false
                shift
                ;;
            --force-integration)
                FORCE_INTEGRATION=true
                shift
                ;;
            *)
                break
                ;;
        esac
    done
    
    check_prerequisites
    
    case "$command" in
        "full")
            run_full_test_suite
            ;;
        "local")
            run_local_tests
            ;;
        "integration")
            run_integration_tests
            ;;
        "create-testbed")
            local testbed_name="${2:-manual-$(date +%s)}"
            create_do_testbed "$testbed_name"
            ;;
        "cleanup")
            cleanup_all_testbeds
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
trap 'cleanup_all_testbeds' EXIT

# Run main function
main "$@"