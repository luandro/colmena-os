# ColmenaOS Documentation

Welcome to the ColmenaOS documentation hub! This directory contains technical documentation and guides for developers and contributors working on ColmenaOS.

## Documentation Structure

### Quick Links

- **[Project README](../README.md)** - Overview, quick start, and deployment instructions
- **[Claude.md](../CLAUDE.md)** - Project context for AI assistants
- **[Technical Context](../context/)** - Detailed technical documentation

### Technical Documentation (context/)

The `context/` directory contains in-depth technical documentation:

- **[Docker Setup](../context/docker-setup.md)** - Docker configuration and build process
- **[Docker Compose Merge](../context/docker-compose-merge.md)** - Service orchestration details
- **[Unified Dockerfile](../context/unified-dockerfile.md)** - Container build strategy
- **[GitHub Workflows Analysis](../context/github-workflows-analysis.md)** - CI/CD pipeline details
- **[Issues Roadmap](../context/issues-roadmap.md)** - Development roadmap and known issues
- **[Architecture Flowchart](../context/FLOWCHART.md)** - System architecture overview

## External Documentation

- **User Documentation**: [docs.colmena.media](https://docs.colmena.media/)
  - Installation guides
  - Usage tutorials
  - Troubleshooting

- **Cooperative Documentation**: [docs.colmena.coop](https://docs.colmena.coop/)
  - Project governance
  - Community guidelines
  - API reference

## Project Overview

ColmenaOS is an offline-first Progressive Web Application (PWA) platform for community podcasting. The platform combines:

- **Frontend**: React PWA for user interface
- **Backend**: Django REST API
- **Services**: PostgreSQL, Nextcloud, Mailcrab
- **Infrastructure**: Docker/Balena-based deployment

## Architecture

```
.
├── frontend/                  # React PWA (submodule)
├── backend/                   # Django API (submodule)
├── colmena-devops/           # DevOps configs (submodule)
├── docker-compose.yml        # Service orchestration
├── balena.yml               # Balena deployment config
├── .github/workflows/       # CI/CD pipelines
└── docs/                    # This documentation
```

## Development Workflow

### Getting Started

1. **Clone with submodules**:
   ```bash
   git clone --recursive https://github.com/colmena-project/colmena-os.git
   cd colmena-os
   ```

2. **Set up environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

3. **Start services**:
   ```bash
   docker compose up -d
   ```

### Working with Submodules

```bash
# Update all submodules
git submodule update --remote --merge

# Update a specific submodule
cd frontend
git pull origin main
cd ..
git add frontend
git commit -m "Update frontend submodule"
```

### Testing

```bash
# Quick test
./scripts/clean_and_test.sh

# Full CI test
./scripts/ci-test.sh local

# Reset database
./scripts/reset_postgres.sh
```

## CI/CD Pipeline

See [GitHub Workflows Analysis](../context/github-workflows-analysis.md) for details on:

- Automated builds and testing
- Docker image publishing
- Balena fleet deployments
- Daily update checks

## Contributing

1. Check [Issues Roadmap](../context/issues-roadmap.md) for current tasks
2. Follow project conventions in [CLAUDE.md](../CLAUDE.md)
3. Test changes locally before pushing
4. Submit PRs with clear descriptions

## Support

- **GitHub Issues**: [github.com/luandro/colmena-os/issues](https://github.com/luandro/colmena-os/issues)
- **Documentation**: [docs.colmena.media](https://docs.colmena.media/)
- **Community**: [colmena.coop](https://colmena.coop/)

## License

MIT License - See [LICENSE](../LICENSE) for details.
