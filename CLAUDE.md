# ColmenaOS Project Context

## Project Overview
ColmenaOS is an offline-first Progressive Web Application (PWA) platform for community podcasting. The goal is to create a single, unified Docker image that combines frontend and backend services, deployable across Docker, CasaOS, and Balena.

## Repository Structure
```
.
├── frontend/                           # Submodule: gitlab.com/colmena-project/dev/frontend
│   └── devops/builder/                 # Contains existing Dockerfile
├── backend/                            # Submodule: gitlab.com/colmena-project/dev/backend  
│   └── devops/builder/                 # Contains existing Dockerfile
├── colmena-devops/                     # Submodule: gitlab.com/colmena-project/dev/colmena-devops
│   └── devops/local/docker-compose.yml # DevOps services (postgres, nextcloud, mail)
├── docker-compose.yml                  # Main compose file (needs updating)
├── balena.yml                          # Balena configuration
├── scripts/                            # Automation scripts
├── tests/                              # Test infrastructure
└── context/                            # Documentation
```

## Current State
- **Frontend**: Has Dockerfile in `./frontend/devops/builder/`
- **Backend**: Has Dockerfile in `./backend/devops/builder/`
- **DevOps**: Has docker-compose with postgres, pgadmin, nextcloud, mail
- **Need**: Unified Dockerfile combining frontend + backend for single image deployment

## Deployment Strategy
1. **Single Image**: Combine frontend and backend into one container
2. **Unified Compose**: Merge app services with devops services
3. **Multi-Platform**: This single setup works for Docker, CasaOS, and Balena

## Key Constraints
- Must maintain submodule structure (don't modify submodules)
- Single docker-compose.yml for all platforms
- Support ARM64 and AMD64 architectures
- Offline-first functionality must be preserved

## Environment Variables
```bash
# From existing docker-compose.yml
POSTGRES_HOSTNAME
POSTGRES_USERNAME  
POSTGRES_PASSWORD
PGADMIN_DEFAULT_EMAIL
PGADMIN_DEFAULT_PASSWORD
NEXTCLOUD_VERSION
NEXTCLOUD_ADMIN_USER
NEXTCLOUD_ADMIN_PASSWORD
```

## Success Metrics
- Single `docker-compose up` deploys everything
- Works on Raspberry Pi (ARM64) and x86 servers
- CasaOS can install with one click
- Balena can deploy to device fleets

## Quick Start for Development
```bash
# Clone with submodules
git clone --recursive https://github.com/luandro/colmena-os

# Check existing Dockerfiles
ls frontend/devops/builder/Dockerfile
ls backend/devops/builder/Dockerfile

# Start with existing compose
docker-compose up -d
```

---
*For specific tasks, see ./context/issues-roadmap.md*