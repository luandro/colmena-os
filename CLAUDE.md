# Claude AI Assistant Context for ColmenaOS

This file provides context and guidelines for AI assistants working with the ColmenaOS project.

## Project Overview

ColmenaOS is an offline-first operating system for community radio and podcasting. It's built on BalenaOS and uses Docker containers for modularity. The project prioritizes:
- Offline functionality
- Low power consumption
- Community sovereignty over data
- Multi-architecture support (AMD64/ARM64)
- Easy deployment via Balena Cloud

## Technical Stack

### Core Technologies
- **OS**: BalenaOS (container OS)
- **Containerization**: Docker, Docker Compose
- **Backend**: Django (Python) - API and business logic
- **Frontend**: React PWA - Offline-capable progressive web app
- **Database**: PostgreSQL 13
- **File Storage**: Nextcloud
- **Email**: Mailcrab (development/testing)
- **CI/CD**: GitHub Actions + Balena Cloud
- **Registry**: Docker Hub

### Architecture Pattern
```
Frontend (React) → Backend (Django) → PostgreSQL
                ↓
            Nextcloud (Files)
```

## Project Structure

```
colmena-os/                 # Main repository
├── .github/               # GitHub Actions workflows and reusable actions
├── backend/               # Django backend (Git submodule)
├── frontend/              # React frontend (Git submodule)
├── devops/                # Infrastructure configs (Git submodule)
├── tests/                 # Test infrastructure and scripts
├── docker-compose.yml     # Service orchestration
├── balena.yml            # Balena configuration
└── docs/                 # Documentation
```

## Key Principles When Coding

1. **Offline First**: Always assume no internet connection. Cache aggressively, handle offline states gracefully.

2. **Resource Conscious**: Optimize for low-power devices (Raspberry Pi). Minimize CPU/RAM usage.

3. **Multi-Architecture**: Ensure all Docker images build for both AMD64 and ARM64.

4. **Security**: No hardcoded secrets. Use environment variables. Follow principle of least privilege.

5. **Idempotency**: All scripts and deployments should be safely re-runnable.

## Common Tasks

### When asked to modify Docker configurations:
- Check both `docker-compose.yml` and individual Dockerfiles
- Ensure changes work for both architectures
- Update balena.yml version if significant changes
- Consider impact on offline functionality

### When asked to update CI/CD:
- Workflows are in `.github/workflows/`
- Reusable actions are in `.github/actions/`
- Always test with `act` locally if possible
- Ensure Docker Hub credentials are referenced correctly

### When asked about deployment:
- Draft deployments are automatic (on push to develop)
- Production releases require manual approval
- Balena handles the actual device updates
- Check balena.yml for version management

### When asked to add features:
1. Consider offline functionality first
2. Check if it needs changes in frontend, backend, or both (submodules)
3. Update tests accordingly
4. Document environment variables in .env.example
5. Update README.md if user-facing

## Environment Variables

Key variables that must be set:
```
# Database
POSTGRES_PASSWORD
POSTGRES_USERNAME
POSTGRES_DB

# Services
NEXTCLOUD_ADMIN_PASSWORD
SECRET_KEY (Django)

# Balena
BALENA_TOKEN
BALENA_FLEET
```

## Testing Approach

1. **Local**: Use docker-compose for integration testing
2. **CI**: GitHub Actions run on every push
3. **Staging**: Balena draft fleet for real device testing
4. **Production**: Manual promotion after testing

Test commands:
```bash
# Local testing
docker compose up -d
./tests/test-integration.sh

# Create DO testbed
./tests/do-testbed_cli.sh create

# Test Balena deployment
./tests/test-balena.sh
```

## Submodule Management

The project uses Git submodules. When making changes:
```bash
# Update submodule
cd backend
git checkout main
git pull
# Make changes
cd ..
git add backend
git commit -m "Update backend submodule"
```

## Error Handling Patterns

1. **Network Errors**: Always provide offline fallbacks
2. **Resource Limits**: Implement graceful degradation
3. **Update Failures**: Ensure rollback capability
4. **User Errors**: Clear, actionable error messages

## Documentation Standards

- User docs: Simple, assume non-technical users
- Dev docs: Include architecture decisions
- API docs: OpenAPI/Swagger format preferred
- Inline comments: Explain "why" not "what"

## Security Considerations

- All services run unprivileged unless absolutely necessary
- Network isolation between services
- No external dependencies in production
- Regular dependency updates via Dependabot
- Input validation at every layer

## Performance Guidelines

- Images should be <500MB per service
- Cold start should be <2 minutes on RPi4
- API responses <200ms for local requests
- Frontend should work offline after first load

## Do's and Don'ts

### Do's
- ✅ Test on both architectures
- ✅ Consider power consumption
- ✅ Write idempotent code
- ✅ Document breaking changes
- ✅ Use semantic versioning

### Don'ts
- ❌ Add external dependencies without offline fallback
- ❌ Store secrets in code
- ❌ Assume reliable internet
- ❌ Break backward compatibility without version bump
- ❌ Ignore resource constraints

## Useful Commands

```bash
# Build all services locally
docker compose build

# Check logs
docker compose logs -f [service]

# Update all submodules
git submodule update --remote --merge

# Validate Balena configuration
balena push --dry-run

# Test multi-arch build
docker buildx build --platform linux/arm64,linux/amd64 .
```

## Related Documentation

- [README.md](./README.md) - Project overview
- [TASKS.md](./TASKS.md) - Current project tasks
- [CONTRIBUTING.md](./CONTRIBUTING.md) - Contribution guidelines
- [Architecture Docs](./docs/architecture.md) - Detailed architecture

## Getting Help

If you need clarification:
1. Check existing documentation first
2. Look for similar patterns in the codebase
3. Consider the offline-first principle
4. Ask for specific implementation details

## Version History

- v1.0.0 - Initial release with basic functionality
- v1.1.0 - Added automated CI/CD pipeline
- v1.2.0 - Current version with full Balena integration
