# Repository Guidelines

## Project Structure & Module Organization
- Root: Docker configs (`docker-compose*.yml`), integration tests (`tests/`, Playwright), helper scripts.
- Backend (Django): `backend/` with apps under `backend/apps/`, settings in `backend/colmena/`, Makefile-driven tasks.
- Frontend (React + Vite + TS): `frontend/` with source in `frontend/src/` and build tooling.
- Submodules: NEVER modify contents directly (e.g., `colmena-devops`). Propose changes upstream and only update the submodule commit/pointer.

## Architecture & Docker Objective
- Unified image: Frontend and Backend run inside a single container image published to Docker Hub (`communityfirst/colmena-app`).
- Compose must “just work”: `docker compose up -d` using `docker-compose.yml` should pull the prebuilt image (no local build) and start all services.
- Keep this contract: if you change image name/tag or ports, update compose and docs so the pull-and-run flow remains seamless.

## Build, Test, and Development Commands
- Backend: `make -C backend venv setup server` — create venv, install deps, init DB, run dev server.
- Backend tests: `make -C backend test` (tags: `test.wip`, `test.nextcloud`); coverage: `USE_COVERAGE=1 make -C backend test`.
- Backend lint/format: `make -C backend lint` (Black).
- Frontend dev: `npm --prefix frontend install && npm --prefix frontend run dev`.
- Frontend build: `npm --prefix frontend run build`; preview: `npm --prefix frontend run preview`.
- Frontend tests: `npm --prefix frontend test` or `npm --prefix frontend run coverage`.
- E2E/integration: from repo root `npm install && npm test` (Playwright).
- Service checks: `node test-verification.js` verifies core endpoints and container health.
- Full stack via Docker: `docker compose up -d` (pulls unified image).

## Coding Style & Naming Conventions
- Python: format with Black (88 cols). Modules/functions `snake_case`; classes `PascalCase`. Django apps live under `backend/apps/<app_name>/`.
- TypeScript/React: ESLint + Prettier. Components `PascalCase` (`MyComponent.tsx`), functions/vars `camelCase`, files usually `kebab-case` for non-components.
- Keep imports ordered and avoid unused exports; run `npm --prefix frontend run lint` and `... run prettier` before pushing.

## Testing Guidelines
- Goal: automated confidence that all services are up and core flows work.
- Playwright: primary end-to-end tests. Run `npm test` after `docker compose up -d`.
- JS service checks: use `node test-verification.js` to assert ports/services before E2E.
- Backend: Django test runner (optional `django-nose` coverage). Place tests under app `tests/` and use tags (`wip`, `nextcloud`) when helpful.
- Frontend: Vitest + Testing Library with `*.test.ts(x)` in `src/`.

## Commit & Pull Request Guidelines
- Commits: follow Conventional Commits (`feat:`, `fix:`, `chore:`) as seen in history.
- PRs: include clear summary, linked issues (`Closes #123`), steps to test, and screenshots for UI changes. Note migrations or env changes; update `.env.example` if applicable.

## Security & Configuration Tips
- Never commit secrets. Use `.env.example` (root, `backend/`, `frontend/`) to document required variables.
- Prefer local `.env` files and Docker overrides for secrets; avoid hardcoding URLs/keys in source.
