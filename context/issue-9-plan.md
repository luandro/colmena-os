# Issue #9 - Nginx Config Consolidation - Implementation Plan

**Date**: 2025-10-31
**Status**: In Progress

## Understanding

**Root Cause**:
- Nginx configuration is duplicated in two places:
  1. Embedded in Dockerfile (lines 162-193) - writes to `/etc/nginx/http.d/default.conf`
  2. Mounted from `./docker/` via docker-compose.yml (lines 165-167)
- The embedded and mounted configs are identical (minus RUN command wrapper), creating drift risk

**Files to Modify**:
- `Dockerfile` - Remove embedded nginx config creation
- `docker/colmena-app-nginx.conf` - Keep as authoritative source, add comments
- `docker/colmena-app-nginx-default-http.conf` - Keep as authoritative source
- Documentation updates

**Decision: Use MOUNTED config as authoritative**
- Better for development (can override without rebuild)
- Docker best practice (config external to image)
- More flexible for different environments

## Implementation Steps

### Step 1: Update Dockerfile
- [x] Remove the embedded nginx config RUN command (lines 162-193)
- [x] Keep nginx package installation
- [x] Keep other configurations (supervisor, healthcheck, etc.)

### Step 2: Enhance Mounted Config Files
- [x] Add comments to `docker/colmena-app-nginx.conf` explaining the configuration
- [x] Ensure `docker/colmena-app-nginx-default-http.conf` is the primary config
- [x] Keep `docker/colmena-app-nginx-disable.conf` as disabled placeholder
- [x] Fixed duplicate default_server conflict by removing from colmena.conf

### Step 3: Documentation Updates
- [x] Update README.md to document nginx config location
- [x] Add guidance on how to customize nginx config

### Step 4: Validation
- [x] Build image and test with `docker compose up`
- [x] Verify nginx serves frontend correctly (curl -I localhost:7180 → 200 OK)
- [x] Verify API proxy works (curl -I localhost:7180/api/ → 502/404 from backend)
- [x] Run smoke tests - PASSED (1 test passed)

## Ready for Review Checklist

- [x] Tests executed successfully
  - Manual curl tests: Frontend (200 OK), Backend (302 redirect), API proxy (404)
  - Smoke test suite: PASSED (1/1 test)
- [x] Documentation updated
  - README.md: Added "Nginx Configuration" section with location and customization instructions
  - docker/colmena-app-nginx.conf: Added detailed comments explaining the configuration
  - docker/colmena-app-nginx-default-http.conf: Added detailed comments
- [x] Code changes reviewed
  - Dockerfile: Removed embedded nginx config, added reference note
  - docker/colmena-app-nginx.conf: Removed default_server directive to avoid conflict
  - docker/colmena-app-nginx-default-http.conf: Populated with proper configuration
- [x] Outstanding follow-up work
  - None - all acceptance criteria met

## Summary of Changes

**Problem Solved**: Nginx configuration was duplicated between embedded Dockerfile config and mounted compose configs, creating drift risk.

**Solution Implemented**: Consolidated to use MOUNTED configs as authoritative source:
- Removed embedded nginx config from Dockerfile
- Enhanced both mounted config files with detailed comments
- Fixed duplicate default_server conflict (kept in default.conf, removed from colmena.conf)
- Added README documentation for contributors

**Testing Results**:
- Build: SUCCESS
- Stack startup: SUCCESS
- Frontend serving: 200 OK
- API proxy: FUNCTIONAL
- Playwright smoke tests: 1/1 PASSED

**Files Modified**:
1. Dockerfile (removed embedded config, ~32 lines removed)
2. docker/colmena-app-nginx.conf (added comments, removed default_server)
3. docker/colmena-app-nginx-default-http.conf (added configuration + comments)
4. README.md (added nginx configuration section)

**Validation**: All acceptance criteria met. Stack runs correctly with single authoritative nginx configuration source.

## Risks & Open Questions
- Need to verify the mounted configs override the default nginx config properly
- Ensure no other parts of the system depend on the embedded config

## Test Commands
```bash
# Build and run
docker compose -f docker-compose.yml -f docker-compose.local.yml build colmena-app
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d

# Test nginx
curl -I localhost:7180
curl -I localhost:7180/api/

# Run smoke tests
./scripts/run-playwright-smoke.sh
```
