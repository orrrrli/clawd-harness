# AI Engineering Stack

A personal Claude Code harness: a 7-agent team, 19 skills and the scripts that
wire them into any project. Clone it once, run one script per machine and one
per project, and every Claude Code session works the same way, with the same
rules, the same reviewers and the same delivery loop.

There is no application here. It is markdown and bash.

**Claude Code only.** Support for Windsurf, OpenCode and other editors was
removed. Everything targets Claude Code's own conventions (`.claude/skills/`,
`~/.claude/agents/`, root `CLAUDE.md`).

```
  ~/.claude/  (global layer, once per machine)        your-project/  (per project)
  ┌──────────────────────────────────────┐            ┌──────────────────────────────────┐
  │ agents/   -> global/agents/          │            │ .claude/skills/<name> -> skills/  │
  │ skills/   -> 8 everyday skills       │            │   (filtered by --stack)           │
  │ settings.json  agent: architect      │            │ CLAUDE.md + .claude/ context tree │
  │ behavior.md, statusline-command.sh   │            │ core.hooksPath -> githooks/       │
  │                                      │            │   (commit-msg, post-checkout)     │
  └──────────────────────────────────────┘            └──────────────────────────────────┘
          install-global.sh                                   init-project.sh
```

## Contents

- [Quick start](#quick-start)
- [What's inside](#whats-inside): agents, skills
- [Global layer](#global-layer-once-per-machine)
- [Cloud sessions](#cloud-sessions-claudeaicode)
- [Per-project installation](#per-project-installation)
- [Tooling](#tooling)
- [Roadmap](#roadmap)
- [Credits and sources](#credits-and-sources)
- [Key files](#key-files)

## Quick start

```bash
git clone <this-repo> ~/dev/personal/clawd-harness

# Once per machine
~/dev/personal/clawd-harness/install-global.sh

# Once per project
~/dev/personal/clawd-harness/init-project.sh ~/dev/my-app --stack=web
```

Then open Claude Code in the project and run `/fill-context`.

## What's inside

### Agents

Installed at user level by `install-global.sh` (`global/agents/`). By default
the main session runs as `software-architect`, which writes the feature code and
dispatches the rest as subagents: one prompt in, one report back.

For visual work, `claude-design` starts a `ui-designer` session instead. It is a
shell alias, kept outside this repo (for example in `~/.zshrc`):

```bash
alias claude-design="claude --agent ui-designer --settings '{\"enabledPlugins\":{\"ponytail@ponytail\":false}}'"
```

The alias turns the ponytail plugin off for that session only. Setting
`PONYTAIL_DEFAULT_MODE=off` instead would delete the global
`~/.claude/.ponytail-active` flag, and a code session running in parallel would
lose ponytail in its subagents.

| Agent | Role |
|-------|------|
| **software-architect** | Main session. Designs, implements, routes work to the others |
| **business-analyst** | Vague ask to spec plus Given/When/Then acceptance criteria |
| **code-reviewer** | Read-only. Reviews a diff against the AC and a code-quality spec |
| **security-auditor** | Read-only. Critical/high issues on auth and untrusted input |
| **debugger** | Root cause of a failing test or wrong behavior, minimal fix |
| **test-writer** | Behavioral tests in the project's existing framework |
| **ui-designer** | Main session for visual work (pen.dev, Figma, visual frontend). Never a subagent |

### Skills

19 skills across 3 categories. Each category directory has its own README:
[engineering](./skills/engineering/README.md), [ui](./skills/ui/README.md),
[productivity](./skills/productivity/README.md).
The **Origin** column is detailed in [Credits and sources](#credits-and-sources).

| Skill | Stacks | What it does | Origin |
|-------|--------|--------------|--------|
| **spec-apply** | all | Implements a GitHub Story across every layer in one cycle (its Tasks are the checklist): explore, propose, failing tests, apply, verify, commit, PR | Own |
| **spec-verify** | all | Checks an implementation against its acceptance criteria in a fresh code-reviewer, with a mutation check | Own |
| **prd-to-github-backlog** | all | PRD to GitHub Project: epics, stories, tasks, sprints, estimates | Own |
| **fill-context** | all | Scans the codebase and interviews you to write the `.claude/` context tree | Own |
| **prompt-rewrite** | all | Audits a skill, agent or prompt against Anthropic's prompting docs | Adapted |
| **tdd** | all | Red-green-refactor loop | mattpocock/skills |
| **diagnose** | all | Reproduce, minimise, hypothesise, instrument, fix, regression-test | mattpocock/skills |
| **improve-codebase-architecture** | all | Finds deepening opportunities using the .claude/ tree and engram; Artifact report | mattpocock/skills |
| **audit-layer-boundaries** | web | Scans for the three violations that break the layer contract | Own |
| **dotnet-clean-architecture** | dotnet | Scans a .NET Clean Architecture solution for dependency-rule violations | Own |
| **android-clean-architecture** | android | Clean Architecture patterns and a layer scan for Android/KMP | affaan-m/everything-claude-code |
| **project-bootstrap** | dotnet | Skeleton plus one vertical slice end to end | Own |
| **write-swift** | ios | Modern Swift: value types, Swift 6 concurrency, generics, Swift Testing | emilkowalski/skills |
| **apple-design** | ios | Apple's rules for static iOS screens: materials, text styles, accessibility, the eight principles | Adapted |
| **swiftui-motion** | ios | SwiftUI motion in decision order: gate, spring, interruption, drag handoff, haptics, Reduce Motion | Adapted |
| **grill-me** | all | Interviews you about a plan until every branch is resolved | mattpocock/skills |
| **handoff** | all | Session handoff document, copied to the clipboard | Own |
| **blind-pick** | all | Options for a hard-to-reverse decision argue against each other; blind judges pick the winner | Own |
| **caveman** | all | Ultra-compressed replies, ~75% fewer tokens | JuliusBrussee/caveman |

`ponytail` is no longer vendored here. It is installed as a Claude Code plugin.

#### How spec-apply writes code

The spec drives the work. The tests are the spec made executable, and the agent that
writes the code does not own them.

```
Story AC (Given/When/Then, approved)          business-analyst drafts them if missing
  -> Propose     one plan for every layer + the contract + one behavior line per AC   STOP for approval
  -> Tests       test-writer turns the AC into failing tests, committed red and read-only
  -> Apply       the implementer makes those tests pass (ponytail ladder), never edits them
  -> Verify      spec-verify reruns the tests and breaks each AC's line to prove its test fails
```

One Story is one cycle across db, backend and frontend. Its Task sub-issues are the checklist
the plan must cover, and are closed together at the end. An XL Story stops before any code
with a proposed split into thinner slices, since the Story's size is the size of the diff
spec-verify reviews.

1. **Tests come from the AC, not the code.** `test-writer` sees the AC and the approved
   interface, never an implementation, so expected values cannot copy what the code returns.
   It adds only a not-implemented stub when the interface does not exist yet.
2. **The implementer cannot buy a green run.** The tests are committed after the Tests phase;
   Verify fails if `git diff` shows them changed. A test that looks wrong stops the run and
   goes to you, since it usually means an ambiguous AC.
3. **Propose names responsibilities.** Each one (business rule, persistence, security,
   external call, presentation) gets a place: an existing component, a new one with a reason,
   or a framework capability. This is what stops a credential check written as a bare `if`.
4. **Passing is not enough.** For each AC, `spec-verify` breaks the implementing line once in
   a scratch worktree. A test that stays green marks the AC `~ PARTIAL`, and the Story fails.

Tasks with no testable behavior (config, scaffolding) say so in Propose and skip the Tests
phase. `tdd` stays a separate skill for test-first work outside a Story.

## Global layer (once per machine)

```bash
~/dev/personal/clawd-harness/install-global.sh
```

- Symlinks `~/.claude/agents` to `global/agents/`.
  An existing `~/.claude/agents` directory is moved to `agents.bak-<timestamp>`.
- Symlinks `~/.claude/behavior.md` to `global/behavior.md`. An existing file is
  moved to `behavior.md.bak-<timestamp>`. Prints a hint when `~/.claude/CLAUDE.md`
  has no `@behavior.md` line to load it.
- Symlinks the skills every session needs into `~/.claude/skills`: fill-context,
  prd-to-github-backlog, prompt-rewrite, spec-apply, spec-verify, blind-pick, grill-me, handoff. Stale links
  are replaced; a real directory with the same name is skipped.
- Sets `"agent": "software-architect"` in `~/.claude/settings.json` with `jq`,
  so sessions run as the architect by default (`claude-design` overrides it). Other keys are left untouched.
- Merges the guardrail rules from `global/permissions.json` into
  `permissions.deny`/`ask` (see Guardrails). Only adds the missing ones, after
  yours; never removes or reorders a rule.
- Symlinks `~/.claude/statusline-command.sh` to `global/` (repo, branch, PR,
  running agent, model, context and rate limits; needs a Nerd Font) and sets
  `statusLine` only when none is configured. A `refreshInterval` of `3000` is
  rewritten to `3`, since the value is in seconds.
- Prints the `claude mcp add` commands for context7 and GitHub. Run them by hand:
  the tokens live in `~/.claude.json` and never in this repo.
- Checks engram and ego-browser and prints their install commands when missing.

Safe to re-run. Agents update with `git pull`, since they are a symlink.

### Guardrails (user level, installed by `install-global.sh`)

The rules live in `global/permissions.json` and `install-global.sh` merges them
into `~/.claude/settings.json`. Claude Code enforces them before a tool runs,
whatever the model decides, and at no cost per call (no process, unlike a hook).
To change one, edit `global/permissions.json` and re-run the script. Removing a
rule from the file does not remove it from a machine that already has it: delete
it from `settings.json` by hand.

- **No Bash sandbox.** Removed: it broke `pbcopy` (`/handoff`) and other projects.
  Permission rules are the only barrier left.
- **Deny rules** in `~/.claude/settings.json`: `Read`/`Edit` of `.env*` anywhere
  (`//**/.env*`) and of `~/.ssh/**`; `git push --force`/`-f`, including the
  `git -C <dir>` form; `rm -rf /*` and `rm -rf ~*`.
- **Ask rules** for commands that destroy uncommitted work: `git reset --hard`,
  `clean -f`, `branch -D`, `checkout .`, `restore .`, each with its `git -C` form.
  Also for adding a dependency: `npm install`/`i`/`add`, `pnpm add`,
  `dotnet add package`, `brew install`.
- Commit messages are checked by the git `commit-msg` hook that init installs
  per project (see "Commit message hook" below), not by a Claude Code hook.

Known gaps:

- `Read`/`Edit` rules cover only those tools. `cat .env` from Bash is not
  blocked; the risk is accepted.
- Bash rules match the start of the command text. Every rule needs a `git -C`
  variant, because the agent is told to use `git -C` instead of `cd`.
- The `block-dangerous-git` hook (see "Optional Claude Code hooks") is not used
  here: it blocks every `git push`, which `spec-apply` needs to open PRs. It
  stays as the opt-in for setups that want a hard block instead of ask rules.

### Optional Claude Code hooks

Scripts in `global/claude-hooks/`. Nothing installs them: no script in this
repo writes a `hooks` key (init leaves `"hooks": {}` empty). You opt in per
project or per machine by pointing a settings file at the script here, the
same way repos point at the commit-msg hook. Never copy it: `git pull` here
updates every place that uses it.

| Hook | Event | Blocks | Cost per call | Scope |
|------|-------|--------|---------------|-------|
| `block-dangerous-git.sh` | `PreToolUse` / `Bash` | `git push` (every form), `reset --hard`, `clean -f`, `branch -D`, `checkout .`, `restore .`, `switch -f`, `stash drop/clear`; also through `git -C`, `bash -c`, `$(...)`, inline aliases and chains. Fails closed: no `jq` or unreadable input blocks every Bash call | One `jq` plus a bash parse of the command | Per machine or project. Not with `spec-apply`, which pushes |
| `merge-gate.sh` | `PreToolUse` / `Bash` | `gh pr merge` called as a command (at line start or after `;` `&` `\|` `(`), unless `gh pr checks` is all green (pending, red, no checks or unknown PR are blocked). The words inside a PR body or heredoc don't trigger it | One `jq`; `gh` only on a merge | Per project, and only where the repo has CI: with no checks it blocks every merge |

Wire one in `.claude/settings.local.json` (project) or `~/.claude/settings.json`
(machine). Merge into an existing `hooks.PreToolUse` array, don't replace it:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "~/dev/personal/clawd-harness/global/claude-hooks/merge-gate.sh" }
        ]
      }
    ]
  }
}
```

- Exit 2 blocks the tool call and shows stderr to Claude. Any other non-zero
  exit lets the command run, so a hook that crashes fails open.
- Project settings come from the folder the session starts in: a session
  opened inside a sub-repo doesn't get the hook. Editing the settings file
  applies to sessions already open too (seen on 2026-10-15), so a bug in a new
  hook hits the session you're working in at once.
- Every `PreToolUse` on `Bash` runs on every command. A new hook must exit at
  its first check when the command isn't its business, and its cost goes in
  the table above.
- Checks, each exits 1 on any failing case:
  `bash global/claude-hooks/test-block-dangerous-git.sh` and
  `bash global/claude-hooks/test-merge-gate.sh <org>/<repo> <green-pr>` (needs `gh`
  signed in). Run them from a file, not by typing the cases in a Bash call: an
  active hook reads that command line and blocks it.

## Cloud sessions (claude.ai/code)

A cloud session runs in a fresh Ubuntu VM with only the repo cloned. It loads
the repo's `CLAUDE.md`, `.claude/` and `.mcp.json`, and nothing from your
`~/.claude`: no user-level agents, skills, settings, plugins or MCP servers
([docs](https://code.claude.com/docs/en/cloud-environments.md)).

The environment's setup script fills that gap. It runs as root before Claude
starts, clones this repo, runs `install-global.sh`, and writes your user-level
`CLAUDE.md` plus the files it imports with `@`.

Setup, once per environment:

1. Install the Claude GitHub App on the repos you'll work in (or run
   `/web-setup` in the CLI).
2. Generate the script: `./global/build-cloud-setup.sh | pbcopy`
3. In claude.ai/code, open the environment settings, keep network access on
   `Trusted`, and paste the script as the setup script.
4. Open a session and check: `ls ~/.claude/agents ~/.claude/*.md`, and ask it
   to quote the first line of its system prompt. It should say it is the
   `software-architect`.

- The output embeds your personal files (name, email, rules). It goes into the
  environment config, never into this repo, which is public.
- Rerun step 2 and paste again after you change `persona.md`, `workflows.md`
  or any file `CLAUDE.md` imports. The script holds a copy, not a link.
- The VM caches the setup for about 7 days. A change merged here reaches cloud
  sessions only when that cache rebuilds. Editing the setup script (even a
  comment) forces it.
- Seen working on 2026-10-16: the session runs as `root` (`HOME=/root`), and
  `"agent": "software-architect"` in the written `settings.json` is honored.
- `RTK.md` is skipped. These don't reach the cloud at all: plugins (claude-mem,
  engram, ponytail), `rtk`, the NotchBuddy statusline and local MCP servers.
  Cloud sessions have no memory between sessions.

## Per-project installation

Use the init script rather than symlinking by hand. It wires the symlinks, the
context tree, the gitignore entries, and the commit-msg hook in one pass.

```bash
# Web / Next.js project
~/dev/personal/clawd-harness/init-project.sh ~/dev/my-app --stack=web

# .NET Clean Architecture project
~/dev/personal/clawd-harness/init-dotnet-project.sh ~/dev/my-api

# Android / Kotlin project
~/dev/personal/clawd-harness/init-project.sh ~/dev/my-app --stack=android

# iOS / SwiftUI project
~/dev/personal/clawd-harness/init-project.sh ~/dev/my-app --stack=ios
```

### `--stack`: install only what the project needs

Every skill declares a `stacks:` field in its frontmatter, and the init
script links only the matching ones. An Android project has no use for
`audit-layer-boundaries`. Agents are not per project: see Global layer.

| `--stack` | skills |
|-----------|--------|
| `web`     | 13 |
| `dotnet`  | 14 |
| `android` | 13 |
| `ios`     | 15 |
| `all`     | 19 |

Omitting the flag installs everything (`all`); `init-dotnet-project.sh` defaults
to `dotnet`. It also links the external repo `~/dev/oss/dotnet-clean-architecture-skills`
into `.claude/commands/dotnet` and `.claude/recipes`, so clone it there first.

### Commit message hook

The hook lives only here, in `global/githooks/commit-msg`. Init points the
project at it with local git config, so nothing is copied or committed into
the work repo:

```bash
git config core.hooksPath ~/dev/personal/clawd-harness/global/githooks
```

The hook rejects a subject that is neither conventional (`fix(scope): ...`) nor
ticket-first (`OG-4703: ...`). It is POSIX `sh` plus `grep -E`.

- It enforces your own commits on this machine, not the team's. Teammates
  and CI never see it.
- For a repo not set up by init (client or team repo), run the `git config`
  line above in it. `git pull` here updates the hook for every repo at once.
- Init does not change `core.hooksPath` when the repo already sets one (husky)
  or has live scripts in `.git/hooks/`, since the switch would disable them.
- Not a git repo yet: init skips the hook. Run `git init`, then init again.
- Undo in a repo: `git config --unset core.hooksPath`.

### Worktree hook

`core.hooksPath` points at the whole `global/githooks/` directory, so
`global/githooks/post-checkout` runs too. It acts only on `git worktree add`
(git passes an all-zero previous ref then). It symlinks the main checkout's
ignored `CLAUDE.md`, `.claude`, `*/CLAUDE.md` and `docs/brain` into the new
worktree, so every worktree shares one copy of the harness. It links the ignored
env files too (`.env`, `.env.local`, `apps/api/.env`, any `.env.*`), so the app
starts in the worktree for e2e tests and the browser check. A tracked
`.env.example` is already there and is left alone.

- A `.claude/` ignore rule with a trailing slash does not match the symlink, so
  git sees it as untracked. Write the rule as `.claude`, without the slash.
- Delete the symlinks before `git worktree remove`.

### After init

1. Open Claude Code in the project and run `/fill-context`. It scans the codebase,
   asks what the code cannot tell it, and writes the `.claude/` context tree with
   the root `CLAUDE.md` as its index.
2. For a brand-new project, `/project-bootstrap` scaffolds the skeleton plus one
   vertical slice end to end.

### What gets committed

The context tree is team-shared instructions, so it belongs in source control.
The generated `.gitignore` excludes only what is machine-local or a symlink
into this stack:

| Committed | Ignored |
|-----------|---------|
| `CLAUDE.md` | `.claude/skills/<skill>` (one symlink per skill) |
| `.claude/business/`, `architecture/`, `domains/`, `engineering/` | `graphify-out/` |
| | `.claude/commands/dotnet`, `.claude/recipes` (dotnet init only) |
| `.claude/settings.json` | `.claude/settings.local.json` |

> [!IMPORTANT]
> Projects initialized before this change have a bare `.claude/` line in their
> `.gitignore`, which keeps the whole tree out of git. The init script detects it
> and tells you, but cannot fix it — a `.gitignore` entry added later cannot
> override a broader one already there. Remove the `.claude/` line by hand, then
> `git add .claude`.

> The index lives in the root `CLAUDE.md`, not `.claude/CLAUDE.md`. Claude Code
> auto-loads a project CLAUDE.md from either location, so the rule is not about
> which one gets read — it is about keeping one file instead of two that drift
> apart. The root is the convention and the one visible on clone.
>
> The files it links to (`.claude/business/*.md`, etc.) are read on demand, when
> a task leads Claude to them.

## Tooling

Seven tools sit around this stack. They solve different problems and none
replaces another.

| Tool | Version | What it does |
|------|---------|--------------|
| **rtk** | 0.47 | CLI proxy that filters and summarizes command output *before* it reaches the context. `git`, `ls`, `find`, `rg`, `docker`, `dotnet`, `pnpm` and friends get rewritten transparently by a hook. 60-90% fewer tokens on routine dev operations. |
| **headroom** | 0.37 | Context optimization layer for LLM applications — a proxy that compresses traffic to the model, plus stored memories and a savings dashboard (`headroom savings`, `headroom dashboard`). |
| **claude-mem** | — | Persistent memory for the main session, captured by hooks with nothing to call. Prior work is injected as context when a session opens. |
| **[engram](https://github.com/Gentleman-Programming/engram)** | 3.0 | Memory for subagents. `code-reviewer`, `debugger` and `security-auditor` search it before working and save confirmed findings through MCP (`mem_search`, `mem_save`), since it can't write files and claude-mem is read-only to subagents. |
| **[ego-browser](https://github.com/citrolabs/ego-lite)** | 2.0 | Browser for agents (ego lite app + skill, macOS). `spec-verify` uses it in web projects to check acceptance criteria that are visible in the UI; without it those criteria stay `~ PARTIAL`. Install: `npx skills add citrolabs/ego-lite -g -a claude-code`. |
| **[graphify](https://github.com/Graphify-Labs/graphify)** | 0.8 | Turns a codebase into a queryable knowledge graph — tree-sitter AST parsing across 37 languages, plus docs, SQL and PDFs. Ask `graphify query "..."` instead of grepping; `path A B` traces how two things connect, `affected X` finds what a change breaks. |
| **[ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)** | 2.13 | Local design database (font pairings, palettes, UX rules, SwiftUI guidelines) with a stdlib-only Python search script. Install as a plugin, one command at a time: `/plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill`, then `/plugin install ui-ux-pro-max@ui-ux-pro-max-skill`. |

`rtk` trims what the tools send; `headroom` trims what reaches the model;
`claude-mem` remembers the main session; `engram` remembers what subagents
found; `graphify` answers questions the code can already answer, so the context
tree does not have to. The two memories are split on purpose and don't see each
other. See `PERSISTENT-MEMORY.md` for the split and the engram setup.

Graphify writes to `graphify-out/` (`graph.json`, `graph.html`, and a
`GRAPH_REPORT.md` naming the god nodes — the entities everything else touches).
Every edge is tagged `EXTRACTED` when it is explicit in the source or
`INFERRED` when graphify resolved it, so derived structure stays separable from
fact. It runs offline for code; LLM calls happen only for the semantic pass over
docs and media. Keep `graphify-out/` out of version control.

## Roadmap

Pending, in order:

1. **Telemetry.** `tools/telemetry.py` (Python stdlib, no deps) reading
   `~/.claude/projects/*/*.jsonl`: skills fired (and never fired), agents
   dispatched, failed tool calls, tokens per project. Complements
   `claude-mem:agent-cost-report` (cost) and `rtk gain` (token savings). Its
   output decides which plugins and skills to prune.
2. **Evals.** A fixture repo with seeded bugs; run `code-reviewer` headless
   (`claude -p --output-format json`) three times and score bugs found against
   the bare model. Then `spec-apply` on a task with pre-written tests. Re-run
   after every prompt rewrite of an agent.

Small cleanups:

- Linux and Windows support for the init scripts, statusline and hooks:
  issue #3.
- Decide whether the commit-msg hook accepts a `release:` type. Today it
  rejects it.
- Repos that use husky skip the stack hook (init leaves `core.hooksPath`
  alone). Wire `global/githooks/commit-msg` from `.husky/` where it matters.

## Credits and sources

This stack stands on other people's work. Vendored skills keep their upstream
structure; adapted ones say in their own file what changed and why.

### Skills taken from upstream

| Source | License | What we took |
|--------|---------|--------------|
| [mattpocock/skills](https://github.com/mattpocock/skills) | MIT | `tdd`, `diagnose` (upstream now `diagnosing-bugs`), `improve-codebase-architecture` (resynced with commit `49dd158`, read 2026-10-17; reads the `.claude/` tree instead of CONTEXT.md, records rejections in engram instead of ADRs, reports as an Artifact), `grill-me`, and `global/claude-hooks/block-dangerous-git.sh` (from its `git-guardrails-claude-code` skill; the skill wrapper was dropped) |
| [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) | MIT | `caveman`, copied in May 2026, before upstream moved to Apache-2.0 in 3.0.0. Its license ships in [skills/productivity/caveman/LICENSE](./skills/productivity/caveman/LICENSE). Only change: the `stacks:` field |
| [emilkowalski/skills](https://github.com/emilkowalski/skills) | MIT | `write-swift`, commit `e8a175d`, read 2026-10-09. Its license ships in [skills/engineering/write-swift/LICENSE](./skills/engineering/write-swift/LICENSE). Only change: the `stacks:` field |
| [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) | MIT | `android-clean-architecture`. Changes: added the `stacks:` field and the Process section, dropped references to skills we do not have |

### Inspiration and adapted rules

| Source | Used in | What we took |
|--------|---------|--------------|
| [mattpocock/skills](https://github.com/mattpocock/skills) | The own skills | The skill format: one focused job, a trigger-first `description`, short imperative steps |
| [NeoLabHQ/context-engineering-kit](https://github.com/NeoLabHQ/context-engineering-kit/tree/master/agents) | `global/agents/` | Role split and reviewer discipline (architect, business-analyst, code-reviewer, security-auditor). Left out its threat prompting and its developer/tech-lead split. Details in `software-architect.md` |
| [rubentanahara/claude-code-config-devtalk](https://github.com/rubentanahara/claude-code-config-devtalk) | `prompt-rewrite` | Skill structure, minus two rules that conflict with Anthropic's docs |
| [Anthropic prompting best practices](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) | `prompt-rewrite`, all agents | The rules every prompt is checked against |
| [emilkowalski/skills](https://github.com/emilkowalski/skills) | `apple-design`, `swiftui-motion` | `apple-design` and `animate`, rewritten for iOS and SwiftUI. Details in [skills/ui/README.md](./skills/ui/README.md) |
| John Ousterhout, *A Philosophy of Software Design* | `improve-codebase-architecture` | "Design It Twice" for exploring alternative interfaces |

### Tools

[rtk](https://github.com/rtk-ai/rtk), headroom, claude-mem,
[engram](https://github.com/Gentleman-Programming/engram),
[ego-browser](https://github.com/citrolabs/ego-lite),
[graphify](https://github.com/Graphify-Labs/graphify),
[ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill)
and the `ponytail` plugin. See [Tooling](#tooling).

## Key files

| File | Purpose |
|------|---------|
| `install-global.sh` | User-level setup, once per machine |
| `global/permissions.json` | Guardrail deny/ask rules, merged into `~/.claude/settings.json` by `install-global.sh` |
| `global/build-cloud-setup.sh` | Prints the setup script for a claude.ai/code cloud environment |
| `init-project.sh` | Project setup, `--stack` aware |
| `init-dotnet-project.sh` | Same, for .NET Clean Architecture (defaults to `dotnet`) |
| `global/agents/` | The 7-agent team |
| `global/githooks/commit-msg` | Commit message hook, referenced via `core.hooksPath` |
| `global/githooks/post-checkout` | Links the local Claude harness and ignored `.env*` files into new worktrees, same `core.hooksPath` |
| `global/claude-hooks/` | Optional Claude Code hooks, opt-in, referenced from settings |
| `global/behavior.md` | How the agent writes and acts, linked as `~/.claude/behavior.md` by `install-global.sh` |
| `PERSISTENT-MEMORY.md` | claude-mem + engram memory guide |
