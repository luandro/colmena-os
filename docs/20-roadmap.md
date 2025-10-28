# Roadmap

**Last updated:** 2025-10-24  
**Aligned objectives:** [1](./10-objectives.md#1-empower-community-media-with-an-offline-first-os), [2](./10-objectives.md#2-ship-a-unified-deployable-stack), [3](./10-objectives.md#3-reach-multi-platform-distribution-with-automation)

## Phase 1 — Unified Stack (Week 1)
**Goal:** Replace split frontend/backend deployments with a single container and compose file.  
**Owner:** Platform team  
**Key docs:** [`../context/unified-dockerfile.md`](../context/unified-dockerfile.md), [`30-implementation/docker-compose.md`](./30-implementation/docker-compose.md)

- ISSUE-001: Build unified Dockerfile (supervisor-based or equivalent). _Definition of done:_ image passes local smoke tests on amd64 and publishes to the internal registry.
- ISSUE-002: Merge devops services into the root `docker-compose.yml`. _Definition of done:_ `docker compose up` exposes app at `:8080`, backend at `:8000`, and support services.

## Phase 2 — Multi-Architecture (Week 2)
**Goal:** Enable arm64 + amd64 distribution for the unified image.  
**Owner:** Release engineering  
**Key docs:** [`../context/github-workflows-analysis.md`](../context/github-workflows-analysis.md)

- ISSUE-003: Configure Buildx and registry publishing. _Definition of done:_ automated build workflow pushes multi-arch manifests.

## Phase 3 — Platform Packaging (Week 3)
**Goal:** Ensure downstream platforms (CasaOS, Balena) consume the same compose definition.  
**Owner:** Integrations  
**Key docs:** [`../context/docker-compose-merge.md`](../context/docker-compose-merge.md), [`../context/FLOWCHART.md`](../context/FLOWCHART.md)

- ISSUE-004: CasaOS integration metadata and submission.
- ISSUE-005: Balena fleet configuration and onboarding docs.

## Phase 4 — Automation (Week 4)
**Goal:** Automate release flow end to end.  
**Owner:** DevOps  
**Key docs:** [`../context/github-workflows-analysis.md`](../context/github-workflows-analysis.md)

- ISSUE-006: CI/CD pipeline harmonizing image builds, Compose validation, and deployment triggers.

For implementation specifics, continue in [`30-implementation`](./30-implementation/README.md).
