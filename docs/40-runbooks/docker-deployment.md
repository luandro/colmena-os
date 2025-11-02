# Docker Deployment Runbook

**Audience:** operators and developers starting ColmenaOS via Docker or Docker Compose.  
**Prerequisites:** Docker Engine 24+, Docker Compose v2, access to `.env` secrets.

## Compose Flavours

### Production (`docker-compose.yml`)
- Pulls the published image `communityfirst/colmena-app:latest`.
- Suitable for CasaOS, Balena, or vanilla Docker hosts where image builds happen elsewhere.

```bash
docker compose up -d        # start
docker compose down         # stop
```

### Local Development (`docker-compose.local.yml`)
- Builds the unified image from source and runs the support services.
- Use the helper script for build + smoke tests:

```bash
cp .env.example .env              # populate secrets before the first run
scripts/test-compose-local.sh         # build, start, wait for health, run checks
TEARDOWN=1 scripts/test-compose-local.sh   # build, test, tear down
```

Manual invocation:

```bash
docker compose -f docker-compose.local.yml up -d --build
docker compose -f docker-compose.local.yml --project-name colmena ps
docker compose -f docker-compose.local.yml --project-name colmena down --remove-orphans
```

### Unified Stack Smoke Test (`docker-compose.yml`)
- Use `scripts/compose-smoke.sh` to verify health and endpoint reachability without manual curl commands.

```bash
ENV_EXPORT_PATH=smoke.env scripts/compose-smoke.sh   # starts stack, waits for health, records ports
source smoke.env                                     # exposes PLAYWRIGHT_* hints for e2e tooling
TEARDOWN=0 scripts/compose-smoke.sh                  # spin up without tearing down (pair with Playwright)
```

## Port Map

| Service        | Host Port | Notes                          |
|----------------|-----------|--------------------------------|
| Frontend (nginx) | 7180      | Primary UI                    |
| Backend (gunicorn) | 7100   | Direct API access             |
| PostgreSQL     | 7432      | External port (5432 internally)|
| pgAdmin        | 7050      | Database admin UI              |
| Nextcloud      | 7103/7104 | UI / API wrapper               |
| Mailcrab       | 7080/7025 | Web UI / SMTP                  |

Use `scripts/cleanup-local-ports.sh` (with `FORCE=1` to kill conflicts) if ports are busy.

## First-Run UX
1. Open `http://localhost:7180`.
2. Add a server pointing to `http://localhost:7180/api` (or the backend host port exported by `scripts/compose-smoke.sh`).
3. Log in with `SUPERADMIN_EMAIL` / `SUPERADMIN_PASSWORD` from `.env`.

For scripted startup without health verification, `scripts/up-local.sh` simply builds and starts the stack; complement it with `scripts/test-compose-local.sh` for smoke tests.

## Startup Behavior

The `colmena-app` container uses `start-backend.sh` which performs the following initialization steps:

1. **Database Setup** — Creates and migrates the PostgreSQL database with retry logic
2. **Seed Data** — Loads initial groups, permissions, languages, and regions
3. **Superadmin Creation** — Creates the superadmin user with Nextcloud app password
   - Uses exponential backoff retry (5 attempts, 2-30s delay)
   - Requires valid `NEXTCLOUD_ADMIN_PASSWORD` in `.env`
   - Logs success/failure explicitly to help with troubleshooting

If superadmin creation fails after retries, the container will exit with an error to prevent running without a superadmin user.

## Environment Checklist

- **Database:** `POSTGRES_PASSWORD`, `POSTGRES_USER`, `POSTGRES_DB`
- **Admin:** `PGADMIN_DEFAULT_PASSWORD`, `NEXTCLOUD_ADMIN_PASSWORD`, `SUPERADMIN_PASSWORD`
- **Secrets:** `SECRET_KEY`, `COLMENA_SECRET_KEY` (50+ random characters)

Additional overrides:
- `HTTP_PORT`, `BACKEND_PORT` for host mapping overrides.
- `DEBUG=true` for local debugging (not recommended for production).

## Single-Container Invocation

```bash
docker run -d \
  --name colmena-app \
  -p 80:80 -p 8000:8000 \
  -e DATABASE_URL=postgresql://user:pass@host:5432/db \
  -e SECRET_KEY=<secret> \
  -e COLMENA_SECRET_KEY=<secret> \
  -e SUPERADMIN_EMAIL=admin@colmena.org \
  -e SUPERADMIN_PASSWORD=<superadmin-password> \
  communityfirst/colmena-app:latest
```

## Updates
- Production: `docker compose pull && docker compose up -d`
- Local: `git pull && scripts/test-compose-local.sh`
- Balena promotion: follow the steps in [`../30-implementation/release-flow.md`](../30-implementation/release-flow.md) after draft validation.

## Troubleshooting
- `curl http://localhost:7180` should return 200; if not, inspect `colmena-app` logs.
- `/api/` returning 404 indicates nginx config missing the proxy block; rebuild the image to refresh `/etc/nginx/http.d/default.conf`.
- If `scripts/compose-smoke.sh` fails, review `smoke-report.md` for captured logs; Playwright artefacts land under `test-results/` and `playwright-report/`.
- For repeated port conflicts, run `scripts/cleanup-local-ports.sh` in dry run mode before forcing termination.

See [`../30-implementation/docker-compose.md`](../30-implementation/docker-compose.md) for architectural decisions underlying this runbook.
