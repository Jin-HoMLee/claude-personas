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

# --- Helpers for wiring ------------------------------------------------------

# Idempotently append a line to the clone's .git/info/exclude (per-clone
# untracked-ness that never dirties the project repo - spec decision log).
EXCLUDE_FILE="$TARGET/.git/info/exclude"
add_exclude() {
  mkdir -p "$(dirname "$EXCLUDE_FILE")"
  touch "$EXCLUDE_FILE"
  grep -qxF "$1" "$EXCLUDE_FILE" 2>/dev/null || printf '%s\n' "$1" >> "$EXCLUDE_FILE"
}

# Per-vendor failures report and continue - one vendor's problem must not
# kill the other two (spec: init-clone.sh changes, last bullet).
VENDOR_WARNINGS=0
vendor_warn() {
  echo "WARN: $*" >&2
  VENDOR_WARNINGS=$((VENDOR_WARNINGS + 1))
}

# --- Core mount (vendor-neutral, rollback-protected) --------------------------
# .agents/memory -> ../../<memory-repo>/<role>   (the single role signal)
# .claude/memory -> ../.agents/memory            (Claude Code in-repo hop)
# A failure anywhere in this window must roll back a clone we created this run.

if ! mkdir -p "$TARGET/.agents" "$TARGET/.claude"; then
  echo "Error: failed to create $TARGET/.agents or $TARGET/.claude" >&2
  rollback_fresh_clone
  exit 1
fi
AGENTS_LINK="$TARGET/.agents/memory"
MEMORY_LINK="$TARGET/.claude/memory"

# Migrate v3.0 layout: legacy root symlink -> back up under .claude/
LEGACY_LINK="$TARGET/memory"
if [[ "$FORCE" -eq 1 && ( -L "$LEGACY_LINK" || -e "$LEGACY_LINK" ) ]]; then
  LEGACY_BACKUP="$TARGET/.claude/memory.legacy-backup-$(date +%Y%m%d-%H%M%S)"
  mv "$LEGACY_LINK" "$LEGACY_BACKUP"
  echo "✓ Migrated legacy root memory/ → $LEGACY_BACKUP"
fi

# Back up whatever sits at either mount point (v3.1 direct symlink on a
# --force migration, or artifacts from a prior run).
for link in "$AGENTS_LINK" "$MEMORY_LINK"; do
  if [[ -e "$link" || -L "$link" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      BACKUP="$link.backup-$(date +%Y%m%d-%H%M%S)"
      mv "$link" "$BACKUP"
      echo "✓ Backed up existing ${link#"$TARGET"/} → ${BACKUP#"$TARGET"/}"
    else
      echo "Error: $link already exists. Use --force to back up." >&2
      rollback_fresh_clone
      exit 1
    fi
  fi
done

if ! ln -s "../../$MEMORY_REPO_NAME/$ROLE" "$AGENTS_LINK"; then
  echo "Error: failed to create memory mount $AGENTS_LINK" >&2
  rollback_fresh_clone
  exit 1
fi
echo "✓ Symlinked .agents/memory → ../../$MEMORY_REPO_NAME/$ROLE"

if ! ln -s "../.agents/memory" "$MEMORY_LINK"; then
  echo "Error: failed to create Claude Code hop $MEMORY_LINK" >&2
  rollback_fresh_clone
  exit 1
fi
echo "✓ Symlinked .claude/memory → ../.agents/memory"

# Untracked-ness via exclude, NOT .gitignore. Existing committed v3.1
# .gitignore lines keep working; we just stop adding new ones. NOTE the
# entries have no trailing slash: a trailing slash matches only real
# directories, and these paths are symlinks.
add_exclude "# claude-personas vendor wiring (per-clone, untracked)"
add_exclude "/.agents/memory"
add_exclude "/.claude/memory"

# Remove legacy /memory/ line on --force (v3.0 -> v3.1 migration) - unchanged.
GITIGNORE="$TARGET/.gitignore"
if [[ "$FORCE" -eq 1 && -f "$GITIGNORE" ]] && grep -qE '^/?memory/?$' "$GITIGNORE"; then
  grep -vE '^/?memory/?$' "$GITIGNORE" > "$GITIGNORE.tmp" || true
  mv "$GITIGNORE.tmp" "$GITIGNORE"
  echo "✓ Removed legacy /memory/ from $GITIGNORE"
fi

# Persist project URL
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$PROJECT_TXT" ]]; then
  echo "$PROJECT_URL" > "$PROJECT_TXT"
  echo "✓ Saved project URL to $PROJECT_TXT"
fi

echo ""
if [[ "$VENDOR_WARNINGS" -gt 0 ]]; then
  echo "Done with $VENDOR_WARNINGS vendor warning(s) - see WARN lines above. Core mount is wired."
  exit 2
fi
echo "Done. Open $TARGET in Claude Code → role memory loads via .claude/memory → .agents/memory."
