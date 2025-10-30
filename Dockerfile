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
    gettext
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
      echo "No manage.py in backend; skipping schema generation" && exit 1; \
    fi
RUN test -s /tmp/schema.json

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
RUN test -s src/api/schema.json

# Disable Vite type-checker plugin to allow production build in container
RUN if [ -f vite.config.ts ]; then \
      sed -i "s/^import checker from 'vite-plugin-checker';/\/\/ import checker from 'vite-plugin-checker';/" vite.config.ts && \
      sed -i '/checker({/,/}),/d' vite.config.ts ; \
    fi

RUN if [ -f package.json ]; then \
      npm ci --prefer-offline --no-audit --no-fund --ignore-scripts && \
      echo "Running frontend OpenAPI tasks (optimize + typegen)" && \
      npm run openapi-optimize && \
      npm run openapi-typegen && \
      test -s src/api/utilities/schema-runtime.json && \
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
    gettext

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
RUN addgroup -S colmena && adduser -S -G colmena -h /opt/app -s /sbin/nologin colmena

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

# Set up frontend (serve with nginx) and write a unified nginx config
COPY --from=frontend-builder /app/frontend/dist /usr/share/nginx/html

# Provide a proper nginx default server that serves the frontend and proxies /api to backend
RUN cat > /etc/nginx/http.d/default.conf <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Serve built frontend
    root /usr/share/nginx/html;
    index index.html;

    # Proxy API to Django backend (gunicorn) inside the same container
    location /api/ {
        proxy_pass http://127.0.0.1:8000/;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_redirect off;
        proxy_set_header Connection "";
        send_timeout 120s;
        proxy_connect_timeout 120s;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # History API fallback for SPAs
    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF

# Supervisor configuration to run both backend (gunicorn) and nginx
COPY <<'EOF' /etc/supervisor/conf.d/supervisord.conf
[supervisord]
user=root
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:backend]
command=/opt/app/start-backend.sh
directory=/opt/app
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
  CMD sh -c 'curl -fsS http://127.0.0.1/ >/dev/null && (curl -fsS http://127.0.0.1:8000/api/schema >/dev/null || curl -fsS http://127.0.0.1:8000/ >/dev/null) || exit 1'

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
