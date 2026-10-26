---
name: migrate-module
stacks: [all]
description: "Port a legacy codebase to the new stack one module at a time, using the legacy code as the spec. First maps the legacy into ordered modules in .claude/migration.md (once per project). Then per module: inventory every legacy behavior with file:line, prove the inventory covers every function and handler, mark each same / fixed / dropped, split it into capabilities with short acceptance criteria, and get one approval. Then build each capability test-first, one commit per capability, with no further stops. No GitHub issues, no PRs: the inventory is the spec and the state. Use when the user says '/migrate-module <module> [capability]', '/migrate-module map', 'migrate the <x> module', 'map the legacy modules', 'next capability of <module>', or 'module status'."
trigger: /migrate-module
---

# /migrate-module [map | <module> [capability]]

The legacy app is the spec. A module is inventoried as a whole so no legacy behavior is lost; it
is delivered one capability (one thing a user can do) at a time. One approval per module, then
build without stopping.

## Project config

Everything project-specific lives in `.claude/migration.md`: repo, legacy files, new code paths,
branch, decisions doc, conventions, tenant, golden paths, and the ordered module table. This skill
calls its values "config". Module docs always live at `docs/migration/<module>/inventory.md`.

If the user names a module out of order, say which earlier modules are not done and ask.

## Resolve

- `/migrate-module map`, or no `.claude/migration.md` → **Step 0**.
- `.claude/migration.md` with `Status: draft` → show it, STOP for approval.
- Otherwise read `docs/migration/<module>/inventory.md`:
  - No file → **Step 1**.
  - `Status: draft` → show it, STOP for approval.
  - `Status: approved` → **Step 2** on the capability named, or the next one not `done` in
    dependency order.
  - Every capability `done` → **Module close**.

A capability specced before this flow in its own doc (`docs/migration/<module>/C<n>.md`) keeps that
doc as its criteria and task list; finish it with Step 2.

## Step 0 — Map the modules (once per project)

Read `map-modules.md` in this folder and follow it. It writes `.claude/migration.md` and stops for
approval. It never starts Step 1 on its own.

## Step 1 — Inventory and plan (the only stop per module)

Read the module's legacy code end to end. For large files dispatch `Explore` per area, each
returning behaviors with `file:line`; check what they return. Write `inventory.md`:

```
# <Module> migration inventory
Status: draft
Legacy source: <files>

## Behaviors
| ID | Behavior | Legacy | Mark | Decision | Golden | Real data | Capability | State |
| B1 | ... | `<file>:2324` | same / fixed / dropped | 34 | yes / - | pending / - | C1 | pending |

## Coverage
Pattern: `<rg pattern>` over <files and line ranges>. Hits: <n>.
| Hit | Legacy | Row |
| saveGroup | `<file>:2310` | B1 |
| legacyExport | `<file>:2980` | dropped (B9) |
| renderShell | `<file>:120` | out of module (foundation) |

## Capabilities
### C1 — <what the user can do>   (rows B1, B4; depends on -; state pending)
- AC1 (B1). Given ..., When ..., Then ... (concrete values from the legacy)
- AC2 (B4). ...
- New entities or tables, if any (from the config's decisions doc; never invent one).
```

- **Mark:** `same` = ported as is; `fixed` = changes because of a decision (cite it); `dropped` =
  not ported (one-line reason). Never invent behavior. A legacy behavior that contradicts a
  decision is `fixed`, never silently changed.
- **AC:** one or more per row, with the legacy's real branches and error messages as values. A
  pure legacy function can be run from the scratchpad to get the expected output.
- **Golden / Real data:** see `golden-and-real-data.md` in this folder; read it only when a row
  needs it. `Real data: pending` on rows with logic, `-` otherwise.
- **Coverage:** Explore reads, it does not prove completeness. After the rows are written, list
  with `rg -n` every function definition, event handler, route, query and exported entry point in
  the module's legacy area. Pick the pattern for the legacy language (JS: `function \w+`,
  `\w+\s*=\s*(async\s*)?\(`, `addEventListener`, `on\w+=`; adapt for others) and write it down
  so the next session can rerun it. Every hit maps to a row, to a `dropped` row, or to
  `out of module (<module>)`. A hit that maps to nothing becomes a new row. The inventory cannot
  leave `draft` while any hit is unmapped.

Report in the user's language: counts per mark, coverage hits and how many became new rows, every
`fixed` and `dropped` row, the capability list, and open questions. **STOP for approval.** On
approval set `Status: approved` and commit (`docs(<module>): Add migration inventory`).

## Step 2 — Build a capability (no stop)

1. Read its criteria and the code it touches.
2. Write the tests first, one or more per AC, plus the negative and boundary cases they imply.
   Expected values come from the AC, never from the new code. If the config names a tenant,
   every capability that reads or writes tenant data includes an isolation test: tenant A never
   sees or changes tenant B's rows.
3. Implement the minimum that makes them pass (ponytail). Follow the config's conventions.
4. Run the full test suite. Green, then commit: `git add` only this capability's files,
   `feat(<MODULE>-<C>): <Imperative summary>`. Subject only, no body, no AI trailer. Include the
   inventory edit setting the capability and its rows to `done` in the same commit.

Stop only when:
- a criterion is ambiguous, or the legacy contradicts a decision in the config's decisions doc;
- the work needs a new entity, table, dependency, or architecture choice not in the inventory;
- a behavior turns up that is not in the inventory (add the row, show it, then build it).

Then go on to the next capability. Report one line per finished capability.

## Module close

When every row is `done` or `dropped`: report counts, list the `dropped` rows for a final OK,
set `Status: closed (<date>)` and commit (`docs(<module>): Close the migration module`), name the
next module. Rows still `Real data: pending` are listed as open, not blocking.

After the last module in the config's table, run one full `security-auditor` pass over the new
code paths before anything ships: tenant isolation, auth, sessions, permissions, untrusted input.

## Rules

- Legacy files are read-only. Write only in the config's new code paths, `docs/` and
  `.claude/migration.md`.
- No real data in git: examples are synthetic; real records stay in gitignored local paths.
- Never edit, skip or weaken a test to get green.
- The inventory is the state: a new session resumes from it, never from memory.
- Commits go on the config's module branch. No PRs. Push only when the user asks.
- Reports and questions in the user's language; docs and code in English.
