# ColmenaOS Documentation Index

## Overview

ColmenaOS is an offline-first, solar-powered operating system for community radio and podcasting. Built on Docker and BalenaOS, it provides a complete platform for sovereign media production.

## Core Documentation

### Getting Started
- [Quick Start Guide](../README.md#quick-start)
- [Installation](../README.md#requirements)
- [Configuration](../README.md#development)

### Architecture
- [System Overview](../README.md#architecture)
- [Docker Setup](../context/docker-setup.md)
- [Service Architecture](../context/docker-compose-merge.md)
- [Build Process](../context/unified-dockerfile.md)

### Development
- [Development Workflow](../context/docker-setup.md)
- [Working with Submodules](../README.md#working-with-submodules)
- [Testing Guide](../README.md#testing)
- [CI/CD Pipeline](../context/github-workflows-analysis.md)

### Deployment
- [Local Development](../README.md#option-1-local-development-recommended-for-testing)
- [Production Deployment](../README.md#option-2-production-deployment-with-balena)
- [Balena Fleet Management](../context/issues-roadmap.md)

## Component Documentation

### Frontend
- Location: `frontend/` (submodule)
- Technology: React PWA
- Port: 8080

### Backend
- Location: `backend/` (submodule)
- Technology: Django REST API
- Port: 8000

### Infrastructure Services
- **PostgreSQL**: Database (port 5432)
- **Nextcloud**: File storage (port 8003)
- **pgAdmin**: Database management (port 5050)
- **Mailcrab**: Email testing (port 1080)

## Additional Resources

### External Documentation
- [User Guides](https://docs.colmena.media/)
- [API Reference](https://docs.colmena.coop/api/)
- [Community](https://colmena.coop/)

### Project Files
- [CLAUDE.md](../CLAUDE.md) - AI assistant context
- [Issues Roadmap](../context/issues-roadmap.md) - Development tracking
- [License](../LICENSE) - MIT License

## Support

For questions and support:
- GitHub Issues: [github.com/luandro/colmena-os/issues](https://github.com/luandro/colmena-os/issues)
- Documentation: [docs.colmena.media](https://docs.colmena.media/)
