# Persistent Memory Guide

This stack uses two memory stores, split by what the note is about (see Memory in `global/behavior.md`). **Auto memory** holds `user` and `feedback` notes that hold in every repo. **engram** holds everything tied to one project.

---

## Overview

| Store | Holds | Trigger |
|-------|-------|---------|
| **Auto memory** | `user` and `feedback` notes that hold in every repo, in the agent's `memory:` directory | Loaded every session |
| **engram** | Everything tied to one project: decisions, bugs, patterns, discoveries, ticket state | The session or agent calls `mem_save` |

**The flow**: the main session saves to engram on engram's protocol. Subagents search engram before they work and save to it after.

---

## How engram Is Used

- **Why subagents can use it**: engram exposes `mem_save` as an MCP tool, so a
  read-only reviewer (`disallowedTools: Write, Edit`) can still save.
- **Deliberate, not automatic**: nothing is captured unless the agent calls
  `mem_save`. Its `SubagentStop` passive capture stored nothing in testing, so
  don't count on it.
- **Who uses it**: the main session, plus `code-reviewer`, `debugger` and
  `security-auditor`, each with a Memory section in its agent file. `business-analyst`
  doesn't: its knowledge already lives in `business/rules.md`.
  The reviewer's section says: run
  `mem_search` (`match_mode: "any"`) before reviewing and treat hits as leads,
  not facts. After the verdict, `mem_save` each confirmed finding that outlives
  the diff, with a root-cause `topic_key`. Before saving under an existing key,
  read the full entry with `mem_get_observation` (search only returns previews)
  and keep every fact not re-verified as false.

---

## Configuration

`harness.sh --global` checks for it and prints these commands, but never runs
them (same rule as the other MCP servers). Run them once per machine:
```bash
brew install gentleman-programming/tap/engram
claude plugin marketplace add Gentleman-Programming/engram
claude plugin install engram@engram
engram setup claude-code      # registers the MCP: engram mcp --tools=agent
```
Tool names are `mcp__engram__mem_*`; that is what `code-reviewer.md` lists.

**Project resolution.** engram picks the project from the cwd, in this order:
`.engram/config.json` (source `config`), then the git remote name, then the git
root name. Watch out for:
- A folder holding several repos with no config resolves as **ambiguous**:
  searches error, and engram's hook denies every `mem_save`.
- A parent's config is **not inherited** by child repos. A child repo needs its
  own config, or it falls back to its remote name (e.g. a generic `api`).
- A session binds to a project on first use. A Bash `cd` elsewhere mid-session
  makes saves get denied or land in the wrong project. Use `git -C` and
  absolute paths instead.

For a product split across repos, use one project per product. Put the same
config in the root and in every child repo, and keep it out of git:
```bash
echo '{ "project_name": "<product>" }' > <root>/.engram/config.json   # and in each <root>/<repo>/
echo '.engram/' >> <root>/<repo>/.git/info/exclude                       # local, never committed
```
A repo added later needs both lines. Check the result with
`curl -s "http://127.0.0.1:7437/project/current?cwd=<dir>"`.

---

## Searching Memory

Search engram with `mem_search` from the session, or `engram search "<query>" --project <p> --match any`,
or browse it with `engram tui`. Same-file findings get flagged as conflicts.
Resolve them there, since the reviewer has no `mem_judge`.

---

## Key Files

| File | Purpose |
|------|---------|
| `global/agents/*.md` | Per-agent memory rules (mem_search before work, mem_save after) |