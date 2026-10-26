---
name: context-sync
stacks: [all]
description: >
  Promote what engram learned into the project's context files. Reads the engram
  notes saved since the last sync (decisions, patterns, bugfixes, findings, security
  notes), checks each fact against CLAUDE.md, the .claude/ tree and the code, and
  proposes one diff per file for the user to approve. Context files stay the source
  of truth; engram is the inbox. Use when the user says "context-sync", "sync the
  context", "sincroniza el contexto", "pasa lo de engram a los docs", or after a
  ticket closes. Writes nothing without approval.
version: "1.0.0"
modes: [architect]
argument-hint: "[project] [--since YYYY-MM-DD]"
---

# Context Sync

engram collects decisions as they happen. The context files (`CLAUDE.md` and the
`.claude/` tree that `fill-context` builds) are what agents are told to trust, and
what `test-writer` and `business-analyst` read instead of engram. Without a sync
step the files go stale and the real rules live only in memory, in several
versions. This skill moves the durable ones into the files, with the user deciding
each one.

**Core principle:** the file wins. A note that contradicts a file is a question for
the user, never an automatic overwrite.

What the user typed after `/context-sync`: `$ARGUMENTS`. A project name overrides
the one engram resolves from the cwd. `--since` overrides the last-sync date.

---

## Phase 1: Resolve the project and its files

1. Call `mem_current_project`. Use its project unless `$ARGUMENTS` names one. If it
   reports the project as ambiguous, stop and ask which one.
2. Find the context tree: the root `CLAUDE.md`, every file it links (usually under
   `.claude/`: `business/`, `architecture/`, `domains/`, `engineering/`), and the
   project's own skills under `.claude/skills/`. A gotcha about a workflow a skill
   runs belongs in that skill.
3. Read the write rules in that `CLAUDE.md`. Some hubs mark team files as
   read-only and say where local knowledge goes. Those rules decide where a
   promotion may land (Phase 4).

No `CLAUDE.md` and no `.claude/` tree? Stop and suggest `fill-context` first. There
is nothing to sync into.

## Phase 2: Collect the candidates

1. Find the last run: `mem_search` for `context-sync state: <project>` and read the
   matching note in full with `mem_get_observation`. It holds `last_synced_at`, the
   ids already promoted or discarded, and the ids still open. No note means first
   run: take the last 30 days unless `--since` says otherwise.
2. Export the project and filter it. `mem_search` caps at 20 results and has no
   date filter, so use the CLI. The export holds every note in plain text,
   security notes included, so delete it when the run ends:

   ```bash
   DIR="$(mktemp -d)"; TMP="$DIR/engram.json"
   engram export "$TMP" --project "<project>"
   jq --arg since "<last_synced_at>" '[.observations[]
       | select(.deleted_at == null)
       | select(.created_at > $since)
       | select(.type != "session_summary")
       | select((.topic_key // "") | startswith("context-sync/") | not)
       | {id, type, title, topic_key, created_at, content}]' "$TMP"
   # at the end of the run:
   rm -rf "$DIR"
   ```

   `created_at` is UTC text (`YYYY-MM-DD HH:MM:SS`), so the string comparison
   works. The export includes soft-deleted notes; the `deleted_at` filter drops
   them. A key that is null is absent from the export, and `jq` reads it as null.
3. Add back the ids the state note lists as open (conflicts and undecided items),
   whatever their date. Drop ids already promoted or discarded.
4. Group notes that restate the same fact and keep the one with the newest
   `created_at` (ids are not in creation order). Notes migrated from other tools
   often have no `topic_key`, so group by content, not by key.

More than 60 candidates? Tell the user the count and offer to split the run by
type or by month. Do not skim.

## Phase 3: Classify each fact

A note often holds several facts: one is already documented, another is new, a
third contradicts a file. Split the note into facts and classify each one.

Check coverage by searching, not by memory: `rg -i '<key term>'` across the context
tree, the project's docs, and the code a fact names. A fact the tracked code, a
test or a committed doc already states is covered. A fact stated only in an
uncommitted change or an unmerged branch is not covered yet: leave it `open` with
the branch name, and check again next run.

| Bucket | Meaning | Action |
|---|---|---|
| `covered` | A file, committed doc or the code already says this | Mark as promoted, no change |
| `promote` | Durable and missing from the files | Propose a change |
| `conflict` | Contradicts what a file says | Ask the user which one is current |
| `open` | Undecided (options with no verdict), or covered only by an unmerged branch | Ask, or carry to the next run |
| `discard` | One-ticket detail, progress note, or noise | Mark as discarded |
| `other-project` | Saved here but about another project or the global setup | List it; never promote it here |

What counts as durable: a business or product rule, a convention, a testing rule,
an integration constraint, a gotcha that will bite again, a security finding (as a
description, never the value). What does not: the status of one PR, a step in a
plan, anything the code or git history already shows.

Pick the target from the tree's own split: business rules to `business/rules.md`,
testing to `engineering/testing.md`, an entity's behavior to `domains/<entity>.md`,
conventions to `engineering/standards.md`, external services to
`architecture/integrations.md`, a workflow gotcha to the skill that runs that
workflow. When no file fits, propose the section to add instead of inventing a new
file.

## Phase 4: Propose, then apply what is approved

Present one block per target file:

```
## .claude/business/rules.md  (2 changes)
1. [promote] engram #481, decision, 2026-10-14
   Adds under "Stakes email": A player who accepts inside the email window gets no stakes email.
2. [conflict] engram #262 vs rules.md:42
   File: reminders stop 24 h before tee time. Note: they stop when the round starts. Which is current?
```

Then one line per remaining bucket with ids (`covered`, `open`, `discard`,
`other-project`), so the user can pull one back.

Ask with the interactive question tool, in this order:
1. Each conflict and each `open` item that needs a decision: which side is current,
   or which option won. A conflict the note wins becomes a `promote`.
2. Then one question per target file: apply all, pick some, or skip.

Apply only what was approved, matching the file's existing voice and structure:
edit the section in place, never append a changelog. Where the `CLAUDE.md` write
rules forbid editing a file (team-owned, tracked), do not edit it. Offer the change
as a ready-to-paste block for a PR, or write it to the local file those rules name.

## Phase 5: Record the run

Save the state with `mem_save` so the next run starts where this one ended:

- `title`: `context-sync state: <project>`
- `type`: `config`
- `topic_key`: `context-sync/<project>` (same key, so it replaces the previous state)
- `content`:
  - `last_synced_at`: the newest `created_at` reviewed, in the same UTC
    `YYYY-MM-DD HH:MM:SS` format.
  - `promoted`: ids with their target file. A note split across buckets goes here
    only when none of its facts is still open.
  - `discarded`: ids, including `other-project` ones.
  - `open`: ids still undecided, with the reason (conflict, no verdict, unmerged
    branch name).

Before saving, read the previous state in full and carry forward its id lists;
`mem_search` only returns previews.

## Report

End with: files changed (path and count), facts promoted, covered, discarded, ids
still open and why, `other-project` ids with the project they belong to, and the PR
blocks the user still has to open. Nothing else.

## Rules

- Never write a context file without the user's approval in this run.
- Never delete or edit engram notes. The state note is the only write to engram.
- Never copy a secret, token or credential from a note into a file. Describe it
  ("chat service secret is hardcoded in application.yml") without the value.
- Delete the export when the run ends.
- Context files are English. Keep the tone and headings the file already uses.
