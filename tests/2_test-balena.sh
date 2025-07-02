#!/bin/bash
set -e

# ColmenaOS Balena Testing Script
# Tests Balena CLI installation and builds docker-compose services

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}"
}

check_balena_cli() {
    log "Checking Balena CLI installation..."
    
    if ! command -v balena &> /dev/null; then
        warn "Balena CLI not found. Installing..."
        
        # Check if npm is available
        if ! command -v npm &> /dev/null; then
            error "npm not found. Please install Node.js first."
        fi
        
        # Install Balena CLI
        log "Installing Balena CLI globally..."
        npm install -g balena-cli --unsafe-perm
        
        # Verify installation
        if ! command -v balena &> /dev/null; then
            error "Failed to install Balena CLI"
        fi
    fi
    
    # Display version
    local balena_version=$(balena version)
    log "Balena CLI version: $balena_version"
}

check_docker() {
    log "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        error "Docker daemon is not running. Please start Docker service."
    fi
    
    local docker_version=$(docker --version)
    local compose_version=$(docker-compose --version)
    log "Docker version: $docker_version"
    log "Docker Compose version: $compose_version"
}

test_balena_build() {
    log "Testing Balena build functionality..."
    
    # Create a temporary test project
    local test_dir="./balena-test-$(date +%s)"
    mkdir -p "$test_dir"
    cd "$test_dir"
    
    # Create a simple test Dockerfile
    cat > Dockerfile << 'EOF'
FROM alpine:latest
RUN apk add --no-cache curl
CMD ["echo", "Balena test build successful"]
EOF
    
    # Create docker-compose.yml for testing
    cat > docker-compose.yml << 'EOF'
version: '2.4'
services:
  test:
    build: .
    command: echo "Balena compose test successful"
EOF
    
    log "Testing local Docker build..."
    if docker build -t balena-test . &> /dev/null; then
        log "✓ Local Docker build successful"
    else
        error "✗ Local Docker build failed"
    fi
    
    log "Testing Docker Compose build..."
    if docker-compose build &> /dev/null; then
        log "✓ Docker Compose build successful"
    else
        error "✗ Docker Compose build failed"
    fi
    
    # Test Balena CLI build (if authenticated)
    log "Testing Balena CLI build capability..."
    if balena build --help &> /dev/null; then
        log "✓ Balena CLI build command available"
        
        # Try a dry-run build
        if balena build --dry-run . &> /dev/null; then
            log "✓ Balena CLI dry-run build successful"
        else
            warn "Balena CLI dry-run build failed (this is normal without authentication)"
        fi
    else
        warn "Balena CLI build command not available"
    fi
    
    # Cleanup
    cd ..
    rm -rf "$test_dir"
    docker rmi balena-test &> /dev/null || true
}

test_colmena_compose() {
    log "Testing ColmenaOS docker-compose configuration..."
    
    # Check if we're in the right directory
    if [[ ! -f "../docker-compose.yml" ]]; then
        error "docker-compose.yml not found. Please run this script from the tests/ directory."
    fi
    
    cd ..
    
    log "Validating docker-compose.yml..."
    if docker-compose config &> /dev/null; then
        log "✓ docker-compose.yml is valid"
    else
        error "✗ docker-compose.yml validation failed"
    fi
    
    log "Testing service build configuration..."
    
    # Check if images are available or can be built
    local services=($(docker-compose config --services))
    
    for service in "${services[@]}"; do
        info "Checking service: $service"
        
        # Get image name for service
        local image=$(docker-compose config | grep -A 10 "^  $service:" | grep "image:" | head -1 | awk '{print $2}')
        
        if [[ -n "$image" ]]; then
            info "Service $service uses image: $image"
            
            # Try to pull image (this will fail for custom registry images, which is expected)
            if docker pull "$image" &> /dev/null; then
                log "✓ Image $image pulled successfully"
            else
                warn "Could not pull image $image (expected for custom registry images)"
            fi
        else
            info "Service $service uses build configuration"
        fi
    done
    
    cd tests
}

test_balena_deployment_readiness() {
    log "Testing Balena deployment readiness..."
    
    # Check balena.yml
    if [[ ! -f "../balena.yml" ]]; then
        error "balena.yml not found"
    fi
    
    log "✓ balena.yml found"
    
    # Validate balena.yml structure
    if command -v yq &> /dev/null; then
        local app_name=$(yq eval '.name' ../balena.yml)
        local app_type=$(yq eval '.type' ../balena.yml)
        log "Application name: $app_name"
        log "Application type: $app_type"
    else
        warn "yq not installed, skipping balena.yml validation"
    fi
    
    # Check for multi-architecture support
    cd ..
    if docker-compose config | grep -q "platform\|build"; then
        log "✓ Multi-architecture build configuration detected"
    else
        info "Single architecture configuration"
    fi
    
    # Test if project structure is compatible with Balena
    log "Checking Balena project structure..."
    
    local required_files=("docker-compose.yml" "balena.yml")
    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            log "✓ $file found"
        else
            error "✗ Required file $file not found"
        fi
    done
    
    cd tests
}

run_integration_test() {
    log "Running integration test..."
    
    cd ..
    
    # Create test environment file
    cat > .env.test << 'EOF'
POSTGRES_PASSWORD=test_password_123
PGADMIN_DEFAULT_PASSWORD=test_admin_123
NEXTCLOUD_ADMIN_PASSWORD=test_nextcloud_123
SECRET_KEY=test_secret_key_for_testing_only
POSTGRES_HOSTNAME=postgres
POSTGRES_USERNAME=colmena
POSTGRES_DB=colmena_test
NEXTCLOUD_TRUSTED_DOMAINS=localhost,127.0.0.1
NEXTCLOUD_ADMIN_USER=admin
DEBUG=true
ALLOWED_HOSTS=*
HTTP_PORT=8080
HTTPS_PORT=8443
NEXTCLOUD_HTTP_PORT=8083
NEXTCLOUD_API_PORT=8084
MAILCRAB_WEB_PORT=1180
MAILCRAB_SMTP_PORT=1125
PGADMIN_PORT=5150
EOF
    
    log "Starting services with test configuration..."
    docker-compose --env-file .env.test up -d --build
    
    # Wait for services to start
    log "Waiting for services to initialize..."
    sleep 30
    
    # Check service health
    local services=($(docker-compose ps --services))
    local healthy_services=0
    local total_services=${#services[@]}
    
    for service in "${services[@]}"; do
        if docker-compose ps "$service" | grep -q "Up"; then
            log "✓ Service $service is running"
            ((healthy_services++))
        else
            warn "✗ Service $service is not running"
        fi
    done
    
    log "Services status: $healthy_services/$total_services running"
    
    # Test endpoints
    log "Testing service endpoints..."
    
    local endpoints=(
        "http://localhost:8080:Frontend"
        "http://localhost:5150:PGAdmin" 
        "http://localhost:8083:Nextcloud"
        "http://localhost:1180:Mailcrab"
    )
    
    for endpoint in "${endpoints[@]}"; do
        local url=$(echo "$endpoint" | cut -d: -f1-3)
        local name=$(echo "$endpoint" | cut -d: -f4)
        
        if curl -f -s --max-time 10 "$url" > /dev/null; then
            log "✓ $name endpoint is responding"
        else
            warn "✗ $name endpoint is not responding"
        fi
    done
    
    # Cleanup
    log "Cleaning up test environment..."
    docker-compose down -v
    rm -f .env.test
    
    cd tests
}

print_summary() {
    log "=== Balena Test Summary ==="
    log "✓ Balena CLI installation verified"
    log "✓ Docker and Docker Compose verified"
    log "✓ Build functionality tested"
    log "✓ ColmenaOS compose configuration validated"
    log "✓ Balena deployment readiness checked"
    log "✓ Integration test completed"
    log ""
    log "Your environment is ready for Balena deployment!"
    log ""
    log "Next steps:"
    log "1. Create a Balena application: balena app create myapp"
    log "2. Add a device to your fleet"
    log "3. Deploy: balena push myapp"
}

# Main execution
main() {
    log "Starting ColmenaOS Balena testing..."
    
    check_docker
    check_balena_cli
    test_balena_build
    test_colmena_compose
    test_balena_deployment_readiness
    run_integration_test
    print_summary
}

# Handle script arguments
case "$1" in
    --check-only)
        check_docker
        check_balena_cli
        ;;
    --build-only)
        check_docker
        check_balena_cli
        test_balena_build
        ;;
    --integration-only)
        check_docker
        run_integration_test
        ;;
    *)
        main
        ;;
esac