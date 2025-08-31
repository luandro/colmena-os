# ColmenaOS Docker Deployment Guide

This repository provides two Docker Compose configurations for different use cases:

## 🚀 Production Deployment (docker-compose.yml)

Uses the **published image** from Docker Hub - no local build required.

```bash
# Start all services using published image
docker-compose up -d

# Stop services
docker-compose down
```

**Image**: `communityfirst/colmena-app:latest`
**Use case**: Production deployments, CasaOS, Balena, etc.

## 🔧 Local Development (docker-compose.local.yml)

Builds the image locally from source code - requires local repository.

```bash
# Build and start all services locally
docker-compose -f docker-compose.local.yml up --build

# Stop services
docker-compose -f docker-compose.local.yml down
```

**Image**: `colmena-app:local` (built from local Dockerfile)
**Use case**: Development, testing, customization

## 📋 Environment Variables

Create a `.env` file with required variables:

```env
# Database Configuration
POSTGRES_PASSWORD=your_secure_password
POSTGRES_USER=colmena
POSTGRES_DB=colmena

# Admin Configuration
PGADMIN_DEFAULT_PASSWORD=admin_password
NEXTCLOUD_ADMIN_PASSWORD=nextcloud_password
SUPERADMIN_PASSWORD=superadmin_password

# Application Security
SECRET_KEY=your-secret-key-here-minimum-50-characters-long

# Optional Overrides
HTTP_PORT=80
BACKEND_PORT=8000
DEBUG=false
```

## 🌐 Service Access

Once running, access services at:

- **Frontend**: http://localhost (or configured HTTP_PORT)
- **Backend API**: http://localhost:8000 (or configured BACKEND_PORT)
- **pgAdmin**: http://localhost:5050
- **Nextcloud**: http://localhost:8003
- **Mail UI**: http://localhost:1080

## 📦 Single Image Deployment

For platforms like CasaOS or simple deployments, you can use just the app image:

```bash
docker run -d \
  --name colmena-app \
  -p 80:80 -p 8000:8000 \
  -e DATABASE_URL=postgresql://user:pass@host:5432/db \
  -e SECRET_KEY=your-secret-key \
  communityfirst/colmena-app:latest
```

## 🔄 Updates

### Production
```bash
docker-compose pull
docker-compose up -d
```

### Local Development
```bash
git pull
docker-compose -f docker-compose.local.yml up --build
```