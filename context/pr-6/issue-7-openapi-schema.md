# Issue #7: OpenAPI Schema Generation Failures

**Status**: 🔴 CRITICAL - Must fix before PR #6 merge

**Related NEXT_STEPS.md Findings**: #3, #7, #8

---

## Problem Statement

The unified Dockerfile contains fallback logic that silently tolerates build failures, allowing CI to pass while shipping broken frontend functionality. This creates three interconnected issues:

### 1. Silent Build Failures (NEXT_STEPS Finding #3)
**Location**: `Dockerfile:78-149`

The Dockerfile generates stub assets when builds fail:
- Placeholder HTML shells
- `any`-typed TypeScript definitions
- Empty JSON schemas

**Impact**: CI succeeds while shipping non-functional code

**Evidence**:
```dockerfile
# Dockerfile fallback logic allows builds to continue even when:
# - Backend OpenAPI export fails
# - Frontend build fails due to schema issues
# - TypeScript compilation errors occur
```

### 2. Empty Schema Runtime (NEXT_STEPS Finding #7)
**Location**: `Dockerfile:52-108`

**Problem**: Building the unified image leaves `schema-runtime.json` empty

**Impact**:
- `vite-plugin-pwa` fails to parse the empty JSON file
- Build ships placeholder HTML shell instead of real PWA bundle
- Users receive broken frontend with missing functionality

**Error Evidence**:
```
docker build --no-cache --target frontend-builder
...
RollupError: Failed to parse JSON file /app/frontend/src/api/utilities/schema-runtime.json
```

**Why It Happens**:
- Backend OpenAPI export step fails or produces invalid output
- Empty/invalid JSON is copied to frontend build context
- Frontend build tooling (Vite, vite-plugin-pwa) fails to parse
- Fallback logic generates placeholder instead of failing build

### 3. TypeScript Namespace Errors (NEXT_STEPS Finding #8)
**Location**:
- `frontend/src/service/team.ts:1-200`
- `frontend/src/pages/User/Configuration/Invitation/InvitationForm.tsx:105-220`

**Problem**: Emergency OpenAPI stubs declare `Paths`/`Schemas` as plain types, but frontend code treats them as namespaces

**Error Evidence**:
```
npm run build
...
TS2702: 'Paths' only refers to a type, but is being used as a namespace here.
TS2713: Cannot access 'Schemas.UserRead' because 'Schemas' is a type, but not a namespace.
```

**Impact**:
- Dozens of TypeScript compilation errors during `npm run build`
- Build degrades to using `any` types
- Type safety completely lost
- Runtime errors become likely

**Why It Happens**:
- Emergency stubs use incorrect TypeScript declaration syntax
- Frontend code expects namespace-style access (`Schemas.UserRead`)
- Stubs provide type-style declarations instead
- Type checker fails, build falls back to `any` types

---

## Root Cause Analysis

### Chain of Failures

1. **Backend OpenAPI Export Fails**
   - Django management command may error
   - Output JSON may be malformed or empty
   - Error is silently caught by fallback logic

2. **Empty Schema Propagates**
   - Empty/invalid `schema-runtime.json` copied to frontend
   - Frontend build tools fail to parse invalid JSON
   - Fallback logic activates instead of failing build

3. **Emergency Stubs Activated**
   - TypeScript stubs use incorrect syntax (type vs namespace)
   - Frontend code incompatible with stub declarations
   - Build succeeds with `any` types, losing all type safety

4. **CI Passes, Production Breaks**
   - No blocking failure signals
   - Broken frontend ships to users
   - Runtime errors occur in production

### Why This Is Critical

- **Silent Failures**: No visibility into build problems until runtime
- **False Positives**: CI shows green while shipping broken code
- **Type Safety Loss**: `any` types mask potential runtime errors
- **User Impact**: Broken frontend functionality in production
- **Debug Difficulty**: Issues only surface after deployment

---

## Solution Requirements

### 1. Fail Fast on Schema Generation Errors
**Requirement**: Backend OpenAPI export must block build on failure

**Implementation Options**:
- Remove `|| true` fallback logic from schema generation
- Add explicit validation of `schema-runtime.json` content
- Exit with non-zero code if schema is empty or invalid

**Validation Checks**:
```bash
# After schema generation, verify:
- File exists and is not empty
- JSON is valid and parseable
- Required top-level keys present (paths, components, etc.)
- No stub/placeholder content
```

### 2. Validate Schema Before Frontend Build
**Requirement**: Frontend build must verify schema validity before proceeding

**Implementation Options**:
- Add pre-build validation step
- Check schema has required structure
- Fail build if schema is invalid

**Example Validation**:
```javascript
// validate-schema.js
const schema = require('./src/api/utilities/schema-runtime.json');
if (!schema.paths || !schema.components) {
  throw new Error('Invalid OpenAPI schema');
}
```

### 3. Fix Emergency Stub Declarations
**Requirement**: If stubs must exist, they should match frontend usage patterns

**Current Problem**:
```typescript
// Emergency stub (WRONG)
export type Paths = { /* ... */ };
export type Schemas = { /* ... */ };

// Frontend usage
import { Paths, Schemas } from './api-client';
const user: Schemas.UserRead = ...; // TS2713 error!
```

**Required Fix**:
```typescript
// Emergency stub (CORRECT)
export namespace Paths {
  // path declarations
}
export namespace Schemas {
  // schema declarations
}

// Frontend usage now works
import { Schemas } from './api-client';
const user: Schemas.UserRead = ...; // ✓ No error
```

### 4. Add CI Validation
**Requirement**: CI must catch schema generation failures

**Implementation**:
- Add explicit test step that validates schema-runtime.json
- Check TypeScript compilation with real schema
- Fail CI if schema is invalid or missing

---

## Proposed Implementation Plan

### Phase 1: Add Schema Validation (Immediate)
1. Add validation script to check schema-runtime.json after generation
2. Make script fail build if schema is invalid or empty
3. Remove `|| true` fallbacks that hide errors

### Phase 2: Fix Emergency Stubs (Immediate)
1. Update stub declarations to use namespace syntax
2. Ensure compatibility with frontend usage patterns
3. Test that stubs compile without TS errors

### Phase 3: Add CI Tests (Before Merge)
1. Add CI step to validate schema generation
2. Run TypeScript compilation as part of CI
3. Ensure build fails on schema or type errors

### Phase 4: Improve Observability (Follow-up)
1. Add logging for schema generation steps
2. Capture and report validation errors clearly
3. Add metrics/monitoring for schema generation success rate

---

## Testing Plan

### Unit Tests
- [ ] Test schema validation logic
- [ ] Test that invalid schemas are rejected
- [ ] Test that valid schemas pass validation

### Integration Tests
- [ ] Build with valid backend (schema should be generated)
- [ ] Build with missing backend (should fail, not fall back to stubs)
- [ ] Build with invalid schema (should fail, not use stubs)

### CI Tests
- [ ] Add explicit schema validation step to CI
- [ ] Verify TypeScript compilation with real schema
- [ ] Ensure builds fail on schema errors

### Manual Verification
- [ ] Build unified image and verify schema-runtime.json content
- [ ] Check frontend bundle includes real PWA assets (not placeholder)
- [ ] Verify TypeScript compilation produces no namespace errors
- [ ] Test frontend functionality with real API

---

## Related Issues

- **PR #6 Issue #7**: Input validation (partially related to schema validation)
- **PR #6 Issue #11**: TypeScript sed workaround (remove once schema generation fixed)
- **NEXT_STEPS Finding #3**: Dockerfile fallback logic
- **NEXT_STEPS Finding #7**: Empty schema-runtime.json
- **NEXT_STEPS Finding #8**: TypeScript namespace errors
- **Backlog Item**: Re-enable frontend TypeScript checker once OpenAPI generation reliable

---

## Next Steps

1. [ ] Review current schema generation logic in backend
2. [ ] Add validation checks for schema-runtime.json
3. [ ] Fix emergency stub declarations (type → namespace)
4. [ ] Remove fallback logic that allows empty schemas
5. [ ] Add CI test for schema validation
6. [ ] Test full build with validation enabled
7. [ ] Update PR #6 tracking when resolved

---

## References

- Dockerfile: Lines 52-108 (schema generation), 78-149 (fallback logic)
- Frontend services: `frontend/src/service/team.ts`
- Frontend components: `frontend/src/pages/User/Configuration/Invitation/InvitationForm.tsx`
- Build logs: `docker build --no-cache --target frontend-builder`
- PR #6 Review: `context/pr-6/pr-6-synthesized-review.md` (Issues #7, #8, #11)

---

Last Updated: 2025-11-01
