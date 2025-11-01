# ColmenaOS Unified Stack

This repo bundles the Colmena frontend, backend, and supporting services into a single Docker Compose deployment. It is the canonical place to run Colmena locally, exercise end-to-end tests, and assemble the unified Docker image that we ship to downstream platforms. Product guidance (audio workflows, user manuals, etc.) lives in the upstream Colmena documentation; this README keeps the engineering view scoped to the stack itself.

## Goals

- Provide a reproducible Compose stack that matches our production Balena deployment.
- Ship a single `colmena-app` image with the Django backend and Vite-built React frontend behind nginx.
- Configure Postgres, Nextcloud, Mailcrab, and pgAdmin with sane defaults for smoke tests.
- Make Playwright smoke tests and CI workflows easy to run locally.

## Services & Ports

| Service            | Purpose                                   | Host Ports (default) |
|--------------------|-------------------------------------------|----------------------|
| `colmena-app`      | Unified frontend + backend (`nginx`+Django) | 7180 (HTTP), 7100 (API) |
| `postgres`         | Application database                      | 7432                 |
| `pgadmin`          | Database admin UI                         | 7050                 |
| `nextcloud`        | Media storage + API wrapper               | 7103 (UI), 7104 (API) |
| `mail` (Mailcrab)  | SMTP sink + web UI                        | 7025 (SMTP), 7080 (UI) |

All ports are overridable through `.env`; the defaults above match `.env.example` and Playwright expectations.

## Prerequisites

- Docker Engine 24+
- Docker Compose plugin 2.20+
- Git (with submodule support)
- Node.js 20.x (only required for frontend lint/tests or Vite builds)

## Clone & Configure

```bash
git clone --recursive https://github.com/colmena-project/colmena-os.git
cd colmena-os

# If you cloned without --recursive
# git submodule update --init --recursive

cp .env.example .env
# Replace every CHANGE_ME with secure values
```

Key environment defaults:

| Variable               | Default                                        | Notes |
|------------------------|------------------------------------------------|-------|
| `HTTP_PORT`            | `7180`                                         | nginx / frontend |
| `BACKEND_PORT`         | `7100`                                         | Gunicorn API |
| `POSTGRES_HOST_PORT`   | `7432`                                         | Exposes Postgres locally |
| `SUPERADMIN_EMAIL`     | `admin@example.com`                            | Consumed by smoke tests |
| `SUPERADMIN_PASSWORD`  | `CHANGE_ME`                                    | Set before first boot |
| `CORS_ALLOWED_ORIGINS` | `http://localhost:7180,http://127.0.0.1:7180,...` | Must include frontend origins |

## Compose Files

- `docker-compose.yml` uses the published Docker Hub image (`communityfirst/colmena-app:latest`).
- `docker-compose.local.yml` rebuilds `colmena-app` from the local sources and exposes developer-friendly ports.

You can combine them to reuse shared service definitions while swapping the app image:

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
```

## Running the Stack

### Using the published image

```bash
docker compose up -d
docker compose logs -f colmena-app  # wait for "Starting colmena" in the output
```

### Building from source

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml build colmena-app
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
```

### Tear down

```bash
docker compose down --volumes
# or, if you used both files:
docker compose -f docker-compose.yml -f docker-compose.local.yml down --volumes
```

## Smoke Testing

`./scripts/run-playwright-smoke.sh` automates the full smoke loop:

```bash
./scripts/run-playwright-smoke.sh            # build, boot, test, tear down
./scripts/run-playwright-smoke.sh --keep-up  # leave the stack running afterwards
./scripts/run-playwright-smoke.sh -- --grep "connects server"  # pass extra flags to Playwright
```

The script expects the defaults from `.env.example`. If you override credentials or ports, export matching `PLAYWRIGHT_*` environment variables before running it (see `tests/playwright/tests/app.smoke.spec.ts`).

## Development Notes

- The frontend submodule temporarily tracks `git@gitlab.com:luandro/frontend.git` on branch `fix-openapi-status-fallback` while the upstream PR is under review.
- Running `npm install` within `frontend/` triggers OpenAPI client generation; ensure the backend schema is reachable (bring the stack up) or install with `--ignore-scripts` and regenerate later.

### Nginx Configuration

- **Bundled default**: `docker/colmena-app-nginx-default-http.conf` (copied into `/etc/nginx/http.d/default.conf` during the image build)
- **Compose override**: `docker/colmena-app-nginx.conf` mounts to `/etc/nginx/http.d/colmena.conf` as an empty override hook for local tweaks
- **Customization**: Copy the default server block (or mount your own file) and restart with `docker compose restart colmena-app`

### Security Headers

The nginx configuration includes baseline security headers to protect against common web vulnerabilities:

- **Content-Security-Policy** (CSP): Controls which resources the browser is allowed to load
- **Strict-Transport-Security** (HSTS): Enforces HTTPS connections (max-age=31536000)
- **X-Content-Type-Options**: Prevents MIME type sniffing attacks
- **X-Frame-Options**: Protects against clickjacking (set to SAMEORIGIN)
- **Referrer-Policy**: Controls referrer information sent with requests
- **Permissions-Policy**: Restricts browser features like geolocation, microphone, and camera

The default CSP is configured to work with the React frontend while maintaining security. To customize the Content-Security-Policy, you can override the nginx config by mounting a custom configuration in `docker/colmena-app-nginx.conf`.

Verify headers are present:

```bash
curl -I localhost:7180 | grep -i "content-security-policy"
curl -I localhost:7180 | grep -i "strict-transport"

### Backend Scripts

The `colmena-app` container provides two startup scripts:

- **`/opt/app/start-backend.sh`** (canonical) – Main startup script used by supervisor. Handles privilege dropping, database setup, migrations, and gunicorn startup. Runs backend as non-root `colmena` user.
- **`/opt/app/entrypoint.sh`** (legacy) – Available for manual management commands. Example: `docker compose exec colmena-app /opt/app/entrypoint.sh migrate`.

For production use, `start-backend.sh` is the recommended script as it includes security improvements and better error handling.

## Useful Commands

```bash
docker compose logs -f colmena-app          # tail nginx + gunicorn logs
docker compose exec colmena-app sh          # open a shell in the unified container
docker compose logs -f postgres             # watch database activity
```

## Documentation Map

- [docs/index.md](docs/index.md) – objectives, roadmap, high-level guidance.
- [docs/30-implementation/](docs/30-implementation/README.md) – Dockerfile/compose/CI details.
- [docs/40-runbooks/](docs/40-runbooks/README.md) – operational runbooks for Docker, CasaOS, Balena, etc.
- [tests/playwright/](tests/playwright) – smoke scenarios and support scripts.
- `context/` – scratch notes to be promoted into docs.

## Contributing & License

See [CONTRIBUTING.md](CONTRIBUTING.md) for coding standards and review expectations (note the submodule policy in `CLAUDE.md`). ColmenaOS is released under the MIT License; view [LICENSE](LICENSE) for the full text.
