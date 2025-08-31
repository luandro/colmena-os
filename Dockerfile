# syntax=docker/dockerfile:1
# Unified Dockerfile for ColmenaOS - Frontend + Backend combined image

# Stage 1: Frontend builder
FROM node:20-alpine AS frontend-builder
WORKDIR /opt/frontend
COPY frontend/ .
RUN npm ci --prefer-offline --no-audit --no-fund
RUN npm run build

# Stage 2: Backend preparation  
FROM python:3.10-alpine AS backend-builder
WORKDIR /opt/backend

# Install system dependencies for Python build
RUN apk add --no-cache \
    alpine-sdk \
    git \
    python3-dev \
    gettext

# Copy backend source and install dependencies
COPY backend/ .
RUN pip install -U pip
RUN pip install -r requirements/prod.txt

# Generate OpenAPI client for Nextcloud
RUN python -m openapi_python_generator \
    apps/nextcloud/openapi/schema.json \
    apps/nextcloud/openapi/client

# Stage 3: Final unified image
FROM python:3.10-alpine

# Install runtime dependencies
RUN apk add --no-cache \
    nginx \
    supervisor \
    gettext \
    curl

# Set up backend
WORKDIR /opt/app
COPY --from=backend-builder /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages
COPY --from=backend-builder /opt/backend .

# Set up frontend
COPY --from=frontend-builder /opt/frontend/dist /usr/share/nginx/html
COPY frontend/devops/local/nginx/app /etc/nginx/conf.d/default.conf

# Configure backend entrypoint
COPY backend/devops/builder/entrypoint.sh .
RUN chmod +x entrypoint.sh
RUN chown -R nobody:nobody /opt/app

# Create supervisor configuration
RUN mkdir -p /var/log/supervisor
COPY <<EOF /etc/supervisor/conf.d/supervisord.conf
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:backend]
command=/opt/app/entrypoint.sh start_prod
directory=/opt/app
user=nobody
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

# Environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/app

# Expose ports
EXPOSE 80 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:80/ && curl -f http://localhost:8000/api/schema || exit 1

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]