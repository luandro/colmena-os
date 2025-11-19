# PR #6 Issue Tracking

This directory tracks all findings and action items related to PR #6: "Fix root Dockerfile to ensure successful local Docker Compose setup"

## Directory Structure
- `TRACKING.md` - This file, overall tracking and directory index
- `PROGRESS.md` - **Canonical progress tracker** with completion status and statistics
- `issue-7-openapi-schema.md` - Detailed tracking for OpenAPI schema generation issues
- `pr-6-synthesized-review.md` - Comprehensive review synthesis
- `pr-6-summary-comment.md` - Summary for PR comment

## Quick Status (from PROGRESS.md)
- ✅ **6 issues completed** (Issues #5a, #6, #8, #9, #10, #14)
- 🚫 **3 issues excluded** (Submodule-related: #11, #12, #17)
- ⏳ **6 issues remaining** (Critical: #5b/5c, #13 | High: #16, #18 | Medium: #15, #19)
- 🔴 **1 critical blocker**: Issue #7 (OpenAPI schema generation) - See below

## Critical Issues Status

### Issue #7: OpenAPI Schema Generation (CRITICAL)
**Related NEXT_STEPS.md Findings**: #3, #7, #8

**Status**: 🔴 OUTSTANDING

**Problem Summary**:
The unified Dockerfile tolerates build failures by generating stub assets, allowing CI to pass while shipping broken functionality:

1. **Finding #3**: Dockerfile fallback logic generates placeholder HTML and `any`-typed definitions when frontend/backend builds fail
2. **Finding #7**: `schema-runtime.json` remains empty, causing `vite-plugin-pwa` to fail and ship placeholder HTML shell
3. **Finding #8**: Emergency OpenAPI stubs declare `Paths`/`Schemas` as plain types instead of namespaces, producing TypeScript errors (TS2702/TS2713)

**Evidence**:
- `Dockerfile:78-149` - Fallback logic for stub generation
- `Dockerfile:52-108` - Schema generation stage
- `docker build --no-cache --target frontend-builder` logs show RollupError parsing `schema-runtime.json`
- `frontend/src/service/team.ts:1-200` - TS2702/TS2713 namespace errors
- `frontend/src/pages/User/Configuration/Invitation/InvitationForm.tsx:105-220` - More namespace errors

**Next Steps**:
1. Review the fallback logic in Dockerfile:78-149
2. Define guardrails so failed builds surface as blocking CI failures
3. Ensure backend OpenAPI export succeeds before copying to frontend
4. Fix emergency OpenAPI stubs to use proper namespace declarations
5. Prevent build from degrading to `any` types or placeholder assets

**Related PR #6 Review Items**:
- Issue #7 from synthesized review (line 237)
- Issue #8 from synthesized review (line 242)

See: `issue-7-openapi-schema.md` for detailed tracking

---

## Outstanding Issues (from PR #6 Summary)

### 🔴 Must Fix Before Merge
- [x] **Issue #5a**: Reduce postgres max_connections from 10000 to 100-200 (`docker-compose.yml:10`) - ✅ COMPLETED (commit `65ce581`)
- [ ] **Issue #5b/5c**: Add database connection retry logic and handle migration failures (`start-backend.sh:63-105`)
- [x] **Issue #8**: Fix Unix socket permissions from 777 to 660 (`docker/colmena-app-entrypoint.sh:124`) - ✅ COMPLETED (commits `06cc1c7`, `8075048`)
- [ ] **Issue #7**: OpenAPI schema generation failures (see above)

### 🟡 Follow-Up (Post-Merge Acceptable)
- [x] **Issue #6**: Remove Nextcloud `privileged: true`, use specific capabilities (`docker-compose.yml:66`) - ✅ COMPLETED (commit `65ce581`)
- [x] **Issue #9**: Consolidate nginx configs (embedded vs mounted approach) - ✅ COMPLETED (commit `4c8cdcc`)
- [x] **Issue #10**: Add nginx security headers (CSP, HSTS, etc.) - ✅ COMPLETED (commits `947adee`, `ae75074`)
- [ ] **Issue #12**: Add backend unit tests to CI (🚫 Excluded - submodule-related)
- [ ] **Issue #13**: Add container security scanning (Trivy/Grype/Snyk) to CI
- [x] **Issue #14**: Document `SECRET_KEY` vs `COLMENA_SECRET_KEY` responsibilities - ✅ COMPLETED (commit `65ce581`)

### 🟢 Nice To Have (Future)
- [ ] **Issue #15**: Optimize Docker build caching
- [ ] **Issue #16**: Add resource constraints to docker-compose.yml
- [ ] **Issue #17**: Add API integration tests
- [ ] **Issue #18**: Broaden test coverage (DB failures, network partitions, etc.)
- [ ] **Issue #19**: Create architecture diagram
- [ ] **Issue #11**: Remove TypeScript sed workaround

---

## Resolved Issues (from PR #6 Summary)

### ✅ Addressed
- [x] **Issue #1**: Supervisor config conflict (commits `1fcf71a`, `740e686`)
- [x] **Issue #2**: Script naming confusion (commit `cc4419a`)
- [x] **Issue #3**: Port configuration alignment (commit `57ce357`)
- [x] **Issue #4**: CI-only credentials disclosure (commit `d37b97a`)
- [x] **Issue #7 (partial)**: Environment variable validation (commits `419b1a2`, `56bb24d`)
- [x] **Workflow hygiene**: Concurrency guards, cache usage, path filters (commits `12f583d`, `405a651`, `2dc9ebb`)

### ✅ From NEXT_STEPS.md
- [x] **Finding #2**: Image naming split between `communityfirst/colmena-app` and `colmena-unified` → Resolved by workflow consolidation in PR #6

---

## Next Actions

1. **Address Issue #7 (OpenAPI schema)** - Critical blocker
2. **Fix remaining PR #6 outstanding issues** (#5a, #5b/5c, #8)
3. **Re-run CI tests** to confirm fixes
4. **Request final review** with updated tracking

---

Last Updated: 2025-11-01
