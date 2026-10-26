#!/usr/bin/env bash
# Prints the setup script for a Claude Code cloud environment (claude.ai/code).
# Cloud sessions load only the repo clone, never ~/.claude, so the setup script
# installs this stack and writes your user-level CLAUDE.md and its @imports.
#
#   ./global/build-cloud-setup.sh | pbcopy
#
# The output embeds your personal files. Paste it into the environment config;
# never commit it. Respects CLAUDE_CONFIG_DIR (defaults to ~/.claude).
set -euo pipefail

STACK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REPO_URL="$(git -C "$STACK_DIR" remote get-url origin)"
EOF_MARK="CLAUDE_CLOUD_EOF"

[ -f "$CLAUDE_DIR/CLAUDE.md" ] || { echo "Missing $CLAUDE_DIR/CLAUDE.md" >&2; exit 1; }

# heredoc NAME CONTENT: one file written into the VM's ~/.claude
heredoc() {
    if printf '%s\n' "$2" | grep -qx "$EOF_MARK"; then
        echo "$1 contains a line '$EOF_MARK', which would end the heredoc early" >&2
        exit 1
    fi
    printf "cat > ~/.claude/%s <<'%s'\n%s\n%s\n" "$1" "$EOF_MARK" "$2" "$EOF_MARK"
}

cat <<EOF
#!/bin/bash
set -euo pipefail
command -v jq >/dev/null || apt-get install -y jq
git clone --depth 1 $REPO_URL /opt/clawd-harness
bash /opt/clawd-harness/harness.sh --global

# Personal files: generated from $CLAUDE_DIR, not in the public repo
EOF

# RTK.md is skipped: rtk is not installed in the cloud VM.
heredoc CLAUDE.md "$(grep -vx '@RTK.md' "$CLAUDE_DIR/CLAUDE.md")"
{ grep -x '@[^ ]*\.md' "$CLAUDE_DIR/CLAUDE.md" || true; } | sed 's/^@//' | while read -r f; do
    [ "$f" = "RTK.md" ] && continue
    [ "$f" = "behavior.md" ] && continue   # linked from the clone by harness.sh --global
    [ -f "$CLAUDE_DIR/$f" ] || { echo "Missing $CLAUDE_DIR/$f (imported by CLAUDE.md)" >&2; exit 1; }
    heredoc "$f" "$(cat "$CLAUDE_DIR/$f")"
done
