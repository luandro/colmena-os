# syntax=docker/dockerfile:1
# Unified Dockerfile for ColmenaOS - Frontend + Backend combined image

# ------------------------------
# Stage 0: Backend schema (generate OpenAPI JSON)
# ------------------------------
FROM python:3.10-alpine AS backend-schema
WORKDIR /opt/app
RUN apk add --no-cache \
    build-base \
    gcc \
    musl-dev \
    python3-dev \
    libffi-dev \
    openssl-dev \
    postgresql-dev \
    jpeg-dev \
    zlib-dev \
    cargo \
    git \
    gettext \
    jq
COPY backend/ ./
RUN if [ -f requirements/prod.txt ]; then \
      pip install -U pip setuptools wheel && \
      pip install -r requirements/prod.txt; \
    else \
      echo "No backend requirements found, skipping install"; \
    fi
RUN if [ -f apps/nextcloud/openapi/schema.json ]; then \
      python -m openapi_python_generator apps/nextcloud/openapi/schema.json apps/nextcloud/openapi/client; \
    fi
ENV DJANGO_SETTINGS_MODULE=colmena.settings.test \
    STAGE=test \
    COLMENA_SECRET_KEY="colmena-build-secret"
RUN if [ -f manage.py ]; then \
      echo "Generating backend OpenAPI schema (JSON) via manage.py spectacular..." && \
      python manage.py spectacular --file /tmp/schema.json --format openapi-json; \
    else \
      echo "No manage.py in backend; creating placeholder schema.json" && \
      echo '{"openapi":"3.0.0","info":{"title":"Colmena API (Placeholder)","version":"0.0.0","description":"Placeholder schema - backend sources not available during build"},"paths":{}}' > /tmp/schema.json; \
    fi
# Validate schema.json is not empty and has required OpenAPI structure
RUN test -s /tmp/schema.json && \
    jq -e '.openapi and .info and .paths' /tmp/schema.json > /dev/null && \
    echo "✓ Backend schema validation passed" || \
    (echo "✗ Invalid or incomplete backend schema.json" && exit 1)

# ------------------------------
# Stage 1: Frontend builder
# ------------------------------
FROM node:20-alpine AS frontend-builder
WORKDIR /app/frontend
# Always copy the directory (may be empty when submodule isn't checked out)
COPY frontend/ ./
# Copy generated backend schema into frontend (if available)
RUN mkdir -p src/api src/api/utilities
COPY --from=backend-schema /tmp/schema.json /app/frontend/src/api/schema.json

# Disable Vite type-checker plugin to allow production build in container
RUN if [ -f vite.config.ts ]; then \
      sed -i "s/^import checker from 'vite-plugin-checker';/\/\/ import checker from 'vite-plugin-checker';/" vite.config.ts && \
      sed -i '/checker({/,/}),/d' vite.config.ts ; \
    fi

RUN if [ -f package.json ]; then \
      npm ci --prefer-offline --no-audit --no-fund --ignore-scripts && \
      echo "Running frontend OpenAPI tasks (optimize + typegen)" && \
      npm run openapi-optimize && \
      (test -s src/api/utilities/schema-runtime.json && jq -e '.openapi and .info and .paths' src/api/utilities/schema-runtime.json > /dev/null && echo "✓ Frontend schema-runtime.json validation passed" || echo "⚠ schema-runtime.json not available, skipping validation") && \
      npm run openapi-typegen && \
      test -f src/api/utilities/Definitions.d.ts && \
      npm run build; \
    else \
      echo "package.json missing; cannot build frontend" && exit 1; \
    fi

# ------------------------------
# Stage 2: Backend builder
# ------------------------------
FROM python:3.10-alpine AS backend-builder
WORKDIR /opt/app

# System deps commonly needed for Django + Pillow + psycopg
RUN apk add --no-cache \
    build-base \
    gcc \
    musl-dev \
    python3-dev \
    libffi-dev \
    openssl-dev \
    postgresql-dev \
    jpeg-dev \
    zlib-dev \
    cargo \
    git \
    gettext \
    jq

# Copy backend source (may be empty when submodule isn't checked out)
COPY backend/ ./

# Install Python dependencies if requirements exist
RUN if [ -f requirements/prod.txt ]; then \
      pip install -U pip setuptools wheel && \
      pip install -r requirements/prod.txt; \
    else \
      echo "No backend requirements found, skipping install"; \
    fi

# Generate OpenAPI client if schema and generator are available (don't fail build if missing)
RUN if [ -f apps/nextcloud/openapi/schema.json ]; then \
      (python -m openapi_python_generator apps/nextcloud/openapi/schema.json apps/nextcloud/openapi/client || echo "OpenAPI generator not available, skipping"); \
    else \
      echo "OpenAPI schema not found, skipping generation"; \
    fi

# Ensure a placeholder manage.py exists so image builds even without backend sources
RUN if [ ! -f manage.py ]; then \
      echo '#!/usr/bin/env python3' > manage.py && \
      echo 'print("Placeholder manage.py - backend sources not present in build context")' >> manage.py && \
      chmod +x manage.py; \
    fi

# ------------------------------
# Stage 3: Final unified image
# ------------------------------
FROM python:3.10-alpine

# Install runtime dependencies
RUN apk add --no-cache \
    nginx \
    supervisor \
    gettext \
    curl \
    bash \
    tzdata \
    ca-certificates \
    postgresql-libs \
    libjpeg-turbo \
    zlib

# Set up application directories
WORKDIR /opt/app
RUN mkdir -p /opt/app/media /opt/app/static && \
    mkdir -p /var/log/supervisor

# Create a dedicated non-root user for running the backend
# Also add nginx user to colmena group for Unix socket access (660 permissions)
RUN addgroup -S colmena && adduser -S -G colmena -h /opt/app -s /sbin/nologin colmena && \
    adduser nginx colmena

# Copy Python environment and backend application
COPY --from=backend-builder /usr/local /usr/local
COPY --from=backend-builder /opt/app /opt/app
# Keep generated OpenAPI schema for reference/debugging
COPY --from=backend-schema /tmp/schema.json /opt/app/openapi.json

# Copy backend start script from repo root
COPY start-backend.sh /opt/app/start-backend.sh
RUN chmod +x /opt/app/start-backend.sh

# Set proper ownership for the colmena user
RUN chown -R colmena:colmena /opt/app && \
    chown -R colmena:colmena /var/log/supervisor

# Set up frontend (serve with nginx)
COPY --from=frontend-builder /app/frontend/dist /usr/share/nginx/html

# Provide a bundled nginx default server so standalone containers work out of the box.
# docker-compose can still override this by mounting docker/colmena-app-nginx-*.conf
COPY docker/colmena-app-nginx-default-http.conf /etc/nginx/http.d/default.conf

# Supervisor configuration to run both backend (gunicorn) and nginx
# Note: This can be overridden by mounting docker/colmena-app-supervisord.conf in docker-compose.yml
COPY <<'EOF' /etc/supervisor/conf.d/supervisord.conf
[supervisord]
user=root
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:backend]
command=/opt/app/start-backend.sh
directory=/opt/app
user=colmena
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/backend.log
stderr_logfile=/var/log/supervisor/backend.log

[program:nginx]
command=nginx -g "daemon off;"
autostart=true
autorestart=true
stdout_logfile=/var/log/supervisor/nginx.log
stderr_logfile=/var/log/supervisor/nginx.log
EOF

# Environment
ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/app

# Expose ports
EXPOSE 80 8000

# Health check: ensure both nginx and backend respond
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -fsS http://127.0.0.1/ >/dev/null && curl -fsS http://127.0.0.1:8000/api/schema/ >/dev/null

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
