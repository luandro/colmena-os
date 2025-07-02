# Testing Guide for ColmenaOS CI/CD Pipeline

This document explains how to test the ColmenaOS CI/CD pipeline locally and on cloud infrastructure before deploying to production.

## 🎯 Testing Overview

ColmenaOS uses a comprehensive testing strategy that combines:

1. **Local Testing** with `act` (GitHub Actions local runner)
2. **Cloud Integration Testing** with Digital Ocean testbeds
3. **Automated Testing** via GitHub Actions workflows

## 📋 Prerequisites

### Local Development
```bash
# Install act (GitHub Actions local runner)
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# Verify Docker is running
docker --version

# Install doctl (Digital Ocean CLI)
# See: https://docs.digitalocean.com/reference/doctl/how-to/install/
```

### Digital Ocean Setup
```bash
# Authenticate with Digital Ocean
doctl auth init

# Verify authentication
doctl account get

# Add SSH key to your DO account (if not already done)
doctl compute ssh-key import --public-key-file ~/.ssh/id_rsa.pub
```

### Environment Configuration
```bash
# Copy and configure secrets for local testing
cp .secrets.example .secrets
# Edit .secrets with your actual credentials

# Copy and configure environment variables  
cp .env.example .env
# Edit .env with your configuration
```

## 🧪 Running Tests

### Quick Start
```bash
# Run complete test suite (local + integration)
./scripts/ci-test.sh full

# Run only local tests (fast feedback)
./scripts/ci-test.sh local

# Run only integration tests (cloud deployment)
./scripts/ci-test.sh integration
```

### Local Testing Only
```bash
# Test all workflows locally
./scripts/local-test.sh test-all

# Test specific workflow
./scripts/local-test.sh test-workflow build-and-push

# Test specific service build
./scripts/local-test.sh test-service frontend
```

### Cloud Integration Testing
```bash
# Create testbed for manual testing
./scripts/ci-test.sh create-testbed manual-test

# Connect to testbed
./tests/0_do-testbed_cli.sh connect manual-test

# Deploy ColmenaOS to testbed
./tests/0_do-testbed_cli.sh deploy manual-test

# Cleanup when done
./tests/0_do-testbed_cli.sh destroy manual-test
```

## 🔄 Automated Testing Workflows

### Test Pipeline (`test-pipeline.yml`)
Runs automatically on:
- Pull requests to `main` or `develop`
- Push to `main` or `develop`
- Manual trigger via `workflow_dispatch`

**Features:**
- Local workflow validation with `act`
- Digital Ocean testbed integration testing
- Health checks and deployment verification
- Automatic cleanup (can be disabled for debugging)

### Daily Update Checker (`daily-update-checker.yml`)
- Runs daily at 6 AM UTC
- Checks for submodule updates
- Triggers builds only when changes detected
- Commits submodule updates automatically

### Build and Push (`build-and-push.yml`)
- Multi-architecture Docker builds (AMD64/ARM64)
- Pushes to Docker Hub with caching
- Triggers Balena draft deployment
- Smart service selection based on changes

## 📊 Test Types Explained

### 1. Local Tests (act)
**Purpose**: Fast feedback loop for workflow validation  
**Duration**: 2-5 minutes  
**Coverage**:
- GitHub Actions workflow syntax validation
- Secret/environment variable validation
- Docker build preparation
- Multi-arch build setup

```bash
# Run specific local tests
./scripts/local-test.sh check           # Prerequisites
./scripts/local-test.sh test-all        # All workflows
./scripts/local-test.sh test-service frontend  # Single service
```

### 2. Integration Tests (Digital Ocean)
**Purpose**: Real cloud environment testing  
**Duration**: 10-15 minutes  
**Coverage**:
- Docker builds on cloud infrastructure
- Full ColmenaOS deployment
- Service health checks
- Network connectivity
- Resource usage validation

```bash
# Run integration tests
./scripts/ci-test.sh integration

# Create testbed for debugging
./scripts/ci-test.sh create-testbed debug-test --no-cleanup
```

### 3. End-to-End Tests (Manual)
**Purpose**: Full production-like validation  
**Duration**: 20-30 minutes  
**Coverage**:
- Balena draft deployment
- Real device testing
- Audio recording/editing functionality
- Offline capability validation

## 🛠️ Debugging Failed Tests

### Local Test Failures
```bash
# Enable verbose output
ACT_VERBOSE=true ./scripts/local-test.sh test-all

# Run act directly for debugging
act push --secret-file .secrets --verbose

# Check act configuration
cat .actrc
```

### Integration Test Failures
```bash
# Create testbed without auto-cleanup
./scripts/ci-test.sh create-testbed debug-$(date +%s) --no-cleanup

# Connect to testbed for investigation
./tests/0_do-testbed_cli.sh connect debug-testbed

# Check container logs
docker compose logs -f

# Test individual components
docker compose ps
docker compose exec backend python manage.py check
```

### GitHub Actions Failures
```bash
# Test workflow locally first
act push --secret-file .secrets --job build

# Check workflow files syntax
act --list --workflows .github/workflows/build-and-push.yml

# Validate environment variables
echo "Check secrets in GitHub repository settings"
```

## 📈 Performance Optimization

### Local Testing
```bash
# Use Docker layer caching
export DOCKER_BUILDKIT=1

# Limit platforms for faster builds
export PLATFORMS=linux/amd64  # Skip ARM64 for local testing

# Use smaller testbed size
export DO_SIZE=s-1vcpu-1gb  # Cheaper for testing
```

### Cost Management
```bash
# Auto-cleanup testbeds
DO_CLEANUP=true ./scripts/ci-test.sh integration

# List and cleanup orphaned testbeds
./tests/0_do-testbed_cli.sh list
./scripts/ci-test.sh cleanup
```

## 🔒 Security Considerations

### Secret Management
- Never commit `.secrets` file to git
- Use GitHub repository secrets for CI/CD
- Rotate API tokens regularly
- Use least privilege access

### Testbed Security
- Testbeds are automatically destroyed after testing
- Use secure passwords for test environments
- Don't deploy production data to testbeds
- Monitor DO spending limits

## 📝 Common Commands Reference

```bash
# Complete test suite
./scripts/ci-test.sh full

# Local only (fastest)
./scripts/local-test.sh test-all

# Create and test on cloud
./scripts/ci-test.sh create-testbed test-$(date +%s)
./tests/0_do-testbed_cli.sh deploy test-$(date +%s)

# Cleanup everything
./scripts/ci-test.sh cleanup

# Debug specific workflow
act push --secret-file .secrets --job build --verbose

# Check testbed status
./tests/0_do-testbed_cli.sh list

# Emergency cleanup (all testbeds)
doctl compute droplet list | grep colmena-testbed | awk '{print $2}' | xargs -r doctl compute droplet delete --force
```

## 🚀 Testing Before Phase 2

Before moving to Phase 2 (production deployment), ensure:

1. ✅ All local tests pass consistently
2. ✅ Integration tests complete successfully  
3. ✅ Docker multi-arch builds work
4. ✅ All GitHub Actions workflows validate
5. ✅ Testbed deployments are stable
6. ✅ Resource usage is within acceptable limits
7. ✅ Security configurations are correct

Run the full test suite:
```bash
./scripts/ci-test.sh full
```

Expected output: All tests passing with no failures or warnings.

## 📞 Getting Help

- **Local issues**: Check `./scripts/local-test.sh help`
- **Integration issues**: Check `./scripts/ci-test.sh help`  
- **Testbed issues**: Check `./tests/0_do-testbed_cli.sh` (no args for help)
- **GitHub Actions**: Check workflow logs in Actions tab

For detailed logs, always run with verbose flags and check individual component outputs.