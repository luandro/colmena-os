# Getting Started with ColmenaOS

This guide will help you set up ColmenaOS for local development or testing.

## Prerequisites

Before you begin, ensure you have:

- **Docker** and **Docker Compose** installed
- **Git** with submodule support
- At least **2GB RAM** and **16GB storage**
- Supported architecture: **AMD64** or **ARM64**

## Quick Setup

### 1. Clone the Repository

```bash
git clone --recursive https://github.com/colmena-project/colmena-os.git
cd colmena-os
```

The `--recursive` flag ensures all submodules (frontend, backend, devops) are cloned.

### 2. Configure Environment

```bash
# Copy example environment file
cp .env.example .env

# Edit the .env file with your settings
nano .env  # or use your preferred editor
```

**Important**: Replace all `CHANGE_ME` values with secure passwords.

Required environment variables:
- `POSTGRES_PASSWORD` - Database password
- `SECRET_KEY` - Django secret key (min 50 characters)
- `SUPERADMIN_PASSWORD` - Admin account password
- `NEXTCLOUD_ADMIN_PASSWORD` - Nextcloud admin password
- `PGADMIN_DEFAULT_PASSWORD` - pgAdmin password

### 3. Start Services

```bash
docker compose up -d
```

This will:
1. Build the ColmenaOS application image
2. Pull required service images (PostgreSQL, Nextcloud, etc.)
3. Start all services in the background

### 4. Wait for Services

Services need 2-3 minutes to fully initialize. Monitor the startup:

```bash
# Watch application logs
docker compose logs -f colmena-app

# Check service status
docker compose ps
```

All services should show "healthy" or "running" status.

### 5. Access the Application

Once services are running, access:

- **Main Application**: http://localhost:8080
- **Backend API**: http://localhost:8000
- **pgAdmin**: http://localhost:5050
- **Nextcloud**: http://localhost:8003
- **Mailcrab**: http://localhost:1080

**Default Login:**
- Email: `admin@colmena.org`
- Password: Your `SUPERADMIN_PASSWORD` from `.env`

## Next Steps

### Explore the Platform

1. **Connect to a server** - Follow the [server setup guide](https://docs.colmena.media/use/add-server/)
2. **Upload content** - Use the web interface to upload audio files
3. **Create episodes** - Build and schedule podcast episodes

### Development Workflow

If you're developing on ColmenaOS:

```bash
# Update submodules
git submodule update --remote --merge

# View logs for a specific service
docker compose logs backend

# Restart a service after changes
docker compose restart backend

# Rebuild after code changes
docker compose up -d --build
```

### Testing Changes

```bash
# Quick test - rebuild and verify
./scripts/clean_and_test.sh

# Reset database if needed
./scripts/reset_postgres.sh

# Run full test suite
./scripts/ci-test.sh local
```

## Troubleshooting

### Services Won't Start

```bash
# Check Docker daemon
sudo systemctl status docker

# Check for port conflicts
sudo netstat -tulpn | grep -E '(8080|8000|5432|5050|8003|1080)'

# View full logs
docker compose logs
```

### Database Connection Errors

```bash
# Reset PostgreSQL
./scripts/reset_postgres.sh

# Or manually reset
docker compose down --volumes
docker compose up -d
```

### Submodule Issues

```bash
# Reinitialize submodules
git submodule deinit -f .
git submodule update --init --recursive

# Update to latest
git submodule update --remote --merge
```

### Clean Slate

If you need to start fresh:

```bash
# Stop all services and remove volumes
docker compose down --volumes

# Remove all containers and images
docker compose down --rmi all --volumes

# Start from scratch
docker compose up -d
```

## Common Issues

**"Port already in use"**
- Another service is using one of the required ports
- Find and stop the conflicting service, or change ports in `docker-compose.yml`

**"Permission denied"**
- Docker requires appropriate permissions
- Add your user to docker group: `sudo usermod -aG docker $USER`
- Log out and back in for changes to take effect

**"Container exited with code 1"**
- Check logs: `docker compose logs [service-name]`
- Usually indicates a configuration error in `.env`

## Production Deployment

For production deployments to Balena:

1. See [Production Deployment Guide](../README.md#option-2-production-deployment-with-balena)
2. Review [Balena Configuration](../balena.yml)
3. Check [Deployment Workflows](../context/github-workflows-analysis.md)

## Additional Resources

- [Docker Setup Guide](../context/docker-setup.md)
- [Architecture Overview](../README.md#architecture)
- [CI/CD Pipeline](../context/github-workflows-analysis.md)
- [Contributing Guidelines](../README.md#contributing)

## Support

Need help?
- [GitHub Issues](https://github.com/luandro/colmena-os/issues)
- [Documentation](https://docs.colmena.media/)
- [Community](https://colmena.coop/)
