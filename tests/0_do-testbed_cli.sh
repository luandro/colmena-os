#!/bin/bash
set -e

# ColmenaOS Digital Ocean Testbed CLI
# Usage: ./do-testbed_cli.sh [create|destroy|list|connect|deploy] [testbed-name]

TESTBED_PREFIX="colmena-testbed"
DO_REGION="nyc3"
DO_SIZE="s-2vcpu-4gb"
DO_IMAGE="ubuntu-22-04-x64"
CLOUD_INIT_FILE="./cloud-init.yml"
DEFAULT_TESTBED_TAG="${TESTBED_TAG:-${TESTBED_PREFIX}-ci}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

check_requirements() {
    # Check if doctl is installed
    if ! command -v doctl &> /dev/null; then
        error "doctl is not installed. Please install it first: https://docs.digitalocean.com/reference/doctl/how-to/install/"
    fi

    # Check if doctl is authenticated
    if ! doctl account get &> /dev/null; then
        error "doctl is not authenticated. Run 'doctl auth init' first."
    fi

    # Check if cloud-init file exists
    if [[ ! -f "$CLOUD_INIT_FILE" ]]; then
        error "Cloud-init file not found: $CLOUD_INIT_FILE"
    fi
}

wait_for_tag_cleanup() {
    local droplet_tag=$1
    local max_attempts=${2:-10}
    local sleep_seconds=${3:-15}

    for ((attempt=1; attempt<=max_attempts; attempt++)); do
        local remaining=$(doctl compute droplet list --tag-name "$droplet_tag" --format ID --no-header 2>/dev/null || true)
        if [[ -z "$remaining" ]]; then
            return 0
        fi

        log "Waiting for droplets tagged $droplet_tag to be fully destroyed (attempt $attempt/$max_attempts)"
        sleep "$sleep_seconds"
    done

    warn "Droplets still tagged with $droplet_tag after waiting"
    return 1
}

create_testbed() {
    local testbed_name=${1:-"default"}
    local droplet_tag=${2:-$DEFAULT_TESTBED_TAG}

    # Normalise tag to meet DigitalOcean requirements (lowercase alphanumeric and dashes)
    droplet_tag=$(echo "$droplet_tag" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

    local droplet_name="${TESTBED_PREFIX}-${testbed_name}-$(date +%s)"
    
    log "Creating testbed: $droplet_name"
    
    # Get SSH keys
    local ssh_keys=$(doctl compute ssh-key list --format ID --no-header | tr '\n' ',' | sed 's/,$//')
    
    if [[ -z "$ssh_keys" ]]; then
        error "No SSH keys found in your DigitalOcean account. Please add an SSH key first."
    fi
    
    # Create droplet
    log "Creating droplet with cloud-init configuration (tag: $droplet_tag)..."
    doctl compute droplet create "$droplet_name" \
        --region "$DO_REGION" \
        --size "$DO_SIZE" \
        --image "$DO_IMAGE" \
        --user-data-file "$CLOUD_INIT_FILE" \
        --ssh-keys "$ssh_keys" \
        --tag-name "$droplet_tag" \
        --wait
    
    # Get droplet IP
    local droplet_ip=$(doctl compute droplet get "$droplet_name" --format PublicIPv4 --no-header)
    
    log "Testbed created successfully!"
    log "Droplet: $droplet_name"
    log "IP: $droplet_ip"
    log "SSH: ssh root@$droplet_ip"
    log "Tag: $droplet_tag"
    
    # Wait for cloud-init to complete
    log "Waiting for system initialization (this may take 2-3 minutes)..."
    sleep 120
    
    # Test SSH connection
    log "Testing SSH connection..."
    local max_attempts=10
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$droplet_ip "echo 'SSH connection successful'" &> /dev/null; then
            log "SSH connection established"
            break
        else
            log "SSH attempt $attempt/$max_attempts failed, retrying in 15 seconds..."
            sleep 15
            ((attempt++))
        fi
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        error "Could not establish SSH connection after $max_attempts attempts"
    fi
    
    # Verify installation
    log "Verifying installations..."
    ssh -o StrictHostKeyChecking=no root@$droplet_ip << 'EOF'
        echo "=== System Information ==="
        uname -a
        echo ""
        
        echo "=== Docker Version ==="
        docker --version || echo "Docker not installed"
        echo ""
        
        echo "=== Docker Compose Version ==="
        docker compose --version || echo "Docker Compose not installed"
        echo ""
        
        echo "=== Node.js Version ==="
        node --version || echo "Node.js not installed"
        echo ""
        
        echo "=== NPM Version ==="
        npm --version || echo "NPM not installed"
        echo ""
        
        echo "=== Python Version ==="
        python3.12 --version || python3 --version || echo "Python not installed"
        echo ""
        
        echo "=== Build Tools ==="
        gcc --version | head -1 || echo "GCC not installed"
        make --version | head -1 || echo "Make not installed"
        echo ""
        
        echo "=== Colmena CLI ==="
        colmena --version || echo "Colmena CLI not found in PATH"
        echo ""
        
        echo "=== Available Disk Space ==="
        df -h /
        echo ""
        
        echo "=== Memory Info ==="
        free -h
EOF
    
    log "Testbed setup complete!"
    log "You can now connect with: ./do-testbed_cli.sh connect $testbed_name"
}

destroy_testbed() {
    local pattern=${1:-$TESTBED_PREFIX}
    local droplet_tag=${2:-$DEFAULT_TESTBED_TAG}

    droplet_tag=$(echo "$droplet_tag" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')

    log "Ensuring testbeds tagged '$droplet_tag' are destroyed"

    # Attempt deletion by tag first; ignore errors if the tag does not exist yet
    if droplet_ids=$(doctl compute droplet list --tag-name "$droplet_tag" --format ID --no-header 2>/dev/null); then
        if [[ -n "$droplet_ids" ]]; then
            log "Found droplets via tag: $(echo "$droplet_ids" | tr '\n' ' ')"
            if ! doctl compute droplet delete --tag-name "$droplet_tag" --force; then
                warn "Failed to delete all droplets by tag $droplet_tag"
            fi
            wait_for_tag_cleanup "$droplet_tag" || return 1
        else
            log "No droplets currently tagged with $droplet_tag"
        fi
    else
        warn "Unable to list droplets by tag $droplet_tag"
    fi

    # Fallback to name pattern matching for legacy resources without the tag
    log "Searching for testbeds matching: $pattern"
    local droplets=$(doctl compute droplet list --format Name --no-header | grep "$pattern" || true)

    if [[ -z "$droplets" ]]; then
        warn "No testbeds found matching pattern: $pattern"
    else
        echo "$droplets" | while read -r droplet; do
            if [[ -n "$droplet" ]]; then
                log "Destroying testbed: $droplet"
                if ! doctl compute droplet delete "$droplet" --force; then
                    warn "Failed to delete droplet $droplet"
                fi
            fi
        done
        wait_for_tag_cleanup "$droplet_tag" || return 1
    fi

    # Verify no droplets remain for the tag
    if remaining=$(doctl compute droplet list --tag-name "$droplet_tag" --format ID --no-header 2>/dev/null); then
        if [[ -n "$remaining" ]]; then
            warn "Droplets still tagged with $droplet_tag after cleanup: $(echo "$remaining" | tr '\n' ' ')"
            return 1
        fi
    fi

    log "Testbed destruction complete"
}

list_testbeds() {
    log "Active testbeds:"
    echo ""
    doctl compute droplet list --format Name,PublicIPv4,Status | grep "$TESTBED_PREFIX" || {
        warn "No active testbeds found"
        return 0
    }
}

connect_testbed() {
    local testbed_name=${1:-"default"}
    
    if [[ "$testbed_name" == "default" ]]; then
        # If no specific name provided, connect to the most recent one
        local droplet_name=$(doctl compute droplet list --format Name,Created --no-header | \
                           grep "$TESTBED_PREFIX" | \
                           sort -k2 -r | \
                           head -1 | \
                           awk '{print $1}')
    else
        local droplet_name=$(doctl compute droplet list --format Name --no-header | \
                           grep "${TESTBED_PREFIX}-${testbed_name}" | \
                           head -1)
    fi
    
    if [[ -z "$droplet_name" ]]; then
        error "No testbed found matching: $testbed_name"
    fi
    
    local droplet_ip=$(doctl compute droplet get "$droplet_name" --format PublicIPv4 --no-header)
    
    log "Connecting to testbed: $droplet_name ($droplet_ip)"
    ssh -o StrictHostKeyChecking=no root@$droplet_ip
}

deploy_colmena() {
    local testbed_name=${1:-"default"}
    local droplet_name=$(doctl compute droplet list --format Name --no-header | \
                       grep "${TESTBED_PREFIX}-${testbed_name}" | \
                       head -1)
    
    if [[ -z "$droplet_name" ]]; then
        error "No testbed found matching: $testbed_name"
    fi
    
    local droplet_ip=$(doctl compute droplet get "$droplet_name" --format PublicIPv4 --no-header)
    
    log "Deploying ColmenaOS to testbed: $droplet_name ($droplet_ip)"
    
    # Copy files to testbed
    log "Copying project files..."
    scp -o StrictHostKeyChecking=no ./docker-compose.yml ./balena.yml root@$droplet_ip:/root/
    
    # Deploy using docker compose
    log "Starting deployment..."
    ssh -o StrictHostKeyChecking=no root@$droplet_ip << 'EOF'
        cd /root
        
        # Create environment file with secure defaults
        cat > .env << 'ENVEOF'
POSTGRES_PASSWORD=$(openssl rand -base64 32)
PGADMIN_DEFAULT_PASSWORD=$(openssl rand -base64 32)
NEXTCLOUD_ADMIN_PASSWORD=$(openssl rand -base64 32)
SECRET_KEY=$(openssl rand -base64 32)
POSTGRES_HOSTNAME=postgres
POSTGRES_USERNAME=colmena
POSTGRES_DB=colmena
NEXTCLOUD_TRUSTED_DOMAINS=colmena.local,localhost,$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
NEXTCLOUD_ADMIN_USER=admin
DEBUG=true
ALLOWED_HOSTS=*
ENVEOF
        
        # Start services
        docker compose up -d
        
        # Wait for services to be ready
        echo "Waiting for services to start..."
        sleep 60
        
        # Check service status
        docker compose ps
        
        # Test endpoints
        echo "Testing service endpoints..."
        curl -f http://localhost:80 && echo "Frontend: OK" || echo "Frontend: FAILED"
        curl -f http://localhost:5050 && echo "PGAdmin: OK" || echo "PGAdmin: FAILED"
        curl -f http://localhost:8003 && echo "Nextcloud: OK" || echo "Nextcloud: FAILED"
        curl -f http://localhost:1080 && echo "Mailcrab: OK" || echo "Mailcrab: FAILED"
EOF
    
    log "Deployment complete!"
    log "Access your ColmenaOS instance at: http://$droplet_ip"
    log "PGAdmin: http://$droplet_ip:5050"
    log "Nextcloud: http://$droplet_ip:8003"
    log "Mailcrab: http://$droplet_ip:1080"
}

# Main command handling
case "$1" in
    create)
        check_requirements
        create_testbed "$2" "$3"
        ;;
    destroy)
        check_requirements
        destroy_testbed "$2" "$3"
        ;;
    list)
        check_requirements
        list_testbeds
        ;;
    connect)
        check_requirements
        connect_testbed "$2"
        ;;
    deploy)
        check_requirements
        deploy_colmena "$2"
        ;;
    *)
        echo "ColmenaOS Digital Ocean Testbed CLI"
        echo ""
        echo "Usage: $0 [create|destroy|list|connect|deploy] [testbed-name] [testbed-tag]"
        echo ""
        echo "Commands:"
        echo "  create [name] [tag]    Create a new testbed (default name: 'default', default tag: '${DEFAULT_TESTBED_TAG}')"
        echo "  destroy [name] [tag]   Destroy testbed(s) with matching name or tag"
        echo "  list            List all active testbeds"
        echo "  connect [name]   SSH into a testbed (connects to most recent if no name)"
        echo "  deploy [name]    Deploy ColmenaOS to a testbed"
        echo ""
        echo "Examples:"
        echo "  $0 create audio-test feature-x-ci   # Create testbed with explicit tag"
        echo "  $0 list                 # List all active testbeds"
        echo "  $0 connect audio-test   # SSH into audio-test testbed"
        echo "  $0 deploy audio-test    # Deploy ColmenaOS to audio-test"
        echo "  $0 destroy audio-test   # Destroy specific testbed"
        echo "  $0 destroy '' feature-x-ci   # Destroy any droplet tagged feature-x-ci"
        echo ""
        echo "Requirements:"
        echo "  - doctl installed and authenticated"
        echo "  - SSH key added to DigitalOcean account"
        echo "  - cloud-init.yml file in current directory"
        exit 1
        ;;
esac
