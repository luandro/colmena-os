# Context Directory

This directory contains working notes, issue plans, and historical archives for ColmenaOS development.

## Active Work

### PR #6 Tracking
See `pr-6/` directory for comprehensive tracking of PR #6: "Fix root Dockerfile to ensure successful local Docker Compose setup"

- `pr-6/TRACKING.md` - Overall PR #6 issue tracking and status
- `pr-6/issue-7-openapi-schema.md` - Detailed tracking for critical OpenAPI schema generation issues
- `pr-6/pr-6-synthesized-review.md` - Comprehensive review synthesis
- `pr-6/pr-6-summary-comment.md` - PR comment summary

### Active Issue Plans
- `issue-9-plan.md` - Issue #9 planning and implementation notes
- `issue-10-plan.md` - Issue #10 (nginx security headers) implementation plan and tracking

### Scratchpads
- `issues-roadmap.md` - Draft milestones and notes before promotion to `docs/20-roadmap.md`
- `FLOWCHART.md` - System architecture flowchart

## Organization Guidelines

### When to Use Context vs Docs
- **Context**: Scratch work, investigation notes, issue-specific plans, PR tracking
- **Docs**: Stable, canonical information ready for team consumption

### File Lifecycle
1. **Create** in `context/` for active work and investigation
2. **Track** progress with clear status markers
3. **Promote** stable decisions to `docs/` when ready
4. **Archive** completed work to `archive/` for historical reference
5. **Delete** truly obsolete files that provide no future value

### Naming Conventions
- `issue-N-plan.md` - Plans and tracking for specific GitHub issues
- `pr-N-*.md` - PR-related tracking and reviews (keep in `pr-N/` subdirectory)
- `*-roadmap.md` - Draft planning before promotion to docs
- `*-analysis.md` - Technical analysis and investigation
- `*-todo.md` - Task checklists (archive when complete)

## Archive

See `archive/README.md` for historical context files that are no longer actively used but preserved for reference.

Archived materials include:
- Completed workflow improvement checklists
- Historical docker setup and merge notes
- Previous architectural analysis

---

Last Updated: 2025-11-01
