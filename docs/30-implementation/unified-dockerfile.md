# Unified Dockerfile

**Related roadmap item:** ISSUE-001  
**Primary objective:** [2 — Ship a Unified Deployable Stack](../10-objectives.md#2-ship-a-unified-deployable-stack)

## Build Strategy
- Multi-stage build on `node:18-alpine` to compile both backend (Django REST + Gunicorn) and frontend (React PWA).
- Install `nginx` and `supervisor` to host static assets and keep backend running.
- Copy production build artifacts into `/opt/colmena/frontend` and `/opt/colmena/backend`.

## Process Supervision
`supervisord.conf` launches:
1. `gunicorn` (Django backend) on port `8000`.
2. `nginx` serving the compiled frontend from `/usr/share/nginx/html`.

Expose ports `8080` (frontend) and `8000` (backend) for compatibility with Docker Compose and CasaOS metadata.

## Health Checks
- Backend: `curl -f http://127.0.0.1:8000/api/health/`
- Frontend: `curl -f http://127.0.0.1:8080/`

## Build Args
- `BUILDPLATFORM` / `TARGETPLATFORM` to support Buildx multi-arch flows.
- `COLMENA_VERSION` to stamp images with SemVer.

For the earlier brainstorming and alternative approaches, refer to [`../context/unified-dockerfile.md`](../context/unified-dockerfile.md).
