# Contributing to ColmenaOS

We welcome contributions to the ColmenaOS project! This document outlines how to contribute effectively.

## Getting Started

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test your changes using the provided test suite
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Development Setup

### Prerequisites
- Docker and Docker Compose
- Balena CLI (for Balena-specific testing)
- Node.js 18+ (for development tools)

### Local Development
```bash
git clone https://gitlab.com/colmena-project/colmena-os.git
cd colmena-os
docker-compose up -d
```

### Testing
```bash
# Run all tests
cd tests
./do-testbed_cli.sh create test-env

# Test Balena deployment
./test-balena.sh
```

## Code Standards

- Use environment variables for all configuration
- Follow Docker best practices for multi-architecture builds
- Test on both AMD64 and ARM64 architectures
- Document all new features and configuration options

## Reporting Issues

When reporting issues, please include:
- Hardware specifications
- Operating system version
- Docker/Balena versions
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs

## License

By contributing, you agree that your contributions will be licensed under the MIT License.