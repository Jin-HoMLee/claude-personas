#!/usr/bin/env bash
# init-worktree.sh — create a project worktree wired to a claude-personas role
# via filesystem symlinks at Claude Code's native per-project memory paths.
#
# Run from inside your PROJECT repo (not claude-personas). Creates a worktree at
# <worktree-path> on a new branch, then sets up symlinks:
#   ~/.claude/projects/<role-hash>/memory  →  <claude-personas-clone>/<role>/
#   <claude-personas-clone>/shared         →  ~/.claude/projects/<main-hash>/memory/
# (the second is a one-time setup that converts shared/ from a real folder to a symlink)
#
# Per-project clone model: this clone becomes wired to ONE project. Use a separate
# clone for each project.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PERSONAS_ROOT="$( dirname "$SCRIPT_DIR" )"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--force] <role> <worktree-path> [branch-name]

  role            Role folder in claude-personas (e.g. developer, pm, designer)
  worktree-path   Path for the new worktree (relative to your project repo, or absolute)
  branch-name     Branch name for the worktree (default: <role>/workspace)

  --force         Back up any pre-existing <role-hash>/memory/ to <role-hash>/memory.backup-DATE/
                  before creating the symlink. Use when prior Claude sessions left content there.

Run from inside your PROJECT repo (not claude-personas).

Examples:
  $(basename "$0") pm ../my-app-pm
  $(basename "$0") developer ../my-app-dev developer/feature-auth
  $(basename "$0") --force pm ../my-app-pm
EOF
}

# Compute Claude Code's project hash from an absolute path.
# Claude Code replaces both "/" and "." with "-" (e.g. /var/folders/x.y/test → -var-folders-x-y-test).
# Caller is responsible for resolving the path to its physical (symlink-resolved) form first.
compute_hash() {
  echo "$1" | tr '/.' '-'
}

# Parse flags
FORCE=0
while [[ "${1-}" =~ ^- ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --force) FORCE=1; shift ;;
    *) echo "Error: unknown flag $1" >&2; usage >&2; exit 1 ;;
  esac
done

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

# Compute hashes from the canonical PHYSICAL absolute paths.
# Claude Code resolves /var → /private/var on macOS, so we use pwd -P to match.
_GIT_CDUP="$(git rev-parse --show-cdup)"
if [[ -z "$_GIT_CDUP" ]]; then
  PROJECT_ABS="$(pwd -P)"
else
  PROJECT_ABS="$(cd "$_GIT_CDUP" && pwd -P)"
fi
MAIN_HASH="$(compute_hash "$PROJECT_ABS")"

# Resolve worktree path to absolute physical form. The worktree leaf doesn't exist
# yet, so we resolve the parent (which exists) via pwd -P, then append the leaf.
case "$WORKTREE_PATH" in
  /*) WORKTREE_ABS_TARGET="$WORKTREE_PATH" ;;
  *)  WORKTREE_ABS_TARGET="$(pwd -P)/$WORKTREE_PATH" ;;
esac
# Normalize: collapse .. and . segments
WORKTREE_ABS_TARGET="$(python3 -c "import os, sys; print(os.path.normpath(sys.argv[1]))" "$WORKTREE_ABS_TARGET")"
# Resolve any symlinks in the parent path (e.g. /var → /private/var on macOS)
_WT_PARENT="$(dirname "$WORKTREE_ABS_TARGET")"
_WT_LEAF="$(basename "$WORKTREE_ABS_TARGET")"
if [[ -d "$_WT_PARENT" ]]; then
  WORKTREE_ABS_TARGET="$(cd "$_WT_PARENT" && pwd -P)/$_WT_LEAF"
fi
ROLE_HASH="$(compute_hash "$WORKTREE_ABS_TARGET")"

ROLE_HASH_DIR="$HOME/.claude/projects/$ROLE_HASH"
ROLE_MEMORY_LINK="$ROLE_HASH_DIR/memory"
MAIN_HASH_DIR="$HOME/.claude/projects/$MAIN_HASH"
MAIN_MEMORY_DIR="$MAIN_HASH_DIR/memory"
SHARED_LINK="$PERSONAS_ROOT/shared"

echo "Creating worktree:"
echo "  Path:       $WORKTREE_PATH (resolved: $WORKTREE_ABS_TARGET)"
echo "  Branch:     $BRANCH_NAME"
echo "  Role:       $ROLE → $ROLE_DIR"
echo "  Role hash:  $ROLE_HASH"
echo "  Main hash:  $MAIN_HASH"
echo ""

# --- Pre-flight check: shared symlink integrity ---
# If clone/shared is already a symlink, verify it points at THIS project's main-hash.
# If it points elsewhere, abort: this clone is wired to a different project.
if [[ -L "$SHARED_LINK" ]]; then
  CURRENT_TARGET="$(readlink "$SHARED_LINK")"
  EXPECTED_TARGET="$MAIN_MEMORY_DIR/"
  EXPECTED_TARGET_NOSLASH="$MAIN_MEMORY_DIR"
  if [[ "$CURRENT_TARGET" != "$EXPECTED_TARGET" && "$CURRENT_TARGET" != "$EXPECTED_TARGET_NOSLASH" ]]; then
    echo "Error: this claude-personas clone is already wired to a different project." >&2
    echo "  $SHARED_LINK currently points to: $CURRENT_TARGET" >&2
    echo "  Expected target for this project: $EXPECTED_TARGET" >&2
    echo "" >&2
    echo "Use a fresh clone of claude-personas for a different project." >&2
    exit 1
  fi
fi

# --- Pre-flight check: role-hash memory dir state ---
ROLE_LINK_PRE_EXISTS=0
if [[ -L "$ROLE_MEMORY_LINK" ]]; then
  CURRENT_ROLE_TARGET="$(readlink "$ROLE_MEMORY_LINK")"
  if [[ "$CURRENT_ROLE_TARGET" == "$ROLE_DIR/" || "$CURRENT_ROLE_TARGET" == "$ROLE_DIR" ]]; then
    ROLE_LINK_PRE_EXISTS=1
    echo "Note: $ROLE_MEMORY_LINK already symlinked to this role (idempotent re-run)."
  else
    echo "Error: $ROLE_MEMORY_LINK is a symlink pointing elsewhere: $CURRENT_ROLE_TARGET" >&2
    echo "Manual review required (use --force to back up and overwrite)." >&2
    if [[ "$FORCE" -ne 1 ]]; then exit 1; fi
  fi
elif [[ -e "$ROLE_MEMORY_LINK" ]]; then
  if [[ "$FORCE" -ne 1 ]]; then
    echo "Error: $ROLE_MEMORY_LINK exists as a real directory with content." >&2
    echo "Re-run with --force to back it up to memory.backup-YYYYMMDD/ and replace with symlink." >&2
    exit 1
  fi
fi

# Cleanup trap for partial git worktree creation
WORKTREE_CREATED=""
cleanup_on_error() {
  if [[ -n "$WORKTREE_CREATED" && -d "$WORKTREE_CREATED" ]]; then
    echo "Cleaning up partial worktree at $WORKTREE_CREATED..." >&2
    git worktree remove --force "$WORKTREE_CREATED" 2>/dev/null || true
    git branch -D "$BRANCH_NAME" 2>/dev/null || true
  fi
}
trap cleanup_on_error ERR

# --- Create the git worktree ---
git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME"
WORKTREE_CREATED="$WORKTREE_PATH"
WORKTREE_ABS="$( cd "$WORKTREE_PATH" && pwd -P )"

# Re-verify role hash matches what we computed (in case of normalization differences)
ACTUAL_ROLE_HASH="$(compute_hash "$WORKTREE_ABS")"
if [[ "$ACTUAL_ROLE_HASH" != "$ROLE_HASH" ]]; then
  echo "Warning: computed hash differs from realized worktree path; using realized hash." >&2
  ROLE_HASH="$ACTUAL_ROLE_HASH"
  ROLE_HASH_DIR="$HOME/.claude/projects/$ROLE_HASH"
  ROLE_MEMORY_LINK="$ROLE_HASH_DIR/memory"
fi

# --- Set up role-hash memory symlink ---
mkdir -p "$ROLE_HASH_DIR"

if [[ "$FORCE" -eq 1 && -e "$ROLE_MEMORY_LINK" && ! -L "$ROLE_MEMORY_LINK" ]]; then
  BACKUP_DIR="$ROLE_HASH_DIR/memory.backup-$(date +%Y%m%d-%H%M%S)"
  mv "$ROLE_MEMORY_LINK" "$BACKUP_DIR"
  echo "✓ Backed up existing memory dir to $BACKUP_DIR"
fi

if [[ "$FORCE" -eq 1 && -L "$ROLE_MEMORY_LINK" ]]; then
  rm "$ROLE_MEMORY_LINK"
fi

if [[ "$ROLE_LINK_PRE_EXISTS" -eq 0 ]]; then
  ln -s "$ROLE_DIR/" "$ROLE_MEMORY_LINK"
  echo "✓ Created symlink: $ROLE_MEMORY_LINK → $ROLE_DIR/"
fi

# --- First-time-only: shared symlink + content migration ---
if [[ -d "$SHARED_LINK" && ! -L "$SHARED_LINK" ]]; then
  # Real folder — migrate content to main-hash and convert to symlink
  echo "First-time setup: migrating shared/ content to $MAIN_MEMORY_DIR"
  mkdir -p "$MAIN_MEMORY_DIR"
  # Copy contents (preserving symlinks within shared, like nested files)
  if [[ -n "$(ls -A "$SHARED_LINK" 2>/dev/null)" ]]; then
    cp -R "$SHARED_LINK"/. "$MAIN_MEMORY_DIR/"
  fi
  rm -rf "$SHARED_LINK"
  ln -s "$MAIN_MEMORY_DIR/" "$SHARED_LINK"
  echo "✓ Migrated shared/ to $MAIN_MEMORY_DIR and replaced with symlink"
elif [[ ! -e "$SHARED_LINK" && ! -L "$SHARED_LINK" ]]; then
  # Doesn't exist at all — create symlink fresh
  mkdir -p "$MAIN_MEMORY_DIR"
  ln -s "$MAIN_MEMORY_DIR/" "$SHARED_LINK"
  echo "✓ Created shared symlink: $SHARED_LINK → $MAIN_MEMORY_DIR/"
fi
# If already a symlink pointing to the right place, no-op (verified in pre-flight)

# Clear ERR trap (we're in success territory now)
trap - ERR

echo ""
echo "Done. Open Claude Code in $WORKTREE_ABS — it will auto-load $ROLE/MEMORY.md from $ROLE_DIR/."
