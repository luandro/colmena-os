# Overview

ColmenaOS is an offline-first operating system tailored for community radio and podcasting. The project ships a unified container stack that bundles the web frontend, Django backend, storage, email, and supporting services so communities can operate without continuous internet access.

## Architecture Snapshot
- **Frontend**: React progressive web app served by nginx.
- **Backend**: Django REST API behind gunicorn.
- **Support services**: PostgreSQL, Nextcloud for media storage, Mailcrab for email testing, optional pgAdmin.
- **Orchestration**: Docker Compose for local and production deployments; Balena and CasaOS reuse the same compose definition.
- **Containment**: A single “colmena-app” image hosts frontend + backend via supervisor.

See [`docs/30-implementation/docker-compose.md`](./30-implementation/docker-compose.md) for service wiring and ports.

## Repository Layout (high level)
- `frontend/`, `backend/`, `colmena-devops/`: upstream submodules that provide core application code and infra definitions.
- `Dockerfile`: builds the unified container image.
- `docker-compose.yml`, `docker-compose.local.yml`: production vs. local compose manifests.
- `docs/`: canonical documentation (objectives, roadmap, implementation guides).
- `context/`: scratchpads for work-in-progress notes.

## Key Flows
- **Developer loop**: build & run via `scripts/test-compose-local.sh` (see [`docs/40-runbooks/docker-deployment.md`](./40-runbooks/docker-deployment.md)).
- **Release pipeline**: multi-arch builds with GitHub Actions followed by Balena fleet promotion (diagrammed in [`docs/30-implementation/release-flow.md`](./30-implementation/release-flow.md)).
- **Operations**: deploy the published image or the compose stack using the runbooks in `docs/40-runbooks/`.

Use the README for quickstarts and this directory for deeper implementation detail.
