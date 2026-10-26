#!/usr/bin/env bash

input=$(cat)

# Tokyo Night
BLUE=$'\033[38;2;122;162;247m'    # #7AA2F7 folder
CYAN=$'\033[38;2;125;207;255m'    # #7DCFFF api/ios icons
PURPLE=$'\033[38;2;187;154;247m'  # #BB9AF7 model
AMBER=$'\033[38;2;224;175;104m'   # #E0AF68 branch / ticket
GREEN=$'\033[38;2;158;206;106m'   # #9ECE6A low usage
YELLOW=$'\033[38;5;221m'
RED=$'\033[38;5;203m'
ORANGE=$'\033[38;5;215m'
DIM=$'\033[38;2;86;95;137m'       # #565F89 separators
RESET=$'\033[0m'

# Nerd Font icons as UTF-8 bytes: the literal glyph gets lost when the file is saved
ICON_REPO=$'\xef\x81\xbb'       # nf-fa-folder
ICON_PR=$'\xef\x90\x87'         # nf-oct-git_pull_request
ICON_MODEL=$'\xef\x8b\x9b'      # nf-fa-microchip
ICON_BOLT=$'\xef\x83\xa7'       # nf-fa-bolt
ICON_API=$'\xef\x88\xb3'        # nf-fa-server
ICON_INTERFACE=$'\xef\x85\xb9'  # nf-fa-apple

# 5 cells of 20%, rounded up: any usage > 0 fills one
make_bar() {
  local pct=$1
  local filled=$(( (pct + 19) / 20 ))
  [ "$filled" -gt 5 ] && filled=5
  local empty=$(( 5 - filled ))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="▰"; done
  for ((i=0; i<empty; i++)); do bar+="▱"; done
  printf '%s' "$bar"
}

# Caps the branch width so it doesn't push the rest of the statusline off the
# terminal. Plain truncation: keep the start, cut the rest. The cap is set with
# CLAUDE_STATUSLINE_BRANCH_MAX.
BRANCH_MAX=${CLAUDE_STATUSLINE_BRANCH_MAX:-24}

shorten_branch() {
  local b=$1
  [ "${#b}" -le "$BRANCH_MAX" ] && { printf '%s' "$b"; return; }
  printf '%s…' "${b:0:$((BRANCH_MAX - 1))}"
}

rate_color() {
  local pct=$1
  if [ "$pct" -ge 80 ]; then   printf '%s' "$RED"
  elif [ "$pct" -ge 50 ]; then printf '%s' "$YELLOW"
  else                          printf '%s' "$GREEN"
  fi
}

# Context bar: green, orange from 50%, red alert at 80%
ctx_color() {
  local pct=$1
  if [ "$pct" -ge 80 ]; then   printf '%s' "$RED"
  elif [ "$pct" -ge 50 ]; then printf '%s' "$ORANGE"
  else                          printf '%s' "$GREEN"
  fi
}

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')

# The Claude Code payload has no repo/branch/worktree: derive them from git.
# If the shell moved to a directory outside the repo, fall back to project_dir
# so the statusline shows the project, not a stray folder.
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$top" ] && [ -n "$project_dir" ]; then
  top=$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null)
  [ -n "$top" ] && cwd="$project_dir"
fi

dir=$(basename "$cwd")
repo=""
branch=""

if [ -n "$top" ]; then
  repo=$(basename "$top")
  branch=$(git -C "$top" rev-parse --abbrev-ref HEAD 2>/dev/null)
  # Detached HEAD: no branch, show the short sha
  if [ "$branch" = "HEAD" ]; then
    branch=$(git -C "$top" rev-parse --short HEAD 2>/dev/null)
  fi
  branch=$(shorten_branch "$branch")
  # dirty marker: diff in the tree or the index, cheaper than status --porcelain
  if ! git -C "$top" diff --quiet --ignore-submodules -- 2>/dev/null \
     || ! git -C "$top" diff --cached --quiet --ignore-submodules -- 2>/dev/null; then
    branch="${branch}*"
  fi
  # Linked worktree: .git is a file, not a directory. The repo name comes from
  # the git-common-dir (the main checkout), not this checkout, or the worktree
  # folder would show instead of the repo. The folder name is not shown: the
  # branch already identifies the work.
  if [ -f "$top/.git" ]; then
    common=$(git -C "$top" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if [ -n "$common" ]; then
      main_root=$(dirname "$common")
      [ -n "$main_root" ] && repo=$(basename "$main_root")
    fi
  fi
fi
# Hub (e.g. ~/dallio/ga): not a repo, branches live in its sub-repos. Only the
# ones on a ticket branch are shown, shortened to the id (TGN-520). /branches
# gives the full detail.
ticket_of() {
  [[ $1 =~ (^|/)([A-Za-z]+-[0-9]+) ]] && printf '%s' "${BASH_REMATCH[2]}" | tr '[:lower:]' '[:upper:]'
}
hub_part=""
if [ -z "$top" ]; then
  hub=""
  for d in "$cwd" "$project_dir"; do
    if [ -d "$d/api/.git" ] || [ -d "$d/interface/.git" ]; then hub=$d; break; fi
  done
  if [ -n "$hub" ]; then
    dir=$(basename "$hub")
    names=(); ids=()
    for r in api interface; do
      id=$(ticket_of "$(git -C "$hub/$r" branch --show-current 2>/dev/null)")
      [ -z "$id" ] && continue
      if ! git -C "$hub/$r" diff --quiet -- 2>/dev/null \
         || ! git -C "$hub/$r" diff --cached --quiet -- 2>/dev/null; then r="${r}*"; fi
      [ "${r%\*}" = api ] && label=$ICON_API || label=$ICON_INTERFACE
      [ "$r" != "${r%\*}" ] && label="${label}*"
      names+=("$label"); ids+=("$id")
    done
    if [ "${#ids[@]}" -eq 2 ] && [ "${ids[0]}" = "${ids[1]}" ]; then
      hub_part="${CYAN}${names[0]} ${names[1]}${RESET} ${AMBER}${ids[0]}${RESET}"
    elif [ "${#ids[@]}" -gt 0 ]; then
      for i in "${!ids[@]}"; do
        [ -n "$hub_part" ] && hub_part+="${DIM} · ${RESET}"
        hub_part+="${CYAN}${names[$i]}${RESET} ${AMBER}${ids[$i]}${RESET}"
      done
    else
      # No ticket branch yet (planning): the last link or branch you pasted.
      # Only your own messages, not tool results, so ids from logs or files are ignored.
      tp=$(echo "$input" | jq -r '.transcript_path // empty')
      if [ -f "$tp" ]; then
        id=$(ticket_of "$(grep '"type":"user"' "$tp" | grep -v '"tool_result"' \
          | grep -oE 'issue/[A-Za-z]+-[0-9]+|[a-z]+/[a-z]{2,5}-[0-9]+-' | tail -1)")
        [ -n "$id" ] && hub_part="${DIM}→ ${id}${RESET}"
      fi
    fi
  fi
fi

model=$(echo "$input" | jq -r '.model.display_name // empty')
model=${model% (*context)}
agent=$(echo "$input" | jq -r '.agent.name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
effort=$(echo "$input" | jq -r '.effort.level // empty')
pr_number=$(echo "$input" | jq -r '.pr.number // empty')
pr_state=$(echo "$input" | jq -r '.pr.review_state // "open"')
five_hour=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

parts=()
sep="${DIM} │ ${RESET}"

# Repo / dir + branch
if [ -n "$repo" ]; then
  loc="${BLUE}${ICON_REPO} ${repo}${RESET}"
elif [ -n "$dir" ]; then
  loc="${BLUE}${ICON_REPO} ${dir}${RESET}"
else
  loc=""
fi
if [ -n "$loc" ] && [ -n "$hub_part" ]; then
  parts+=("${loc}  ${hub_part}")
elif [ -n "$loc" ] && [ -n "$branch" ]; then
  parts+=("${loc}  ${AMBER}${branch}${RESET}")
elif [ -n "$loc" ]; then
  parts+=("$loc")
fi

if [ -n "$pr_number" ]; then
  case "$pr_state" in
    approved)          pr_color="$GREEN" ;;
    changes_requested) pr_color="$RED" ;;
    draft)             pr_color="$DIM" ;;
    *)                 pr_color="$YELLOW" ;;
  esac
  parts+=("${pr_color}${ICON_PR} #${pr_number}${RESET}")
fi

if [ -n "$agent" ]; then
  parts+=("${CYAN}${agent}${RESET}")
fi

# Runtime mode for spec-apply/spec-verify (~/.claude/runtime-mode); missing file = light
if [ "$(cat "$HOME/.claude/runtime-mode" 2>/dev/null)" = "full" ]; then
  parts+=("${GREEN}full${RESET}")
else
  parts+=("${DIM}light${RESET}")
fi

if [ -n "$model" ]; then
  parts+=("${PURPLE}${ICON_MODEL} ${model}${RESET}")
fi

if [ -n "$effort" ] && [ "$effort" != "medium" ]; then
  parts+=("${ORANGE}${ICON_BOLT} ${effort}${RESET}")
fi

if [ -n "$used_pct" ]; then
  used_int=$(printf '%.0f' "$used_pct")
  ctx_color=$(ctx_color "$used_int")
  bar=$(make_bar "$used_int")
  parts+=("${ctx_color}${bar} ${used_int}%${RESET}")
fi

# Rate limits
rate_part=""
if [ -n "$five_hour" ]; then
  five_int=$(printf '%.0f' "$five_hour")
  five_color=$(rate_color "$five_int")
  rate_part="${five_color}5h ${five_int}%${RESET}"
fi
if [ -n "$seven_day" ]; then
  seven_int=$(printf '%.0f' "$seven_day")
  seven_color=$(rate_color "$seven_int")
  seven_part="${seven_color}7d ${seven_int}%${RESET}"
  if [ -n "$rate_part" ]; then
    rate_part="${rate_part}${DIM} · ${RESET}${seven_part}"
  else
    rate_part="$seven_part"
  fi
fi
if [ -n "$rate_part" ]; then
  parts+=("$rate_part")
fi

result=""
for part in "${parts[@]}"; do
  if [ -z "$result" ]; then
    result="$part"
  else
    result="${result}${sep}${part}"
  fi
done

printf '%s\n' "$result"
