# Docker Compose Integration

**Related roadmap items:** ISSUE-001, ISSUE-002  
**Primary objective:** [2 — Ship a Unified Deployable Stack](../10-objectives.md#2-ship-a-unified-deployable-stack)

## Target Layout

```yaml
services:
  colmena-app:
    image: communityfirst/colmena-app:latest
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "${HTTP_PORT:-7180}:80"    # Frontend (nginx)
      - "${BACKEND_PORT:-7100}:8000"  # Backend (gunicorn)
    depends_on:
      - postgres
      - nextcloud
      - mail
    networks:
      - colmena_devops
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:80/"]
      interval: 30s
      timeout: 10s
      retries: 3

  postgres:
    image: postgres:13-alpine
    volumes:
      - pg_data:/var/lib/postgresql/data

  pgadmin:
    image: dpage/pgadmin4:latest
    depends_on:
      - postgres

  nextcloud:
    image: nextcloud:stable-apache
    depends_on:
      - postgres

  mail:
    image: colmena/mail:latest
```

Shared `x-casaos` metadata is attached to `colmena-app` so CasaOS reads compose annotations without requiring a forked file.

## Default Ports

| Service        | Host Port | Container Port | Notes                    |
|----------------|-----------|----------------|--------------------------|
| Frontend (nginx) | 7180      | 80             | Main UI                  |
| Backend (gunicorn) | 7100   | 8000           | Direct API access        |
| PostgreSQL     | 7432      | 5432           | External vs internal gap |
| pgAdmin        | 7050      | 80             | Optional admin UI        |
| Nextcloud      | 7103/7104 | 80/5001        | UI / API wrapper         |
| Mailcrab       | 7080/7025 | 1080/1025      | Web UI / SMTP            |

Adjust the host ports via environment overrides (`HTTP_PORT`, `BACKEND_PORT`, etc.) when conflicts arise. Use `scripts/cleanup-local-ports.sh` to diagnose occupied ports.

## Environment Expectations
- The unified container reads `DATABASE_URL`, `SECRET_KEY`, and super-admin credentials from `.env`.
- Support services (postgres, nextcloud, mail) expect the standard variables exported in the sample `.env.example`.
- CasaOS metadata attaches to `colmena-app`, so keep the `x-casaos` block in sync with CasaOS requirements.

## Acceptance
- `docker compose up` from repo root spins up all services without manual edits.
- Health checks report healthy within 3 retries.
- `tests/compose-smoke/` passes against this layout.

See [`../context/docker-compose-merge.md`](../context/docker-compose-merge.md) for exploratory notes that fed this decision.
