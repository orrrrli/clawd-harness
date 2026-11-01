---
name: project-bootstrap
stacks: [dotnet]
description: >
  Scaffold a brand-new full-stack project in one pass — backend .NET Clean
  Architecture + CQRS (MediatR) and mobile React Native/Expo — going from an
  already-filled root CLAUDE.md context straight to a working skeleton plus
  exactly one vertical slice example feature implemented end-to-end. Fills the
  gap between fill-context (context only, no code) and spec-apply (per-issue,
  too granular for day-zero). Use when the user wants to "levantar el
  proyecto", bootstrap a new app from scratch, scaffold Clean Architecture +
  Expo, or says "project-bootstrap".
trigger: /project-bootstrap
version: "1.0.0"
---

# Project Bootstrap

Turn an already-documented project into running code: solution skeleton +
**one** end-to-end vertical slice. Not a feature factory — a reference
implementation the developer (or a later Claude session) copies to build
everything else.

**Core principle:** the context already answered the business questions.
This skill answers the code-structure questions once, concretely, and stops.

---

## Phase 0 — Require real context

**Goal:** refuse to invent business context. This skill reads decisions, it
doesn't make them.

```bash
cat CLAUDE.md 2>/dev/null
```

- If the file is missing, or contains placeholder text like `[Entity 1]` or
  `[Explain in 1-2 paragraphs...]`, **stop** and tell the developer:
  > "No filled project context found. Run `fill-context` first — I need real
  > business rules and domain entities, not invented ones."
- Otherwise, read the linked files: `business/overview.md`,
  `business/rules.md`, `business/glossary.md`, `domains/*.md`,
  `architecture/overview.md`. Confirm the stack matches .NET Clean
  Architecture + CQRS and React Native/Expo — if `architecture/overview.md`
  names a different stack, stop and ask which one to scaffold for.

**Exit gate:** state the detected project name, the domain entities found,
and which single entity looks like the best candidate for the example slice
(smallest one with at least one real business rule attached). Ask the
developer to confirm or pick a different entity before continuing.

---

## Phase 1 — Plan the skeleton

**Goal:** decide exactly what gets created, nothing implicit.

Backend (`src/`):
```
src/
  Domain/            # entities, value objects, domain events — zero dependencies
  Application/       # CQRS commands/queries + handlers (MediatR), interfaces
  Infrastructure/    # EF Core DbContext, interface implementations
  Api/               # Minimal API endpoints, DI wiring, middleware
tests/
  Application.Tests/
  Api.Tests/         # integration, WebApplicationFactory
```

Mobile (`apps/mobile/` or repo-appropriate path):
```
app/                 # Expo Router file-based routes
lib/api/             # typed API client for the backend
lib/query/           # TanStack Query hooks
```

State the exact list of files this run will create — solution/project files,
the example slice's files per layer, and the mobile files. No file outside
this list gets written in Phase 3.

**Exit gate:** present the file list. Wait for confirmation before scaffolding.

---

## Phase 2 — Scaffold the skeleton

**Goal:** empty-but-wired structure. No business logic yet.

1. Create the .NET solution and four projects with correct project references
   (`Domain` → none, `Application` → `Domain`, `Infrastructure` →
   `Application`, `Api` → `Application` + `Infrastructure`).
2. Wire DI in `Api` (MediatR registration, DbContext registration, minimal
   health-check endpoint).
3. Create the two test projects referencing their targets.
4. Create the Expo app structure (or extend it if `apps/mobile` already
   exists) with Expo Router, TanStack Query provider, and an empty typed API
   client pointing at the backend's base URL from env.

Do not add authentication, generic repositories, service layers, or any
entity other than the one chosen in Phase 0 — that's out of scope for this
skill (see Hard rules).

---

## Phase 3 — Build the one vertical slice (Ponytail Principles)

**Goal:** implement the chosen entity's simplest real use case, end-to-end,
as the reference pattern for everything that comes after.

Apply the same discipline as `spec-apply`'s Apply phase:
1. **Does this need to exist at all?** Only what the slice requires.
2. **Already in the codebase?** Nothing yet — this run establishes the
   pattern others reuse. Don't pre-build abstractions for future slices.
3. **Stdlib / framework feature covers it?** Prefer it over a package.
4. **Minimum code that works.**

Anti-overengineering defaults for this stack — deviate only if
`architecture/overview.md` or `engineering/standards.md` explicitly says
otherwise:
- No generic `IRepository<T>` — a repository scoped to this one entity. Handlers
  never touch `DbContext`.
- No service layer duplicating what the Command/Query handler already does.
- No CQRS bus, no event sourcing, no outbox — MediatR in-process only.
- **Carter modules** on Minimal APIs, not Controllers.
- **FluentValidation only if the business rule is non-trivial** (more than a
  null/empty check) — otherwise validate inline in the handler.
- **`ErrorOr<T>`** for expected failure paths (validation, not-found) instead
  of throwing exceptions for control flow.
- Mobile: TanStack Query for the fetch/mutation, no Zustand unless the slice
  genuinely needs cross-screen state (it usually doesn't for one slice).

Slice contents (adjust command vs query to match the chosen use case):
- `Domain`: the entity + any invariant the business rule requires
- `Application`: one Command or Query + Handler, validation per the rule above
- `Infrastructure`: EF Core configuration/migration for the entity
- `Api`: one Carter module endpoint wired to the handler
- `Application.Tests`: handler test covering the business rule
- `Api.Tests`: one integration test hitting the endpoint
- Mobile: one screen (Expo Router route) that calls the endpoint via a
  TanStack Query hook and renders the result

After each file, state: file path + what it does + why (one line). Mark any
deliberate simplification with a `// ponytail:` comment, same convention as
`spec-apply`.

---

## Phase 4 — Verify it actually runs

**Goal:** prove the skeleton builds and the slice works, not just that files
exist.

```bash
dotnet build
dotnet test tests/Application.Tests
dotnet test tests/Api.Tests
```

```bash
cd apps/mobile && npx expo start   # or the repo's existing mobile run command
```

Report the result of each command. If something fails, fix it within this
skill's scope (the files it just created) — do not expand scope to fix
unrelated pre-existing issues; report those separately instead.

**Exit gate:** state pass/fail for build, both test projects, and whether the
mobile screen renders against the running API.

---

## Done

Report: what was scaffolded, where the example slice lives (list all files),
and the verify results. Then stop — **do not implement further features.**
Point the developer at:
- Normal prompting or `spec-apply` for the next feature, following the slice's
  pattern
- `prd-to-github-backlog` if they want the remaining work turned into tracked
  issues first

---

## Hard rules

- **Never run without a filled root `CLAUDE.md`.** Phase 0 is not
  optional — this skill must not invent business rules or entity names.
- **Exactly one vertical slice.** Not auth, not multiple entities, not every
  CRUD verb — one Command or Query, one endpoint, one screen. More features
  is what `spec-apply` and normal prompting are for afterward.
- **No new dependencies without asking** — same rule as `spec-apply`.
- **Ponytail principles apply to Phase 3 code**, same as `spec-apply`'s Apply
  phase — favor simplicity, reuse, and minimalism over premature structure.
- **Two stop gates only:** Phase 0 entity confirmation, Phase 1 file list.
  Phase 2–4 run straight through once confirmed — this is a single-pass
  bootstrap, not a per-task loop.
- If the repo already has a non-empty `src/` or conflicting structure, stop
  and ask before overwriting anything.
