---
name: spec-verify
stacks: [all]
context: fork
agent: code-reviewer
argument-hint: "[task-id | story-id | issue# | path to spec]"
description: >
  Verify an implementation against its Story's acceptance criteria and the
  code-quality spec, in a fresh code-reviewer subagent. Delivers PASS/FAIL per
  criterion with file:line evidence, after running the project's own tests.
  Report only: never fixes, never closes issues. Use after implementing a task,
  when the user says "verify this", "does this match the spec", "spec-verify",
  and from spec-apply Phase 4.
---

# Spec Verify

Verify `$ARGUMENTS` against its acceptance criteria. You start with no
conversation history: everything you need is in this file, the repo, and GitHub.

## 1. Resolve the acceptance criteria

`$ARGUMENTS` is one of:

- **A path to a spec file**: read the acceptance criteria from it.
- **A Task ID** (`FS-AUTH-1-T1`), **Story ID** (`FS-AUTH-1`) or **issue number** (`#42`),
  from a backlog made by `prd-to-github-backlog`. Titles are `"<ID>: <title>"`;
  a Task's Story is its ID without the trailing `-T<k>`.

```bash
gh repo view --json nameWithOwner,defaultBranchRef \
  --jq '.nameWithOwner + " " + .defaultBranchRef.name'
gh issue list --label type:story --state all --search "in:title <STORY_ID>" \
  --json number,title --jq '.[] | select(.title | startswith("<STORY_ID>:")) | .number'
gh issue view <story#>       # Given/When/Then acceptance criteria live here
gh issue view <task#>        # for a Task: its scope narrows which criteria apply
```

For a raw `#N`, check its `type:*` label; a `type:task` walks up to its parent
Story (`gh api repos/<owner/repo>/issues/<N>/parent --jq '.number'`).

If several Stories match, use the open one (else the most recent) and name the
one you used in the report. If their acceptance criteria are identical, say so:
the choice does not change the review.

If no acceptance criteria can be found, or they are not testable (no observable
outcome), stop and report exactly that. Do not invent criteria.

## 2. Identify the change under review

```bash
git status --porcelain
git diff HEAD                  # uncommitted: the task in progress
git diff <BASE>...HEAD         # committed on this branch
```

If `$ARGUMENTS` carries `--since <sha>`, review `git diff <sha>`: everything
committed after that SHA plus the uncommitted work (spec-apply passes the commit
before the Story's red tests, so the tests are reviewed with their implementation).
Otherwise, if the working tree has changes, review those (the work in progress). If it is
clean, review `<BASE>...HEAD`. Read every changed file in full, not only the hunks.

**In scope** = the lines that implement this Story/Task. If the diff also carries
other work, review it only for the "Outside this change" section; it never
decides the verdict.

Judge an in-scope line by what it does to the product, not only against the AC.
If it breaks behavior that worked on the base, or leaves the Story's feature
unreachable from the product's real entry points (API, UI), it is [blocking]
even when every criterion passes as written. The missing piece may live outside
the diff; the in-scope line that depends on it is what blocks. A `fullstack`
Story (`FS-` ID) must work from the UI against the real backend.

## 3. Load the project's rules

Find the context index: `CLAUDE.md` at the repo root, else `.claude/CLAUDE.md`,
else the parent directory's `.claude/` (monorepo). Read it and the files it links
under Engineering and Business, mainly `engineering/standards.md`,
`engineering/testing.md`, `business/rules.md`.

## 4. Run the tests

**Runtime mode.** Read it first: `cat ~/.claude/runtime-mode 2>/dev/null`.
`full` runs everything below. Anything else, including a missing file, is
`light`: the machine is shared with other work (simulators, JVM backends), so
nothing that needs the running stack is started. In `light`:
- Skip the e2e test command and the browser check.
- Mark each criterion that only they can prove `~ DEFERRED (light mode: <e2e |
  browser check> not run)`. A criterion another test already proves keeps its
  normal verdict.
- Unit, component and integration tests that need no running stack still run,
  and so does the mutation check.

Use the commands from `engineering/testing.md`; otherwise the project's own
(`npm test`, `pnpm test`, `dotnet test`, `./gradlew test`). Record what actually
ran and the result. If they could not run, say why. Never report "tests pass"
without running them.

If a test fails, check whether it also fails without the change: run it in a
scratch worktree (`git worktree add --detach "$(mktemp -d)" HEAD` for
uncommitted work, `<BASE>` for committed work), then `git worktree remove` it.
Never stash or touch the real working tree: other reviewers read it in
parallel. Failures that already exist on the base are reported as
**pre-existing** and do not count toward the verdict.

### Mutation check

For each in-scope criterion with a passing test, prove the test catches a fault:

1. Build a scratch worktree with the change applied: `git worktree add --detach
   "$(mktemp -d)" HEAD`, then copy into it every file from
   `git ls-files -m -o --exclude-standard` (committed work: use HEAD as is).
2. Break the line that implements the criterion, once: invert a condition, shift a
   boundary (`>` to `>=`), drop a guard, or return a default.
3. Run only that criterion's test. Red = the test detects the fault. Green = it does not.
4. `git worktree remove` it. Never mutate the real working tree.

One mutation per criterion. Do not hunt for exotic mutations.

Rely on the project's existing tests. Do not build your own harness (scratch
apps, ad-hoc HTTP clients, containers) unless an in-scope criterion has no test
at all; then the smallest check that proves it. The browser check below is
the one exception.

### Browser check (web projects only)

Run it only when the project is web (Next.js, React, any app served to a
browser) AND an in-scope criterion describes something visible in the UI
(rendered content, a form, navigation, an error message on screen). Skip it
for backend-only or API-only criteria.

1. Check the tool: `command -v ego-browser || ls ~/.local/bin/ego-browser`.
   Missing → do not install it. Mark those criteria `~ PARTIAL (ego-browser
   not installed, UI not checked)` and go on.
2. Read `~/.claude/skills/ego-browser/SKILL.md` before writing any script.
   Its API is not Playwright; use only what that file lists.
3. Start what the criterion needs, in the background. In a worktree with
   `.env.worktree`, load it first (`set -a; . ./.env.worktree; set +a`) so the
   stack takes that worktree's ports and its own compose project, and two
   Stories never share a database:
   - UI only (no API call behind it): the frontend dev server, command from
     `engineering/testing.md`, else `package.json` scripts.
   - A `fullstack` Story, or any criterion whose UI calls the backend: the whole
     stack (db, backend, frontend) with the "Run the full stack" command from
     `engineering/testing.md`. Without one, start each part with its own
     documented command. If neither exists, mark those criteria `~ PARTIAL (full
     stack start not documented in engineering/testing.md)` and go on. Never
     point the UI at a mocked API: the check is the real slice.
   Use the ports the env files set, so the frontend reaches the backend. A port
   already in use is reported as the reason for `~ PARTIAL`; never kill a
   process you did not start.
4. Use one TaskSpace for the whole check. Drive the flow the criterion
   describes, through the UI the user would use. Record the URL, the steps,
   and what the snapshot showed.
5. Stop every process you started when done (`docker compose down` if the full
   stack command started containers; keep the volume, the Story reuses it).

A criterion confirmed in the browser counts as ✓ even with no automated test
for that layer; cite the steps and snapshot as evidence. If the browser shows
the criterion failing, it is ✗ regardless of what the tests say.

## 5. Verify

- **Spec 1, acceptance criteria:** only the criteria this change is due to
  satisfy. Check behavior, not that some code exists for it.
  ✓ = a test exercises the behavior (at any layer), passes, and fails under the
  mutation check.
  ~ PARTIAL = the code does it but no test proves it, or the test stays green
  under the mutation (it does not detect the fault).
  A layer the AC names but no test covers (e.g. the HTTP status) is a minor
  finding, not a downgrade.
- **Spec 2, code quality** (in-scope lines only): duplication, naming,
  architecture boundaries, control flow, error handling, function size, dead
  code, tests that exercise the real path instead of a mock of it, and tests
  that seed state the product's own entry points cannot produce.

Write the reasoning before each verdict.

## 6. Report

```
VERDICT: PASS | PASS (DEFERRED) | FAIL   <ID> — <title>   (Story #<n>)
Mode: light | full
Tests: <command> → <result>   [pre-existing failures: <list or none>]
Mutation: AC1 <mutation> → red | AC2 <mutation> → GREEN (survived)

Acceptance criteria
  ✓ AC1 <criterion>: <evidence, file:line>
  ✗ AC2 <criterion>: <what is missing, file:line>
  ~ AC3 <criterion>: PARTIAL, <why>
  ~ AC4 <criterion>: DEFERRED (light mode: e2e not run)

Code quality, in scope (blocking first)
  [blocking] file:line — <issue>
  [minor]    file:line — <issue>

Outside this change (never blocking)
  file:line — <issue>
```

FAIL if any criterion is ✗ or ~ PARTIAL, a test fails because of this change, tests
could not run, or there is an in-scope blocking finding. PASS (DEFERRED) when the
only gaps are `~ DEFERRED` criteria: everything that ran passed, and the slice
still needs a `full` run before the PR can leave draft. In `full` mode no
criterion is ever DEFERRED.

## Hard rules

- Report only. No edits, no commits, no issue comments, no closing issues.
- Every ✗ and every finding cites file:line.
- Never guess. If the implementation cannot be found, say so.
