# CI/CD Pipeline

**Related roadmap item:** ISSUE-006  
**Primary objective:** [3 — Reach Multi-Platform Distribution with Automation](../10-objectives.md#3-reach-multi-platform-distribution-with-automation)

## Workflow Overview
- `test-pipeline.yml` — validates workflows locally, runs integration deploy tests, and reports results to pull requests.
- `build-and-push.yml` — builds the unified application image for amd64 and arm64 using Docker Buildx and pushes manifests to the registry.
- `deploy-balena-production.yml` — promotes vetted images to the Balena production fleet after manual approval.
- `claude.yml` — assists PR reviews; dependency only, no release impact.

## Build Strategy
1. Determine target platforms and version from Git metadata.
2. Build the unified container image with `--platform linux/amd64,linux/arm64`.
3. Push tagged multi-arch manifests to Docker Hub (`colmena/unified`).
4. Notify downstream workflows when a new image is available.

## Testing & Quality Gates
- Local workflow syntax validation via `act`.
- Integration smoke tests using `docker compose -f docker-compose.local.yml`.
- Unified container smoke test `./tests/test-unified.sh` (ensure workflow includes this step).
- Security scans inherit from existing build jobs; keep Trivy/Grype in place when updating.

## Release Promotion
- Draft images deploy automatically to the Balena test fleet.
- Human testing required before triggering production promotion.
- Production run requires manual workflow dispatch or signed tag.

## Open Items
- Ensure `test-pipeline.yml` calls the unified smoke test job before merges.
- Update `build-and-push.yml` matrix to skip legacy frontend/backend-only builds.
- Watch for pkg_resources deprecation warning in supervisord image.

These items are tracked in [`../backlog.md#active-initiatives`](../backlog.md#active-initiatives); update the backlog when work progresses.
