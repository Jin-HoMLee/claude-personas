# claude-personas v3 — Clones Pivot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace v2's worktree+autoMemoryDirectory mechanism with independent-clone-per-role + `memory/` symlink wiring. Hard release, MIGRATION.md walkthrough, no parallel v2 docs.

**Architecture:** Each role gets a real independent clone of the project repo at a sibling path. A single `memory/` symlink inside each project clone points into the sibling memory repo (`claude-personas-<app>/`), which holds role-split memory dirs + a shared layer reached via `<role>/shared -> ../shared` symlinks.

**Tech Stack:** Bash 4+, `git`, POSIX `ln -s`, no language runtime dependency beyond what v2 already used (`python3` for path normalization).

**Spec:** [`docs/superpowers/specs/2026-05-15-v3-clones-pivot-design.md`](../specs/2026-05-15-v3-clones-pivot-design.md)

---

## File map

**Files to create:**

- `scripts/init-clone.sh` (replaces init-worktree.sh)
- `scripts/tests/test_init_clone.sh`
- `scientist/MEMORY.md`
- `scientist/shared` (symlink → `../shared`)
- `examples/scientist/` (3 ported patterns from splice scientist memory)
- `MIGRATION.md` at repo root

**Files to rewrite (same path):**

- `scripts/list-roles.sh` (new content for v3 layout)
- `scripts/tests/test_list_roles.sh` (new content)
- `pm/MEMORY.md` / `developer/MEMORY.md` / `designer/MEMORY.md` (v2 → v3 boilerplate)
- `README.md` (v3 architecture + quick start + FAQ)
- `CONVENTIONS.md` (drop v2 mechanism, describe v3)

**Files to extend:**

- `scripts/tests/test_helpers.sh` (clone-based fixture helpers)
- `CHANGELOG.md` (v3.0.0 entry)
- `.gitignore` (add `.claude-personas/project.txt`)

**Files to delete (preserved in `v2-final` tag):**

- `scripts/init-worktree.sh`
- `scripts/tests/test_init_worktree.sh`

---

## Task 1: Branch setup + v2 archival tag

**Files:**

- Tag: `v2-final` (annotated, points at current `main`)
- Branch: `v3-dev` (new, off `main`)

- [ ] **Step 1: Confirm working tree clean and on main**

Run: `cd ~/dev/GitHub/Jin-HoMLee/claude-personas && git status && git rev-parse --abbrev-ref HEAD`

Expected: `nothing to commit, working tree clean` and `main`.

- [ ] **Step 2: Create the annotated v2-final tag on main**

```bash
git tag -a v2-final -m "v2.0.1 archival tag — last release before v3 clones-pivot.

Pinned for users on Claude Code <v2.1.49 who want the worktree+autoMemoryDirectory mechanism."
```

- [ ] **Step 3: Push tag**

Run: `git push origin v2-final`

Expected: `* [new tag] v2-final -> v2-final`.

- [ ] **Step 4: Create v3-dev branch and switch**

```bash
git checkout -b v3-dev
git push -u origin v3-dev
```

Expected: branch tracked at `origin/v3-dev`.

---

## Task 2: Scientist role skeleton + examples

**Files:**

- Create: `scientist/MEMORY.md`
- Create: `scientist/shared` (symlink)
- Create: `examples/scientist/feedback_manuscript_edits.md`
- Create: `examples/scientist/feedback_zotero_note_format.md`
- Create: `examples/scientist/feedback_american_spelling.md`

- [ ] **Step 1: Create scientist/ directory and MEMORY.md**

```bash
mkdir -p scientist
```

Create `scientist/MEMORY.md` with content:

```markdown
# Memory Index — Scientist

<!--
  Usage: this folder is loaded by Claude Code via the `memory/` symlink in your
  Scientist project clone. The symlink is created by scripts/init-clone.sh.
  See CONVENTIONS.md for the full v3 mechanism.
-->

## Always in effect (no file read required)

<!-- Add inline rules here. Use drift annotations: <!-- src: ... --> -->

## Shared (all sessions)

- [Shared memory index](shared/MEMORY.md) — All cross-role conventions

## Role: Scientist

<!-- Add links to role-specific memory files. Example:
- [Manuscript editing workflow](feedback_manuscript_edits.md) — section-by-section with todo list
-->
```

- [ ] **Step 2: Create the shared symlink inside scientist/**

```bash
cd scientist && ln -s ../shared shared && cd ..
```

- [ ] **Step 3: Verify symlink resolves**

Run: `ls -la scientist/shared && readlink scientist/shared`

Expected: `scientist/shared` is a symlink, `readlink` outputs `../shared`.

- [ ] **Step 4: Create examples/scientist/ directory and port 3 patterns**

```bash
mkdir -p examples/scientist
```

Create `examples/scientist/feedback_manuscript_edits.md` with content:

```markdown
# Manuscript editing workflow

**Rule:** When editing a manuscript section, work section-by-section using TodoWrite. Explain each change before making it. Never silently delete.

**Why:** Manuscripts are high-stakes prose; silent rewrites lose the author's reasoning and trigger trust issues. Section-by-section keeps each edit reviewable.

**How to apply:** Open the section. Add a TodoWrite item per edit. For each: state the change, the reason, the before/after. Edit. Move to next.

Carry over from splice (Scientist role, 2026-05-07).
```

Create `examples/scientist/feedback_zotero_note_format.md` with content:

```markdown
# Zotero note format (HTML, 3 sections)

**Rule:** Notes attached to Zotero items follow a fixed structure: **Findings / Methods / vs. our pipeline**. Bold-keyword leads. Telegraphic bullets, ~8 words each, ~18-word cap. 2–3 bullets per section. Push HTML directly to Zotero (no markdown preview).

**Why:** Consistent shape makes notes scannable across hundreds of items. Bold leads serve as ad-hoc tags.

**How to apply:** Use `python research/scripts/zotero_add.py <DOI> --note "..."` with the HTML body. The 3 sections are non-negotiable; "vs. our pipeline" forces explicit relevance framing.

Carry over from splice (Scientist role, 2026-05-08).
```

Create `examples/scientist/feedback_american_spelling.md` with content:

```markdown
# American spelling in manuscripts

**Rule:** Use American forms (`tumor`, `personalized`, `recognize`, `intratumoral`) in all new manuscript prose.

**Why:** Target venues use American spelling; consistency matters for blind review.

**How to apply:** When editing manuscript files (`.tex`, `.md`, etc.) check spelling on every change. British forms (`tumour`, `personalised`) get rewritten on the spot.

Established splice 2026-05-07.
```

- [ ] **Step 5: Commit**

```bash
git add scientist/ examples/scientist/
git commit -m "feat: add scientist role skeleton + 3 ported examples

Adds the fourth default role for v3. Examples ported from splice's
scientist memory: manuscript workflow, Zotero note format, American
spelling convention."
```

---

## Task 3: Test scaffolding for clone-based fixtures

**Files:**

- Modify: `scripts/tests/test_helpers.sh` (append clone-fixture helpers)

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test_clone_fixture.sh`:

```bash
#!/usr/bin/env bash
# Test that make_clone_test_fixture creates a valid memory repo + bare project repo.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

echo "=== test_clone_fixture ==="

tmp="$(mktemp -d)"
make_clone_test_fixture "$tmp"

assert_exists "$tmp/memory-repo" "memory repo created"
assert_exists "$tmp/memory-repo/developer/MEMORY.md" "developer role exists"
assert_exists "$tmp/memory-repo/pm/MEMORY.md" "pm role exists"
assert_exists "$tmp/memory-repo/scientist/MEMORY.md" "scientist role exists"
assert_exists "$tmp/memory-repo/shared/MEMORY.md" "shared/MEMORY.md exists"
assert_symlink "$tmp/memory-repo/pm/shared" "../shared" "pm/shared symlink"
assert_exists "$tmp/project-repo.git/HEAD" "bare project repo exists"

cleanup_clone_test_fixture "$tmp"
assert_not_exists "$tmp" "fixture removed after cleanup"

print_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test_clone_fixture.sh`

Expected: FAIL with `make_clone_test_fixture: command not found` (or similar bash error).

- [ ] **Step 3: Implement helpers**

Append to `scripts/tests/test_helpers.sh`:

```bash

# --- v3 clone-test fixtures ---

# Create a fake memory repo + bare project repo for clone-based tests.
# Layout produced at $1:
#   $1/memory-repo/                  (working clone-personas-style repo)
#     .git/                          (real git repo with one commit)
#     developer/MEMORY.md
#     pm/MEMORY.md
#     scientist/MEMORY.md
#     shared/MEMORY.md
#     <role>/shared -> ../shared      (symlink in each role)
#   $1/project-repo.git/             (bare repo to clone from)
make_clone_test_fixture() {
  local base="$1"
  mkdir -p "$base"

  # Bare project repo to clone from
  git init --bare --quiet "$base/project-repo.git"
  # Seed the bare repo with one commit
  local seed; seed="$(mktemp -d)"
  ( cd "$seed" && git init --quiet && \
    echo "# project" > README.md && \
    git add README.md && \
    git -c user.email=test@x -c user.name=Test commit --quiet -m "init" && \
    git remote add origin "$base/project-repo.git" && \
    git push --quiet origin master 2>/dev/null || git push --quiet origin main 2>/dev/null )
  rm -rf "$seed"

  # Memory repo
  mkdir -p "$base/memory-repo"
  ( cd "$base/memory-repo" && git init --quiet )
  for role in developer pm scientist designer; do
    mkdir -p "$base/memory-repo/$role"
    printf "# Memory Index — %s\n" "$role" > "$base/memory-repo/$role/MEMORY.md"
    ( cd "$base/memory-repo/$role" && ln -s ../shared shared )
  done
  mkdir -p "$base/memory-repo/shared"
  printf "# Shared Memory Index\n" > "$base/memory-repo/shared/MEMORY.md"
  ( cd "$base/memory-repo" && \
    git -c user.email=test@x -c user.name=Test add . && \
    git -c user.email=test@x -c user.name=Test commit --quiet -m "init memory repo" )
}

# Remove the fixture directory created by make_clone_test_fixture.
cleanup_clone_test_fixture() {
  local base="$1"
  rm -rf "$base"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test_clone_fixture.sh`

Expected: all 7 PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/test_helpers.sh scripts/tests/test_clone_fixture.sh
git commit -m "test: add clone-based fixture helpers for v3 test suite

make_clone_test_fixture creates a bare project repo + memory repo with
role dirs and shared symlinks. cleanup_clone_test_fixture removes it.
Used by upcoming init-clone.sh and list-roles.sh tests."
```

---

## Task 4: init-clone.sh — happy path (developer claims no-suffix)

**Files:**

- Create: `scripts/init-clone.sh`
- Create: `scripts/tests/test_init_clone.sh`

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test_init_clone.sh`:

```bash
#!/usr/bin/env bash
# Test init-clone.sh happy path for developer (claims no-suffix slot).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
INIT_CLONE="$(cd "$SCRIPT_DIR/.." && pwd)/init-clone.sh"

echo "=== test_init_clone happy path (developer = no-suffix) ==="

tmp="$(mktemp -d)"
make_clone_test_fixture "$tmp"

# Rename memory-repo to claude-personas-myapp to match real naming
mv "$tmp/memory-repo" "$tmp/claude-personas-myapp"

# Run init-clone.sh developer with --project-url
( cd "$tmp/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --project-url "$tmp/project-repo.git" )

assert_exists "$tmp/myapp" "developer clone landed at no-suffix path"
assert_exists "$tmp/myapp/.git" "developer clone is a real git repo"
assert_symlink "$tmp/myapp/memory" "../claude-personas-myapp/developer" "memory symlink points to developer/"
assert_exists "$tmp/myapp/memory/MEMORY.md" "MEMORY.md resolves through symlink"

# memory/ added to .gitignore
if grep -q "^memory/$\|^memory$\|^/memory$\|^/memory/$" "$tmp/myapp/.gitignore" 2>/dev/null; then
  echo "  PASS: memory/ in .gitignore"
else
  echo "  FAIL: memory/ not in .gitignore (or .gitignore missing)"
  exit 1
fi

# project.txt persisted
assert_exists "$tmp/claude-personas-myapp/.claude-personas/project.txt" "project.txt persisted"
if grep -q "$tmp/project-repo.git" "$tmp/claude-personas-myapp/.claude-personas/project.txt"; then
  echo "  PASS: project.txt contains URL"
else
  echo "  FAIL: project.txt missing URL"
  exit 1
fi

cleanup_clone_test_fixture "$tmp"
print_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test_init_clone.sh`

Expected: FAIL — `init-clone.sh` doesn't exist yet.

- [ ] **Step 3: Implement init-clone.sh minimum viable**

Create `scripts/init-clone.sh`:

```bash
#!/usr/bin/env bash
# init-clone.sh — create an independent project-repo clone for a role and wire
# the memory/ symlink to the sibling claude-personas memory repo.
#
# Run from inside your memory repo (claude-personas-<app>/).

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MEMORY_REPO="$( dirname "$SCRIPT_DIR" )"
PARENT_DIR="$( dirname "$MEMORY_REPO" )"
MEMORY_REPO_NAME="$( basename "$MEMORY_REPO" )"

usage() {
  cat <<EOF
Usage: $(basename "$0") <role> [--project-url <url>] [--target <path>] [--main] [--force]

  role            Role folder in the memory repo (developer, pm, designer, scientist, ...)
  --project-url   Project git URL to clone. Falls back to .claude-personas/project.txt, then prompts.
  --target        Explicit target path for the clone. Overrides suffix rules.
  --main          Force this role to claim the no-suffix path \$PARENT/<project-name>/.
  --force         Re-wire memory/ in an existing clean clone (must be same project URL).

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

# Derive project name from URL
PROJECT_NAME="$(basename "$PROJECT_URL")"
PROJECT_NAME="${PROJECT_NAME%.git}"

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
  echo "✓ --force: existing clone at '$TARGET' matches project URL; will only re-wire memory/"
else
  # Clone fresh
  echo "Cloning $PROJECT_URL → $TARGET"
  git clone "$PROJECT_URL" "$TARGET"
fi

# Wire memory symlink (back up existing first if --force and broken)
MEMORY_LINK="$TARGET/memory"
if [[ -e "$MEMORY_LINK" || -L "$MEMORY_LINK" ]]; then
  if [[ "$FORCE" -eq 1 ]]; then
    BACKUP="$TARGET/memory.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$MEMORY_LINK" "$BACKUP"
    echo "✓ Backed up existing memory/ to $BACKUP"
  else
    echo "Error: $MEMORY_LINK already exists. Use --force to back up." >&2
    exit 1
  fi
fi

ln -s "../$MEMORY_REPO_NAME/$ROLE" "$MEMORY_LINK"
echo "✓ Symlinked $MEMORY_LINK → ../$MEMORY_REPO_NAME/$ROLE"

# Add memory/ to .gitignore idempotently
GITIGNORE="$TARGET/.gitignore"
touch "$GITIGNORE"
if ! grep -qE '^/?memory/?$' "$GITIGNORE"; then
  printf "\n# claude-personas role-memory symlink\nmemory/\n" >> "$GITIGNORE"
  echo "✓ Added memory/ to $GITIGNORE"
fi

# Persist project URL
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$PROJECT_TXT" ]]; then
  echo "$PROJECT_URL" > "$PROJECT_TXT"
  echo "✓ Saved project URL to $PROJECT_TXT"
fi

echo ""
echo "Done. Open $TARGET in Claude Code → memory/MEMORY.md auto-loads."
```

- [ ] **Step 4: Make executable**

Run: `chmod +x scripts/init-clone.sh`

- [ ] **Step 5: Run test to verify it passes**

Run: `bash scripts/tests/test_init_clone.sh`

Expected: all PASS, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/init-clone.sh scripts/tests/test_init_clone.sh
git commit -m "feat: init-clone.sh happy path — clone + memory symlink + .gitignore

Implements the v3 init script's developer-claims-no-suffix path:
clones the project repo, wires the memory/ symlink, adds memory/ to
.gitignore, persists project URL to .claude-personas/project.txt."
```

---

## Task 5: init-clone.sh — role validation + project URL precedence

**Files:**

- Modify: `scripts/tests/test_init_clone.sh` (append cases)

- [ ] **Step 1: Append failing tests for role validation**

Append to `scripts/tests/test_init_clone.sh` (before `print_summary`):

```bash

# --- Role validation ---
echo "=== test_init_clone role validation ==="
tmp2="$(mktemp -d)"
make_clone_test_fixture "$tmp2"
mv "$tmp2/memory-repo" "$tmp2/claude-personas-myapp"

# Unknown role should fail
if ( cd "$tmp2/claude-personas-myapp" && \
     bash "$INIT_CLONE" nonexistentrole --project-url "$tmp2/project-repo.git" ) 2>/dev/null; then
  echo "  FAIL: should have exited nonzero for unknown role"
  exit 1
else
  echo "  PASS: unknown role rejected"
fi

cleanup_clone_test_fixture "$tmp2"

# --- URL precedence: flag > project.txt > prompt ---
echo "=== test_init_clone URL precedence ==="
tmp3="$(mktemp -d)"
make_clone_test_fixture "$tmp3"
mv "$tmp3/memory-repo" "$tmp3/claude-personas-myapp"

# Pre-seed project.txt with a WRONG url
mkdir -p "$tmp3/claude-personas-myapp/.claude-personas"
echo "/this/does/not/exist.git" > "$tmp3/claude-personas-myapp/.claude-personas/project.txt"

# --project-url flag should override the file
( cd "$tmp3/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --project-url "$tmp3/project-repo.git" )

assert_exists "$tmp3/myapp" "flag overrode project.txt; clone landed"

# project.txt should NOT be overwritten by the flag (only created if missing)
saved_url="$(cat "$tmp3/claude-personas-myapp/.claude-personas/project.txt")"
assert_equal "/this/does/not/exist.git" "$saved_url" "project.txt preserved (not overwritten by flag)"

cleanup_clone_test_fixture "$tmp3"

# --- URL from project.txt when no flag ---
echo "=== test_init_clone URL from project.txt ==="
tmp4="$(mktemp -d)"
make_clone_test_fixture "$tmp4"
mv "$tmp4/memory-repo" "$tmp4/claude-personas-myapp"

mkdir -p "$tmp4/claude-personas-myapp/.claude-personas"
echo "$tmp4/project-repo.git" > "$tmp4/claude-personas-myapp/.claude-personas/project.txt"

( cd "$tmp4/claude-personas-myapp" && bash "$INIT_CLONE" pm )

assert_exists "$tmp4/myapp-pm" "URL read from project.txt; pm clone landed (suffixed)"

cleanup_clone_test_fixture "$tmp4"
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash scripts/tests/test_init_clone.sh`

Expected: all PASS (the cases work with the Task 4 implementation; this task is verification, not new code).

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_init_clone.sh
git commit -m "test: cover role validation + project URL precedence

Adds 3 cases: unknown role rejection, --project-url flag overrides
project.txt without overwriting it, project.txt is read when no flag
is passed."
```

---

## Task 6: init-clone.sh — main-role slot override

**Files:**

- Modify: `scripts/tests/test_init_clone.sh` (append cases)
- No code change expected (Task 4 already handles `--main` and `main-role.txt`)

- [ ] **Step 1: Append failing tests**

Append to `scripts/tests/test_init_clone.sh` (before `print_summary`):

```bash

# --- --main flag claims no-suffix slot for non-default role ---
echo "=== test_init_clone --main flag ==="
tmp5="$(mktemp -d)"
make_clone_test_fixture "$tmp5"
mv "$tmp5/memory-repo" "$tmp5/claude-personas-myapp"

( cd "$tmp5/claude-personas-myapp" && \
  bash "$INIT_CLONE" pm --main --project-url "$tmp5/project-repo.git" )

assert_exists "$tmp5/myapp" "pm with --main landed at no-suffix path"
assert_symlink "$tmp5/myapp/memory" "../claude-personas-myapp/pm" "memory points to pm/"

cleanup_clone_test_fixture "$tmp5"

# --- main-role.txt overrides default 'developer' ---
echo "=== test_init_clone main-role.txt override ==="
tmp6="$(mktemp -d)"
make_clone_test_fixture "$tmp6"
mv "$tmp6/memory-repo" "$tmp6/claude-personas-myapp"

mkdir -p "$tmp6/claude-personas-myapp/.claude-personas"
echo "scientist" > "$tmp6/claude-personas-myapp/.claude-personas/main-role.txt"

( cd "$tmp6/claude-personas-myapp" && \
  bash "$INIT_CLONE" scientist --project-url "$tmp6/project-repo.git" )

assert_exists "$tmp6/myapp" "scientist landed at no-suffix path (main-role.txt)"
assert_symlink "$tmp6/myapp/memory" "../claude-personas-myapp/scientist" "memory points to scientist/"

# Now running developer should NOT claim no-suffix (already taken)
( cd "$tmp6/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --project-url "$tmp6/project-repo.git" )

assert_exists "$tmp6/myapp-developer" "developer fell back to suffixed path"

cleanup_clone_test_fixture "$tmp6"
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash scripts/tests/test_init_clone.sh`

Expected: all PASS.

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_init_clone.sh
git commit -m "test: cover --main flag + main-role.txt override

Verifies that --main lets any role claim the no-suffix slot, that
main-role.txt overrides the default 'developer' claimer, and that
fallback-to-suffix kicks in when the no-suffix path is taken."
```

---

## Task 7: init-clone.sh — --force + edge cases

**Files:**

- Modify: `scripts/tests/test_init_clone.sh` (append cases)
- Modify: `scripts/init-clone.sh` if any case fails

- [ ] **Step 1: Append failing tests**

Append to `scripts/tests/test_init_clone.sh` (before `print_summary`):

```bash

# --- --force on existing same-project clone rewires memory only ---
echo "=== test_init_clone --force on same-project clone ==="
tmp7="$(mktemp -d)"
make_clone_test_fixture "$tmp7"
mv "$tmp7/memory-repo" "$tmp7/claude-personas-myapp"

# First init creates the clone
( cd "$tmp7/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --project-url "$tmp7/project-repo.git" )

# Break the memory symlink
rm "$tmp7/myapp/memory"
ln -s /nonexistent "$tmp7/myapp/memory"

# --force should detect, back up, re-wire
( cd "$tmp7/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --force --project-url "$tmp7/project-repo.git" )

assert_symlink "$tmp7/myapp/memory" "../claude-personas-myapp/developer" "memory re-wired"
backup_count="$(find "$tmp7/myapp" -maxdepth 1 -name "memory.backup-*" | wc -l | tr -d ' ')"
assert_equal "1" "$backup_count" "exactly one backup created"

cleanup_clone_test_fixture "$tmp7"

# --- --force on wrong-project clone should fail ---
echo "=== test_init_clone --force on wrong-project clone ==="
tmp8="$(mktemp -d)"
make_clone_test_fixture "$tmp8"
mv "$tmp8/memory-repo" "$tmp8/claude-personas-myapp"

# Create a clone of a DIFFERENT project at the target path
git init --bare --quiet "$tmp8/other-project.git"
( cd "$(mktemp -d)" && git init --quiet && \
  echo "x" > a && \
  git add a && \
  git -c user.email=t@x -c user.name=T commit --quiet -m i && \
  git remote add origin "$tmp8/other-project.git" && \
  git push --quiet origin master 2>/dev/null || git push --quiet origin main 2>/dev/null )
git clone --quiet "$tmp8/other-project.git" "$tmp8/myapp"

# --force should refuse
if ( cd "$tmp8/claude-personas-myapp" && \
     bash "$INIT_CLONE" developer --force --project-url "$tmp8/project-repo.git" ) 2>/dev/null; then
  echo "  FAIL: should have refused --force on wrong-project clone"
  exit 1
else
  echo "  PASS: --force refused wrong-project clone"
fi

cleanup_clone_test_fixture "$tmp8"

# --- target collision without --force fails ---
echo "=== test_init_clone target collision no --force ==="
tmp9="$(mktemp -d)"
make_clone_test_fixture "$tmp9"
mv "$tmp9/memory-repo" "$tmp9/claude-personas-myapp"

mkdir "$tmp9/myapp"  # block the no-suffix path

if ( cd "$tmp9/claude-personas-myapp" && \
     bash "$INIT_CLONE" developer --project-url "$tmp9/project-repo.git" ) 2>/dev/null; then
  # Should have fallen through to suffixed path since no-suffix is taken
  assert_exists "$tmp9/myapp-developer" "developer fell through to suffix when no-suffix taken"
else
  echo "  FAIL: should have succeeded with suffix fallback"
  exit 1
fi

cleanup_clone_test_fixture "$tmp9"

# --- .gitignore idempotency: running init twice doesn't double-add ---
echo "=== test_init_clone .gitignore idempotency ==="
tmp10="$(mktemp -d)"
make_clone_test_fixture "$tmp10"
mv "$tmp10/memory-repo" "$tmp10/claude-personas-myapp"

( cd "$tmp10/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --project-url "$tmp10/project-repo.git" )

count1="$(grep -cE '^/?memory/?$' "$tmp10/myapp/.gitignore" || true)"

# Re-run with --force
( cd "$tmp10/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --force --project-url "$tmp10/project-repo.git" )

count2="$(grep -cE '^/?memory/?$' "$tmp10/myapp/.gitignore" || true)"
assert_equal "$count1" "$count2" "memory/ line count unchanged after --force re-run"
assert_equal "1" "$count2" "exactly one memory/ line in .gitignore"

cleanup_clone_test_fixture "$tmp10"
```

- [ ] **Step 2: Run test to verify behavior**

Run: `bash scripts/tests/test_init_clone.sh`

Expected: all PASS. If any fails, adjust `scripts/init-clone.sh` (the most likely needed fix is the wrong-project-URL check in --force; that's already in the Task 4 implementation).

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_init_clone.sh scripts/init-clone.sh
git commit -m "test: cover --force edge cases and .gitignore idempotency

Verifies --force backs up broken symlinks, refuses wrong-project clones,
falls through to suffixed path when no-suffix is taken, and that
memory/ stays singly-listed in .gitignore across re-runs."
```

---

## Task 8: Rewrite list-roles.sh for v3 layout

**Files:**

- Rewrite: `scripts/list-roles.sh`
- Rewrite: `scripts/tests/test_list_roles.sh`

- [ ] **Step 1: Write the failing test**

Replace `scripts/tests/test_list_roles.sh` contents with:

```bash
#!/usr/bin/env bash
# Test list-roles.sh against a v3 clones-pivot layout.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
LIST_ROLES="$(cd "$SCRIPT_DIR/.." && pwd)/list-roles.sh"
INIT_CLONE="$(cd "$SCRIPT_DIR/.." && pwd)/init-clone.sh"

echo "=== test_list_roles v3 layout ==="

tmp="$(mktemp -d)"
make_clone_test_fixture "$tmp"
mv "$tmp/memory-repo" "$tmp/claude-personas-myapp"

# Wire 2 roles
( cd "$tmp/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --project-url "$tmp/project-repo.git" )
( cd "$tmp/claude-personas-myapp" && \
  bash "$INIT_CLONE" pm --project-url "$tmp/project-repo.git" )

# Break the pm memory symlink (simulate drift)
rm "$tmp/myapp-pm/memory"
ln -s /nonexistent "$tmp/myapp-pm/memory"

# Run list-roles.sh
output="$( cd "$tmp/claude-personas-myapp" && bash "$LIST_ROLES" 2>&1 || true )"

# Should mention developer clone as healthy
if echo "$output" | grep -q "developer.*OK"; then
  echo "  PASS: developer reported OK"
else
  echo "  FAIL: developer not reported OK"
  echo "$output"
  exit 1
fi

# Should mention pm as broken
if echo "$output" | grep -qiE "pm.*broken|broken.*pm"; then
  echo "  PASS: pm reported BROKEN"
else
  echo "  FAIL: pm not reported broken"
  echo "$output"
  exit 1
fi

# Should mention scientist as missing
if echo "$output" | grep -qiE "scientist.*missing|missing.*scientist|no clone"; then
  echo "  PASS: scientist reported missing"
else
  echo "  FAIL: scientist not reported missing"
  echo "$output"
  exit 1
fi

cleanup_clone_test_fixture "$tmp"
print_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test_list_roles.sh`

Expected: FAIL — current list-roles.sh scans `~/.claude/projects/` (v2 mechanism), not sibling clones.

- [ ] **Step 3: Rewrite list-roles.sh**

Replace `scripts/list-roles.sh` contents with:

```bash
#!/usr/bin/env bash
# list-roles.sh — audit v3 role clones in this memory repo's parent dir.
#
# Walks $PARENT/<project>* sibling directories, reports for each:
#   role (from memory/ symlink target), symlink status, git status.
#
# Run from inside your memory repo (claude-personas-<app>/).

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
MEMORY_REPO="$( dirname "$SCRIPT_DIR" )"
PARENT_DIR="$( dirname "$MEMORY_REPO" )"
MEMORY_REPO_NAME="$( basename "$MEMORY_REPO" )"

# Derive project name from memory repo name (strip leading claude-personas-)
PROJECT_NAME="${MEMORY_REPO_NAME#claude-personas-}"

if [[ "$PROJECT_NAME" == "$MEMORY_REPO_NAME" ]]; then
  echo "Error: memory repo name '$MEMORY_REPO_NAME' doesn't start with 'claude-personas-'." >&2
  echo "Cannot derive project name." >&2
  exit 1
fi

# Discover available roles in memory repo
ROLES=()
for d in "$MEMORY_REPO"/*/; do
  n="$(basename "$d")"
  if [[ -f "$d/MEMORY.md" && "$n" != "shared" && "$n" != "examples" ]]; then
    ROLES+=("$n")
  fi
done

printf "%-12s  %-40s  %-25s  %s\n" "Role" "Clone path" "Memory symlink" "Git status"
printf "%-12s  %-40s  %-25s  %s\n" "----" "----------" "---------------" "----------"

healthy=0
broken=0
missing=0

for role in "${ROLES[@]}"; do
  # Two candidate paths: no-suffix and suffix
  candidates=("$PARENT_DIR/$PROJECT_NAME" "$PARENT_DIR/$PROJECT_NAME-$role")
  found_clone=""
  for cand in "${candidates[@]}"; do
    if [[ -d "$cand/.git" && -L "$cand/memory" ]]; then
      target="$(readlink "$cand/memory")"
      # Match if symlink target ends with /<role>
      if [[ "$target" == *"/$role" || "$target" == "$role" ]]; then
        found_clone="$cand"
        break
      fi
    fi
  done

  if [[ -z "$found_clone" ]]; then
    printf "%-12s  %-40s  %-25s  %s\n" "$role" "<missing>" "—" "—"
    missing=$((missing + 1))
    continue
  fi

  # Inspect symlink health
  link_target="$(readlink "$found_clone/memory")"
  resolved="$found_clone/memory/MEMORY.md"
  if [[ -f "$resolved" ]]; then
    sym_status="OK → $role/"
    healthy=$((healthy + 1))
  else
    sym_status="BROKEN"
    broken=$((broken + 1))
  fi

  # git status
  if ! ( cd "$found_clone" && git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null ); then
    git_status="dirty"
  else
    git_status="clean"
  fi

  # Relative path to clone
  rel="${found_clone#$PARENT_DIR/}"
  printf "%-12s  %-40s  %-25s  %s\n" "$role" "$rel/" "$sym_status" "$git_status"
done

echo ""
echo "Summary: $healthy healthy, $broken broken, $missing missing"
[[ "$broken" -eq 0 ]] || exit 1
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test_list_roles.sh`

Expected: all PASS, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/list-roles.sh scripts/tests/test_list_roles.sh
git commit -m "feat: rewrite list-roles.sh for v3 sibling-clones layout

Walks PARENT/<project>* siblings instead of ~/.claude/projects/<hash>.
Reports per-role status: clone path, memory symlink health, git
dirty/clean state. Detects healthy, broken, and missing clones."
```

---

## Task 9: Update role MEMORY.md boilerplate for v3

**Files:**

- Rewrite: `developer/MEMORY.md`
- Rewrite: `pm/MEMORY.md`
- Rewrite: `designer/MEMORY.md`
- Rewrite: `scientist/MEMORY.md`

- [ ] **Step 1: Rewrite developer/MEMORY.md**

Replace contents with:

```markdown
# Memory Index — Developer

<!--
  Usage: this folder is loaded by Claude Code via the `memory/` symlink in your
  Developer project clone. The symlink is created by scripts/init-clone.sh.
  See CONVENTIONS.md for the v3 mechanism.
-->

## Always in effect (no file read required)

<!-- Add inline rules here. Use drift annotations: <!-- src: ... --> -->

## Shared (all sessions)

- [Shared memory index](shared/MEMORY.md) — All cross-role conventions

## Role: Developer

<!-- Add links to role-specific memory files. Example:
- [Test before PR](feedback_test_before_pr.md) — always run tests before opening a PR
-->
```

- [ ] **Step 2: Rewrite pm/MEMORY.md**

Replace contents with:

```markdown
# Memory Index — PM

<!--
  Usage: this folder is loaded by Claude Code via the `memory/` symlink in your
  PM project clone. The symlink is created by scripts/init-clone.sh.
  See CONVENTIONS.md for the v3 mechanism.
-->

## Always in effect (no file read required)

<!-- Add inline rules here. Use drift annotations: <!-- src: ... --> -->

## Shared (all sessions)

- [Shared memory index](shared/MEMORY.md) — All cross-role conventions

## Role: PM

<!-- Add links to role-specific memory files. Example:
- [Check board first](feedback_check_board.md) — query live board at session start, not memory snapshots
-->
```

- [ ] **Step 3: Rewrite designer/MEMORY.md**

Replace contents with:

```markdown
# Memory Index — Designer

<!--
  Usage: this folder is loaded by Claude Code via the `memory/` symlink in your
  Designer project clone. The symlink is created by scripts/init-clone.sh.
  See CONVENTIONS.md for the v3 mechanism.
-->

## Always in effect (no file read required)

<!-- Add inline rules here. Use drift annotations: <!-- src: ... --> -->

## Shared (all sessions)

- [Shared memory index](shared/MEMORY.md) — All cross-role conventions

## Role: Designer

<!-- Add links to role-specific memory files. Example:
- [Design system](feedback_design_system.md) — token and component naming conventions
-->
```

- [ ] **Step 4: Verify scientist/MEMORY.md from Task 2 still matches the v3 boilerplate pattern**

Run: `head -10 scientist/MEMORY.md`

Expected: contains "loaded by Claude Code via the `memory/` symlink" — the Task 2 content already matches. No change needed.

- [ ] **Step 5: Commit**

```bash
git add developer/MEMORY.md pm/MEMORY.md designer/MEMORY.md
git commit -m "docs: update role MEMORY.md boilerplate for v3 mechanism

Drops references to v2's hash-derived paths and init-worktree.sh.
Replaces with v3's memory/ symlink wired by init-clone.sh."
```

---

## Task 10: Write MIGRATION.md

**Files:**

- Create: `MIGRATION.md` (repo root)

- [ ] **Step 1: Create MIGRATION.md**

Create `MIGRATION.md` with content:

```markdown
# Migrating from claude-personas v2 to v3

v3 replaces v2's git worktrees + hash-symlinks mechanism with independent project-repo clones + a single `memory/` symlink per clone.

**Why migrate?** v2 silently broke under Claude Code v2.1.49+ (Feb 2026), which collapses all worktrees of one repo into a single auto-memory hash dir. v2 symlinks at per-worktree hash paths never load.

**Estimated time:** ~10 minutes per project.

## Prerequisites

- Your memory repo (`claude-personas-<app>`) is pushed and clean.
- You're on Claude Code v2.1.49 or newer (older users can pin to the `v2-final` git tag).

## Steps

### 1. Push and verify memory repo

```bash
cd ~/path/to/claude-personas-<app>
git status                          # should be clean
git push origin main                # ensure remote is up-to-date
```

### 2. Tear down v2 worktrees

For each v2 worktree (one per role), find it via:

```bash
cd ~/path/to/<project>              # your main project repo
git worktree list
```

Remove each:

```bash
git worktree remove ../<project>-pm
git worktree remove ../<project>-designer
# ...etc per role
```

### 3. Delete v2 hash-symlinks

v2 created symlinks at `~/.claude/projects/<hash>/memory/`. Find and remove the ones from your worktree paths:

```bash
ls -la ~/.claude/projects/ | grep memory
```

For each broken or worktree-specific entry, delete the `memory` symlink:

```bash
rm ~/.claude/projects/<some-hash>/memory
```

**Caution:** don't delete the hash dir itself (`<some-hash>/`) — Claude Code may have session JSONLs there. Only delete the `memory` symlink inside.

### 4. Run `init-clone.sh` for each role

```bash
cd ~/path/to/claude-personas-<app>
./scripts/init-clone.sh developer --project-url <project-repo-url>
./scripts/init-clone.sh pm
./scripts/init-clone.sh designer
./scripts/init-clone.sh scientist     # if you ship the scientist role
```

The first run persists the project URL to `.claude-personas/project.txt` — subsequent runs read it automatically.

Result:
- `<project>/` — Developer clone (no suffix, primary)
- `<project>-pm/`, `<project>-designer/`, `<project>-scientist/` — other role clones
- Each with a `memory/` symlink into the memory repo

### 5. Verify

```bash
./scripts/list-roles.sh
```

Expected: all roles reported `OK`. Open each clone in Claude Code, confirm:
- Role's `MEMORY.md` auto-loads (look for the "always in effect" rules in the first response).
- `memory/shared/MEMORY.md` resolves (try a Read on it).

### 6. Optional: tidy old hash dirs

If you don't need the v2 session JSONLs, archive or delete the orphaned hash dirs:

```bash
mv ~/.claude/projects/<old-hash> ~/.claude/projects-archive/  # or rm -rf
```

## Rollback

If anything goes wrong:

```bash
cd ~/path/to/claude-personas-<app>
git checkout v2-final         # the archival tag
```

Re-run the v2 `init-worktree.sh` from that checkout — your role memory content is unchanged.

## FAQ

**Q: Do I lose any memory content?**
No. The role directories (`developer/`, `pm/`, etc.) are untouched. Only the wiring changes.

**Q: Can I keep using v2 on older Claude Code?**
Yes — pin your memory repo to the `v2-final` tag and use the v2 scripts. v3 only matters on Claude Code v2.1.49+.

**Q: My init-clone.sh asks for a project URL each time.**
Likely cause: `.claude-personas/project.txt` was wiped or never created. Re-run with `--project-url` once; the file will be re-created.
```

- [ ] **Step 2: Commit**

```bash
git add MIGRATION.md
git commit -m "docs: add MIGRATION.md walkthrough for v2 to v3

Six-step guide: push memory repo, tear down v2 worktrees, delete v2
hash-symlinks, run init-clone.sh per role, verify with list-roles.sh,
optionally tidy old hash dirs. Includes rollback via v2-final tag."
```

---

## Task 11: Rewrite README.md for v3

**Files:**

- Rewrite: `README.md`

- [ ] **Step 1: Replace README.md contents**

Replace `README.md` with:

```markdown
# claude-personas

[![CI](https://github.com/Jin-HoMLee/claude-personas/actions/workflows/validate.yml/badge.svg)](https://github.com/Jin-HoMLee/claude-personas/actions/workflows/validate.yml)

**Lead your own AI team.** Role-aware persistent memory for solo multi-persona Claude Code workflows.

![Four VSCode windows running Developer, PM, Designer, and Scientist personas in parallel on macOS, each with its own MEMORY.md](assets/mac-vscode-personas-overview-annotated.png)

*A real setup: four roles working in parallel, each in its own VSCode window, each with its own `MEMORY.md`.*

---

## The problem

When you play multiple roles on a project (coding Monday, triaging Tuesday, reviewing Wednesday), you want Claude to behave differently in each context. Your Developer Claude shouldn't have to wade through PM rules, and your PM Claude shouldn't inherit Developer habits. One memory directory mashes them all together.

You need a roster, not a single shared brain.

## What this gives you

Each persona or role on your team gets its own `MEMORY.md` — a playbook of habits, conventions, and rules tailored to that role. `claude-personas` is a **memory-only repo** — you fork the template once per project and never use it as your project codebase. Your actual project repo stays separate.

For each role you want active, you create an independent **clone** of your project repo (sibling-dir style: `my-app/`, `my-app-pm/`, `my-app-scientist/`, ...). Each project clone has a `memory/` symlink into the matching role folder in your `claude-personas-<my-app>` repo. Claude auto-loads the right playbook based on which clone you open.

A `shared/` folder holds team-wide conventions. An `examples/` tree of patterns is included if you want to crib plays from another team.

**For:** solo developers who lead multiple personas across project clones.
**Not for:** multi-human teams, agent-to-agent coordination, or automated memory capture.

## Quick start (~10 minutes per project)

1. Click **Use this template** → create your `claude-personas-<my-app>` repo (one per project).
2. Clone the memory repo next to where you want your project clones:
   ```sh
   cd ~/dev
   git clone git@github.com:<you>/claude-personas-<my-app>.git
   ```
3. Run `init-clone.sh` once per role you want active:
   ```sh
   cd claude-personas-<my-app>
   ./scripts/init-clone.sh developer --project-url git@github.com:<you>/<my-app>.git
   ./scripts/init-clone.sh pm
   ./scripts/init-clone.sh designer
   ./scripts/init-clone.sh scientist
   ```
   First call persists the project URL — subsequent calls don't need `--project-url`.
4. Open any role's clone (e.g. `~/dev/my-app-pm/`) in Claude Code → role's MEMORY.md auto-loads via `memory/MEMORY.md`.
5. Browse `examples/` for patterns; copy what fits into your role's `feedback_*.md` files (then commit + push from your memory repo).

**Default no-suffix slot:** `developer` claims the `<project>/` (no-suffix) path. Override with `--main` on another role or by writing the role name into `.claude-personas/main-role.txt`.

## How it works

```text
~/dev/                                       (parent dir; both repos are siblings here)
├── my-app/                                  (Developer clone — no suffix)
│   ├── .git/                                (real, full project repo)
│   ├── memory ─symlink─► ../claude-personas-my-app/developer/
│   └── [project files...]
│
├── my-app-pm/                               (PM clone)
│   ├── memory ─symlink─► ../claude-personas-my-app/pm/
│   └── [project files...]
│
├── my-app-designer/                         (Designer clone — same shape)
├── my-app-scientist/                        (Scientist clone — same shape)
│
└── claude-personas-my-app/                  (memory repo, your fork of the template)
    ├── developer/
    │   ├── MEMORY.md
    │   └── shared ─symlink─► ../shared
    ├── pm/         (same shape)
    ├── designer/   (same shape)
    ├── scientist/  (same shape)
    ├── shared/                              (canonical shared layer)
    │   └── MEMORY.md
    ├── examples/   (cribbable patterns)
    └── scripts/    init-clone.sh, list-roles.sh
```

When you open `my-app-pm/` in Claude Code, the auto-memory loader reads `my-app-pm/memory/MEMORY.md` — which resolves through the symlink to `claude-personas-my-app/pm/MEMORY.md`. References to `memory/shared/MEMORY.md` resolve through a second symlink (`pm/shared -> ../shared`) to the canonical shared layer.

Two layers of symlinks; both invisible to Claude Code.

Each `MEMORY.md` has two sections:

- **Always in effect** — rules inlined directly; Claude reads these at session start with no file reads required.
- **Reference** — links to `feedback_*.md` files Claude reads on demand.

Rules start in Reference, get promoted to Always-in-effect when they keep being missed. See [`CONVENTIONS.md`](CONVENTIONS.md) for the full pattern.

## What `init-clone.sh` does (one-time per role)

For each role, the script:

1. Validates the role exists in the memory repo (`<role>/MEMORY.md` present).
2. Resolves the project URL: `--project-url` flag > `.claude-personas/project.txt` > prompt.
3. Decides the target clone path:
   - If `--main` or the role matches `.claude-personas/main-role.txt` (default `developer`), claims `<parent>/<project-name>/`.
   - Otherwise, target is `<parent>/<project-name>-<role>/`.
   - Falls through to suffixed path if the no-suffix path is taken.
4. `git clone <url> <target>`.
5. Creates the `memory/` symlink in the new clone pointing into `<memory-repo>/<role>`.
6. Adds `memory/` to the clone's `.gitignore` (idempotent).
7. On first run, persists the project URL to `.claude-personas/project.txt`.

**Audit:** run `./scripts/list-roles.sh` from inside your memory repo to see which clones exist, which are wired correctly, and which need fixing.

## Windows

Symlink creation needs Developer Mode on Windows (Settings → Privacy & Security → Developer Mode). If Developer Mode isn't an option in your environment, use WSL.

## FAQ

**Q: Do I need all four roles?**
No. Skip roles you don't use. Each `init-clone.sh` call is independent. The role dirs you don't run still ship in your fork's memory repo — delete them if you want.

**Q: Can I add custom roles?**
Yes. Create a new folder in your memory repo (e.g. `mlops/`), add a `MEMORY.md` + `shared -> ../shared` symlink, then `init-clone.sh mlops`.

**Q: How is this different from auto-memory?**
Auto-memory captures everything automatically. This is curated and hand-edited — you decide what rules to keep and how to phrase them. Different tradeoff: more work, more intentional.

**Q: Disk cost?**
Each project clone is a full `git clone` — for most projects, ~few hundred MB. Today's machines have terabytes; disk is no longer a concern for the typical solo developer.

**Q: What if I move the memory repo after init?**
The `memory/` symlinks become broken. Re-run `init-clone.sh <role> --force` for each affected clone, OR manually re-point the symlink with `ln -sf ../<new-path>/<role> <clone>/memory`.

**Q: Multiple projects?**
Each project needs its own memory repo (`claude-personas-<app1>`, `claude-personas-<app2>`, ...). Memory content and conventions are project-specific anyway.

## Upgrading from v2

See [`MIGRATION.md`](MIGRATION.md) for a six-step walkthrough. Takes ~10 minutes per project.

**Why v3?** v2's mechanism (git worktrees + hash-derived symlinks) silently broke under Claude Code v2.1.49+ — that release collapses all worktrees into a single hash dir, so v2's per-worktree symlinks never load. v3 uses real independent clones, which each get their own native auto-memory dir.

Users on Claude Code <v2.1.49 can pin their memory repo to the `v2-final` git tag.

## License

[MIT](LICENSE)
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for v3 clones-pivot architecture

New on-disk layout diagram, init-clone.sh quick start, updated FAQ
(adds disk-cost question, removes worktree-specific items). Adds
pointer to MIGRATION.md and explains why v3 exists (CC v2.1.49+
worktree collapse). v2 users can pin to v2-final tag."
```

---

## Task 12: Rewrite CONVENTIONS.md for v3

**Files:**

- Rewrite: `CONVENTIONS.md`

- [ ] **Step 1: Replace CONVENTIONS.md contents**

Replace `CONVENTIONS.md` with:

```markdown
# Conventions

Read this once to understand the system. Then close it and start writing rules.

## The mental model in one paragraph

`claude-personas` is a **memory-only repo** — you fork it once per project (`claude-personas-<my-app>`) and never use it as your project codebase. Inside it, each role (`developer/`, `pm/`, `designer/`, `scientist/`) is just a folder of memory files.

Your **project repo** (the codebase you actually work on) is separate. For each role you want to use, you create one **independent project clone** at a sibling path (`my-app/`, `my-app-pm/`, etc.). Each project clone has a single `memory/` symlink pointing into the matching role folder of the memory repo. Claude Code auto-loads the right `MEMORY.md` based on which clone you're working in.

Each role's clone is a real `git clone` of the project — `git fetch origin` between clones is exactly how human team members sync via GitHub.

## The two-system split

Claude Code offers two places to give Claude persistent instructions:

| Layer | File | What goes here | Committed? |
|---|---|---|---|
| **Project facts** | `CLAUDE.md` (in your project repo) | Non-obvious codebase decisions, known gotchas, infra quirks, API behavior | Yes |
| **AI behavior rules** | Memory files (`MEMORY.md` + `feedback_*.md`, in the memory repo) | How Claude should behave: tone, habits, workflow rules, role-specific conventions | Yes (in the memory repo) |

Keeping these separate prevents a common failure mode: mixing codebase facts with AI behavior rules, which makes both harder to maintain and share.

## Why role-specific memory directories?

When you play multiple roles on a project (Developer on Monday, PM on Tuesday, Designer on Wednesday, Scientist on Thursday), you want Claude to behave differently in each context. The Developer should know your test conventions; the PM should know your milestone format; neither should wade through the other's rules.

Each role gets its own project clone (and so its own Claude Code auto-memory hash dir). The `memory/` symlink in that clone resolves to the role-specific folder in the memory repo. Claude context-switches automatically when you open a different clone — no settings to configure inside the clone, no per-session flags.

## The MEMORY.md two-tier structure

Each role's `MEMORY.md` has two sections:

### Always in effect

Rules inlined directly in the index file. Claude reads these without opening any file — they're in `MEMORY.md` itself, which is auto-loaded every session.

**Use this tier for:** rules that must be applied on every turn regardless of context. Examples: "never commit to main", "always add a role label to issues", "use Read not cat".

**Drift annotations:** when you promote a rule from a reference file into "Always in effect", add a comment showing where it came from:

```text
- **My rule:** Don't do X, do Y instead. <!-- src: shared/feedback_my_rule.md -->
```

This lets you find and update the source file if the rule ever changes, and prevents duplicate edits.

### Reference

Links to separate `feedback_*.md` files. Claude reads these only when the linked topic is relevant to the current task.

**Use this tier for:** rules that apply in specific situations (git workflow, PR process, testing conventions), detailed explanations with examples, rules that are rarely needed.

## The escalation pattern

When Claude repeats a mistake you've already corrected:

1. Search for an existing memory on that topic across all memory files.
   - Found in "Always in effect" → rule already fires at session start; rewrite it to be more specific or actionable.
   - Found only behind a link → **promote it**: copy the rule inline into the role's `MEMORY.md` under "Always in effect", add a drift annotation.
   - Not found anywhere → create a new `feedback_<topic>.md` **and** add it inline to `MEMORY.md` immediately.
2. Never create a duplicate — find and update the existing rule first.

The pattern: rules start as reference, get promoted when they're repeatedly needed inline. Browse `examples/shared/feedback_memory_escalation.md` for the full decision tree.

## Role boundaries

Ask: "Would this rule apply to every role I play on this project?"

- Yes → `shared/`
- No → the specific role's directory

Examples:
- "Never create a PR without running tests first" → `developer/` (only Developer opens PRs)
- "Always add a Created-by line to issue bodies" → `shared/` (all roles create issues)
- "Milestone names must follow the `i<N> - S<N> - <Name>` format" → `pm/` (only PM manages milestones)

## Symlinks

The `shared/` symlink inside each role folder (`developer/shared -> ../shared`) lets you reference shared memory files with a consistent relative path (`shared/feedback_X.md`) regardless of which role you're in. This path appears in drift annotations.

The `memory/` symlink in each project clone (`<project-clone>/memory -> ../claude-personas-<app>/<role>`) is what Claude Code reads at session start. It's created by `init-clone.sh`.

**Windows:** Symlink creation requires Developer Mode on Windows (Settings → Privacy & Security → Developer Mode). If you're on Windows without Developer Mode, use WSL.

## Getting started

See the [Quick start in README.md](README.md#quick-start-10-minutes-per-project) — `scripts/init-clone.sh` automates the clone creation + symlink wiring. Once a role is wired, open Claude Code in the role's clone and it auto-loads the matching `MEMORY.md`.

Then: browse `examples/` for patterns to adopt, and start writing rules into your role's `MEMORY.md` (in your memory repo, then commit and push).
```

- [ ] **Step 2: Commit**

```bash
git add CONVENTIONS.md
git commit -m "docs: rewrite CONVENTIONS.md for v3 mechanism

Replaces v2's worktree+hash-symlink explanation with v3's
independent-clones-per-role + memory/-symlink model. Adds scientist
to the role-list examples."
```

---

## Task 13: CHANGELOG + retire v2 scripts

**Files:**

- Modify: `CHANGELOG.md` (prepend v3.0.0 entry)
- Modify: `.gitignore` (add `.claude-personas/project.txt`)
- Delete: `scripts/init-worktree.sh`
- Delete: `scripts/tests/test_init_worktree.sh`

- [ ] **Step 1: Prepend v3.0.0 entry to CHANGELOG.md**

Open `CHANGELOG.md` and insert at top (before existing v2.0.1 entry):

```markdown
## [3.0.0] — 2026-05-15

### Breaking changes

v3 replaces v2's git-worktree + hash-derived-symlink mechanism with
**independent project-repo clones** per role, wired by a single `memory/`
symlink in each clone pointing into a sibling memory repo.

**Why**: Claude Code v2.1.49+ (Feb 2026) intentionally collapses all
worktrees of one repo into the main repo's auto-memory hash dir. v2's
per-worktree symlinks silently never load on current Claude Code.

**Architecture**: each role gets a real `git clone` at a sibling path
(e.g. `my-app/`, `my-app-pm/`, `my-app-scientist/`). The Developer role
claims the no-suffix path by default; other roles get `-<role>` suffixes.
Override the claimer with `--main` or `.claude-personas/main-role.txt`.

Pinned `v2-final` git tag preserves v2 for users on older Claude Code.

### Added

- `scripts/init-clone.sh` replaces v2's `scripts/init-worktree.sh`.
- `scientist/` role skeleton + `examples/scientist/` ported patterns.
- `MIGRATION.md` with six-step v2-to-v3 walkthrough.
- `.claude-personas/project.txt` (gitignored) persists project URL after first init.
- `.claude-personas/main-role.txt` (tracked, optional) overrides default no-suffix claimer.

### Changed

- `scripts/list-roles.sh` rewritten to walk sibling clone dirs instead of
  `~/.claude/projects/<hash>/memory` paths.
- `README.md` and `CONVENTIONS.md` rewritten for the clones model.
- Role MEMORY.md boilerplate updated to drop v2-specific commentary.

### Removed

- `scripts/init-worktree.sh` (preserved in the `v2-final` tag).
- `scripts/tests/test_init_worktree.sh` (preserved in the `v2-final` tag).
- v2 `autoMemoryDirectory` references in docs.

```

- [ ] **Step 2: Add .claude-personas/project.txt to .gitignore**

Open `.gitignore` and append (if not present):

```text

# Per-user config for init-clone.sh (project URL is per-clone-user)
.claude-personas/project.txt
```

- [ ] **Step 3: Delete v2 scripts**

```bash
git rm scripts/init-worktree.sh scripts/tests/test_init_worktree.sh
```

- [ ] **Step 4: Verify nothing else references the deleted files**

Run: `grep -rn "init-worktree" . --include="*.md" --include="*.sh" --include="*.yml" 2>/dev/null || true`

Expected: zero matches (CONVENTIONS, README, etc. have been rewritten in earlier tasks).

If matches appear: review and update each, then re-run.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md .gitignore
git commit -m "feat: v3.0.0 — retire v2 scripts, document breaking changes

Removes scripts/init-worktree.sh and its tests (preserved in v2-final
tag). Adds CHANGELOG entry explaining the worktree-collapse rationale
and the new clones architecture. Gitignores .claude-personas/project.txt."
```

---

## Task 14: Update CI workflow if needed

**Files:**

- Modify: `.github/workflows/validate.yml` (if v2-specific commands present)

- [ ] **Step 1: Inspect CI workflow**

Run: `cat .github/workflows/validate.yml`

Expected content includes `bash scripts/tests/run_all.sh` (or similar). The runner discovers `test_*.sh` files in `scripts/tests/`, so the new `test_init_clone.sh`, `test_list_roles.sh`, and `test_clone_fixture.sh` files are picked up automatically.

- [ ] **Step 2: Run the full test suite locally**

```bash
bash scripts/tests/run_all.sh
```

Expected: every test_*.sh PASSES. Resolve any failures before continuing.

- [ ] **Step 3: If CI references init-worktree.sh or other deleted files, update**

Open `.github/workflows/validate.yml`. Replace any reference to:
- `init-worktree.sh` → remove the line (no v3 equivalent CI invocation needed; just run tests).
- `worktree`-specific test names → replace with `init-clone`-specific names if present.

If no changes needed: skip to Step 4.

- [ ] **Step 4: Commit (if changes made)**

```bash
git add .github/workflows/validate.yml
git commit -m "ci: update validate.yml for v3 test surface"
```

If no changes: skip the commit.

---

## Task 15: Update hero diagram annotation (deferred-acceptable)

**Files:**

- Modify: `assets/mac-vscode-personas-overview-annotated.png` (re-annotate via existing pipeline)
- Modify: `scripts/annotate_hero.py` (if annotation references "worktree")

- [ ] **Step 1: Check current annotation text**

Run: `grep -n -i "worktree\|persona" scripts/annotate_hero.py | head -20`

Expected: shows whatever current labels say. If they use "worktree" anywhere, update to "clone".

- [ ] **Step 2: If updates needed, apply minimal text changes**

Replace "worktree" with "clone" in annotation strings. Keep the four-role layout (Developer, PM, Designer, Scientist).

- [ ] **Step 3: Regenerate the annotated PNG**

Run: `python3 scripts/annotate_hero.py` (or whatever invocation the script expects — check its `if __name__ == "__main__"` block).

Expected: refreshed `assets/mac-vscode-personas-overview-annotated.png`.

- [ ] **Step 4: Commit (if changes made)**

```bash
git add assets/mac-vscode-personas-overview-annotated.png scripts/annotate_hero.py
git commit -m "docs: update hero diagram to v3 clones terminology"
```

**Deferred-acceptable:** if the annotation pipeline is brittle or time-constrained, open a follow-up issue ("v3: refresh hero diagram") and proceed. The README still works with the existing image — its caption says "four roles working in parallel," which remains accurate.

---

## Task 16: Open PR + release

**Files:**

- Branch: `v3-dev` (push final state)
- PR: `v3-dev` → `main`
- Tag: `v3.0.0` (on main after merge)

- [ ] **Step 1: Final local run of all tests**

```bash
bash scripts/tests/run_all.sh
```

Expected: ALL PASS.

- [ ] **Step 2: Push v3-dev**

```bash
git push origin v3-dev
```

- [ ] **Step 3: Open PR via gh**

```bash
gh pr create --base main --head v3-dev --title "v3.0.0 — clones-pivot mechanism" --body "$(cat <<'EOF'
## Summary

- Replaces v2's worktree + hash-symlink mechanism with independent-clone-per-role.
- Each role gets a real `git clone` of the project; a `memory/` symlink in each clone wires the role's playbook.
- Hard release with `MIGRATION.md` walkthrough. v2 preserved at the `v2-final` git tag.

## Why

Claude Code v2.1.49+ collapses all worktrees into a single auto-memory hash dir. v2's per-worktree symlinks silently never load.

## Test plan

- [ ] `bash scripts/tests/run_all.sh` passes locally
- [ ] CI green
- [ ] `init-clone.sh` happy path (developer claims no-suffix)
- [ ] `--force` on broken symlink backs up and re-wires
- [ ] `--force` on wrong-project clone fails
- [ ] `list-roles.sh` detects healthy / broken / missing roles
- [ ] Read MIGRATION.md end-to-end — instructions resolve

## Spec + plan

- Spec: `docs/superpowers/specs/2026-05-15-v3-clones-pivot-design.md`
- Plan: `docs/superpowers/plans/2026-05-15-v3-clones-pivot.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 4: Merge after review + CI green**

```bash
gh pr merge --merge --delete-branch
```

- [ ] **Step 5: Tag v3.0.0 on main**

```bash
git checkout main && git pull
git tag -a v3.0.0 -m "v3.0.0 — clones-pivot mechanism

See CHANGELOG.md for full notes. Migration: MIGRATION.md."
git push origin v3.0.0
```

- [ ] **Step 6: Verify release on GitHub**

```bash
gh release create v3.0.0 --notes-from-tag --title "v3.0.0 — clones-pivot"
```

Done.
