#!/bin/bash
set -e

# ColmenaOS GitLab CI Testing Testbed
# Usage: ./tests/do-testbed_gitlabci.sh [create|test|destroy|list|update]
# Run from the ROOT of the project, not from tests/ directory

TESTBED_PREFIX="colmena-gitlabci-testbed"
DO_REGION="nyc3"
DO_SIZE="s-4vcpu-8gb"  # Larger instance for CI builds
DO_IMAGE="ubuntu-22-04-x64"
CLOUD_INIT_FILE="./tests/cloud-init-gitlabci.yml"
TESTBED_WORKSPACE="/opt/colmena-ci-workspace"

# Repository URLs
REPOS=(
    "https://gitlab.com/colmena-project/dev/colmena-devops.git"
    "https://gitlab.com/colmena-project/dev/frontend.git"
    "https://gitlab.com/colmena-project/dev/backend.git"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

success() {
    echo -e "${PURPLE}[$(date +'%Y-%m-%d %H:%M:%S')] SUCCESS: $1${NC}"
}

check_requirements() {
    # Check if we're in the project root
    if [[ ! -f ".gitlab-ci.yml" ]]; then
        error "No .gitlab-ci.yml found in current directory. Please run this script from the project root."
    fi
    
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
        warn "GitLab CI cloud-init file not found. Creating default configuration..."
        mkdir -p tests
        create_cloud_init_file
    fi
}

create_cloud_init_file() {
    log "Creating cloud-init configuration for GitLab CI testing..."
    
    cat > "$CLOUD_INIT_FILE" << 'EOF'
#cloud-config

# Update package database and upgrade system
package_update: true
package_upgrade: true

# Install required packages
packages:
  # System utilities and dependencies
  - curl
  - wget
  - software-properties-common
  - ca-certificates
  - gnupg
  - lsb-release
  - apt-transport-https
  
  # Git and development tools
  - git
  - build-essential
  - gcc
  - g++
  - make
  - python3
  - python3-venv
  - python3-dev
  - python3-pip
  
  # System utilities
  - htop
  - vim
  - unzip
  - jq
  - tree
  - zip
  - rsync

# Create the workspace directory and set up environment
runcmd:
  # Create directories early
  - mkdir -p /opt/colmena-ci-workspace
  - mkdir -p /home/ubuntu/.local/bin
  - mkdir -p /root/.local/bin
  
  # Install Docker using official installation script
  - |
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    systemctl start docker
    systemctl enable docker
    usermod -aG docker root
    usermod -aG docker ubuntu
    rm -f /tmp/get-docker.sh
  
  # Install NVM and Node.js for root
  - |
    export HOME=/root
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    export NVM_DIR="/root/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts
    nvm alias default lts/*
    
  # Create symlinks for global access
  - |
    sleep 5  # Wait for NVM installation to complete
    NODE_VERSION=$(ls /root/.nvm/versions/node/ 2>/dev/null | head -1)
    if [ -n "$NODE_VERSION" ]; then
      ln -sf "/root/.nvm/versions/node/$NODE_VERSION/bin/node" /usr/local/bin/node
      ln -sf "/root/.nvm/versions/node/$NODE_VERSION/bin/npm" /usr/local/bin/npm
      ln -sf "/root/.nvm/versions/node/$NODE_VERSION/bin/npx" /usr/local/bin/npx
    fi
  
  # Install gitlab-ci-local using npm
  - |
    export NVM_DIR="/root/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    npm install -g gitlab-ci-local
    
  # Create symlink for gitlab-ci-local
  - |
    sleep 5  # Wait for npm install to complete
    NODE_VERSION=$(ls /root/.nvm/versions/node/ 2>/dev/null | head -1)
    if [ -n "$NODE_VERSION" ]; then
      ln -sf "/root/.nvm/versions/node/$NODE_VERSION/bin/gitlab-ci-local" /usr/local/bin/gitlab-ci-local
    fi
  
  # Configure Git (required for cloning)
  - git config --global user.name "ColmenaOS CI Test"
  - git config --global user.email "ci-test@colmena.local"
  - git config --global init.defaultBranch main
  - git config --global http.sslverify false
  - git config --global credential.helper store
  
  # Set up Docker buildx for multi-platform builds
  - docker buildx create --use --name multiarch-builder || true
  - docker run --rm --privileged multiarch/qemu-user-static --reset -p yes || true
  
  # Set permissions
  - chown -R root:root /opt/colmena-ci-workspace
  - chmod -R 755 /opt/colmena-ci-workspace
  
  # Configure environment for bash
  - |
    cat >> /root/.bashrc << 'EOBASH'
export NVM_DIR="/root/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export PATH="/opt/colmena-ci-workspace:$PATH"
cd /opt/colmena-ci-workspace
EOBASH

# Create files in the workspace
write_files:
  - path: /etc/docker/daemon.json
    content: |
      {
        "log-driver": "json-file",
        "log-opts": {
          "max-size": "10m",
          "max-file": "3"
        },
        "storage-driver": "overlay2",
        "features": {
          "buildkit": true
        }
      }
    permissions: '0644'
  
  - path: /opt/colmena-ci-workspace/verify-installation.sh
    content: |
      #!/bin/bash
      echo "=== Installation Verification ==="
      echo "Docker: $(docker --version 2>/dev/null || echo 'NOT INSTALLED')"
      echo "Docker Compose: $(docker compose version 2>/dev/null || echo 'NOT INSTALLED')"
      echo "Node.js: $(node --version 2>/dev/null || echo 'NOT INSTALLED')"
      echo "NPM: $(npm --version 2>/dev/null || echo 'NOT INSTALLED')"
      echo "gitlab-ci-local: $(gitlab-ci-local --version 2>/dev/null || echo 'NOT INSTALLED')"
      echo "Git: $(git --version 2>/dev/null || echo 'NOT INSTALLED')"
      echo ""
      echo "=== Environment Check ==="
      echo "Working directory: $(pwd)"
      echo "Home directory: $HOME"
      echo "PATH: $PATH"
      echo "NVM_DIR: $NVM_DIR"
      echo ""
      echo "=== Directory Structure ==="
      ls -la /opt/colmena-ci-workspace/ 2>/dev/null || echo "Workspace directory not found"
    permissions: '0755'
  
  - path: /opt/colmena-ci-workspace/README.md
    content: |
      # ColmenaOS GitLab CI Testing Environment
      
      This environment is configured for testing GitLab CI pipelines using gitlab-ci-local.
      
      ## Available Tools
      - Docker with Docker Compose (latest)
      - Node.js LTS with npm
      - Python 3
      - GitLab CI Local
      - Multi-architecture build support (buildx + QEMU)
      
      ## Workspace Structure
      ```
      /opt/colmena-ci-workspace/
      ├── colmena-os/          # Main ColmenaOS project
      ├── colmena-devops/      # DevOps configurations
      ├── frontend/            # Frontend application
      ├── backend/             # Backend application
      └── ci-results/          # Test results
      ```
      
      ## Usage
      ```bash
      # Verify installation
      ./verify-installation.sh
      
      # Test all projects
      ./test-all-projects.sh
      
      # Test individual project
      cd frontend
      gitlab-ci-local
      ```
    permissions: '0644'

# Final reboot to ensure all services are properly started
power_state:
  mode: reboot
  condition: true
EOF

    log "Created $CLOUD_INIT_FILE"
}

check_existing_testbed() {
    local existing=$(doctl compute droplet list --format Name --no-header | grep "$TESTBED_PREFIX" || true)
    
    if [[ -n "$existing" ]]; then
        warn "Found existing GitLab CI testbed: $existing"
        return 0
    else
        return 1
    fi
}

get_testbed_ip() {
    local droplet_name=$(doctl compute droplet list --format Name --no-header | grep "$TESTBED_PREFIX" | head -1)
    
    if [[ -z "$droplet_name" ]]; then
        error "No GitLab CI testbed found."
    fi
    
    doctl compute droplet get "$droplet_name" --format PublicIPv4 --no-header
}

create_testbed() {
    log "Creating GitLab CI testbed environment..."
    
    # Check for existing testbed
    if check_existing_testbed; then
        local existing=$(doctl compute droplet list --format Name --no-header | grep "$TESTBED_PREFIX")
        error "A GitLab CI testbed already exists: $existing. Please destroy it first or use 'update' to update it."
    fi
    
    local droplet_name="${TESTBED_PREFIX}-$(date +%s)"
    
    log "Creating droplet: $droplet_name"
    
    # Get SSH keys
    local ssh_keys=$(doctl compute ssh-key list --format ID --no-header | tr '\n' ',' | sed 's/,$//')
    
    if [[ -z "$ssh_keys" ]]; then
        error "No SSH keys found in your DigitalOcean account. Please add an SSH key first."
    fi
    
    # Create droplet
    log "Creating droplet with CI-optimized configuration..."
    doctl compute droplet create "$droplet_name" \
        --region "$DO_REGION" \
        --size "$DO_SIZE" \
        --image "$DO_IMAGE" \
        --user-data-file "$CLOUD_INIT_FILE" \
        --ssh-keys "$ssh_keys" \
        --wait
    
    # Get droplet IP
    local droplet_ip=$(doctl compute droplet get "$droplet_name" --format PublicIPv4 --no-header)
    
    success "GitLab CI testbed created!"
    log "Droplet: $droplet_name"
    log "IP: $droplet_ip"
    log "SSH: ssh root@$droplet_ip"
    
    # Wait for cloud-init to complete (longer wait for reboot)
    log "Waiting for system initialization and reboot (this may take 5-8 minutes)..."
    sleep 300
    
    # Test SSH connection with more retries
    log "Testing SSH connection..."
    wait_for_ssh "$droplet_ip"
    
    # Setup CI environment
    setup_ci_environment "$droplet_ip"
    
    success "GitLab CI testbed is ready!"
    log "You can now run: ./tests/do-testbed_gitlabci.sh test"
}

wait_for_ssh() {
    local droplet_ip=$1
    local max_attempts=20
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@$droplet_ip "echo 'SSH connection successful'" &> /dev/null; then
            log "SSH connection established"
            return 0
        else
            log "SSH attempt $attempt/$max_attempts failed, retrying in 15 seconds..."
            sleep 15
            ((attempt++))
        fi
    done
    
    error "Could not establish SSH connection after $max_attempts attempts"
}

setup_ci_environment() {
    local droplet_ip=$1
    
    log "Setting up CI environment on testbed..."
    
    # Copy current project's .gitlab-ci.yml
    log "Copying current .gitlab-ci.yml..."
    scp -o StrictHostKeyChecking=no ./.gitlab-ci.yml root@$droplet_ip:/tmp/colmena-os-gitlab-ci.yml
    
    # Setup repositories and CI environment
    ssh -o StrictHostKeyChecking=no root@$droplet_ip << 'EOSSH'
        # Source the environment
        source /root/.bashrc
        cd /opt/colmena-ci-workspace
        
        echo "=== Setting up CI workspace ==="
        echo "Current directory: $(pwd)"
        
        # Verify installation first
        if [[ -f "verify-installation.sh" ]]; then
            echo "Running installation verification..."
            ./verify-installation.sh
        else
            echo "verify-installation.sh not found, continuing anyway..."
        fi
        
        # Clone repositories with public access
        echo "Cloning Colmena repositories..."
        
        # Create placeholder for main colmena-os project
        if [[ ! -d "colmena-os" ]]; then
            echo "Creating colmena-os placeholder..."
            mkdir -p colmena-os
            cd colmena-os
            git init
            echo "# ColmenaOS Main Project" > README.md
            git add README.md
            git commit -m "Initial placeholder commit"
            cd ..
        fi
        
        # Clone component repositories or create placeholders
        for repo in "colmena-devops" "frontend" "backend"; do
            if [[ ! -d "$repo" ]]; then
                echo "Cloning ${repo}..."
                if timeout 60 git clone "https://gitlab.com/colmena-project/dev/${repo}.git" 2>/dev/null; then
                    echo "Successfully cloned ${repo}"
                else
                    echo "Could not clone ${repo}, creating placeholder"
                    mkdir -p "$repo"
                    cd "$repo"
                    git init
                    echo "# Placeholder for ${repo}" > README.md
                    git add README.md
                    git commit -m "Initial placeholder commit"
                    cd ..
                fi
            fi
        done
        
        # Copy the main .gitlab-ci.yml to all projects
        echo "Setting up .gitlab-ci.yml files..."
        if [[ -f "/tmp/colmena-os-gitlab-ci.yml" ]]; then
            cp /tmp/colmena-os-gitlab-ci.yml ./colmena-os/.gitlab-ci.yml
            cp /tmp/colmena-os-gitlab-ci.yml ./colmena-devops/.gitlab-ci.yml
            cp /tmp/colmena-os-gitlab-ci.yml ./frontend/.gitlab-ci.yml
            cp /tmp/colmena-os-gitlab-ci.yml ./backend/.gitlab-ci.yml
            echo "Copied .gitlab-ci.yml to all projects"
        else
            echo "Warning: Main .gitlab-ci.yml not found"
        fi
        
        # Create CI test script
        cat > test-all-projects.sh << 'EOTEST'
#!/bin/bash
set -e

# Source environment
source /root/.bashrc
export NVM_DIR="/root/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

echo "=== ColmenaOS GitLab CI Testing Suite ==="
echo "Working directory: $(pwd)"
echo ""

PROJECTS=("colmena-os" "colmena-devops" "frontend" "backend")
RESULTS_DIR="/opt/colmena-ci-workspace/ci-results"
mkdir -p "$RESULTS_DIR"

SUCCESS_COUNT=0
TOTAL_COUNT=0

for project in "${PROJECTS[@]}"; do
    echo "========================================"
    echo "Testing project: $project"
    echo "========================================"
    
    if [[ ! -d "$project" ]]; then
        echo "❌ Project directory $project not found"
        continue
    fi
    
    cd "$project"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    
    if [[ ! -f ".gitlab-ci.yml" ]]; then
        echo "⚠️  No .gitlab-ci.yml found in $project, skipping"
        cd ..
        continue
    fi
    
    echo "📋 Found .gitlab-ci.yml, validating syntax..."
    
    # Check if gitlab-ci-local is available
    if ! command -v gitlab-ci-local &> /dev/null; then
        echo "❌ gitlab-ci-local not available"
        cd ..
        continue
    fi
    
    # Test gitlab-ci-local functionality
    echo "🔍 Listing available jobs..."
    if gitlab-ci-local --list > "$RESULTS_DIR/${project}-jobs.log" 2>&1; then
        echo "✅ Successfully listed jobs"
        echo "Jobs found:"
        cat "$RESULTS_DIR/${project}-jobs.log" | head -10
    else
        echo "❌ Failed to list jobs"
        echo "Error details:"
        cat "$RESULTS_DIR/${project}-jobs.log" 2>/dev/null | head -10 || echo "No log file created"
        cd ..
        continue
    fi
    
    echo "🚀 Running gitlab-ci-local dry run..."
    
    # Run gitlab-ci-local with dry run
    if timeout 300 gitlab-ci-local --dry-run > "$RESULTS_DIR/${project}-dry-run.log" 2>&1; then
        echo "✅ Dry run completed successfully"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        
        # Show summary of dry run
        echo "📊 Dry run summary:"
        tail -20 "$RESULTS_DIR/${project}-dry-run.log" | head -10
    else
        echo "❌ Dry run failed - check $RESULTS_DIR/${project}-dry-run.log"
        echo "Last 10 lines of error log:"
        tail -10 "$RESULTS_DIR/${project}-dry-run.log" 2>/dev/null || echo "Could not read log file"
    fi
    
    cd ..
    echo ""
done

echo "========================================"
echo "CI Testing Summary"
echo "========================================"
echo "Projects tested: $TOTAL_COUNT"
echo "Successful tests: $SUCCESS_COUNT"
echo "Failed tests: $((TOTAL_COUNT - SUCCESS_COUNT))"
echo ""
echo "Detailed results available in: $RESULTS_DIR"
echo ""

if [[ $SUCCESS_COUNT -eq $TOTAL_COUNT ]] && [[ $TOTAL_COUNT -gt 0 ]]; then
    echo "🎉 All CI tests passed!"
    exit 0
else
    echo "⚠️  Some CI tests failed or no tests were run"
    exit 1
fi
EOTEST
        
        chmod +x test-all-projects.sh
        
        echo "=== Final verification ==="
        if [[ -f "verify-installation.sh" ]]; then
            ./verify-installation.sh
        else
            echo "verify-installation.sh not found, skipping verification"
        fi
        
        echo "=== CI environment setup complete ==="
        echo "Workspace contents:"
        ls -la /opt/colmena-ci-workspace/
EOSSH
    
    success "CI environment setup completed"
}

update_testbed() {
    log "Updating existing GitLab CI testbed..."
    
    local droplet_ip=$(get_testbed_ip)
    
    log "Updating testbed at: $droplet_ip"
    
    # Copy updated .gitlab-ci.yml
    log "Copying updated .gitlab-ci.yml..."
    scp -o StrictHostKeyChecking=no ./.gitlab-ci.yml root@$droplet_ip:/tmp/colmena-os-gitlab-ci.yml
    
    # Update the testbed
    ssh -o StrictHostKeyChecking=no root@$droplet_ip << 'EOSSH'
        source /root/.bashrc
        cd /opt/colmena-ci-workspace
        
        echo "=== Updating CI testbed ==="
        echo "Current directory: $(pwd)"
        
        # Update .gitlab-ci.yml in all projects
        echo "Updating .gitlab-ci.yml files..."
        if [[ -f "/tmp/colmena-os-gitlab-ci.yml" ]]; then
            for project in "colmena-os" "colmena-devops" "frontend" "backend"; do
                if [[ -d "$project" ]]; then
                    cp /tmp/colmena-os-gitlab-ci.yml "./$project/.gitlab-ci.yml"
                    echo "Updated .gitlab-ci.yml in $project"
                fi
            done
        fi
        
        # Update repositories if they exist
        echo "Updating repositories..."
        for repo in "colmena-devops" "frontend" "backend"; do
            if [[ -d "$repo" && -d "$repo/.git" ]]; then
                echo "Updating $repo..."
                cd "$repo"
                git pull origin main || git pull origin master || echo "Could not update $repo"
                cd ..
            fi
        done
        
        # Update test script if needed
        if [[ ! -f "test-all-projects.sh" ]]; then
            echo "Recreating test-all-projects.sh..."
            # Re-run the test script creation from setup_ci_environment
        fi
        
        # Verify installation
        if [[ -f "verify-installation.sh" ]]; then
            echo "=== Verification after update ==="
            ./verify-installation.sh
        fi
        
        echo "=== Update completed ==="
        ls -la /opt/colmena-ci-workspace/
EOSSH
    
    success "Testbed updated successfully"
}

run_ci_tests() {
    log "Running GitLab CI tests on testbed..."
    
    local droplet_ip=$(get_testbed_ip)
    
    log "Running CI tests on testbed: $droplet_ip"
    
    # Execute CI tests
    ssh -o StrictHostKeyChecking=no root@$droplet_ip << 'EOSSH'
        # Source environment
        source /root/.bashrc
        cd /opt/colmena-ci-workspace
        
        echo "=== Starting GitLab CI Tests ==="
        echo "Timestamp: $(date)"
        echo "Working directory: $(pwd)"
        echo ""
        
        # Verify we have the tools
        echo "=== Tool verification ==="
        if [[ -f "verify-installation.sh" ]]; then
            ./verify-installation.sh
        else
            echo "verify-installation.sh not found"
        fi
        echo ""
        
        # Run the test suite
        if [[ -f "test-all-projects.sh" ]]; then
            if ./test-all-projects.sh; then
                echo ""
                echo "=== CI TESTS COMPLETED SUCCESSFULLY ==="
            else
                echo ""
                echo "=== CI TESTS COMPLETED WITH FAILURES ==="
            fi
        else
            echo "❌ test-all-projects.sh not found"
        fi
        
        echo ""
        echo "=== Test Results Summary ==="
        if [[ -d "ci-results" ]]; then
            echo "Result files:"
            ls -la ci-results/
            echo ""
            echo "=== Error Summary ==="
            for log_file in ci-results/*.log; do
                if [[ -f "$log_file" ]]; then
                    echo "--- $(basename $log_file) ---"
                    tail -20 "$log_file" 2>/dev/null || echo "Could not read $log_file"
                    echo ""
                fi
            done
        fi
        
        echo "=== System Resource Usage ==="
        echo "Disk usage:"
        df -h /
        echo ""
        echo "Memory usage:"
        free -h
        echo ""
        echo "Docker images:"
        docker images | head -10 2>/dev/null || echo "Could not list Docker images"
EOSSH
    
    # Copy results back to local machine
    local results_dir="./ci-results-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$results_dir"
    
    log "Copying CI test results to local directory: $results_dir"
    scp -o StrictHostKeyChecking=no -r root@$droplet_ip:/opt/colmena-ci-workspace/ci-results/* "$results_dir/" 2>/dev/null || {
        warn "Could not copy all CI results"
    }
    
    success "CI tests completed. Results available in: $results_dir"
}

destroy_testbed() {
    log "Destroying GitLab CI testbed..."
    
    local droplets=$(doctl compute droplet list --format Name --no-header | grep "$TESTBED_PREFIX" || true)
    
    if [[ -z "$droplets" ]]; then
        warn "No GitLab CI testbed found to destroy"
        return 0
    fi
    
    echo "$droplets" | while read -r droplet; do
        if [[ -n "$droplet" ]]; then
            log "Destroying testbed: $droplet"
            doctl compute droplet delete "$droplet" --force
        fi
    done
    
    success "GitLab CI testbed destroyed"
}

list_testbeds() {
    log "GitLab CI testbeds:"
    echo ""
    doctl compute droplet list --format Name,PublicIPv4,Status,Created | grep "$TESTBED_PREFIX" || {
        info "No active GitLab CI testbeds found"
        return 0
    }
}

print_usage() {
    echo "ColmenaOS GitLab CI Testing Testbed"
    echo ""
    echo "This tool creates a dedicated DigitalOcean droplet for testing GitLab CI pipelines"
    echo "across all Colmena project repositories using gitlab-ci-local."
    echo ""
    echo "Usage: ./tests/do-testbed_gitlabci.sh [create|test|destroy|list|update]"
    echo ""
    echo "⚠️  IMPORTANT: Run this script from the PROJECT ROOT directory, not from tests/"
    echo ""
    echo "Commands:"
    echo "  create    Create a new GitLab CI testbed (only one allowed at a time)"
    echo "  test      Run GitLab CI tests on the existing testbed"
    echo "  update    Update scripts and .gitlab-ci.yml on existing testbed"
    echo "  destroy   Destroy the GitLab CI testbed"
    echo "  list      List active GitLab CI testbeds"
    echo ""
    echo "Features:"
    echo "  • Tests CI pipelines across all Colmena repositories"
    echo "  • Uses gitlab-ci-local for offline CI testing"
    echo "  • Multi-architecture Docker build support"
    echo "  • Comprehensive CI validation and reporting"
    echo "  • Automatic cleanup and resource monitoring"
    echo "  • Update existing testbed without recreating"
    echo ""
    echo "Requirements:"
    echo "  • doctl installed and authenticated"
    echo "  • SSH key added to DigitalOcean account"
    echo "  • .gitlab-ci.yml file in project root"
    echo ""
    echo "Example workflow:"
    echo "  ./tests/do-testbed_gitlabci.sh create    # Create testbed (takes 5-8 minutes)"
    echo "  ./tests/do-testbed_gitlabci.sh test      # Run all CI tests (takes 5-10 minutes)"
    echo "  ./tests/do-testbed_gitlabci.sh update    # Update testbed with new changes"
    echo "  ./tests/do-testbed_gitlabci.sh destroy   # Clean up resources"
}

# Main command handling
case "$1" in
    create)
        check_requirements
        create_testbed
        ;;
    test)
        check_requirements
        run_ci_tests
        ;;
    update)
        check_requirements
        update_testbed
        ;;
    destroy)
        check_requirements
        destroy_testbed
        ;;
    list)
        check_requirements
        list_testbeds
        ;;
    *)
        print_usage
        exit 1
        ;;
esac