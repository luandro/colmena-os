# Unified Dockerfile for ColmenaOS - Frontend + Backend in single container
# Based on existing submodule Dockerfiles with supervisor process management

# Stage 1: Frontend builder
FROM node:20-alpine AS frontend-builder

WORKDIR /app/frontend

# Copy frontend files
COPY frontend/package*.json ./
COPY frontend/ ./

# Install dependencies and build
RUN npm ci && npm run build

# Stage 2: Backend builder  
FROM python:3.10-alpine AS backend-builder

WORKDIR /app/backend

# Copy backend requirements
COPY backend/requirements/base.txt /app/backend/requirements/base.txt
COPY backend/requirements/prod.txt /app/backend/requirements/prod.txt

# Install system dependencies
RUN apk add --no-cache \
    alpine-sdk \
    git \
    python3-dev \
    gettext \
    nginx

# Install Python dependencies
RUN pip install -U pip && pip install -r requirements/prod.txt

# Copy backend source
COPY backend/ ./

# Generate OpenAPI client
RUN python -m openapi_python_generator \
    apps/nextcloud/openapi/schema.json \
    apps/nextcloud/openapi/client

# Stage 3: Final production image
FROM python:3.10-alpine

# Install system dependencies
RUN apk add --no-cache \
    nginx \
    supervisor \
    gettext \
    libstdc++

# Create app directory structure
WORKDIR /app

# Copy built frontend from builder
COPY --from=frontend-builder /app/frontend/dist /app/frontend/dist

# Copy backend with installed dependencies
COPY --from=backend-builder /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages
COPY --from=backend-builder /app/backend /app/backend

# Copy nginx configuration for frontend
COPY frontend/devops/local/nginx/app /etc/nginx/conf.d/default.conf

# Copy backend entrypoint script
COPY backend/devops/builder/entrypoint.sh /app/backend/entrypoint.sh
RUN chmod +x /app/backend/entrypoint.sh

# Copy supervisor configuration
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Create directories for Django
RUN mkdir -p /app/backend/media /app/backend/static

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/backend \
    DJANGO_SETTINGS_MODULE=colmena.settings.prod \
    STATIC_ROOT=/app/backend/static \
    MEDIA_ROOT=/app/backend/media \
    PORT=8000

# Expose ports: 80 for frontend (nginx), 8000 for backend (gunicorn)
EXPOSE 80 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:80/ || \
        wget --no-verbose --tries=1 --spider http://localhost:8000/health/ || exit 1

# Start supervisor to manage both processes
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]