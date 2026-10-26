#!/usr/bin/env bash
# One entry point for the harness.
#
#   harness.sh [dir] [--stack=all|web|dotnet|android|ios[,...]]   set up a project
#   harness.sh [dir] --update [--stack=...]                        relink a project's skills only
#   harness.sh --global                                            user-level setup, once per machine
#   harness.sh --global --update                                   relink agents, behavior, skills, statusline only
#
# A project remembers its stacks in .claude/harness-stack, so --update needs no
# --stack after the first run. Every mode is safe to re-run.

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTNET_SKILLS_DIR="$HOME/dev/oss/dotnet-clean-architecture-skills"
STACK_FILE=".claude/harness-stack"

usage() {
    sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

GLOBAL=0
UPDATE=0
STACK=""
POSITIONAL=()
for arg in "$@"; do
    case "$arg" in
        --global) GLOBAL=1 ;;
        --update) UPDATE=1 ;;
        --stack=*) STACK="${arg#--stack=}" ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "ERROR: Unknown flag '$arg'."; usage; exit 1 ;;
        *) POSITIONAL+=("$arg") ;;
    esac
done

# =============================================================================
# Global: the user-level layer (agents, behavior, skills, settings)
# =============================================================================

# Skills available in every session, not only in set-up projects.
GLOBAL_SKILLS=(
    engineering/context-sync
    engineering/fill-context
    engineering/prd-to-github-backlog
    engineering/prompt-rewrite
    engineering/spec-apply
    engineering/spec-verify
    productivity/blind-pick
    productivity/grill-me
    productivity/handoff
)

# Links agents, behavior, global skills and the statusline script. Touches no settings.
global_links() {
    local src="$STACK_DIR/global/agents" agents="$CLAUDE_DIR/agents" backup s dest linked=0

    # Agents: ~/.claude/agents -> global/agents (a real directory is backed up, never deleted)
    if [ -L "$agents" ] && [ "$(readlink "$agents")" = "$src" ]; then
        echo "agents: already linked"
    else
        if [ -e "$agents" ] && [ ! -L "$agents" ]; then
            backup="$agents.bak-$(date +%Y%m%d-%H%M%S)"
            mv "$agents" "$backup"
            echo "agents: existing directory moved to $backup"
        fi
        ln -sfn "$src" "$agents"
        echo "agents: $agents -> $src"
    fi

    # Behavior rules: ~/.claude/behavior.md -> global/behavior.md (a real file is backed up).
    # CLAUDE.md loads it with an `@behavior.md` line; personal identity stays in persona.md.
    local behavior="$CLAUDE_DIR/behavior.md"
    if [ -e "$behavior" ] && [ ! -L "$behavior" ]; then
        mv "$behavior" "$behavior.bak-$(date +%Y%m%d-%H%M%S)"
        echo "behavior: existing file backed up"
    fi
    ln -sfn "$STACK_DIR/global/behavior.md" "$behavior"
    echo "behavior: $behavior -> $STACK_DIR/global/behavior.md"
    grep -qx '@behavior.md' "$CLAUDE_DIR/CLAUDE.md" 2>/dev/null \
        || echo "behavior: add an '@behavior.md' line to $CLAUDE_DIR/CLAUDE.md to load it"

    # Global skills. A real directory with the same name is left alone (it is not ours to replace).
    mkdir -p "$CLAUDE_DIR/skills"
    for s in "${GLOBAL_SKILLS[@]}"; do
        dest="$CLAUDE_DIR/skills/$(basename "$s")"
        if [ -e "$dest" ] && [ ! -L "$dest" ]; then
            echo "skills: $dest is a real directory, skipped"
            continue
        fi
        ln -sfn "$STACK_DIR/skills/$s" "$dest"
        linked=$((linked + 1))
    done
    echo "skills: $linked linked into $CLAUDE_DIR/skills"

    # Statusline script (shows the running agent). A real file is backed up.
    STATUSLINE="$CLAUDE_DIR/statusline-command.sh"
    if [ -e "$STATUSLINE" ] && [ ! -L "$STATUSLINE" ]; then
        mv "$STATUSLINE" "$STATUSLINE.bak-$(date +%Y%m%d-%H%M%S)"
        echo "statusline: existing script backed up"
    fi
    ln -sfn "$STACK_DIR/global/statusline-command.sh" "$STATUSLINE"
    echo "statusline: script linked"
}

# Writes $2 (a jq program) over settings.json in place: keeps permissions and any symlink.
settings_jq() {
    local tmp
    tmp="$(mktemp)"
    jq "${@:2}" "$1" "$SETTINGS" > "$tmp" || { rm -f "$tmp"; echo "ERROR: jq failed on $SETTINGS" >&2; exit 1; }
    cat "$tmp" > "$SETTINGS"
    rm -f "$tmp"
}

# Main-session agent, guardrail permissions and statusLine in settings.json.
global_settings() {
    local main_agent="software-architect" perms="$STACK_DIR/global/permissions.json" before after

    [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

    # Main-session agent: merge one key, keep everything else.
    if [ "$(jq -r '.agent // empty' "$SETTINGS")" = "$main_agent" ]; then
        echo "settings: agent already $main_agent"
    else
        settings_jq '.agent = $a' --arg a "$main_agent"
        echo "settings: agent set to $main_agent"
    fi

    # Guardrails: add the missing deny/ask rules after the user's own; never remove or reorder one.
    before="$(jq '[.permissions.deny // [], .permissions.ask // []] | add | length' "$SETTINGS")"
    settings_jq '
        .permissions.deny = ((.permissions.deny // []) as $e | $e + ($p[0].permissions.deny - $e))
      | .permissions.ask  = ((.permissions.ask  // []) as $e | $e + ($p[0].permissions.ask  - $e))
    ' --slurpfile p "$perms"
    after="$(jq '[.permissions.deny, .permissions.ask] | add | length' "$SETTINGS")"
    echo "permissions: $((after - before)) deny/ask rules added from global/permissions.json"

    # statusLine: set only if none exists.
    if [ "$(jq -r '.statusLine.refreshInterval // empty' "$SETTINGS")" = "3000" ]; then
        settings_jq '.statusLine.refreshInterval = 3'
        echo "statusline: refreshInterval 3000 -> 3 (it is in seconds)"
    fi
    if [ -n "$(jq -r '.statusLine.command // empty' "$SETTINGS")" ]; then
        echo "statusline: statusLine already configured, left as is"
    else
        settings_jq '.statusLine = {type: "command", command: $c, refreshInterval: 3}' \
            --arg c "bash $(printf '%q' "$STATUSLINE")"
        echo "statusline: set in settings"
    fi
}

# Tools the harness expects but never installs.
global_checks() {
    if command -v engram >/dev/null; then
        echo "engram: $(engram version 2>/dev/null || echo installed)"
    else
        echo "engram: NOT installed, code-reviewer memory tools will be missing (commands below)"
    fi
    if command -v ego-browser >/dev/null || [ -x "$HOME/.local/bin/ego-browser" ]; then
        echo "ego-browser: installed"
    else
        echo "ego-browser: NOT installed, spec-verify cannot check UI criteria in a browser (commands below)"
    fi

    # MCP servers write to ~/.claude.json (some hold tokens), so they are never scripted here.
    cat <<'EOF'

MCP servers (run by hand, once per machine):

  # context7: an API key is optional (higher rate limits), add it with --header "CONTEXT7_API_KEY: <key>"
  claude mcp add --scope user --transport http context7 https://mcp.context7.com/mcp

  # GitHub: fine-grained PAT, read-only Contents/Issues/PRs. Do not use `read -s`, the paste breaks.
  read "GH?Paste PAT: " && [[ $GH == github_pat_* ]] && claude mcp add --scope user --transport http github https://api.githubcopilot.com/mcp --header "Authorization: Bearer ${GH//[[:space:]]/}"; unset GH; clear

  # engram: subagent memory. Setup registers the MCP as `engram mcp --tools=agent`.
  brew install gentleman-programming/tap/engram
  claude plugin marketplace add Gentleman-Programming/engram
  claude plugin install engram@engram
  engram setup claude-code

  claude mcp list   # context7, github and engram should show Connected

  # ego-browser: browser for UI checks in spec-verify (web). macOS only.
  # The skill installs the ego lite app on first use; finish its onboarding in the app.
  npx skills add citrolabs/ego-lite -g -a claude-code
EOF
}

if [ "$GLOBAL" = 1 ]; then
    [ ${#POSITIONAL[@]} -eq 0 ] && [ -z "$STACK" ] \
        || { echo "ERROR: --global takes no directory and no --stack."; exit 1; }
    # Respects CLAUDE_CONFIG_DIR (defaults to ~/.claude).
    CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    SETTINGS="$CLAUDE_DIR/settings.json"
    [ -f "$STACK_DIR/global/agents/software-architect.md" ] \
        || { echo "Missing $STACK_DIR/global/agents/software-architect.md" >&2; exit 1; }
    mkdir -p "$CLAUDE_DIR"

    global_links
    if [ "$UPDATE" = 1 ]; then
        echo "update: settings.json left untouched"
        exit 0
    fi
    command -v jq >/dev/null || { echo "jq is required: brew install jq" >&2; exit 1; }
    global_settings
    global_checks
    exit 0
fi

# =============================================================================
# Project: skills by stack, context tree, settings, CLAUDE.md, commit hook
# =============================================================================

TARGET_DIR="${POSITIONAL[0]:-$(pwd)}"
PROJECT_NAME="$(basename "$TARGET_DIR")"

# --update without --stack reads the stacks recorded by the first run.
if [ -z "$STACK" ] && [ "$UPDATE" = 1 ]; then
    STACK="$(cat "$TARGET_DIR/$STACK_FILE" 2>/dev/null)"
    [ -n "$STACK" ] || { echo "ERROR: $TARGET_DIR/$STACK_FILE not found. Pass --stack once; --update remembers it."; exit 1; }
fi
STACK="${STACK:-all}"

STACKS=(${STACK//,/ })
[ ${#STACKS[@]} -gt 0 ] || { echo "ERROR: Empty --stack."; exit 1; }
for s in "${STACKS[@]}"; do
    case "$s" in
        web|dotnet|android|ios) ;;
        all) [ ${#STACKS[@]} -eq 1 ] || { echo "ERROR: 'all' cannot be combined with other stacks."; exit 1; } ;;
        *) echo "ERROR: Unknown stack '$s'. Use: all, web, dotnet, android, ios (comma-separated)"; exit 1 ;;
    esac
done

# Returns 0 if $1 is one of the requested stacks.
has_stack() {
    local s
    for s in "${STACKS[@]}"; do [ "$s" = "$1" ] && return 0; done
    return 1
}

# Returns 0 if the file's `stacks:` frontmatter includes any requested stack (or "all").
stack_match() {
    has_stack all && return 0
    local line s
    # -a: some SKILL.md files contain stray control bytes, and without it grep
    # answers "Binary file ... matches" instead of the line.
    line="$(grep -a -m1 '^stacks: \[' "$1")" || return 1
    case "$line" in *all*) return 0 ;; esac
    for s in "${STACKS[@]}"; do
        case "$line" in *"$s"*) return 0 ;; esac
    done
    return 1
}

# A link belongs to the stack when it points into this repo, or when it is
# broken (left behind after the stack repo moved). Anything else is the user's.
is_stack_link() {
    [ -L "$1" ] || return 1
    case "$(readlink "$1")" in
        "$STACK_DIR"/*|"$DOTNET_SKILLS_DIR"/*) return 0 ;;
    esac
    [ ! -e "$1" ]
}

drop_stack_links() {
    local path="$1" link
    if [ -L "$path" ]; then
        if is_stack_link "$path"; then
            rm -f "$path"
        else
            echo "WARNING: $path is your own symlink, leaving it."
        fi
        return
    fi
    [ -d "$path" ] || return 0
    find "$path" -type l -print0 | while IFS= read -r -d '' link; do
        is_stack_link "$link" || continue
        rm -f "$link"
        rmdir -p "$(dirname "$link")" 2>/dev/null || true
    done
}

# Symlinks every matching skill into $1.
link_stack_skills() {
    local dest="$1" cat skill name
    LINKED_SKILLS=0
    STACK_SKILLS=()
    if [ -L "$dest" ]; then
        echo "WARNING: $dest is your own symlink, not linking stack skills into it."
        return
    fi
    mkdir -p "$dest"
    for cat in "$STACK_DIR/skills"/*/; do
        for skill in "$cat"*/; do
            [ -f "${skill}SKILL.md" ] || continue
            stack_match "${skill}SKILL.md" || continue
            name="$(basename "$skill")"
            case " ${STACK_SKILLS[*]} " in
                *" $dest/$name "*)
                    echo "WARNING: two skills named '$name', skipping ${skill%/}."
                    continue ;;
            esac
            if { [ -e "$dest/$name" ] || [ -L "$dest/$name" ]; } && ! is_stack_link "$dest/$name"; then
                echo "WARNING: $dest/$name is yours, not a stack link, skipping."
                if grep -qxF -- "$dest/$name" .gitignore 2>/dev/null; then
                    echo "    It is still in .gitignore, remove that line to commit it."
                fi
                continue
            fi
            ln -sfn "${skill%/}" "$dest/$name"
            STACK_SKILLS+=("$dest/$name")
            LINKED_SKILLS=$((LINKED_SKILLS + 1))
        done
    done
}

# Removes the stack's links (including names used before the Claude-Code-only
# migration), links the skills for STACKS and, for dotnet, the external .NET repo.
link_project() {
    mkdir -p .claude
    # .claude/agents held per-project agent links; agents now live at user level (--global).
    drop_stack_links .claude/commands
    drop_stack_links .claude/agents
    drop_stack_links .claude/skills
    drop_stack_links .claude/recipes
    drop_stack_links .agents/skills
    rm -f .claude/personas .agents/personas .agents/commands .agents/agents .agents/recipes

    link_stack_skills ".claude/skills"
    EXTRA_LINKS=()
    # The external .NET skills repo carries no stacks: frontmatter. It is all .NET
    # by definition, so it links wholesale, and only when dotnet is named.
    if has_stack dotnet; then
        if [ ! -d "$DOTNET_SKILLS_DIR" ]; then
            echo "WARNING: $DOTNET_SKILLS_DIR not found, skipping the .NET skills repo."
        else
            mkdir -p .claude/commands
            if [ -e .claude/commands/dotnet ] && [ ! -L .claude/commands/dotnet ]; then
                echo "WARNING: .claude/commands/dotnet is not a symlink, skipping."
            else
                ln -sfn "$DOTNET_SKILLS_DIR/skills" .claude/commands/dotnet
                EXTRA_LINKS+=(".claude/commands/dotnet")
            fi
            if [ -e .claude/recipes ] && [ ! -L .claude/recipes ]; then
                echo "WARNING: .claude/recipes is not a symlink, skipping."
            else
                ln -sfn "$DOTNET_SKILLS_DIR/recipes" .claude/recipes
                EXTRA_LINKS+=(".claude/recipes")
            fi
        fi
    fi
    echo "$STACK" > "$STACK_FILE"
    echo "OK: Linked $LINKED_SKILLS skills for stack '$STACK'${EXTRA_LINKS[*]:+, plus the .NET skills repo}"
}

# Ignores only what is machine-local or a symlink into the stack. The context
# tree (.claude/business, architecture, domains, engineering) and the root
# CLAUDE.md are team-shared instructions and MUST stay in source control.
update_gitignore() {
    local entry header="# AI Engineering Stack"
    local entries=(".claude/settings.local.json" "$STACK_FILE" "graphify-out/" "${EXTRA_LINKS[@]}" "${STACK_SKILLS[@]}")

    if [ ! -f ".gitignore" ]; then
        touch ".gitignore"
        echo "OK: Created .gitignore"
    fi
    # Without a final newline, the first append would glue onto the user's last line.
    [ -n "$(tail -c1 .gitignore)" ] && echo >> ".gitignore"
    grep -q "$header" ".gitignore" || echo -e "\n$header" >> ".gitignore"
    for entry in "${entries[@]}"; do
        [ -n "$entry" ] || continue
        grep -qxF -- "$entry" ".gitignore" && continue
        echo "$entry" >> ".gitignore"
        echo "OK: Added $entry to .gitignore"
    done
    # Clean up potential double newlines
    sed -i '' '/^$/N;/^\n$/D' ".gitignore" 2>/dev/null || true

    if grep -qxE '\.claude/(commands|agents)/?' ".gitignore"; then
        echo "WARNING: .gitignore still has '.claude/commands' or '.claude/agents' from an"
        echo "    older init. Skills now live in .claude/skills, so remove those lines if"
        echo "    you keep your own commands or agents there."
    fi
    # A project set up before the context tree was versioned still has a bare
    # ".claude/" line, which keeps ignoring everything under it.
    if grep -qE '^\.claude/?$' ".gitignore"; then
        echo "WARNING: .gitignore still has a bare '.claude/' entry — it ignores the whole"
        echo "    context tree. Remove that line so .claude/business, architecture,"
        echo "    domains and engineering get committed."
    fi
}

project_settings() {
    if [ -f ".claude/settings.json" ]; then
        echo "WARNING: .claude/settings.json already exists, skipping."
    elif has_stack web; then
        # Web projects use pnpm: the deny blocks npm/npx so the rule holds even when the model forgets it.
        cat > ".claude/settings.json" <<'EOF'
{
  "permissions": {
    "deny": ["Bash(npm *)", "Bash(npx *)"]
  },
  "hooks": {}
}
EOF
        echo "OK: Created .claude/settings.json (npm/npx denied, use pnpm)"
    else
        cat > ".claude/settings.json" <<'EOF'
{
  "hooks": {}
}
EOF
        echo "OK: Created .claude/settings.json"
    fi
}

# Root CLAUDE.md as the context index. Claude Code auto-loads ./CLAUDE.md or
# ./.claude/CLAUDE.md; the root keeps a single instruction file. An existing one
# (e.g. checked-in team instructions) is left untouched: /fill-context merges into it.
project_claude_md() {
    if [ -f "CLAUDE.md" ]; then
        echo "WARNING: CLAUDE.md already exists, skipping (run /fill-context to merge the context index into it)."
        return
    fi
    local recipes="" arch="Stack, patterns, directory structure" commands pm_rule=""
    if has_stack dotnet; then
        recipes=$'\n> **.NET Clean Architecture**: Refer to `.claude/recipes` for backend workflows.'
        arch="Stack, patterns, layer boundaries"
    fi
    if [ "$STACK" = "dotnet" ]; then
        commands=$'dotnet build         # Build project\ndotnet test          # Run tests'
    else
        local pm="npm"
        if has_stack web; then
            pm="pnpm"
            pm_rule="Always use pnpm, never npm or npx (\`pnpm dlx\` for one-off binaries)."
        fi
        commands="$pm run dev          # Dev server
$pm run lint         # ESLint
$pm run test         # Unit tests"
    fi
    cat > "CLAUDE.md" <<EOF
# $PROJECT_NAME — Claude Code Instructions

> Read the linked files for domain, architecture, and business context before proposing changes or adding new entities.
> **Context not yet generated.** Run \`/fill-context\` in Claude Code to populate the sections below.$recipes

## Business
- [Overview](.claude/business/overview.md) — Purpose, users, success metrics
- [Rules](.claude/business/rules.md) — Non-negotiable business rules
- [Glossary](.claude/business/glossary.md) — Ubiquitous language

## Architecture
- [Overview](.claude/architecture/overview.md) — $arch
- [Integrations](.claude/architecture/integrations.md) — External services and APIs

## Domains
*(Generated by \`/fill-context\`)*

## Engineering
- [Standards](.claude/engineering/standards.md) — Coding conventions and patterns
- [Testing](.claude/engineering/testing.md) — Test strategy and commands

---

## Commands

\`\`\`bash
$commands
\`\`\`${pm_rule:+
$pm_rule}
EOF
    echo "OK: Created CLAUDE.md"
}

# Commit message hook. It lives only in this stack: the repo gets local,
# untracked config pointing at it, and no file is copied into the project.
project_commit_hook() {
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "WARNING: Not a git repository, skipping the commit-msg hook. Run git init, then re-run this script."
        return
    fi
    local hooks_dir="$STACK_DIR/global/githooks" hooks_path live_hook
    hooks_path="$(git config --local core.hooksPath)"
    # core.hooksPath replaces .git/hooks entirely, so never switch it over live hooks.
    live_hook="$(find "$(git rev-parse --git-path hooks)" -type f ! -name '*.sample' 2>/dev/null | head -1)"
    if [ "$hooks_path" = "$hooks_dir" ]; then
        echo "OK: core.hooksPath already points to the stack hooks"
    elif [ -n "$hooks_path" ]; then
        echo "WARNING: core.hooksPath is '$hooks_path' (husky?). Not overriding it; call $hooks_dir/commit-msg from there."
    elif [ -n "$live_hook" ]; then
        echo "WARNING: .git/hooks has live hooks that core.hooksPath would disable. Not enabling the commit-msg hook."
    else
        git config core.hooksPath "$hooks_dir"
        echo "OK: Enabled commit-msg hook (core.hooksPath -> $hooks_dir)"
    fi
}

if [ "$UPDATE" = 1 ]; then
    [ -d "$TARGET_DIR" ] || { echo "ERROR: $TARGET_DIR does not exist."; exit 1; }
    cd "$TARGET_DIR" || { echo "Failed to cd to $TARGET_DIR"; exit 1; }
    echo "Updating harness links for $PROJECT_NAME (stack '$STACK')"
    link_project
    update_gitignore
    exit 0
fi

echo "Setting up the harness for project: $PROJECT_NAME at $TARGET_DIR"
mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR" || { echo "Failed to cd to $TARGET_DIR"; exit 1; }

link_project
for context_dir in .claude/business .claude/architecture .claude/domains .claude/engineering; do
    mkdir -p "$context_dir"
done
echo "OK: Created .claude/ context subdirectories"
update_gitignore
project_settings
project_claude_md
project_commit_hook

echo ""
echo "Setup complete for $PROJECT_NAME!"
echo ""
echo "Next step: open Claude Code in this project and run:"
echo "   /fill-context"
echo "   The AI will scan the codebase, ask what the code cannot tell it, and write the .claude/ context tree with the root CLAUDE.md as its index."
