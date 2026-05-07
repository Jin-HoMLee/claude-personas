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
# Note: the hash function (replace / with -) is lossy when paths contain dashes.
# We use heuristics to preserve common patterns that shouldn't be split:
# - mktemp-style temp directory names (e.g., list-roles-healthy-XXXX.randomstuff)
# - project name suffixes (e.g., -project-pm)
unhash() {
  local hash="$1"
  local path="${hash#-}"  # Remove leading dash

  # Match paths with /var/folders (macOS temp directory style)
  # Pattern: var-folders-...-T-<tempdir-with-dashes>-XXXX.<alphanum>-<suffix>
  if [[ "$path" =~ ^(.+)-T-([a-z-]+-XXXX\.[a-zA-Z0-9]+)(.*)$ ]]; then
    local prefix="${BASH_REMATCH[1]}"
    local tempdir="${BASH_REMATCH[2]}"
    local suffix="${BASH_REMATCH[3]}"  # e.g., "-project-pm"

    # Convert prefix dashes to slashes
    prefix="${prefix//-//}"

    # Convert suffix leading dash to slash (but preserve remaining dashes in project name)
    suffix="${suffix/#-//}"

    path="/$prefix/T/$tempdir$suffix"
  else
    # Fallback for non-/var/folders paths: convert all dashes
    # This will be lossy but is the best we can do without the T/ marker
    path="/${path//-//}"
  fi

  echo "$path"
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
