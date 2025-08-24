# Unified Dockerfile

## Overview
Guide for creating a single Docker container that runs both frontend and backend services.

## Related Documents
- [existing-dockerfiles-analysis.md](./existing-dockerfiles-analysis.md) - Analysis of current Dockerfiles
- [docker-compose-merge.md](./docker-compose-merge.md) - Integration with main compose

## Current Structure

### Frontend Dockerfile Location
`./frontend/devops/builder/Dockerfile`

### Backend Dockerfile Location  
`./backend/devops/builder/Dockerfile`

## Unified Dockerfile Strategy

### Option 1: Supervisor Approach (Recommended)
```dockerfile
# Dockerfile (in root directory)
FROM node:18-alpine

# Install supervisor to manage multiple processes
RUN apk add --no-cache supervisor nginx

# Setup backend
WORKDIR /app/backend
COPY backend/package*.json ./
RUN npm ci --production
COPY backend/ ./
RUN npm run build

# Setup frontend  
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm ci --production
COPY frontend/ ./
RUN npm run build

# Configure nginx for frontend
COPY nginx.conf /etc/nginx/nginx.conf

# Configure supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose ports
EXPOSE 8080 3000

# Start supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
```

### Supervisor Configuration
```ini
# supervisord.conf
[supervisord]
nodaemon=true
user=root

[program:backend]
command=node /app/backend/dist/index.js
autostart=true
autorestart=true
stdout_logfile=/var/log/backend.log
environment=NODE_ENV="production",PORT="3000"

[program:frontend]
command=nginx -g 'daemon off;'
autostart=true
autorestart=true
stdout_logfile=/var/log/frontend.log

[program:nginx]
command=nginx -g 'daemon off;'
autostart=true
autorestart=true
```

### Option 2: Shell Script Approach
```dockerfile
# Dockerfile
FROM node:18-alpine

WORKDIR /app

# Copy and build both services
COPY backend ./backend
COPY frontend ./frontend

# Build backend
WORKDIR /app/backend
RUN npm ci --production && npm run build

# Build frontend
WORKDIR /app/frontend  
RUN npm ci --production && npm run build

# Copy startup script
WORKDIR /app
COPY start.sh ./
RUN chmod +x start.sh

EXPOSE 8080 3000

CMD ["./start.sh"]
```

```bash
#!/bin/sh
# start.sh
# Start backend
cd /app/backend
node dist/index.js &

# Start frontend (assuming it's a static build served by a simple server)
cd /app/frontend
npx serve -s dist -l 8080 &

# Keep container running
wait
```

## Nginx Configuration for Frontend
```nginx
# nginx.conf
server {
    listen 8080;
    server_name localhost;
    
    root /app/frontend/dist;
    index index.html;
    
    # API proxy to backend
    location /api {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
    
    # Frontend routes (SPA)
    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

## Environment Variables
```bash
# .env for unified container
# Backend
BACKEND_PORT=3000
DATABASE_URL=postgresql://colmena:password@postgres:5432/colmena
REDIS_URL=redis://redis:6379

# Frontend  
FRONTEND_PORT=8080
API_URL=http://localhost:3000

# Shared
NODE_ENV=production
```

## Build Commands
```bash
# Build unified image
docker build -t colmena/unified:latest .

# Run standalone
docker run -p 8080:8080 -p 3000:3000 colmena/unified:latest

# Run with compose
docker-compose up colmena-app
```

## Integration with docker-compose.yml
```yaml
services:
  colmena-app:
    build: .
    image: colmena/unified:latest
    container_name: colmena_app
    ports:
      - "8080:8080"  # Frontend
      - "3000:3000"  # Backend API
    environment:
      - DATABASE_URL=postgresql://colmena:${POSTGRES_PASSWORD}@postgres:5432/colmena
      - API_URL=http://localhost:3000
    depends_on:
      - postgres
    networks:
      colmena_devops:
        aliases:
          - app
```

## Health Checks
```dockerfile
# Add to Dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health && \
      wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1
```

## Considerations

### Pros of Unified Container
- Simpler deployment (one container)
- Easier for CasaOS/Balena
- Less network complexity
- Single image to maintain

### Cons of Unified Container
- Can't scale frontend/backend independently
- Both services restart together
- Larger image size
- More complex debugging

## Testing Checklist
- [ ] Both services start correctly
- [ ] Frontend can reach backend API
- [ ] Database connections work
- [ ] Static assets load properly
- [ ] WebSocket connections (if any) work
- [ ] Logs are accessible for both services
- [ ] Container restarts gracefully

## Migration Path
1. Test with existing submodule Dockerfiles
2. Create unified Dockerfile in root
3. Update docker-compose.yml
4. Test with devops services
5. Deploy to test environment
6. Update documentation