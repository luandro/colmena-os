# CI/CD Pipeline

**Related roadmap item:** ISSUE-006  
**Primary objective:** [3 — Reach Multi-Platform Distribution with Automation](../10-objectives.md#3-reach-multi-platform-distribution-with-automation)

## Workflow Overview
- `test-pipeline.yml` — validates workflows locally, runs integration deploy tests, and reports results to pull requests.
- `build-unified.yml` — runs compose smoke + Playwright tests against a locally built image, then pushes the unified amd64/arm64 manifest to Docker Hub.
- `deploy-balena-production.yml` — promotes vetted images to the Balena production fleet after manual approval.
- `claude.yml` — assists PR reviews; dependency only, no release impact.

## Build Strategy
1. Determine target platforms and version from Git metadata.
2. Build the unified container image with `--platform linux/amd64,linux/arm64`.
3. Push tagged multi-arch manifests to Docker Hub (`communityfirst/colmena-app`).
4. Notify downstream workflows when a new image is available.

## Testing & Quality Gates
- Local workflow syntax validation via `act`.
- `scripts/compose-smoke.sh` verifies container health and key HTTP endpoints before any push.
- Playwright smoke suite (`tests/playwright`) exercises server onboarding, authentication, and core navigation against the running stack.
- **Container Security Scanning**: Trivy vulnerability scanner runs in CI pipelines:
  - PR validation: Scans local builds and reports vulnerabilities without blocking merges
  - Production publish: Scans published images and blocks deployment on CRITICAL vulnerabilities
  - SARIF reports uploaded to GitHub Security tab for visibility
  - Severity filtering: CRITICAL and HIGH vulnerabilities tracked, CRITICAL blocks production

## Release Promotion
- Draft images deploy automatically to the Balena test fleet.
- Human testing required before triggering production promotion.
- Production run requires manual workflow dispatch or signed tag.

## Open Items
- Wire Playwright smoke artifacts into release notes for easier debugging when failures arise.
- Watch for `pkg_resources` deprecation warning in the supervisord image.

These items are tracked in [`../backlog.md#active-initiatives`](../backlog.md#active-initiatives); update the backlog when work progresses.
