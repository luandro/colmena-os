# Backlog

Last updated: 2025-11-02

## Critical Issues (PR #6 Blockers)
See `context/pr-6/TRACKING.md` for detailed tracking of PR #6 issues.

**Must Fix Before PR #6 Merge**:
- Issue #5a: Reduce postgres max_connections from 10000 to 100-200
- Issue #8: Fix Unix socket permissions from 777 to 660

## Resolved Issues
- **Issue #5b/5c**: Database connection retry and migration failure handling - RESOLVED ✅
  - Added retry logic with exponential backoff (2s-30s, 5 retries) to postgres.py
  - Added migration retry logic to start-backend.sh
  - Handles PostgreSQL startup delays gracefully with clear logging
  - See `context/issue-5b-5c-plan.md` and `context/issue-5b-5c-pr-comment.md`
- **Issue #7**: OpenAPI schema generation failures - RESOLVED ✅
  - Added strict validation for backend schema, frontend schema.json, and runtime schema
  - Emergency TypeScript definitions stub prevents namespace errors
  - Build fails immediately on invalid schemas with clear error messages
  - See `context/issue-7-resolution.md` and `context/issue-7-review.md`
- **Issue #18**: Broaden test coverage (DB failures, network partitions, etc.) - RESOLVED ✅
  - Added 4 new Playwright test files with 13 additional tests
  - DB migration failure handling tests (2 tests)
  - Network partition scenario tests (3 tests)
  - Volume permission and edge case tests (5 tests)
  - Load testing framework (3 tests)
  - See `context/issue-18-plan.md` for full documentation

## Active Initiatives
- Align CI workflows so `test-pipeline.yml` exercises the unified image and reports results alongside integration smoke tests.
- Determine long-term plan for docker-compose service testing that requires submodule build context (mail, nextcloud).

## Local Compose + OpenAPI Tasks
- Re-enable the frontend TypeScript checker once OpenAPI type generation runs reliably inside the container build.
- Add a CI job that runs `scripts/test-compose-local.sh` and uploads the resulting report when failures occur.
- Surface the backend OpenAPI version in the UI (e.g., via `/api/schema/version`).

## Frontend ↔ Backend UX
- Provide a default server URL (`http://localhost:7180/api`) on first run.
- Add a banner CTA to auto-configure the local server.
- Improve unauthenticated error messages (401/403) to guide users toward login or server selection.

## Developer Ergonomics
- Explore `docker compose watch` for faster inner-loop feedback.
- Extend runbooks with “quick diagnose” commands (logs, `docker compose ps`, `docker inspect`) for on-call use.

## Health & Observability
- Expose dedicated `/health/`, `/-/ready`, and `/-/live` endpoints and wire them into health checks.
- Introduce log rotation for nginx/gunicorn in production profiles.
- Document recommended Prometheus/Grafana exporters for devices running ColmenaOS.

## Security & Configuration
- Verify `ALLOWED_HOSTS` and `CSRF_TRUSTED_ORIGINS` cover all deployment domains and local ports.
- Document CORS/cookie expectations for HTTP (development) versus HTTPS (production).
- Capture a secrets management guide covering `.env`, CasaOS overrides, and Balena fleet variables.

## Documentation & Platform Alignment
- **CasaOS Metadata Alignment**: The CasaOS runbook assumes an `x-casaos` metadata block in the compose file, but `docker-compose.yml` omits it. Decide whether to add CasaOS annotations to compose file or revise runbook. (_NEXT_STEPS Finding #1_)
- **CasaOS Volume Naming**: CasaOS runbook volume names (`app_data`, `media_uploads`) differ from compose definitions (`media_data`, `static_data`). Reconcile documented volume list with compose file. (_NEXT_STEPS Finding #4_)
- **Nextcloud Dockerfile Warning**: `colmena-devops/devops/apps/nextcloud/builder/Dockerfile` references `FROM nextcloud:$NEXTCLOUD_VERSION-apache` which BuildKit flags as invalid default tag. Add default value or use `${NEXTCLOUD_VERSION}` syntax. (_NEXT_STEPS Finding #9_)

## Build Optimization
- **Unused Dockerfile Stage**: The Dockerfile defines `frontend-builder-schema` stage (lines 152-175) that is not consumed in final image. Trace original intent and either wire it in or remove for simplification. (_NEXT_STEPS Finding #6_)
- Optimize Docker build caching for faster pipelines (PR #6 Issue #15)
- Remove TypeScript sed workaround once OpenAPI generation is fixed (PR #6 Issue #11)

## Testing & Quality
- Add backend unit tests to CI (PR #6 Issue #12) - Excluded (submodule-related)
- Add container security scanning (Trivy/Grype/Snyk) to CI (PR #6 Issue #13) - RESOLVED ✅
- Add API integration tests (PR #6 Issue #17) - Excluded (submodule-related)
- Broaden test coverage: DB migration failures, network partitions, socket permissions, load/security testing (PR #6 Issue #18) - RESOLVED ✅

## Infrastructure & Deployment
- Remove Nextcloud `privileged: true`, use specific capabilities (PR #6 Issue #6)
- Consolidate nginx configs - choose embedded vs mounted approach (PR #6 Issue #9)
- Add nginx security headers (CSP, HSTS, etc.) (PR #6 Issue #10)
- Add resource constraints to docker-compose.yml (PR #6 Issue #16)
- Document `SECRET_KEY` vs `COLMENA_SECRET_KEY` responsibilities (PR #6 Issue #14)
- Create architecture diagram for documentation (PR #6 Issue #19)

See [`docs/20-roadmap.md`](docs/20-roadmap.md) for scheduled work and [`context/`](context) for scratch notes tied to future research.
