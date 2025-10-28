# Release Flow

**Related roadmap items:** ISSUE-003, ISSUE-006  
**Primary objective:** [3 — Reach Multi-Platform Distribution with Automation](../10-objectives.md#3-reach-multi-platform-distribution-with-automation)

```mermaid
flowchart TD
    A[Daily GitHub Action] --> B{Submodule Updates?}
    B -->|Yes| C[Build Unified Image]
    B -->|No| Z[Exit]
    C --> D[Push Multi-Arch Manifest to Docker Hub]
    D --> E[Trigger Draft Deployment to Balena Fleet]
    E --> F[Devices Pull Draft Release]
    F --> G[Human QA]
    G -->|Approved| H[Manual Release Dispatch]
    H --> I[Deploy to Balena Production Fleet]
```

## Key Responsibilities
- **Automation:** Handle daily checks, build, and draft deployment.
- **Release Manager:** Validate draft fleet, approve production run.
- **Ops:** Monitor device rollout and rollback if required.

## Rollback Plan
- Retain previous tagged images in Docker Hub.
- Use Balena dashboard to pin devices back to prior release if post-deploy checks fail.

For raw brainstorming diagrams see [`../context/FLOWCHART.md`](../context/FLOWCHART.md).
