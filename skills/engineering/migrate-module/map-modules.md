# Step 0 — Map the legacy into modules

Goal: `.claude/migration.md`, the config every later step reads. It holds the project config and
the module table in build order. One approval, then Step 1 can start on module 0.

## 1. Read what already exists

- The root `CLAUDE.md`, the `.claude/` context tree, `README`, and any doc the user points to that
  already describes the legacy modules. A doc that names the modules is the starting list; the
  code confirms or corrects it, never the other way round.
- The legacy code. Find its own module boundaries: navigation entries, tab or view ids, routes,
  menu items, files, storage keys or tables each area owns. For large files dispatch `Explore`
  per file or area, each returning candidate modules with `file:line` evidence; check what they
  return.
- `git remote -v` for the repo, and the new code's directories if they already exist.

## 2. Draft the module table

One row per module, numbered in build order:

| Column | Content |
|--------|---------|
| # | Build order. Module 0 is `foundation` when the legacy has cross-cutting code (login, session, tenant, roles, permissions, persistence, app shell); the other modules depend on it. |
| Slug | kebab-case, used for the branch and `docs/migration/<slug>/` |
| Legacy module id | The id the legacy itself uses (tab id, route, storage key), or `none` |
| Legacy source | Files, and the area inside them when one file holds several modules |
| Depends on | Slugs whose data or code this module reads |

Order by dependency: a module comes after every module it reads from. Break ties by what the
users need first, and ask when that is not clear from the docs. Never invent a module the legacy
does not have; legacy code that belongs to no module goes in a `## Unmapped` list with
`file:line`, for the user to assign or drop.

## 3. Draft the config

Fill from the repo; ask only what the code cannot answer, one question at a time:

| Key | Content |
|-----|---------|
| Repo | `owner/name` |
| Legacy (read-only) | Files or directories |
| New code | Backend and frontend paths |
| Branch | Pattern per module, e.g. `migracion/<module>`, and where it merges |
| Decisions doc | The doc holding the data model decisions Step 1 cites, or `none` (then every new entity is a Step 2 stop) |
| Conventions | Architecture, standards and testing docs |
| Tenant | The tenant entity for isolation tests, or `none` |
| Golden cases | Path per test project for golden case files |
| Real data | Who owns the real records and what sharing they allow |

## 4. Write and stop

```
# Migration map
Status: draft

## Config
| Key | Value |
...

## Modules
| # | Slug | Legacy module id | Legacy source | Depends on |
...

## Unmapped
- `<file>:<line>` <what it does>
```

Report in the user's language: the module list in order with one line on why each sits where it
does, the unmapped code, and open questions. **STOP for approval.** On approval set
`Status: approved` and commit (`docs(migration): Add the module map`).

## Re-mapping

`/migrate-module map` on an existing map edits it in place. A module that already has an
inventory keeps its slug and number; a new module between two existing ones takes a letter
suffix (`4b`). Show the diff and stop for approval again.
