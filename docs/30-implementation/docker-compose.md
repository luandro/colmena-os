# Docker Compose Integration

**Related roadmap items:** ISSUE-001, ISSUE-002  
**Primary objective:** [2 — Ship a Unified Deployable Stack](../10-objectives.md#2-ship-a-unified-deployable-stack)

## Target Layout

```yaml
services:
  colmena-app:
    image: colmena/unified:latest
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8080:8080"   # Frontend
      - "7100:8000"   # Backend
    depends_on:
      - postgres
      - nextcloud
      - mail
    networks:
      - colmena_devops
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/"]
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

## Acceptance
- `docker compose up` from repo root spins up all services without manual edits.
- Health checks report healthy within 3 retries.
- `tests/compose-smoke/` passes against this layout.

See [`../context/docker-compose-merge.md`](../context/docker-compose-merge.md) for exploratory notes that fed this decision.
