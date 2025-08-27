# Docker Setup

## Overview
Complete Docker containerization requirements and implementation guide for ColmenaOS services.

## Related Documents
- [Multi-Arch Builds](./multi-arch-builds.md) - Cross-platform build configuration
- [Environment Config](./environment-config.md) - Environment variable management
- [Deployment Overview](./deployment-overview.md) - Overall deployment strategy
- [CI/CD Pipeline](./ci-cd-pipeline.md) - Automated build integration

## Issues Addressed
- Issue #001: Implement Docker Containerization (Critical)
- Issue #008: Optimize Container Images (Medium)

## Current State Analysis

### Existing Files
- `docker-compose.yml` exists but needs verification
- No Dockerfiles found in frontend/backend directories
- `balena.yml` suggests container awareness but Balena-specific

### Missing Components
- Individual service Dockerfiles
- Multi-stage build optimization
- Health check configurations
- Volume management strategy
- Network configuration

## Docker Architecture Design

### Service Structure
```yaml
services:
  frontend:
    build: ./frontend
    ports: ["8080:8080"]
    depends_on: ["backend"]
    
  backend:
    build: ./backend
    ports: ["3000:3000"]
    depends_on: ["postgres", "redis"]
    
  postgres:
    image: postgres:15-alpine
    volumes: ["postgres_data:/var/lib/postgresql/data"]
    
  redis:
    image: redis:7-alpine
    volumes: ["redis_data:/data"]
```

### Network Architecture
```
┌─────────────┐
│   Traefik   │ (optional reverse proxy)
└──────┬──────┘
       │
┌──────┴──────┐
│   Frontend  │ ←── Public Access
└──────┬──────┘
       │
┌──────┴──────┐
│   Backend   │ ←── Internal Only
└──────┬──────┘
       │
┌──────┴──────┐
│  Database   │ ←── Internal Only
└─────────────┘
```

## Frontend Dockerfile

```dockerfile
# ./frontend/Dockerfile
# Multi-stage build for optimal size
FROM node:18-alpine AS builder

# Build arguments for configuration
ARG NODE_ENV=production
ARG API_URL=http://backend:3000

WORKDIR /app

# Copy dependency files
COPY package*.json ./
RUN npm ci --only=production

# Copy source code
COPY . .

# Build the application
RUN npm run build

# Production stage
FROM nginx:alpine

# Copy built assets
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy nginx configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
```

## Backend Dockerfile

```dockerfile
# ./backend/Dockerfile
FROM node:18-alpine AS builder

WORKDIR /app

# Copy dependency files
COPY package*.json ./
RUN npm ci --only=production

# Copy source code
COPY . .

# Build TypeScript (if applicable)
RUN npm run build

# Production stage
FROM node:18-alpine

WORKDIR /app

# Install production dependencies only
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

# Copy built application
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/public ./public

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

USER nodejs

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node healthcheck.js || exit 1

EXPOSE 3000
CMD ["node", "dist/index.js"]
```

## Docker Compose Configuration

```yaml
# docker-compose.yml
version: '3.8'

services:
  frontend:
    build: 
      context: ./frontend
      args:
        API_URL: ${API_URL:-http://backend:3000}
    ports:
      - "${FRONTEND_PORT:-8080}:8080"
    environment:
      - NODE_ENV=production
    depends_on:
      backend:
        condition: service_healthy
    restart: unless-stopped
    networks:
      - colmena-net

  backend:
    build: ./backend
    ports:
      - "${BACKEND_PORT:-3000}:3000"
    environment:
      - NODE_ENV=production
      - DATABASE_URL=postgresql://colmena:${DB_PASSWORD}@postgres:5432/colmena
      - REDIS_URL=redis://redis:6379
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started
    restart: unless-stopped
    networks:
      - colmena-net

  postgres:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=colmena
      - POSTGRES_PASSWORD=${DB_PASSWORD}
      - POSTGRES_DB=colmena
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U colmena"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - colmena-net

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes:
      - redis_data:/data
    restart: unless-stopped
    networks:
      - colmena-net

volumes:
  postgres_data:
  redis_data:

networks:
  colmena-net:
    driver: bridge
```

## Environment Configuration

### .env.example
```bash
# Database
DB_PASSWORD=secure_password_here
DATABASE_URL=postgresql://colmena:secure_password_here@postgres:5432/colmena

# Redis
REDIS_URL=redis://redis:6379

# Ports
FRONTEND_PORT=8080
BACKEND_PORT=3000

# API Configuration
API_URL=http://localhost:3000

# Environment
NODE_ENV=production
```

## Volume Management

### Persistent Data Volumes
- `postgres_data`: Database storage
- `redis_data`: Cache and session storage
- `media_uploads`: User uploaded content
- `backup_data`: Automated backups

### Backup Strategy
```bash
# Backup script
docker exec postgres pg_dump -U colmena colmena > backup_$(date +%Y%m%d).sql
docker cp backend:/app/uploads ./backup_uploads_$(date +%Y%m%d)
```

## Health Checks

### Implementation Requirements
1. Each service must expose `/health` endpoint
2. Check critical dependencies (DB, Redis)
3. Return appropriate HTTP status codes
4. Include version information

### Example Health Check Endpoint
```javascript
// backend/healthcheck.js
app.get('/health', async (req, res) => {
  const checks = {
    service: 'backend',
    status: 'healthy',
    version: process.env.npm_package_version,
    checks: {
      database: await checkDatabase(),
      redis: await checkRedis(),
      diskSpace: await checkDiskSpace()
    }
  };
  
  const isHealthy = Object.values(checks.checks).every(check => check);
  res.status(isHealthy ? 200 : 503).json(checks);
});
```

## Security Considerations

### Container Security
- Run as non-root user
- Use official Alpine-based images
- Scan images for vulnerabilities
- Implement secret management
- Network isolation between services

### Secret Management
```yaml
# docker-compose.yml with secrets
secrets:
  db_password:
    file: ./secrets/db_password.txt
  jwt_secret:
    file: ./secrets/jwt_secret.txt
```

## Optimization Strategies

### Image Size Reduction
1. Use Alpine Linux base images
2. Multi-stage builds
3. Remove development dependencies
4. Combine RUN commands
5. Use .dockerignore files

### .dockerignore Template
```
node_modules
npm-debug.log
.git
.gitignore
README.md
.env
.env.*
.vscode
.idea
coverage
.nyc_output
```

## Implementation Checklist

### Phase 1: Basic Containerization
- [ ] Create frontend Dockerfile
- [ ] Create backend Dockerfile
- [ ] Update docker-compose.yml
- [ ] Add .dockerignore files
- [ ] Test local deployment

### Phase 2: Optimization
- [ ] Implement multi-stage builds
- [ ] Add health checks
- [ ] Configure volumes
- [ ] Set up networking
- [ ] Add security configurations

### Phase 3: Production Ready
- [ ] Environment variable management
- [ ] Secret management
- [ ] Backup procedures
- [ ] Monitoring integration
- [ ] Documentation

## Testing Commands

```bash
# Build all services
docker-compose build

# Start services
docker-compose up -d

# Check health
docker-compose ps
curl http://localhost:8080/health
curl http://localhost:3000/health

# View logs
docker-compose logs -f

# Clean up
docker-compose down -v
```

## References
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Node.js Docker Guidelines](https://github.com/nodejs/docker-node/blob/main/docs/BestPractices.md)
- [Docker Compose Specification](https://docs.docker.com/compose/compose-file/)