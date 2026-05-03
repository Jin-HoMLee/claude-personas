#!/usr/bin/env bash
# init-worktree.sh — create a project worktree bound to a claude-personas role.
#
# Run from inside your PROJECT repo (not claude-personas). Creates a worktree at
# <worktree-path> on a new branch, then writes the per-worktree config files:
#   - .claude/settings.local.json (autoMemoryDirectory pointing at the role)
#   - CLAUDE.local.md (role label + absolute role path)
# and adds both to the worktree's .gitignore.
#
# Discovers the claude-personas root from this script's own location, so the
# user invokes it by absolute path — e.g.
#   ~/projects/claude-personas/scripts/init-worktree.sh pm ../my-app-pm

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PERSONAS_ROOT="$( dirname "$SCRIPT_DIR" )"

usage() {
  cat <<EOF
Usage: $(basename "$0") <role> <worktree-path> [branch-name]

  role            Role folder in claude-personas (e.g. developer, pm, designer)
  worktree-path   Path for the new worktree (relative to your project repo, or absolute)
  branch-name     Branch name for the worktree (default: <role>/workspace)

Run from inside your PROJECT repo (not claude-personas).

Examples:
  $(basename "$0") pm ../my-app-pm
  $(basename "$0") developer ../my-app-dev developer/feature-auth
EOF
}

case "${1-}" in
  -h|--help) usage; exit 0 ;;
esac

if [[ $# -lt 2 ]]; then
  usage >&2
  exit 1
fi

ROLE="$1"
WORKTREE_PATH="$2"
BRANCH_NAME="${3:-$ROLE/workspace}"

ROLE_DIR="$PERSONAS_ROOT/$ROLE"

if [[ ! -d "$ROLE_DIR" || ! -f "$ROLE_DIR/MEMORY.md" ]]; then
  echo "Error: role '$ROLE' not found (expected $ROLE_DIR/MEMORY.md)" >&2
  echo "" >&2
  echo "Available roles in $PERSONAS_ROOT:" >&2
  for dir in "$PERSONAS_ROOT"/*/; do
    name="$(basename "$dir")"
    if [[ -f "$dir/MEMORY.md" && "$name" != "shared" && "$name" != "examples" ]]; then
      echo "  $name" >&2
    fi
  done
  exit 1
fi

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "Error: not inside a git repo. Run this from your PROJECT repo." >&2
  exit 1
fi

if [[ -e "$WORKTREE_PATH" ]]; then
  echo "Error: '$WORKTREE_PATH' already exists." >&2
  exit 1
fi

if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
  echo "Error: branch '$BRANCH_NAME' already exists." >&2
  echo "Pass a different branch name as the 3rd argument, or delete the existing branch first." >&2
  exit 1
fi

echo "Creating worktree:"
echo "  Path:   $WORKTREE_PATH"
echo "  Branch: $BRANCH_NAME"
echo "  Role:   $ROLE → $ROLE_DIR"
echo ""

# If a step after `git worktree add` fails, undo the worktree + branch so the
# user can re-run the script without first cleaning up by hand.
WORKTREE_CREATED=""
cleanup_on_error() {
  if [[ -n "$WORKTREE_CREATED" && -d "$WORKTREE_CREATED" ]]; then
    echo "Cleaning up partial worktree at $WORKTREE_CREATED..." >&2
    git worktree remove --force "$WORKTREE_CREATED" 2>/dev/null || true
    git branch -D "$BRANCH_NAME" 2>/dev/null || true
  fi
}
trap cleanup_on_error ERR

git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME"
WORKTREE_CREATED="$WORKTREE_PATH"

WORKTREE_ABS="$( cd "$WORKTREE_PATH" && pwd )"

mkdir -p "$WORKTREE_ABS/.claude"
cat > "$WORKTREE_ABS/.claude/settings.local.json" <<EOF
{
  "autoMemoryDirectory": "$ROLE_DIR"
}
EOF
echo "✓ Wrote $WORKTREE_ABS/.claude/settings.local.json"

cat > "$WORKTREE_ABS/CLAUDE.local.md" <<EOF
# Local notes (this machine only — gitignored)

## Worktree role: $ROLE

This is the $ROLE worktree. claude-personas role memory and behavior rules
are in \`autoMemoryDirectory\` (loaded automatically at session start).

## claude-personas memory absolute path

Use this prefix with the Read tool when accessing role memory or shared memory:

\`\`\`
$ROLE_DIR/
\`\`\`

- Role MEMORY.md: \`$ROLE_DIR/MEMORY.md\`
- Shared MEMORY.md: \`$ROLE_DIR/shared/MEMORY.md\` (the \`shared/\` folder is a symlink to \`../shared/\`)
EOF
echo "✓ Wrote $WORKTREE_ABS/CLAUDE.local.md"

GITIGNORE="$WORKTREE_ABS/.gitignore"
add_ignore() {
  local pattern="$1"
  if [[ -f "$GITIGNORE" ]] && grep -qxF "$pattern" "$GITIGNORE"; then
    return
  fi
  # Ensure trailing newline before appending if file exists and lacks one
  if [[ -f "$GITIGNORE" && -s "$GITIGNORE" ]] && [[ "$(tail -c 1 "$GITIGNORE")" != "" ]]; then
    echo "" >> "$GITIGNORE"
  fi
  echo "$pattern" >> "$GITIGNORE"
  echo "✓ Added '$pattern' to .gitignore"
}
add_ignore "CLAUDE.local.md"
add_ignore ".claude/settings.local.json"

echo ""
echo "Done. Open Claude Code in $WORKTREE_ABS — it will auto-load $ROLE/MEMORY.md."
