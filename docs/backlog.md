# Backlog

Last updated: 2025-10-28

## Active Initiatives
- Align CI workflows so `test-pipeline.yml` exercises the unified image and reports results alongside integration smoke tests.
- Determine long-term plan for docker-compose service testing that requires submodule build context (mail, nextcloud).
- Capture operational runbooks for CasaOS and Balena deployments building on [`docs/40-runbooks/docker-deployment.md`](docs/40-runbooks/docker-deployment.md), including fleet variables and rollback steps.

## Local Compose + OpenAPI Tasks
- Re-enable the frontend TypeScript checker once OpenAPI type generation runs reliably inside the container build.
- Generate `schema-runtime.json` and `Definitions.d.ts` during the frontend build directly from the backend schema.
- Add a CI job that runs `scripts/test-compose-local.sh` and uploads the resulting report when failures occur.
- Surface the backend OpenAPI version in the UI (e.g., via `/api/schema/version`).

## Frontend ↔ Backend UX
- Provide a default server URL (`http://localhost:7180/api`) on first run.
- Add a banner CTA to auto-configure the local server.
- Improve unauthenticated error messages (401/403) to guide users toward login or server selection.

## Developer Ergonomics
- Integrate `scripts/cleanup-local-ports.sh` as a pre-flight step in `scripts/test-compose-local.sh` (dry run + optional `FORCE=1`).
- Add Makefile shortcuts: `up-local`, `test-local`, `down-local`, `clean-ports`.
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

See [`docs/20-roadmap.md`](docs/20-roadmap.md) for scheduled work and [`context/`](context) for scratch notes tied to future research.
