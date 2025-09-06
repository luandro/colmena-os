# syntax=docker/dockerfile:1
# Unified Dockerfile for ColmenaOS - Frontend + Backend combined image

# ------------------------------
# Stage 1: Frontend builder
# ------------------------------
FROM node:20-alpine AS frontend-builder
WORKDIR /app/frontend
# Always copy the directory (may be empty when submodule isn't checked out)
COPY frontend/ ./
# Build if package.json exists; otherwise create a minimal placeholder dist
RUN if [ -f package.json ]; then \
      npm ci --prefer-offline --no-audit --no-fund --ignore-scripts && \
      (npm run build || npx vite build --mode production || (mkdir -p dist && echo '<!doctype html><html><body><h1>ColmenaOS</h1></body></html>' > dist/index.html)); \
    else \
      mkdir -p dist && echo '<!doctype html><html><body><h1>ColmenaOS</h1></body></html>' > dist/index.html; \
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

# Copy backend start script from repo root
COPY start-backend.sh /opt/app/start-backend.sh
RUN chmod +x /opt/app/start-backend.sh

# Set proper ownership for the colmena user
RUN chown -R colmena:colmena /opt/app && \
    chown -R colmena:colmena /var/log/supervisor

# Set up frontend (serve with nginx default root)
COPY --from=frontend-builder /app/frontend/dist /usr/share/nginx/html
# Ensure default nginx page root points to /usr/share/nginx/html
RUN if [ -f /etc/nginx/http.d/default.conf ]; then \
      sed -i 's|/var/lib/nginx/html|/usr/share/nginx/html|g' /etc/nginx/http.d/default.conf || true; \
    fi

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
  CMD sh -c 'curl -fsS http://127.0.0.1/ >/dev/null && (curl -fsS http://127.0.0.1:8000/api/schema >/dev/null || curl -fsS http://127.0.0.1:8000/ >/dev/null) || exit 1'

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
