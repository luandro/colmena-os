# Unified Dockerfile for ColmenaOS - Frontend + Backend with dynamic OpenAPI schema
# Multi-stage build with temporary backend for schema generation

# Stage 1: Backend builder  
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
    nginx \
    curl \
    sqlite

# Install Python dependencies
RUN pip install -U pip && pip install -r requirements/prod.txt

# Copy backend source
COPY backend/ ./

# Generate OpenAPI client for Nextcloud
RUN python -m openapi_python_generator \
    apps/nextcloud/openapi/schema.json \
    apps/nextcloud/openapi/client

# Stage 2: Schema generator (temporary backend instance)
FROM backend-builder AS schema-generator

# Set environment variables for schema generation
ENV DJANGO_SETTINGS_MODULE=colmena.settings.prod \
    COLMENA_SECRET_KEY=temp-build-key-12345 \
    ALLOWED_HOSTS="localhost 127.0.0.1" \
    CORS_ALLOWED_ORIGINS=http://localhost:3000 \
    CSRF_TRUSTED_ORIGINS=http://localhost:3000 \
    STAGE=local

# Generate dynamic schema directly without database migration
RUN python manage.py spectacular --color --file /tmp/openapi-schema.json

# Stage 3: Frontend builder with dynamic schema
FROM node:20-alpine AS frontend-builder

WORKDIR /app/frontend

# Install system dependencies
RUN apk add --no-cache python3 py3-pip curl

# Copy frontend source
COPY frontend/ ./

# Copy the dynamically generated schema from backend
COPY --from=schema-generator /tmp/openapi-schema.json ./src/api/schema.json

# Install frontend dependencies
RUN npm ci --prefer-offline --no-audit --no-fund --ignore-scripts

# Generate TypeScript types from the dynamic schema
RUN npm run openapi-optimize && npm run openapi-typegen

# Build frontend
RUN npm run build

# Stage 4: Final production image
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
COPY frontend/devops/local/nginx/app /etc/nginx/http.d/default.conf

# Copy backend entrypoint scripts
COPY backend/devops/builder/entrypoint.sh /app/backend/entrypoint.sh
COPY start-backend.sh /app/backend/start-backend.sh
RUN chmod +x /app/backend/entrypoint.sh /app/backend/start-backend.sh

# Fix gunicorn command to use Python module syntax
RUN sed -i 's/gunicorn --timeout/python -m gunicorn --timeout/g' /app/backend/entrypoint.sh

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
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:80/ || exit 1

# Start supervisor to manage both processes
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]