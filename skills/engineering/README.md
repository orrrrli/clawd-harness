# Engineering

Code-specific skills: architecture audits, spec-driven delivery, testing and debugging.

- **[android-clean-architecture](./android-clean-architecture/SKILL.md)** — Clean Architecture patterns for Android and Kotlin Multiplatform projects: module structure, dependency rules, UseCases, Repositories, and data layer patterns.
- **[audit-layer-boundaries](./audit-layer-boundaries/SKILL.md)** — Scan the codebase for the three architectural violations that break the layer contract in this project.
- **[diagnose](./diagnose/SKILL.md)** — Disciplined diagnosis loop for hard bugs and performance regressions. Reproduce → minimise → hypothesise → instrument → fix → regression-test.
- **[dotnet-clean-architecture](./dotnet-clean-architecture/SKILL.md)** — Scan a .NET Clean Architecture solution for the five violations that break the dependency rule.
- **[fill-context](./fill-context/SKILL.md)** — Build or regenerate the full .claude/ context tree by scanning the codebase and grilling the developer on what can't be inferred from code alone.
- **[improve-codebase-architecture](./improve-codebase-architecture/SKILL.md)** — Find deepening opportunities in a codebase, informed by the .claude/ context tree and past rejections in engram, presented as a claude.ai Artifact report. Manual only.
- **[prd-to-github-backlog](./prd-to-github-backlog/SKILL.md)** — Turn a PRD/spec into a GitHub Project with a full engineering backlog: epics → vertical-slice `fullstack` stories → task sub-issues with their own area, organized by phase and sprint.
- **[project-bootstrap](./project-bootstrap/SKILL.md)** — Scaffold a brand-new full-stack project in one pass: a working skeleton plus exactly one vertical slice implemented end-to-end.
- **[prompt-rewrite](./prompt-rewrite/SKILL.md)** — Audit or rewrite LLM instructions (a skill, CLAUDE.md, agent definition, system prompt, tool description or a single prompt) against Anthropic's prompting guidance for current Claude models.
- **[spec-apply](./spec-apply/SKILL.md)** — Implement a GitHub Story across every layer it touches in one spec-driven cycle, its Task sub-issues as the checklist: the AC become failing tests written by test-writer, then ponytail code makes them pass.
- **[spec-verify](./spec-verify/SKILL.md)** — Verify an implementation against its Story's acceptance criteria and the code-quality spec, in a fresh code-reviewer subagent, with a mutation check that proves each test catches a fault, and the e2e and browser checks against the real stack (deferred in light mode).
- **[tdd](./tdd/SKILL.md)** — Test-driven development with red-green-refactor loop.
- **[write-swift](./write-swift/SKILL.md)** — Modern Swift: value types, Swift 6 concurrency, some vs any, API design, performance, Swift Testing. Vendored from emilkowalski/skills; its license ships in the folder.
