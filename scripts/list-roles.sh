#!/usr/bin/env bash
# list-roles.sh — audit which project worktrees are wired to which claude-personas roles.
#
# Scans ~/.claude/projects/*/memory for symlinks and reports their target role + status.

set -uo pipefail

PROJECTS_DIR="$HOME/.claude/projects"

if [[ ! -d "$PROJECTS_DIR" ]]; then
  echo "No ~/.claude/projects/ directory — no Claude Code projects yet."
  exit 0
fi

# Reverse the hash transform: -Users-foo-bar → /Users/foo/bar
# Note: this is lossy if the original path contained dashes (e.g., my-app-pm
# becomes my/app/pm). The output is for human auditing, not exact reconstruction —
# users can recognize their worktrees from the role name + general structure.
unhash() {
  echo "$1" | sed 's|^-|/|; s|-|/|g'
}

found=0
broken=0

for memory_link in "$PROJECTS_DIR"/*/memory; do
  [[ -e "$memory_link" || -L "$memory_link" ]] || continue
  if [[ -L "$memory_link" ]]; then
    found=$((found + 1))
    hash_dir="$(dirname "$memory_link")"
    hash="$(basename "$hash_dir")"
    worktree="$(unhash "$hash")"
    target="$(readlink "$memory_link")"
    role="$(basename "$target")"

    if [[ -d "$target" ]]; then
      echo "✓ $worktree"
      echo "    role:   $role"
      echo "    target: $target"
    else
      broken=$((broken + 1))
      echo "✗ $worktree (BROKEN)"
      echo "    role:   $role"
      echo "    target: $target  ← does not exist"
    fi
  fi
done

if [[ "$found" -eq 0 ]]; then
  echo "No claude-personas role symlinks found in $PROJECTS_DIR"
  echo "(no worktrees have been wired with init-worktree.sh)"
  exit 0
fi

echo ""
echo "$found wired worktree(s) found, $broken broken."
[[ "$broken" -eq 0 ]] || exit 1
