---
name: fill-context
stacks: [all]
description: >
  Build or regenerate the full .claude/ context tree by scanning the codebase and
  grilling the developer on what can't be inferred from code alone. Produces a
  multi-file context structure (business, architecture, domains, engineering) with
  the root CLAUDE.md as the index. Use after project init or whenever context is
  missing, stale, or incomplete.
version: "3.0.0"
modes: [architect]
---

# Fill Context

Build a complete `.claude/` context tree from real project data — not guesses, not placeholders.

**Core principle:** Derive everything possible from the codebase first. Only ask the developer for what the code cannot tell you.

**Why the root `CLAUDE.md` is the index, not `.claude/CLAUDE.md`:** Claude Code
accepts a project CLAUDE.md in *either* location — `./CLAUDE.md` and
`./.claude/CLAUDE.md` are both auto-loaded at session start. So this is not
about one being read and the other ignored. It is about picking one: keep both
and you get two project instruction files that drift apart, and the docs warn
that contradicting instructions make Claude choose arbitrarily. The root file
is the convention — `/init` writes there, and it is what shows up on clone. So
the root `CLAUDE.md` IS the index; there is no separate `.claude/CLAUDE.md`.

The files the index links to (`.claude/business/rules.md` and friends) are not
auto-loaded by anything: they are plain markdown that Claude opens when a task
leads it there. That is the point — cheap index always present, detail read on
demand.

**Output structure:**
```
CLAUDE.md                    # Main index — auto-loaded every session, at the repo root
.claude/
├── business/
│   ├── overview.md          # Purpose, users, success metrics
│   ├── rules.md             # Non-negotiable business rules
│   └── glossary.md          # Ubiquitous language
├── architecture/
│   ├── overview.md          # Stack, patterns, directory structure
│   └── integrations.md      # External services and APIs
├── domains/
│   └── [entity].md          # One file per main domain entity
└── engineering/
    ├── standards.md         # Coding conventions and patterns
    └── testing.md           # Test strategy, commands, full-stack start, e2e
```

---

## Phase 1 — Scan the Codebase

Run all scans silently. Do NOT report findings yet — collect data to populate every file above.

### 1.1 Framework and stack
```bash
cat package.json 2>/dev/null || cat pyproject.toml 2>/dev/null || cat *.csproj 2>/dev/null | head -60
```

### 1.2 Directory structure
```bash
eza --tree --level=3 --ignore-glob="node_modules|.git|.next|dist|build|coverage" 2>/dev/null || find . -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/.next/*' -maxdepth 3 -type d
```

### 1.3 Domain entities (schema + models)
```bash
cat prisma/schema.prisma 2>/dev/null
cat src/Domain/**/*.cs 2>/dev/null | head -200
find . -name "*.sql" -not -path '*/node_modules/*' | head -5 | xargs cat 2>/dev/null | head -100
```

### 1.4 README
```bash
cat README.md 2>/dev/null | head -80
```

### 1.5 Existing context
```bash
cat CLAUDE.md 2>/dev/null && ls .claude/ 2>/dev/null
```

### 1.6 Engineering conventions
```bash
cat .eslintrc* 2>/dev/null | head -30
cat jest.config* 2>/dev/null | head -20
cat vitest.config* 2>/dev/null | head -20
cat tsconfig.json 2>/dev/null | head -30
```

From the scan, extract:
- **App name** — from `package.json` or README
- **Framework + version** — Next.js, .NET, Django, etc.
- **Database, backend, ORM** — from deps and schema files
- **Key integrations** — from `package.json` deps (Stripe, Resend, Supabase…)
- **Domain entities** — model/schema names → these become `domains/*.md` files
- **Directory conventions + architecture pattern** — from file structure
- **Test framework and run commands** — from `package.json` scripts and config files
- **Coding conventions** — from ESLint, tsconfig, file naming patterns

---

## Phase 2 — Targeted Grill

Only ask about what Phase 1 could NOT determine. Never ask for something the code already told you.

Say exactly this to the developer:

> "I've scanned the codebase. It's a **[detected stack]** project with these domain entities: **[detected entities]**. I need [N] answers to build the full context — the code can't tell me these:"

Then ask ONLY these questions (all at once, numbered):

1. **Business purpose** — What problem does this project solve, who uses it, and what does success look like? (2-3 sentences; include success metrics like "fast load times", "zero data loss")
2. **Business rules** — What are the 2-3 rules the code must NEVER break? (e.g., "Users cannot access other accounts' data", "Soft deletes only, never hard deletes")
3. **Domain vocabulary** — Are any entity names in the code different from how the business talks about them? (e.g., "`User` in code = `Client` in the business")
4. **Domain context** — For each entity detected, what is its core responsibility in one sentence? (Skip any that are self-evident)

Wait for the developer's answers before proceeding to Phase 3.

---

## Phase 3 — Generate Files

Using Phase 1 data + Phase 2 answers, generate every file. Show file content to the developer before writing.

### Root `CLAUDE.md` — the index

**If a root `CLAUDE.md` already exists with real content** (not a bare stub, and not
just this skill's own index format from a prior run): do NOT overwrite it wholesale.
Read it fully first. Any section in it that doesn't already belong in the segmented
tree (team workflow, git conventions, ticket-tracker config, deploy commands, etc.)
stays in the root file, verbatim, in its own section — merge the index links in
underneath rather than replacing the file. The root file is allowed to carry both
project-specific operating rules AND the context index at once; it does not need to
be minimal. What it must never be is a stub that just points at a second index file
inside `.claude/` — see the "Why the root CLAUDE.md is the index" note above.

**If no root `CLAUDE.md` exists, or it's just the bare `harness.sh` stub:**
generate it fresh with this shape:

```markdown
# [Project Name] — Claude Code Instructions

[If existing root content had a project description/intro, keep it here verbatim.]

## Business
- [Overview](.claude/business/overview.md) — Purpose, users, success metrics
- [Rules](.claude/business/rules.md) — Non-negotiable business rules
- [Glossary](.claude/business/glossary.md) — Ubiquitous language

## Architecture
- [Overview](.claude/architecture/overview.md) — Stack, patterns, directory structure
- [Integrations](.claude/architecture/integrations.md) — External services and APIs

## Domains
[One link per detected entity]
- [[Entity]](.claude/domains/[entity].md)

## Engineering
- [Standards](.claude/engineering/standards.md) — Coding conventions and patterns
- [Testing](.claude/engineering/testing.md) — Test strategy, commands, full-stack start, e2e
```

Note all links are relative to the repo root (`.claude/business/...`), not to `.claude/` itself.

---

### `business/overview.md`

```markdown
# Business Overview

## Purpose
[From developer answer #1 — what problem it solves, 1-2 sentences]

## Core Users
[From developer answer #1 — who uses it]

## Success Metrics
[From developer answer #1 — what success looks like]
```

---

### `business/rules.md`

```markdown
# Business Rules

*Rules the code must never break under any circumstances.*

1. **[Rule name]:** [What triggers it, what the consequence is, where it must be enforced]
2. ...
```

---

### `business/glossary.md`

```markdown
# Domain Glossary (Ubiquitous Language)

*The exact vocabulary Claude and developers MUST use in code, variables, and database tables.*

| Code Name | Business Name | Definition |
|-----------|--------------|------------|
| `[entity]` | [business term if different, otherwise same] | [one-line definition] |

> Note to AI: NEVER invent synonyms. If the entity is `Order`, never write `Purchase` or `Transaction`.
```

---

### `architecture/overview.md`

```markdown
# Architecture Overview

## Stack
- **Core Framework:** [from scan]
- **Database / Backend:** [from scan]
- **ORM / Query Builder:** [from scan]
- **UI / Styling:** [from scan]
- **Global State:** [from scan — omit this line entirely if no state library found]
- **Key Integrations:** [from scan — only what's in deps]

## Pattern
[from scan — e.g., "Next.js App Router with Server Actions", "Clean Architecture CQRS"]

## Directory Structure
[From scan — key directories only, one-line purpose each]
- `[path]`: [what it's for]
```

---

### `architecture/integrations.md`

```markdown
# Integrations

*External services this project depends on.*

| Service | Purpose | Where configured |
|---------|---------|-----------------|
| [from scan] | [inferred from package or usage] | [env var or config file] |
```

---

### `domains/[entity].md` — one file per detected entity

```markdown
# [Entity Name]

## Responsibility
[From developer answer #4 — one sentence]

## Key Fields
[From schema — most important fields with brief meaning]

## Business Rules
[Entity-specific rules from developer answers or schema constraints]

## Relationships
[Other entities this one relates to, from schema]
```

---

### `engineering/standards.md`

```markdown
# Engineering Standards

## Conventions
[From scan — inferred from ESLint, tsconfig, file structure patterns]

## Architecture Rules
[Key patterns the team follows — e.g., "Server Actions only, no API routes for internal calls"]
```

---

### `engineering/testing.md`

```markdown
# Testing

## Commands
[From package.json scripts — exact commands to run tests]

## Run the full stack
[One command that starts db, backend and frontend together, from docker-compose
files, Makefile, Procfile or package.json scripts. Then the URL and port of each
part, and how the frontend finds the backend (env var name). If parts start
separately, one command per part in start order. spec-verify's browser check runs
against this.]

[Worktree ports: the command first loads `.env.worktree` when it exists
(`set -a; [ -f .env.worktree ] && . ./.env.worktree; set +a`), and the project reads
its ports with defaults: `"${WT_DB_PORT:-5432}:5432"` in compose,
`${WT_API_PORT:-<port>}` for the API, `${WT_WEB_PORT:-<port>}` for the frontend, and
the db port inside the API's connection string. Note here whether the project
follows this. If it hardcodes ports, say which files to change: until then two
Story worktrees cannot run their stacks at the same time.]

## E2E command
[The e2e runner (Playwright, Cypress, ...) and its exact command, from its config
file and scripts. If the project has none, write "None" — spec-apply then asks
before adding one.]

## Strategy
[Inferred from test file structure and config — unit, integration, e2e]
```

If the full-stack start or the e2e command cannot be inferred from the code, ask
for them in Phase 2 (within its question limit): spec-apply and spec-verify depend on both for fullstack Stories.

---

## Phase 4 — Confirm and Write

1. Show the developer the full list of files to be created/modified with a one-line
   summary of each, INCLUDING whether the root `CLAUDE.md` is being merged-into vs.
   created fresh
2. Ask: "Does this look right? Anything to adjust before I write?"
3. Wait for confirmation
4. Write the root `CLAUDE.md` and all files to `.claude/`
5. Print: "Context built. [N] files written ([root CLAUDE.md merged/created] + N under `.claude/`)."

---

## Rules

- NEVER write placeholder text like `[Entity 1]` or `[Ex: ...]` in any output file. If you don't know something, ask.
- NEVER skip Phase 1. Asking for information the code already has wastes the developer's time.
- NEVER ask more than 4 questions in Phase 2.
- NEVER create a `.claude/CLAUDE.md` file. Claude Code would load it too, giving the project two instruction files to keep in sync. The index always lives in the root `CLAUDE.md` — see "Why the root CLAUDE.md is the index" above. If a stray `.claude/CLAUDE.md` is found during Phase 1, its content must be merged into the root `CLAUDE.md` and the stray file deleted as part of this run.
- If a root `CLAUDE.md` exists AND does NOT contain the phrase "Context not yet generated", treat it as real content: show it and ask "Context already exists — regenerate everything, update a specific file, or add a new domain?" A stub created by `harness.sh` always contains that phrase — skip the prompt and proceed directly to Phase 1.
- If the project has no `package.json` and no recognized structure, say so and ask what stack they're using before scanning further.
- Domain files are generated only for entities found in the schema or models. Never invent entities.
- Omit `Global State` from `architecture/overview.md` if no state management library is detected.
- The `business/glossary.md` table must include every entity, even if the code name and business name are the same.
