#!/usr/bin/env bash
# init-clone.sh — create an independent project-repo clone for a role and wire
# the .claude/memory/ symlink to the sibling claude-personas memory repo.
#
# Run from inside your memory repo (claude-personas-<app>/).

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MEMORY_REPO="$( pwd )"
PARENT_DIR="$( dirname "$MEMORY_REPO" )"
MEMORY_REPO_NAME="$( basename "$MEMORY_REPO" )"

usage() {
  cat <<EOF
Usage: $(basename "$0") <role> [--project-url <url>] [--target <path>] [--main] [--force]

  role            Role folder in the memory repo (developer, pm, designer, scientist, ...)
  --project-url   Project git URL to clone. Falls back to .claude-personas/project.txt, then prompts.
  --target        Explicit target path for the clone. Overrides suffix rules.
  --main          Force this role to claim the no-suffix path \$PARENT/<project-name>/.
  --force         Re-wire .claude/memory/ in an existing clean clone (must be same project URL).

Run from inside your memory repo (claude-personas-<app>/).
EOF
}

# Parse args
ROLE=""
PROJECT_URL=""
TARGET=""
MAIN=0
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project-url) PROJECT_URL="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --main) MAIN=1; shift ;;
    --force) FORCE=1; shift ;;
    -*) echo "Error: unknown flag $1" >&2; usage >&2; exit 1 ;;
    *) if [[ -z "$ROLE" ]]; then ROLE="$1"; shift; else echo "Error: unexpected arg $1" >&2; exit 1; fi ;;
  esac
done

if [[ -z "$ROLE" ]]; then usage >&2; exit 1; fi

# Validate role
ROLE_DIR="$MEMORY_REPO/$ROLE"
if [[ ! -d "$ROLE_DIR" || ! -f "$ROLE_DIR/MEMORY.md" ]]; then
  echo "Error: role '$ROLE' not found in $MEMORY_REPO/" >&2
  echo "Available roles:" >&2
  for d in "$MEMORY_REPO"/*/; do
    n="$(basename "$d")"
    if [[ -f "$d/MEMORY.md" && "$n" != "shared" && "$n" != "examples" ]]; then
      echo "  $n" >&2
    fi
  done
  exit 1
fi

# Resolve project URL
CONFIG_DIR="$MEMORY_REPO/.claude-personas"
PROJECT_TXT="$CONFIG_DIR/project.txt"
if [[ -z "$PROJECT_URL" && -f "$PROJECT_TXT" ]]; then
  PROJECT_URL="$(cat "$PROJECT_TXT")"
fi
if [[ -z "$PROJECT_URL" ]]; then
  read -r -p "Project git URL: " PROJECT_URL
fi
if [[ -z "$PROJECT_URL" ]]; then
  echo "Error: project URL is required" >&2
  exit 1
fi

# Derive project name from memory repo name (strip leading claude-personas-)
PROJECT_NAME="${MEMORY_REPO_NAME#claude-personas-}"

if [[ "$PROJECT_NAME" == "$MEMORY_REPO_NAME" ]]; then
  # Fallback: derive from project URL basename
  PROJECT_NAME="$(basename "$PROJECT_URL")"
  PROJECT_NAME="${PROJECT_NAME%.git}"
fi

# Determine no-suffix claimer
MAIN_ROLE_TXT="$CONFIG_DIR/main-role.txt"
DEFAULT_MAIN="developer"
if [[ -f "$MAIN_ROLE_TXT" ]]; then
  DEFAULT_MAIN="$(cat "$MAIN_ROLE_TXT")"
fi

CLAIMS_NO_SUFFIX=0
NO_SUFFIX_PATH="$PARENT_DIR/$PROJECT_NAME"
if [[ "$MAIN" -eq 1 ]] || [[ "$ROLE" == "$DEFAULT_MAIN" ]]; then
  if [[ ! -e "$NO_SUFFIX_PATH" ]] || [[ "$FORCE" -eq 1 ]]; then
    CLAIMS_NO_SUFFIX=1
  elif [[ "$MAIN" -eq 1 ]]; then
    # Explicit --main: fail rather than silently fall back to suffix.
    echo "Error: --main requested but '$NO_SUFFIX_PATH' already exists." >&2
    echo "Pass --force to re-wire .claude/memory/ in place, or remove/rename the existing directory." >&2
    exit 1
  fi
fi

# Resolve target
if [[ -z "$TARGET" ]]; then
  if [[ "$CLAIMS_NO_SUFFIX" -eq 1 ]]; then
    TARGET="$NO_SUFFIX_PATH"
  else
    TARGET="$PARENT_DIR/$PROJECT_NAME-$ROLE"
  fi
fi

# Validate target
if [[ -e "$TARGET" && "$FORCE" -ne 1 ]]; then
  echo "Error: target '$TARGET' already exists. Use --force or --target to override." >&2
  exit 1
fi

# Track whether THIS run created the clone — governs rollback on a later
# failure. A pre-existing clone (reused via --force) must never be deleted.
CREATED_CLONE=0

# Roll back a clone WE created this run (spec error table: "rollback by
# removing the target clone if we created it this run"). No-op for a clone
# reused via --force, since CREATED_CLONE stays 0 there. The -n/-d guards are
# defensive belt-and-suspenders on top of that invariant.
rollback_fresh_clone() {
  if [[ "$CREATED_CLONE" -eq 1 && -n "$TARGET" && -d "$TARGET" ]]; then
    rm -rf "$TARGET"
    echo "✓ Rolled back freshly-created clone at $TARGET" >&2
  fi
}

if [[ -e "$TARGET" && "$FORCE" -eq 1 ]]; then
  # Must be a clean git checkout of the same project URL
  if [[ ! -d "$TARGET/.git" ]]; then
    echo "Error: '$TARGET' exists but is not a git repo. Refusing --force." >&2
    exit 1
  fi
  EXISTING_URL="$( cd "$TARGET" && git config --get remote.origin.url 2>/dev/null || echo "" )"
  if [[ "$EXISTING_URL" != "$PROJECT_URL" ]]; then
    echo "Error: '$TARGET' is a clone of '$EXISTING_URL', not '$PROJECT_URL'. Refusing --force." >&2
    exit 1
  fi
  echo "✓ --force: existing clone at '$TARGET' matches project URL; will only re-wire .claude/memory/"
else
  # Clone fresh
  echo "Cloning $PROJECT_URL → $TARGET"
  git clone "$PROJECT_URL" "$TARGET"
  CREATED_CLONE=1
fi

# Wire memory symlink under .claude/. On --force, also clean up any legacy
# root-level memory/ symlink and stale /memory/ .gitignore line from v3.0.
# A failure anywhere in this post-clone wiring window must roll back a clone
# we created this run — not only an ln -s failure.
if ! mkdir -p "$TARGET/.claude"; then
  echo "Error: failed to create $TARGET/.claude" >&2
  rollback_fresh_clone
  exit 1
fi
MEMORY_LINK="$TARGET/.claude/memory"

# Migrate v3.0 layout: legacy root symlink → back up under .claude/
LEGACY_LINK="$TARGET/memory"
if [[ "$FORCE" -eq 1 && ( -L "$LEGACY_LINK" || -e "$LEGACY_LINK" ) ]]; then
  LEGACY_BACKUP="$TARGET/.claude/memory.legacy-backup-$(date +%Y%m%d-%H%M%S)"
  mv "$LEGACY_LINK" "$LEGACY_BACKUP"
  echo "✓ Migrated legacy root memory/ → $LEGACY_BACKUP"
fi

if [[ -e "$MEMORY_LINK" || -L "$MEMORY_LINK" ]]; then
  if [[ "$FORCE" -eq 1 ]]; then
    BACKUP="$TARGET/.claude/memory.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$MEMORY_LINK" "$BACKUP"
    echo "✓ Backed up existing .claude/memory → $BACKUP"
  else
    echo "Error: $MEMORY_LINK already exists. Use --force to back up." >&2
    # Reachable only on a fresh clone (FORCE=0 + existing target exits earlier),
    # so this leaves an unwired clone too — roll it back. --force re-run re-clones.
    rollback_fresh_clone
    exit 1
  fi
fi

if ! ln -s "../../$MEMORY_REPO_NAME/$ROLE" "$MEMORY_LINK"; then
  echo "Error: failed to create memory symlink $MEMORY_LINK" >&2
  rollback_fresh_clone
  exit 1
fi
echo "✓ Symlinked $MEMORY_LINK → ../../$MEMORY_REPO_NAME/$ROLE"

# Update .gitignore: add /.claude/memory/, remove legacy /memory/ if present
GITIGNORE="$TARGET/.gitignore"
touch "$GITIGNORE"

# Remove legacy /memory/ line on --force (v3.0 → v3.1 migration)
if [[ "$FORCE" -eq 1 ]] && grep -qE '^/?memory/?$' "$GITIGNORE"; then
  # Portable in-place edit: write to temp, swap. grep -v exits 1 when output
  # is empty (e.g. .gitignore was only the legacy line); || true keeps us
  # going so the mv still runs and replaces the file with empty content.
  grep -vE '^/?memory/?$' "$GITIGNORE" > "$GITIGNORE.tmp" || true
  mv "$GITIGNORE.tmp" "$GITIGNORE"
  echo "✓ Removed legacy /memory/ from $GITIGNORE"
fi

if ! grep -qE '^/?\.claude/memory/?$' "$GITIGNORE"; then
  printf "\n# claude-personas role-memory symlink\n/.claude/memory/\n" >> "$GITIGNORE"
  echo "✓ Added /.claude/memory/ to $GITIGNORE"
fi

# Persist project URL
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$PROJECT_TXT" ]]; then
  echo "$PROJECT_URL" > "$PROJECT_TXT"
  echo "✓ Saved project URL to $PROJECT_TXT"
fi

echo ""
echo "Done. Open $TARGET in Claude Code → .claude/memory/MEMORY.md auto-loads."
