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

<skills_system priority="1">

## Available Skills

<!-- SKILLS_TABLE_START -->
<usage>
When users ask you to perform tasks, check if any of the available skills below can help complete the task more effectively. Skills provide specialized capabilities and domain knowledge.

How to use skills:
- Invoke: Bash("openskills read <skill-name>")
- The skill content will load with detailed instructions on how to complete the task
- Base directory provided in output for resolving bundled resources (references/, scripts/, assets/)

Usage notes:
- Only use skills listed in <available_skills> below
- Do not invoke a skill that is already loaded in your context
- Each skill invocation is stateless
</usage>

<available_skills>

<skill>
<name>webapp-testing</name>
<description>Toolkit for interacting with and testing local web applications using Playwright. Supports verifying frontend functionality, debugging UI behavior, capturing browser screenshots, and viewing browser logs.</description>
<location>project</location>
</skill>

</available_skills>
<!-- SKILLS_TABLE_END -->

</skills_system>
