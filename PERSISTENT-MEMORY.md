# Persistent Memory Guide

This stack uses two memory layers. **claude-mem** captures what happens in the main session on its own. **engram** holds what subagents confirm and save.

---

## Overview

| Layer | System | Purpose | Trigger |
|-------|--------|---------|---------|
| **Automatic** | claude-mem | Main session: *"what we did last time"*, decisions, patterns | Hooks, with no action from you |
| **Subagent** | engram | Findings a subagent confirmed that outlive the diff (bugs in shared code, broken conventions) | The agent calls `mem_save` |

**The flow**: claude-mem records the main session on its own in the background. Subagents search engram before they work and save to it after.

---

## How They Complement Each Other

### claude-mem
- **Automatic**: observes the session through hooks — nothing to call, nothing to remember to do
- **Injected at startup**: prior work arrives as context when a session opens
- **Searchable**: earlier sessions can be queried by meaning, not just keywords
- **Not documented here**: it is a Claude Code plugin with its own docs. Run the
  `claude-mem:how-it-works` skill for how it captures and where it stores things.
  Duplicating that here would just rot.

### engram (subagents only)
- **Why it exists**: subagents can't write to claude-mem. Its MCP is read-only
  and it has no subagent hooks. engram exposes `mem_save` as an MCP tool, so a
  read-only reviewer (`disallowedTools: Write, Edit`) can still save.
- **Deliberate, not automatic**: nothing is captured unless the agent calls
  `mem_save`. Its `SubagentStop` passive capture stored nothing in testing, so
  don't count on it.
- **Who uses it**: `code-reviewer`, `debugger` and `security-auditor`, each
  with a Memory section in its agent file. `test-writer` and `business-analyst`
  don't: their knowledge already lives in `testing.md` and `business/rules.md`.
  The reviewer's section says: run
  `mem_search` (`match_mode: "any"`) before reviewing and treat hits as leads,
  not facts. After the verdict, `mem_save` each confirmed finding that outlives
  the diff, with a root-cause `topic_key`. Before saving under an existing key,
  read the full entry with `mem_get_observation` (search only returns previews)
  and keep every fact not re-verified as false.

**The split, on purpose**: the main session stays on claude-mem; subagents use
engram.
- For: nothing is lost (the claude-mem history stays), automatic capture keeps
  running, and it's cheap to reverse.
- Against: two memories, each knowing half. What the reviewer finds lives in
  engram, and the main session doesn't see it unless it searches there.

---

## Configuration

### 1. claude-mem

Installed as a Claude Code plugin; it needs no configuration here. See the
`claude-mem:how-it-works` skill.

### 2. engram

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

### claude-mem (Automatic)
Claude searches it on its own when you ask things like:
- *"What did we work on last time?"*
- *"What decisions were made about authentication?"*

It does not see engram. For what subagents found, search engram directly:
`mem_search` from the session, or `engram search "<query>" --project <p> --match any`,
or browse it with `engram tui`. Same-file findings get flagged as conflicts.
Resolve them there, since the reviewer has no `mem_judge`.

---

## Key Files

| File | Purpose |
|------|---------|
| `global/agents/*.md` | Per-agent memory rules (mem_search before work, mem_save after) |