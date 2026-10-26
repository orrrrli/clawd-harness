# clawd-harness

The Claude Code harness itself: skills, agents, and the init scripts that wire
them into a project. There is no application here — it is markdown and bash.

## Layout

```
skills/<category>/<name>/SKILL.md   19 skills across 3 categories
global/agents/<name>.md             7-agent team, user-level (all projects)
init-project.sh                     project setup, --stack aware
init-dotnet-project.sh              same, for .NET (defaults to --stack=dotnet)
install-global.sh                   user-level setup, once per machine
global/behavior.md                  how the agent writes and acts (no personal data), linked as ~/.claude/behavior.md by install-global.sh
global/statusline-command.sh        statusline, linked by install-global.sh
global/permissions.json             guardrail deny/ask rules, merged into ~/.claude/settings.json by install-global.sh
global/build-cloud-setup.sh         prints the claude.ai/code environment setup script; output holds personal files, never commit it
global/githooks/commit-msg          commit message hook; repos point at it via core.hooksPath, never copied
global/githooks/post-checkout       on `git worktree add`, symlinks the ignored Claude harness and .env* files from the main checkout
global/claude-hooks/<name>.sh       optional Claude Code hooks; settings point at them, never copied, nothing installs them```

Each skill is symlinked into a target project as `.claude/skills/<skill>` by the init scripts. There are no per-project agents.

`global/agents/` is symlinked as `~/.claude/agents` by `install-global.sh`, which
also sets `"agent": "software-architect"` in `~/.claude/settings.json`. That
setting is the default for every session, including folders never init'ed, so the
architect must live at user level. `claude-design` (a shell alias for
`claude --agent ui-designer`, see README) starts a ui-designer session instead.

## Commands

```bash
./init-project.sh <dir> --stack=all|web|dotnet|android|ios   # or a list: --stack=web,dotnet
./init-dotnet-project.sh <dir>
bash -n init-project.sh              # syntax check
```

There is no build, no test runner, and no package.json. To verify a change to
the init scripts, run them against a scratch directory and inspect the result —
they create real symlinks and set real git config, so use a throwaway path
and clean up after.

## Conventions

**Every skill declares `stacks:` in its frontmatter.** The init
scripts read it and link only what matches `--stack`, so a .NET project does
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
