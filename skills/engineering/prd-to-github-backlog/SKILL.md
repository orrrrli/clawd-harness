---
name: prd-to-github-backlog
stacks: [all]
description: "Turn a PRD/spec into a GitHub Project with a full engineering backlog: epics → vertical-slice story sub-issues (one fullstack story per feature, API + UI together) → task sub-issues, organized by phase and sprint, with sizes/estimates, area labels (fullstack/backend/frontend/design/QA/security/devops), and project fields (Status/Sprint/Size/Estimate). Use when the user wants to create a GitHub project + issues + sub-tasks from a PRD, build/seed a backlog, decompose a spec into epics/stories/tasks, or set up a project board from requirements."
trigger: /prd-to-github-backlog
---

# /prd-to-github-backlog

Decompose a PRD (and any UX/design docs) into a GitHub-ready engineering backlog and create it for real:
a **Project V2** plus nested issues — **Epic → Story → Task** — phased into sprints, sized, labeled by
discipline, and wired to project fields. The manifest is the single source of truth; everything else is
generated from it and is idempotent/resumable.

## When to use

- "Create a GitHub project + issues from this PRD", "build the backlog", "decompose this spec into epics/stories/tasks", "set up the project board", "seed sprints/issues from requirements".

## Prerequisites (check first)

- `gh auth status` succeeds with scopes incl. **repo** and **project** (`gh auth refresh -s project` if missing).
- A target **repo** exists (issues are created in it). If not, ask whether to create one.
- Python 3. The scripts shell out to `gh` only.

Scripts live next to this file under `scripts/`; the manifest contract is `references/manifest-schema.md`
(+ `references/manifest-example.json`). **Read the schema before authoring the manifest.**

## Workflow

### Step 1 — Read the source docs
Read the PRD in full (and any UX/system-design doc). Identify: functional requirements (FR-1..N), release
phases, the screen/flow inventory if present, and non-functional requirements (security, performance,
accessibility) — these become security/QA/perf stories.

### Step 2 — Determine repo strategy
Ask the user: **single repo or multi-repo?**

- **Single repo (monorepo):** one `repo` at manifest top level, all issues in one repo. Current behavior.
- **Multi-repo:** separate repos per area (e.g. backend → `orrrrli/metavix-api`,
  frontend → `orrrrli/metavix-app`). Ask for the repo mapping per area that differs from the global.

In the manifest, set the global `repo` to the most-used repo (usually backend or the one that hosts the
project board). Stories that belong in a different repo get a per-story `repo` field. Cross-repo
sub-issue linking is skipped automatically (GitHub doesn't support it). Tasks inherit their story's repo.

### Step 3 — Author the manifest (the real work)
Write `manifest.json` per `references/manifest-schema.md`. Methodology:

- **Epics by feature / FR**, each tagged with its `phase` and a `size` (S/M/L) and `sprint`.
- Each feature epic gets **vertical-slice `fullstack` stories** (`FS-<EPIC>-<n>`): one story carries the
  API and the UI for one user-visible behavior, so `spec-apply` builds both in one cycle and one PR,
  with the frontend and backend following the same approved contract. Never split a feature into a backend story and a
  frontend story. Every `fullstack` story has at least one acceptance criterion the user observes
  in the UI ("Then sees the dashboard"), not only API outcomes. Give each task its own `area` (`backend` tasks first, then `frontend`). A slice
  bigger than L is split into thinner slices (email login, then OAuth), never by layer.
  Use `backend`/`frontend` stories only for work with no other side (foundation, a job, a pure UI
  refactor). Add **design (UX/UI)**, **QA**, and **security** stories where there's real work; put
  **devops** on the foundation + launch epics.
- **Story titles are short imperative phrases** (≤ ~60 chars, e.g. "Add HasAscvd + pregnancy dates to Patient"). The full user-story intent lives in the
  **Given/When/Then** acceptance criteria — do not put "As a … I want … so that …" in the title, it makes issue names unreadable. Epics and tasks are
  already short imperative / noun phrases; keep them so. Stories carry an `estimate` (XS–XL → points 1/2/3/5/8). Cite real screen IDs / workflow IDs / NFR targets.
- Tasks are short imperative strings (auto-numbered `<story-id>-T<k>`).
- If using **multi-repo**, add `"repo": "owner/name"` to stories that live outside the global repo
  (e.g. frontend stories in the app repo). Tasks inherit their parent story's repo.
- If the PRD/UX has a **screen inventory**, set top-level `screens` so coverage is enforced: every screen
  must appear in some `design` story's `screens`.
- Lay out **sprints** by phase + dependency order (e.g. foundations → auth → core features → polish → launch).

Sanity-check counts with the user before creating anything (issues count = epics + stories + tasks).

### Step 4 — Create / find the Project
```
python3 scripts/setup_project.py --owner <login> --title "<Project title>"
```
Prints `PROJECT_NUMBER=<n>`. Put `repo`, `owner`, `project_number`, `assignee` into the manifest.
(Set `owner_type: "organization"` for org-owned projects.)

### Step 5 — Generate docs (optional but recommended)
```
python3 scripts/render_docs.py --manifest manifest.json --out docs/engineering-backlog.md \
    [--prd docs/prd.md --prd-section 14] [--wiki /tmp/Repo.wiki --wiki-prd PRD.md]
```
Writes the backlog page, injects a summary section into the PRD (idempotent, between `BACKLOG:START/END`
markers), and mirrors into a wiki clone if given. **Runs assertions** (unique ids, every epic has stories,
every story has tasks, screen coverage) — fix the manifest until it passes.

### Step 6 — Create the issues
Dry-run first, then create. The full run is **long** — run it in the background; it is resumable.
```
python3 scripts/create_issues.py --manifest manifest.json --dry-run        # sanity: counts + labels
python3 scripts/create_issues.py --manifest manifest.json                  # real (resumable via .state.json)
python3 scripts/create_issues.py --manifest manifest.json --limit 5        # optional: validate fields on a small batch first
```
This creates labels, every issue (assigned), nests Story→Epic and Task→Story as sub-issues, adds each to
the Project, ensures the **Backlog** Status option + **Sprint** field (and Size/Estimate if missing), and
sets Status=Backlog + Sprint on all items, Size + Estimate (points) on epics + stories.

### Step 7 — Verify
```
gh project view <n> --owner <login> --format json --jq '.items.totalCount'   # == epics+stories+tasks
gh issue list --repo <repo> --label type:epic --limit 50                      # epic count
gh api repos/<repo>/issues/<EPIC#>/sub_issues --jq 'length'                    # nesting spot-check
```
Then commit `manifest.json` + the scripts + generated docs, and (if used) commit+push the wiki — **confirm
with the user before any push** to a shared remote.

## Hard-won gotchas (baked into the scripts)

- **Resumable, never re-create:** `.state.json` (next to the manifest) is the ledger; re-running skips done
  work and reconciles missing links/fields **and titles** (edit a story `title` in the manifest, re-run, and
  the live issue is renamed via PATCH). Keep `.state.json` **gitignored**. A network reset mid-run is retried.
- **Sub-issue linking** uses `POST /repos/{owner}/{repo}/issues/{parent}/sub_issues` with the child's
  **numeric id** (not its number). Limits: 100 sub-issues/parent, 8 nesting levels.
- **Project field values** are set via `updateProjectV2ItemFieldValue`. Single-select option ids must be
  passed as **strings** (`gh api -f`, not `-F`) — all-digit option ids get coerced to int by `-F` and
  rejected as `String!`. Adding a Status option **replaces** the whole option set, so existing options are
  re-sent.
- **Throttle:** ~1.3 s between creates to dodge GitHub secondary rate limits; the script backs off on
  rate-limit / 5xx / connection-reset.

## Notes
- Edit the **manifest** and re-run the scripts — never hand-edit the generated docs or issues.
- The manifest carries all config (repo/owner/project), so the scripts are project-agnostic and reusable.
