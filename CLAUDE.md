# ColmenaOS Project Context

You only need two entry points:
- [`README.md`](README.md) — product overview, quick start, env setup, and links to app endpoints.
- [`docs/index.md`](docs/index.md) — documentation hub with objectives, roadmap, implementation briefs, runbooks (Docker, CasaOS, Balena), backlog, and archives.

For technical details jump directly to:
- [`docs/30-implementation/`](docs/30-implementation/README.md) for the unified Dockerfile, compose layout, CI/CD, and release flow.
- [`docs/40-runbooks/`](docs/40-runbooks/README.md) for day-to-day operations across platforms.
- [`docs/backlog.md`](docs/backlog.md) to see active tasks.

Keep scratch notes in `context/` and promote stable decisions into `docs/`. Update this file whenever the primary navigation changes.***

> **Submodule policy:** Git submodules (e.g., `backend/`, `frontend/`) must not be modified unless explicitly required to unblock testing or builds. Document any required deviation before committing.
