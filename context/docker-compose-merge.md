# Docker Compose Merge

## Overview
Strategy for merging the ColmenaOS app service with existing devops services into a single docker-compose.yml.

## Related Documents
- [unified-dockerfile.md](./unified-dockerfile.md) - Single container implementation
- [service-networking.md](./service-networking.md) - Network configuration
- [casaos-metadata.md](./casaos-metadata.md) - CasaOS compatibility

## Current Services (from colmena-devops)

```yaml
services:
  postgres:       # Port 5432 - Database
  pgadmin:        # Port 5050 - Database admin
  nextcloud:      # Ports 8003, 8004 - File storage
  mail:           # Ports 1080, 1025 - Mail service
```

## Target Unified Compose

```yaml
# docker-compose.yml (root directory)
version: '3.8'

x-casaos: &casaos-annotations
  # CasaOS metadata for app store
  casaos:
    architectures:
      - amd64
      - arm64
    main: colmena-app
    store_app_id: colmena-os
    category: Media
    author: Colmena Project
    icon: https://raw.githubusercontent.com/luandro/colmena-os/main/icon.png

services:
  # ----------------------------------------------------------------------------
  # Main Colmena Application (Frontend + Backend)
  #
  colmena-app:
    <<: *casaos-annotations
    container_name: colmena_app
    image: colmena/unified:latest
    build:
      context: .
      dockerfile: Dockerfile
      args:
        - BUILDPLATFORM=${BUILDPLATFORM:-linux/amd64}
        - TARGETPLATFORM=${TARGETPLATFORM:-linux/amd64}
    ports:
      - "8080:8080"  # Frontend
      - "3000:3000"  # Backend API
    environment:
      # Backend configuration
      - NODE_ENV=${NODE_ENV:-production}
      - DATABASE_URL=postgresql://${POSTGRES_USERNAME}:${POSTGRES_PASSWORD}@postgres:5432/colmena
      - NEXTCLOUD_URL=http://nextcloud:80
      - MAIL_HOST=mail
      - MAIL_PORT=1025
      
      # Frontend configuration  
      - API_URL=${API_URL:-http://localhost:3000}
      - PUBLIC_URL=${PUBLIC_URL:-http://localhost:8080}
    depends_on:
      - postgres
      - nextcloud
      - mail
    volumes:
      - app_data:/app/data
      - media_uploads:/app/uploads
    restart: unless-stopped
    networks:
      colmena_devops:
        aliases:
          - app
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  # ----------------------------------------------------------------------------
  # Database Services
  #
  postgres:
    image: postgres:13-alpine
    command: postgres -c 'max_connections=200'
    container_name: colmena_postgres
    hostname: ${POSTGRES_HOSTNAME:-postgres}
    environment:
      POSTGRES_USER: ${POSTGRES_USERNAME:-colmena}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-changeme}
      POSTGRES_DB: colmena
    ports:
      - "5432:5432"
    volumes:
      - pg_data:/var/lib/postgresql/data
      - ./scripts/init-db.sql:/docker-entrypoint-initdb.d/init.sql
    restart: unless-stopped
    networks:
      colmena_devops:
        aliases:
          - postgres
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USERNAME:-colmena}"]
      interval: 10s
      timeout: 5s
      retries: 5

  pgadmin:
    container_name: colmena_pgadmin
    image: dpage/pgadmin4:latest
    environment:
      PGADMIN_DEFAULT_EMAIL: ${PGADMIN_DEFAULT_EMAIL:-admin@colmena.local}
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_DEFAULT_PASSWORD:-admin}
      PGADMIN_CONFIG_SERVER_MODE: 'False'
    ports:
      - "5050:80"
    volumes:
      - pgadmin_data:/var/lib/pgadmin
    depends_on:
      - postgres
    restart: unless-stopped
    networks:
      colmena_devops:
        aliases:
          - pgadmin

  # ----------------------------------------------------------------------------
  # Storage Service
  #
  nextcloud:
    container_name: colmena_nextcloud
    image: nextcloud:stable-apache
    environment:
      - POSTGRES_HOST=postgres
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=${POSTGRES_USERNAME:-colmena}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-changeme}
      - NEXTCLOUD_ADMIN_USER=${NEXTCLOUD_ADMIN_USER:-admin}
      - NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD:-admin}
      - NEXTCLOUD_TRUSTED_DOMAINS=${NEXTCLOUD_TRUSTED_DOMAINS:-localhost}
    ports:
      - "8003:80"
    volumes:
      - nextcloud_data:/var/www/html
    depends_on:
      - postgres
    restart: unless-stopped
    networks:
      colmena_devops:
        aliases:
          - nextcloud

  # ----------------------------------------------------------------------------
  # Mail Service
  #
  mail:
    container_name: colmena_mail
    image: maildev/maildev:latest
    ports:
      - "1080:1080"  # Web interface
      - "1025:1025"  # SMTP
    environment:
      - MAILDEV_INCOMING_USER=${MAIL_USER:-}
      - MAILDEV_INCOMING_PASS=${MAIL_PASS:-}
    restart: unless-stopped
    networks:
      colmena_devops:
        aliases:
          - mail

networks:
  colmena_devops:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 172.20.0.0/16

volumes:
  app_data:
    driver: local
  media_uploads:
    driver: local
  pg_data:
    driver: local
  pgadmin_data:
    driver: local
  nextcloud_data:
    driver: local
```

## Environment File (.env)

```bash
# .env.example
# Database
POSTGRES_HOSTNAME=postgres
POSTGRES_USERNAME=colmena
POSTGRES_PASSWORD=secure_password_here

# PgAdmin
PGADMIN_DEFAULT_EMAIL=admin@colmena.local
PGADMIN_DEFAULT_PASSWORD=admin_password

# Nextcloud
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=admin_password
NEXTCLOUD_TRUSTED_DOMAINS=localhost,colmena.local

# Mail
MAIL_USER=
MAIL_PASS=

# Application
NODE_ENV=production
API_URL=http://localhost:3000
PUBLIC_URL=http://localhost:8080

# Ports (optional overrides)
FRONTEND_PORT=8080
BACKEND_PORT=3000
```

## Service Dependencies

```mermaid
graph TD
    A[colmena-app] --> B[postgres]
    A --> C[nextcloud]
    A --> D[mail]
    E[pgadmin] --> B
    C --> B
```

## Network Configuration

All services share the `colmena_devops` network with these considerations:

1. **Internal Communication**: Services use hostnames (postgres, nextcloud, mail)
2. **External Access**: Only necessary ports exposed to host
3. **Security**: Database not directly accessible from outside

## CasaOS Compatibility

The compose file includes CasaOS metadata via x-casaos extension:
- Specifies supported architectures
- Defines main service
- Sets app store ID
- Includes category and author info

## Balena Compatibility

For Balena deployment, the same compose file works with minor adjustments:
- Remove port mappings (Balena handles this)
- Use Balena-specific environment variables
- Adjust restart policies if needed

## Migration Steps

1. **Backup existing data**
   ```bash
   docker-compose down
   docker run --rm -v colmena-os_pg_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres-backup.tar.gz /data
   ```

2. **Update compose file**
   ```bash
   cp docker-compose.yml docker-compose.old.yml
   # Apply new configuration
   ```

3. **Build unified image**
   ```bash
   docker-compose build colmena-app
   ```

4. **Start services**
   ```bash
   docker-compose up -d
   ```

5. **Verify health**
   ```bash
   docker-compose ps
   curl http://localhost:8080/health
   ```

## Troubleshooting

### Service Connection Issues
```bash
# Check network
docker network inspect colmena-os_colmena_devops

# Test internal connectivity
docker-compose exec colmena-app ping postgres
```

### Database Initialization
```bash
# Manual database creation if needed
docker-compose exec postgres psql -U colmena -c "CREATE DATABASE colmena;"
```

### Port Conflicts
```bash
# Check port usage
netstat -tulpn | grep -E '8080|3000|5432'

# Override in .env if needed
FRONTEND_PORT=8081
```

## Benefits of Merged Compose

1. **Single Command Deployment**: `docker-compose up -d` starts everything
2. **Unified Networking**: All services can communicate internally
3. **Shared Volume Management**: Consistent data persistence
4. **Environment Consistency**: Single .env file for all config
5. **Platform Compatibility**: Works for Docker, CasaOS, and Balena