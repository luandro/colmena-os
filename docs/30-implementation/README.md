# Implementation Notes

These notes anchor stable configuration decisions. Detailed scratch work remains in `context/`.

- [`docker-compose.md`](./docker-compose.md) — canonical service layout, port map, and environment expectations used by Docker, CasaOS, and Balena.
- [`unified-dockerfile.md`](./unified-dockerfile.md) — multi-stage build, supervisor processes, and nginx proxy configuration for the unified image.
- [`ci-cd.md`](./ci-cd.md) — GitHub Actions workflows, multi-arch build strategy, and required quality gates.
- [`release-flow.md`](./release-flow.md) — daily build to Balena production promotion flow, responsibilities, and rollback plan.

Add new files here as decisions harden, and link back to the roadmap items they satisfy.
