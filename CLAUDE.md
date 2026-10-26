# clawd-harness

The Claude Code harness itself: skills, agents, and the installer (`harness.sh`) that wires
them into a project. There is no application here — it is markdown and bash.

## Layout

```
skills/<category>/<name>/SKILL.md   19 skills across 3 categories
global/agents/<name>.md             7-agent team, user-level (all projects)
harness.sh                          the only installer: project setup (--stack aware), --global, --update
global/behavior.md                  how the agent writes and acts (no personal data), linked as ~/.claude/behavior.md by harness.sh --global
global/statusline-command.sh        statusline, linked by harness.sh --global
global/permissions.json             guardrail deny/ask rules, merged into ~/.claude/settings.json by harness.sh --global
global/build-cloud-setup.sh         prints the claude.ai/code environment setup script; output holds personal files, never commit it
global/githooks/commit-msg          commit message hook; repos point at it via core.hooksPath, never copied
global/githooks/post-checkout       on `git worktree add`, symlinks the ignored Claude harness and .env* files from the main checkout
global/claude-hooks/<name>.sh       optional Claude Code hooks; settings point at them, never copied, nothing installs them```

Each skill is symlinked into a target project as `.claude/skills/<skill>` by `harness.sh`. There are no per-project agents.

`global/agents/` is symlinked as `~/.claude/agents` by `harness.sh --global`, which
also sets `"agent": "software-architect"` in `~/.claude/settings.json`. That
setting is the default for every session, including folders never init'ed, so the
architect must live at user level. `claude-design` (a shell alias for
`claude --agent ui-designer`, see README) starts a ui-designer session instead.

## Commands

```bash
./harness.sh <dir> --stack=all|web|dotnet|android|ios   # or a list: --stack=web,dotnet
./harness.sh <dir> --update          # relink skills only, stacks read from .claude/harness-stack
./harness.sh --global                # user level; add --update to relink without touching settings.json
bash -n harness.sh                   # syntax check
```

There is no build, no test runner, and no package.json. To verify a change to
`harness.sh`, run it against a scratch directory and inspect the result —
it creates real symlinks and set real git config, so use a throwaway path
and clean up after.

## Conventions

**Every skill declares `stacks:` in its frontmatter.** `harness.sh`
reads it and links only what matches `--stack`, so a .NET project does
not receive `audit-layer-boundaries`. Valid values: `all`, `web`, `dotnet`, `android`, `ios`. `all`
is exclusive — never combine it with another value.

```yaml
---
name: my-skill
stacks: [web]
description: One line. This is what makes Claude load the skill, so say when to use it.
---
```

A skill with no `description` is never surfaced. A skill with no `stacks:` is
silently dropped from every filtered install.

Agents in `global/agents/` have no `stacks:`. Nothing filters them; every
machine gets the whole team.

**Delivery is vertical slices.** `prd-to-github-backlog` writes one `fullstack`
Story (`FS-<EPIC>-<n>`) per feature, and `spec-apply` builds a Story across every
layer in one cycle. Never reintroduce a backend-story + frontend-story split or a
per-task loop.

**Two runtime modes.** A trailing `full` or `light` on `/spec-apply` or `/spec-verify`
picks the mode for that run; otherwise `~/.claude/runtime-mode` decides, and a missing
file means `full`. `light` starts no stack and defers the e2e
and browser checks; `full` runs them on the worktree's own stack from
`.env.worktree` (written by `global/githooks/post-checkout`). A change to either
skill's stack steps must keep both modes working.

**Claude Code only.** Support for Windsurf and OpenCode was removed; do not
reintroduce `.windsurf/`, `.opencode/` or their rules files.

**Category READMEs must match the directory.** `skills/engineering/`,
`ui/` and `productivity/` each have a README listing their skills. Adding or removing a
skill means updating it in the same commit.

## Context

This repo has no `.claude/` context tree — `/fill-context` has never run here,
and for a repo this small the file you are reading is the whole context.

Project-level docs: `README.md` (installation and inventory),
`PERSISTENT-MEMORY.md` (claude-mem + engram).
