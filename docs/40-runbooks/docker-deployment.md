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
2. Add a server pointing to `http://localhost:7180/api`.
3. Log in with `SUPERADMIN_EMAIL` / `SUPERADMIN_PASSWORD` from `.env`.

For scripted startup without health verification, `scripts/up-local.sh` simply builds and starts the stack; complement it with `scripts/test-compose-local.sh` for smoke tests.

## Environment Checklist

```env
# Database
POSTGRES_PASSWORD=...
POSTGRES_USER=colmena
POSTGRES_DB=colmena

# Admin
PGADMIN_DEFAULT_PASSWORD=...
NEXTCLOUD_ADMIN_PASSWORD=...
SUPERADMIN_PASSWORD=...

# Secrets
SECRET_KEY=50-char-random-string
```

Additional overrides:
- `HTTP_PORT`, `BACKEND_PORT` for host mapping overrides.
- `DEBUG=true` for local debugging (not recommended for production).

## Single-Container Invocation

```bash
docker run -d \
  --name colmena-app \
  -p 80:80 -p 8000:8000 \
  -e DATABASE_URL=postgresql://user:pass@host:5432/db \
  -e SECRET_KEY=your-secret-key \
  -e SUPERADMIN_EMAIL=admin@colmena.org \
  -e SUPERADMIN_PASSWORD=change_me \
  communityfirst/colmena-app:latest
```

## Updates
- Production: `docker compose pull && docker compose up -d`
- Local: `git pull && scripts/test-compose-local.sh`

## Troubleshooting
- `curl http://localhost:7180` should return 200; if not, inspect `colmena-app` logs.
- `/api/` returning 404 indicates nginx config missing the proxy block; rebuild the image to refresh `/etc/nginx/http.d/default.conf`.
- If Playwright or smoke tests fail, check artefacts under `test-results/` and `playwright-report/`.
- For repeated port conflicts, run `scripts/cleanup-local-ports.sh` in dry run mode before forcing termination.

See [`../30-implementation/docker-compose.md`](../30-implementation/docker-compose.md) for architectural decisions underlying this runbook.
