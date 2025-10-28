# Objectives

**Last updated:** 2025-10-24  
**Source inputs:** `README.md`, `context/issues-roadmap.md`

## 1. Empower Community Media with an Offline-First OS
- Deliver a self-contained stack that runs without internet and on low-power hardware.
- Provide recording, editing, storage, and broadcast tooling in a single deployment.
- Success check: demo sites operating in offline mode on target hardware (ARM64 + AMD64) with documented workflows.

## 2. Ship a Unified Deployable Stack
- Maintain a single Docker Compose bundle that includes the app, storage, mail, and database services.
- Back the bundle with one unified container image for frontend and backend.
- Success check: `docker compose up` from the repository root brings up all services and passes the acceptance tests captured in `tests/`.

## 3. Reach Multi-Platform Distribution with Automation
- Support CasaOS, Balena, and vanilla Docker installations from the same sources.
- Produce multi-architecture images (arm64, amd64) through CI/CD.
- Success check: automated pipeline publishes signed images, and deployment runbooks exist for CasaOS and Balena fleets.

Next: see [`20-roadmap.md`](./20-roadmap.md) for sequencing and owners.
