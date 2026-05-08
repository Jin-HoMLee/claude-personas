# claude-personas v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace claude-personas v1's broken `autoMemoryDirectory` mechanism with native filesystem symlinks at Claude Code's per-project hash-derived memory paths, while preserving v1's role-based memory model.

**Architecture:** Per-project clones of claude-personas. Each role's `~/.claude/projects/<role-hash>/memory/` becomes a symlink into the clone's role folder. The clone's `shared/` is a symlink to the project's main-repo hash dir, which hosts shared content. Worktree-per-role is mandatory.

**Tech Stack:** Bash 4+, git, GitHub Actions, plain shell-based tests (no test framework dependency).

**Source spec:** `docs/superpowers/specs/2026-05-07-claude-personas-v2-design.md`

---

## File structure

**Files created:**
- `scripts/tests/test_helpers.sh` — shared assertion helpers (assertEqual, assertSymlink, etc.)
- `scripts/tests/test_init_worktree.sh` — smoke + integration tests for init script
- `scripts/tests/test_list_roles.sh` — tests for list-roles
- `scripts/tests/run_all.sh` — test runner that executes all `test_*.sh`
- `scripts/list-roles.sh` — audit script that lists wired worktrees
- `CHANGELOG.md` — v2.0.0 release notes with breaking changes + manual upgrade recipe

**Files modified:**
- `scripts/init-worktree.sh` — full rewrite per design Section "Implementation"
- `README.md` — major rewrite (per-project clone model, triple-symlink topology, worktree-per-role)
- `CONVENTIONS.md` — drop CLAUDE.local.md row from Three-system table; rewrite "Why role-specific memory directories?"
- `developer/MEMORY.md`, `pm/MEMORY.md`, `designer/MEMORY.md`, `shared/MEMORY.md` — replace v1 boilerplate references to autoMemoryDirectory/settings.local.json
- `.github/workflows/validate.yml` — drop checks for removed `.example` files; add init smoke test + list-roles smoke test

**Files deleted:**
- `settings.local.json.example`
- `CLAUDE.local.md.example`

---

## Task 1: Tag v1.0 and create v2-dev branch

**Files:**
- No file changes (git operations only)

- [ ] **Step 1: Confirm clean working tree on main**

```bash
cd /Users/jin-holee/Documents/GitHub/Jin-HoMLee/claude-personas
git status
git checkout main
git pull
```

Expected: clean tree, branch up to date with origin/main.

- [ ] **Step 2: Tag current main as v1.0**

```bash
git tag -a v1.0 -m "claude-personas v1.0 — final release before v2 mechanism rewrite"
git push origin v1.0
```

Expected: tag created and pushed.

- [ ] **Step 3: Create and switch to v2-dev branch**

```bash
git checkout -b v2-dev
git push -u origin v2-dev
```

Expected: branch v2-dev tracks origin/v2-dev.

---

## Task 2: Test infrastructure scaffolding

**Files:**
- Create: `scripts/tests/test_helpers.sh`
- Create: `scripts/tests/run_all.sh`

- [ ] **Step 1: Create the test helpers file**

Write `scripts/tests/test_helpers.sh`:

```bash
#!/usr/bin/env bash
# Shared assertion helpers for claude-personas test scripts.
# Source this in each test_*.sh file.

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Print colored output if terminal supports it
if [ -t 1 ]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  RESET=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; RESET=''
fi

assert_equal() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-assert_equal}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$expected" = "$actual" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}  PASS${RESET}: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$msg")
    echo "${RED}  FAIL${RESET}: $msg"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_symlink() {
  local path="$1"
  local expected_target="$2"
  local msg="${3:-assert_symlink $path}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$path" ]; then
    local actual_target
    actual_target="$(readlink "$path")"
    if [ "$actual_target" = "$expected_target" ]; then
      TESTS_PASSED=$((TESTS_PASSED + 1))
      echo "${GREEN}  PASS${RESET}: $msg"
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
      FAILED_TESTS+=("$msg")
      echo "${RED}  FAIL${RESET}: $msg"
      echo "    expected target: $expected_target"
      echo "    actual target:   $actual_target"
    fi
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$msg")
    echo "${RED}  FAIL${RESET}: $msg"
    echo "    path is not a symlink (or doesn't exist): $path"
  fi
}

assert_exists() {
  local path="$1"
  local msg="${2:-assert_exists $path}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -e "$path" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}  PASS${RESET}: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$msg")
    echo "${RED}  FAIL${RESET}: $msg"
  fi
}

assert_not_exists() {
  local path="$1"
  local msg="${2:-assert_not_exists $path}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}  PASS${RESET}: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$msg")
    echo "${RED}  FAIL${RESET}: $msg"
  fi
}

assert_exit_nonzero() {
  local msg="${1:-command should exit non-zero}"
  shift || true
  TESTS_RUN=$((TESTS_RUN + 1))
  if ! "$@" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}  PASS${RESET}: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$msg")
    echo "${RED}  FAIL${RESET}: $msg"
  fi
}

# Compute Claude Code's project hash (path → hash transform)
# Replicates whatever transform Claude Code uses; based on observation: /Users/foo/bar → -Users-foo-bar
compute_hash() {
  echo "$1" | sed 's|/|-|g'
}

# Print test summary; exit non-zero if any failed
print_summary() {
  echo ""
  echo "----"
  echo "Tests run:    $TESTS_RUN"
  echo "${GREEN}Passed:${RESET}       $TESTS_PASSED"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    echo "${RED}Failed:${RESET}       $TESTS_FAILED"
    echo ""
    echo "Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
      echo "  - $t"
    done
    return 1
  fi
  return 0
}
```

- [ ] **Step 2: Create the test runner**

Write `scripts/tests/run_all.sh`:

```bash
#!/usr/bin/env bash
# Run all test_*.sh files in this directory.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OVERALL_STATUS=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
  if [ -f "$test_file" ]; then
    echo "=== Running $(basename "$test_file") ==="
    if ! bash "$test_file"; then
      OVERALL_STATUS=1
    fi
    echo ""
  fi
done

exit $OVERALL_STATUS
```

- [ ] **Step 3: Make scripts executable**

```bash
chmod +x scripts/tests/test_helpers.sh scripts/tests/run_all.sh
```

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/test_helpers.sh scripts/tests/run_all.sh
git commit -m "test: add test scaffolding (helpers + runner)"
```

---

## Task 3: Init script tests (test-first)

**Files:**
- Create: `scripts/tests/test_init_worktree.sh`

- [ ] **Step 1: Write the test file with all test cases**

Write `scripts/tests/test_init_worktree.sh`:

```bash
#!/usr/bin/env bash
# Smoke + integration tests for scripts/init-worktree.sh
# Each test creates an isolated temp environment.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERSONAS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INIT_SCRIPT="$PERSONAS_ROOT/scripts/init-worktree.sh"

source "$SCRIPT_DIR/test_helpers.sh"

# Each test creates its own temp dir with a fake project repo + a fake claude-personas clone
make_test_env() {
  local test_name="$1"
  local tmp
  tmp="$(mktemp -d -t "claude-personas-test-${test_name}-XXXXXX")"

  # Fake project repo
  mkdir -p "$tmp/project"
  (cd "$tmp/project" && git init -q && git commit --allow-empty -q -m "initial")

  # Fake claude-personas clone with role folders
  mkdir -p "$tmp/clone/developer" "$tmp/clone/pm" "$tmp/clone/scientist" "$tmp/clone/shared"
  for role in developer pm scientist; do
    echo "# $role MEMORY.md" > "$tmp/clone/$role/MEMORY.md"
    (cd "$tmp/clone/$role" && ln -s ../shared shared)
  done
  echo "# shared MEMORY.md" > "$tmp/clone/shared/MEMORY.md"
  echo "shared content" > "$tmp/clone/shared/feedback_test.md"

  # Copy our init script + helpers into the test clone (so the test runs the latest version)
  mkdir -p "$tmp/clone/scripts"
  cp "$INIT_SCRIPT" "$tmp/clone/scripts/init-worktree.sh"

  # Use a fake HOME so we don't pollute the real ~/.claude/projects/
  export HOME="$tmp/home"
  mkdir -p "$HOME/.claude/projects"

  echo "$tmp"
}

cleanup_test_env() {
  rm -rf "$1"
  unset HOME
  export HOME="$ORIGINAL_HOME"
}

ORIGINAL_HOME="$HOME"

# ---- Test 1: Basic init creates expected symlinks ----
echo "Test 1: Basic init creates role-hash symlink + main-hash dir + shared symlink"

env_dir="$(make_test_env "basic")"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree" >/dev/null 2>&1)

main_hash="$(compute_hash "$project")"
role_hash="$(compute_hash "$worktree")"

assert_symlink "$HOME/.claude/projects/$role_hash/memory" "$clone/pm/" "role symlink created"
assert_exists "$HOME/.claude/projects/$main_hash/memory" "main-hash memory dir created"
assert_symlink "$clone/shared" "$HOME/.claude/projects/$main_hash/memory/" "clone/shared symlinked to main-hash"
assert_exists "$HOME/.claude/projects/$main_hash/memory/feedback_test.md" "shared content migrated to main-hash"

cleanup_test_env "$env_dir"

# ---- Test 2: No project-side files created ----
echo ""
echo "Test 2: No .claude/settings.local.json or CLAUDE.local.md created in worktree"

env_dir="$(make_test_env "no-project-files")"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-dev"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" developer "$worktree" >/dev/null 2>&1)

assert_not_exists "$worktree/.claude/settings.local.json" "settings.local.json not created"
assert_not_exists "$worktree/CLAUDE.local.md" "CLAUDE.local.md not created"

cleanup_test_env "$env_dir"

# ---- Test 3: Idempotent re-run with same role ----
echo ""
echo "Test 3: Re-running init for same role is idempotent (no error)"

env_dir="$(make_test_env "idempotent")"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree" >/dev/null 2>&1)
# Remove the worktree and re-add (simulate user re-running init for an existing wiring)
git -C "$project" worktree remove --force "$worktree" >/dev/null 2>&1
rm -rf "$worktree"
git -C "$project" branch -D pm/workspace >/dev/null 2>&1 || true

# Re-run — should succeed because the symlinks already point right
(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree" >/dev/null 2>&1)
status=$?
assert_equal "0" "$status" "second run succeeds"

cleanup_test_env "$env_dir"

# ---- Test 4: Second role in same project — shared symlink already correct, skip migration ----
echo ""
echo "Test 4: Second role init skips shared-folder migration but creates role symlink"

env_dir="$(make_test_env "second-role")"
project="$env_dir/project"
clone="$env_dir/clone"
worktree_pm="$env_dir/project-pm"
worktree_dev="$env_dir/project-dev"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree_pm" >/dev/null 2>&1)
(cd "$project" && bash "$clone/scripts/init-worktree.sh" developer "$worktree_dev" >/dev/null 2>&1)

main_hash="$(compute_hash "$project")"
dev_hash="$(compute_hash "$worktree_dev")"

assert_symlink "$HOME/.claude/projects/$dev_hash/memory" "$clone/developer/" "dev role symlink created on second init"
assert_symlink "$clone/shared" "$HOME/.claude/projects/$main_hash/memory/" "clone/shared still pointing at same main-hash"

cleanup_test_env "$env_dir"

# ---- Test 5: Refuses if memory dir already exists as real dir ----
echo ""
echo "Test 5: Init fails if <role-hash>/memory exists as real dir (without --force)"

env_dir="$(make_test_env "preexisting-real")"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"

# Pre-create role-hash memory dir with content
role_hash="$(compute_hash "$worktree")"
mkdir -p "$HOME/.claude/projects/$role_hash/memory"
echo "existing content" > "$HOME/.claude/projects/$role_hash/memory/MEMORY.md"

# init should fail (note: worktree path doesn't exist yet, so role-hash is computed from the requested path)
(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree" >/dev/null 2>&1)
status=$?
assert_equal "1" "$status" "init exits non-zero when memory dir has prior content"

cleanup_test_env "$env_dir"

# ---- Test 6: --force flag backs up and overwrites ----
echo ""
echo "Test 6: --force flag backs up existing memory and creates symlink"

env_dir="$(make_test_env "force-flag")"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"

role_hash="$(compute_hash "$worktree")"
mkdir -p "$HOME/.claude/projects/$role_hash/memory"
echo "existing content" > "$HOME/.claude/projects/$role_hash/memory/MEMORY.md"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" --force pm "$worktree" >/dev/null 2>&1)

assert_symlink "$HOME/.claude/projects/$role_hash/memory" "$clone/pm/" "role symlink created with --force"
# Backup dir should exist
backup_count=$(find "$HOME/.claude/projects/$role_hash" -maxdepth 1 -name 'memory.backup-*' -type d 2>/dev/null | wc -l)
assert_equal "1" "$(echo "$backup_count" | tr -d ' ')" "backup directory created"

cleanup_test_env "$env_dir"

# ---- Test 7: Refuses to use clone wired to a different project ----
echo ""
echo "Test 7: Init fails if clone's shared/ is symlinked to a different main-hash"

env_dir="$(make_test_env "wrong-clone")"
project_a="$env_dir/project-a"
project_b="$env_dir/project-b"
clone="$env_dir/clone"

# Set up project A
mkdir -p "$project_a"
(cd "$project_a" && git init -q && git commit --allow-empty -q -m "initial")

# Set up project B
mkdir -p "$project_b"
(cd "$project_b" && git init -q && git commit --allow-empty -q -m "initial")

# Init clone for project A
(cd "$project_a" && bash "$clone/scripts/init-worktree.sh" pm "$env_dir/project-a-pm" >/dev/null 2>&1)

# Try to init same clone from project B — should fail
(cd "$project_b" && bash "$clone/scripts/init-worktree.sh" pm "$env_dir/project-b-pm" >/dev/null 2>&1)
status=$?
assert_equal "1" "$status" "init exits non-zero when clone is wired to a different project"

cleanup_test_env "$env_dir"

# ---- Test 8: Worktree is created (git worktree add succeeds) ----
echo ""
echo "Test 8: git worktree is actually created"

env_dir="$(make_test_env "worktree-created")"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree" >/dev/null 2>&1)

assert_exists "$worktree/.git" "worktree's .git exists"

cleanup_test_env "$env_dir"

# ---- Test 9: Unknown role exits with error ----
echo ""
echo "Test 9: Unknown role rejected"

env_dir="$(make_test_env "bad-role")"
project="$env_dir/project"
clone="$env_dir/clone"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" nonexistent "$env_dir/project-x" >/dev/null 2>&1)
status=$?
assert_equal "1" "$status" "init exits non-zero on unknown role"

cleanup_test_env "$env_dir"

print_summary
exit $?
```

- [ ] **Step 2: Make test executable**

```bash
chmod +x scripts/tests/test_init_worktree.sh
```

- [ ] **Step 3: Run test (expect failure since init script not yet rewritten)**

```bash
bash scripts/tests/test_init_worktree.sh
```

Expected: most/all tests FAIL because v1 init script doesn't implement v2 behavior.

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/test_init_worktree.sh
git commit -m "test: add init-worktree.sh tests (will pass after v2 rewrite)"
```

---

## Task 4: Rewrite init script (full v2 implementation)

**Files:**
- Modify: `scripts/init-worktree.sh` (replace entire content)

- [ ] **Step 1: Replace init-worktree.sh with v2 implementation**

Replace `scripts/init-worktree.sh` with:

```bash
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

# Compute Claude Code's project hash from an absolute path
# Algorithm: replace each "/" with "-"
compute_hash() {
  echo "$1" | sed 's|/|-|g'
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

# Compute hashes from the canonical absolute paths
PROJECT_ABS="$(cd "$(git rev-parse --show-toplevel)" && pwd -P)"
MAIN_HASH="$(compute_hash "$PROJECT_ABS")"

# Resolve worktree path to absolute (it doesn't exist yet, so we resolve manually)
case "$WORKTREE_PATH" in
  /*) WORKTREE_ABS_TARGET="$WORKTREE_PATH" ;;
  *)  WORKTREE_ABS_TARGET="$(pwd -P)/$WORKTREE_PATH" ;;
esac
# Normalize: collapse .. and . segments
WORKTREE_ABS_TARGET="$(python3 -c "import os, sys; print(os.path.normpath(sys.argv[1]))" "$WORKTREE_ABS_TARGET")"
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
```

- [ ] **Step 2: Ensure script is executable**

```bash
chmod +x scripts/init-worktree.sh
```

- [ ] **Step 3: Run init script tests**

```bash
bash scripts/tests/test_init_worktree.sh
```

Expected: all 9 tests PASS. If any fail, fix the script and re-run.

- [ ] **Step 4: Commit**

```bash
git add scripts/init-worktree.sh
git commit -m "feat: rewrite init-worktree.sh for v2 (symlink-based mechanism)"
```

---

## Task 5: list-roles.sh tests

**Files:**
- Create: `scripts/tests/test_list_roles.sh`

- [ ] **Step 1: Write the test file**

Write `scripts/tests/test_list_roles.sh`:

```bash
#!/usr/bin/env bash
# Tests for scripts/list-roles.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERSONAS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIST_SCRIPT="$PERSONAS_ROOT/scripts/list-roles.sh"

source "$SCRIPT_DIR/test_helpers.sh"

ORIGINAL_HOME="$HOME"

# ---- Test 1: list-roles outputs nothing when no symlinks present ----
echo "Test 1: empty output when no role symlinks"

tmp="$(mktemp -d -t list-roles-empty-XXXX)"
export HOME="$tmp"
mkdir -p "$HOME/.claude/projects"

output="$(bash "$LIST_SCRIPT" 2>&1 || true)"
echo "$output" | grep -qi "no" || echo "$output" | grep -qE "0 |empty|none"
status=$?
assert_equal "0" "$status" "list-roles handles empty state without crashing"

rm -rf "$tmp"
export HOME="$ORIGINAL_HOME"

# ---- Test 2: list-roles reports a healthy symlink ----
echo ""
echo "Test 2: reports healthy symlink with role + worktree path"

tmp="$(mktemp -d -t list-roles-healthy-XXXX)"
export HOME="$tmp"
mkdir -p "$HOME/.claude/projects"

# Fake clone + role
mkdir -p "$tmp/clone/pm"
echo "# pm" > "$tmp/clone/pm/MEMORY.md"

# Fake worktree path → hash
worktree_abs="$tmp/project-pm"
hash="$(compute_hash "$worktree_abs")"
mkdir -p "$HOME/.claude/projects/$hash"
ln -s "$tmp/clone/pm/" "$HOME/.claude/projects/$hash/memory"

output="$(bash "$LIST_SCRIPT" 2>&1 || true)"
echo "$output" | grep -q "pm" && echo "$output" | grep -q "$worktree_abs"
status=$?
assert_equal "0" "$status" "list-roles output mentions role 'pm' and worktree path"

rm -rf "$tmp"
export HOME="$ORIGINAL_HOME"

# ---- Test 3: list-roles flags broken symlinks ----
echo ""
echo "Test 3: broken symlinks flagged as broken/dead"

tmp="$(mktemp -d -t list-roles-broken-XXXX)"
export HOME="$tmp"
mkdir -p "$HOME/.claude/projects"

worktree_abs="$tmp/project-pm"
hash="$(compute_hash "$worktree_abs")"
mkdir -p "$HOME/.claude/projects/$hash"
# Create a symlink to a non-existent target
ln -s "$tmp/nonexistent/pm/" "$HOME/.claude/projects/$hash/memory"

output="$(bash "$LIST_SCRIPT" 2>&1 || true)"
echo "$output" | grep -qiE "broken|dead|missing|invalid"
status=$?
assert_equal "0" "$status" "broken symlink flagged in output"

rm -rf "$tmp"
export HOME="$ORIGINAL_HOME"

print_summary
exit $?
```

- [ ] **Step 2: Make test executable**

```bash
chmod +x scripts/tests/test_list_roles.sh
```

- [ ] **Step 3: Run tests (expect failure since list-roles.sh doesn't exist)**

```bash
bash scripts/tests/test_list_roles.sh
```

Expected: tests FAIL (script not found).

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/test_list_roles.sh
git commit -m "test: add list-roles.sh tests"
```

---

## Task 6: Implement list-roles.sh

**Files:**
- Create: `scripts/list-roles.sh`

- [ ] **Step 1: Write list-roles.sh**

Write `scripts/list-roles.sh`:

```bash
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/list-roles.sh
```

- [ ] **Step 3: Run tests**

```bash
bash scripts/tests/test_list_roles.sh
```

Expected: all 3 tests PASS.

- [ ] **Step 4: Commit**

```bash
git add scripts/list-roles.sh
git commit -m "feat: add scripts/list-roles.sh audit companion"
```

---

## Task 7: Remove obsolete example files

**Files:**
- Delete: `settings.local.json.example`
- Delete: `CLAUDE.local.md.example`

- [ ] **Step 1: Remove the files**

```bash
git rm settings.local.json.example CLAUDE.local.md.example
```

- [ ] **Step 2: Verify removal**

```bash
ls settings.local.json.example CLAUDE.local.md.example 2>&1
```

Expected: "No such file or directory" for both.

- [ ] **Step 3: Commit**

```bash
git commit -m "chore: remove v1 example config files (no longer needed in v2)"
```

---

## Task 8: Update role MEMORY.md boilerplate

**Files:**
- Modify: `developer/MEMORY.md`
- Modify: `pm/MEMORY.md`
- Modify: `designer/MEMORY.md`
- Modify: `shared/MEMORY.md`

- [ ] **Step 1: Inspect current boilerplate references**

```bash
grep -n -E "autoMemoryDirectory|settings\.local\.json|CLAUDE\.local\.md" developer/MEMORY.md pm/MEMORY.md designer/MEMORY.md shared/MEMORY.md
```

Note the line numbers and surrounding context for each match. The boilerplate typically appears as a comment block near the top of each file describing how memory loading works. Plan minimal edits at each match site.

- [ ] **Step 2: Update each MEMORY.md by replacing autoMemoryDirectory references**

For each occurrence, replace v1 phrasing with v2 phrasing. Common patterns:

**Replace:**
```
Usage: set autoMemoryDirectory to the absolute path of this folder in
your project worktree's .claude/settings.local.json
```

**With:**
```
Usage: this folder is reached via a symlink at ~/.claude/projects/<hash>/memory
created by scripts/init-worktree.sh — no per-project config needed.
```

Apply equivalent replacement for each grep match, preserving the surrounding markdown structure. Do this individually per file using Edit (specifying the unique surrounding context for each match).

- [ ] **Step 3: Re-verify no leftover references**

```bash
grep -rn -E "autoMemoryDirectory|settings\.local\.json|CLAUDE\.local\.md" developer/ pm/ designer/ shared/ 2>&1 | grep -v "examples/" || echo "Clean"
```

Expected: "Clean" (no matches outside of `examples/` which is unchanged).

- [ ] **Step 4: Commit**

```bash
git add developer/MEMORY.md pm/MEMORY.md designer/MEMORY.md shared/MEMORY.md
git commit -m "docs: update role MEMORY.md boilerplate for v2 mechanism"
```

---

## Task 9: Rewrite CONVENTIONS.md

**Files:**
- Modify: `CONVENTIONS.md`

- [ ] **Step 1: Read current CONVENTIONS.md**

```bash
cat CONVENTIONS.md
```

Identify two specific edits needed:
1. Drop the `CLAUDE.local.md` row from the "Three-system split" table → table becomes two rows
2. Rewrite "Why role-specific memory directories?" section: replace explanation of `autoMemoryDirectory` with explanation of the symlink mechanism

- [ ] **Step 2: Edit the "Three-system split" table**

Find the table (search for "Project facts" + "AI behavior rules" + "Machine-specific"). Remove the entire `**Machine-specific**` row (the row that describes `CLAUDE.local.md`).

Update the surrounding paragraph that explains the split: change "three places" to "two places".

- [ ] **Step 3: Rewrite "Why role-specific memory directories?"**

Replace the section's body (currently explaining `autoMemoryDirectory`) with the v2 explanation:

```markdown
## Why role-specific memory directories?

When you play multiple roles on a project (Developer on Monday, PM on
Tuesday, Designer on Wednesday), you want Claude to behave differently in
each context. The Developer should know your test conventions; the PM should
know your milestone format; neither should wade through the other's rules.

Claude Code automatically loads `MEMORY.md` from a per-project directory
under `~/.claude/projects/<hash>/memory/`, where `<hash>` is derived from the
project worktree's absolute path. By creating a separate worktree per role
(each with its own absolute path → its own hash → its own memory dir) and
symlinking each role's memory dir to the matching role folder inside
claude-personas, Claude context-switches automatically when you switch
worktrees — no settings to configure.
```

- [ ] **Step 4: Verify changes**

```bash
grep -n "CLAUDE.local.md\|autoMemoryDirectory" CONVENTIONS.md || echo "Clean"
```

Expected: "Clean" — both references removed.

- [ ] **Step 5: Commit**

```bash
git add CONVENTIONS.md
git commit -m "docs: update CONVENTIONS.md for v2 (drop CLAUDE.local.md row, explain symlinks)"
```

---

## Task 10: Rewrite README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update "The problem" section**

Find the existing problem section and replace its core description. Replace any text claiming `autoMemoryDirectory` works at project level with v2 framing.

New text for "The problem" section:

```markdown
## The problem

When you play multiple roles on a project (coding Monday, triaging Tuesday,
reviewing Wednesday), you want Claude to behave differently in each context.
Your Developer Claude shouldn't have to wade through PM rules, and your PM
Claude shouldn't inherit Developer habits. One memory directory mashes them
all together.

You need a roster, not a single shared brain.
```

- [ ] **Step 2: Replace "How it works" diagram**

Find the existing fenced code block under "How it works" and replace it with the v2 topology:

```markdown
## How it works

```text
~/projects/my-app/                       (main repo — no role uses it; hosts shared)
~/projects/my-app-dev/                   (developer worktree)
~/projects/my-app-pm/                    (PM worktree)
~/projects/my-app-designer/              (designer worktree)

~/projects/claude-personas-my-app/       (per-project clone of this repo)
├── developer/MEMORY.md
├── pm/MEMORY.md
├── designer/MEMORY.md
└── shared  ─symlink─►  ~/.claude/projects/<main-hash>/memory/

Claude Code's native paths:
~/.claude/projects/<dev-hash>/memory   ─symlink─►  claude-personas-my-app/developer/
~/.claude/projects/<pm-hash>/memory    ─symlink─►  claude-personas-my-app/pm/
~/.claude/projects/<des-hash>/memory   ─symlink─►  claude-personas-my-app/designer/
~/.claude/projects/<main-hash>/memory/  (real dir — actual shared content)
```

Open Claude Code in any role's worktree and it auto-loads the matching MEMORY.md
through the symlink chain. No `autoMemoryDirectory`, no per-worktree config files.

> ⓘ **Coming in v3**: a single claude-personas clone serving multiple projects
> via a project-tier structure. v2 is one clone per project.
```

- [ ] **Step 3: Update "Quick start" section**

Replace its content with:

```markdown
## Quick start (~5 minutes per project)

1. Click **Use this template** → create your `claude-personas-<my-app>` repo (one per project)
2. Clone it next to your project repo:
   `git clone git@github.com:<you>/claude-personas-<my-app>.git ~/projects/claude-personas-<my-app>`
3. From inside your **project repo** (not claude-personas), create a worktree per role:

   ```sh
   ~/projects/claude-personas-<my-app>/scripts/init-worktree.sh developer ../my-app-dev
   ~/projects/claude-personas-<my-app>/scripts/init-worktree.sh pm ../my-app-pm
   ~/projects/claude-personas-<my-app>/scripts/init-worktree.sh designer ../my-app-designer
   ```

   Each call creates a worktree on a `<role>/workspace` branch and sets up the symlinks
   so Claude Code auto-loads the right MEMORY.md when you open the worktree.

4. Open Claude Code in any role's worktree → it auto-loads that role's MEMORY.md.

5. Browse `examples/` for patterns; copy what fits into your role's `feedback_*.md`
   files (then commit + push from your claude-personas clone).

**Note**: every role gets its own worktree. The main project repo path stays
"unused by any role" — its hash dir hosts the shared layer.
```

- [ ] **Step 4: Replace "Per-project-worktree setup" section**

Replace v1's section with:

```markdown
## What init-worktree.sh does (one-time per role)

`scripts/init-worktree.sh` automates this section. Read on if you want to know what
it does, or do it by hand.

For each role, the script:

1. Creates a git worktree on a new `<role>/workspace` branch
2. Computes Claude Code's hash from the worktree's absolute path
3. Symlinks `~/.claude/projects/<role-hash>/memory` to the role folder in your clone
4. (First role only) migrates your clone's `shared/` content into
   `~/.claude/projects/<main-hash>/memory/` and replaces `shared/` with a symlink
   pointing there

After init, the project worktree contains nothing claude-personas-related — no
`.claude/settings.local.json`, no `CLAUDE.local.md`. Your project's `.gitignore`
stays clean.

**Audit:** run `~/projects/claude-personas-<my-app>/scripts/list-roles.sh` to see
which worktrees are currently wired to which roles.
```

- [ ] **Step 5: Update "Windows" section**

Replace with:

```markdown
## Windows

v2 requires symlinks at multiple paths. Enable Developer Mode (Settings → Privacy
& Security → Developer Mode) so non-admin users can create symlinks. If Developer
Mode isn't an option in your environment, use WSL — claude-personas v2 has no
non-symlink fallback.
```

- [ ] **Step 6: Update FAQ**

Remove FAQ entries about `autoMemoryDirectory` and `CLAUDE.local.md`. Add new entries:

```markdown
**Q: Does claude-personas need to be in the same parent directory as my project?**
No, but it must be reachable via an absolute path that won't move (the role
symlinks store the path verbatim). One natural place: `~/projects/claude-personas-<my-app>/`
next to your project repo.

**Q: What if I move or rename the claude-personas clone after init?**
The role symlinks become broken. Run `scripts/list-roles.sh` to detect, then
re-run `scripts/init-worktree.sh <role> <worktree>` (with `--force`) for each
role to re-create the symlinks at the new path.

**Q: Can I have multiple projects share one claude-personas clone?**
Not in v2. Each clone is wired to one project on first init (the `shared` symlink
hardcodes that project's main-hash). Use a separate clone per project. v3 may
support multi-project via a project-tier directory structure.
```

- [ ] **Step 7: Add upgrade-from-v1 section near the bottom**

```markdown
## Upgrading from v1

v2 is a breaking change from v1. v1 used `autoMemoryDirectory` in a project-level
settings file, which is silently ignored by Claude Code (see issue #55801). v2
replaces this with native filesystem symlinks.

**Manual upgrade per project**:

1. In each role's project worktree, delete `.claude/settings.local.json` and
   `CLAUDE.local.md`, and remove their entries from `.gitignore`.
2. Re-run `scripts/init-worktree.sh <role> <worktree-path>` from your project
   repo — the v2 script produces symlink-based wiring instead of v1's config files.

Your `claude-personas/<role>/` memory files are unchanged; only the wiring mechanism
between project worktree and role memory has changed.
```

- [ ] **Step 8: Verify no leftover v1 references**

```bash
grep -nE "autoMemoryDirectory|settings\.local\.json|CLAUDE\.local\.md" README.md | grep -v "Upgrading from v1\|delete\|remove"
```

Expected: empty output (only "Upgrading from v1" section may legitimately reference v1 terms in its instructions).

- [ ] **Step 9: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for v2 (per-project clone, symlink topology, worktree-per-role)"
```

---

## Task 11: Add CHANGELOG.md

**Files:**
- Create: `CHANGELOG.md`

- [ ] **Step 1: Write CHANGELOG.md**

```markdown
# Changelog

## [2.0.0] — 2026-XX-XX

### Breaking changes

v2 replaces v1's `autoMemoryDirectory` mechanism with native filesystem symlinks
at Claude Code's per-project hash-derived memory paths.

**Why**: project-level `autoMemoryDirectory` in `.claude/settings.local.json` is
silently ignored by Claude Code (see [issue #55801](https://github.com/anthropics/claude-code/issues/55801)).
v1 was non-functional as documented.

**Architecture**: per-project clones of claude-personas. Each role's worktree has
its memory dir at `~/.claude/projects/<role-hash>/memory/` symlinked to the clone's
role folder. The clone's `shared/` is a symlink to the project's main-repo hash dir.

### Removed

- `settings.local.json.example`
- `CLAUDE.local.md.example`
- "Single clone serves many projects" pattern (v3 candidate)

### Added

- `CHANGELOG.md` (this file)
- `scripts/list-roles.sh` — audit which worktrees are wired to which roles
- `scripts/tests/` — test scripts and runner for init script + list-roles
- v2 init script: full rewrite using symlink mechanism

### Manual upgrade from v1

1. In each role's project worktree, delete `.claude/settings.local.json` and
   `CLAUDE.local.md`, and remove their entries from `.gitignore`.
2. Re-run `scripts/init-worktree.sh <role> <worktree-path>` from your project repo.

No memory data is lost; only the wiring mechanism changes.

## [1.0] — 2026-04-30

Initial public release of claude-personas. v1 architecture used `autoMemoryDirectory`
in `.claude/settings.local.json` (subsequently discovered to be silently ignored).
Tagged before v2 development as `v1.0` for archival.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: add CHANGELOG.md with v2.0.0 release notes and v1.0 archival"
```

---

## Task 12: Update CI workflow

**Files:**
- Modify: `.github/workflows/validate.yml`

- [ ] **Step 1: Replace validate.yml content**

```yaml
name: validate

on:
  push:
  pull_request:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: claude-personas internal symlinks resolve
        run: |
          for role in developer pm designer; do
            target=$(readlink "$role/shared")
            resolved="$role/$target"
            if [ ! -d "$resolved" ]; then
              echo "FAIL: $role/shared -> $target does not resolve"
              exit 1
            fi
            echo "OK: $role/shared -> $target"
          done

      - name: scripts are executable
        run: |
          for s in scripts/init-worktree.sh scripts/list-roles.sh scripts/tests/run_all.sh; do
            if [ ! -x "$s" ]; then
              echo "FAIL: $s is not executable"
              exit 1
            fi
            echo "OK: $s is executable"
          done

      - name: each role has MEMORY.md
        run: |
          for role in developer pm designer shared; do
            if [ ! -f "$role/MEMORY.md" ]; then
              echo "FAIL: $role/MEMORY.md missing"
              exit 1
            fi
            echo "OK: $role/MEMORY.md exists"
          done

      - name: run tests
        run: bash scripts/tests/run_all.sh
```

- [ ] **Step 2: Verify YAML syntax locally**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/validate.yml'))" && echo "OK"
```

Expected: "OK".

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/validate.yml
git commit -m "ci: update validation for v2 (run tests, drop .example checks)"
```

---

## Task 13: Final integration test on real machine

**Files:**
- No file changes (manual end-to-end verification)

- [ ] **Step 1: Run full test suite locally**

```bash
bash scripts/tests/run_all.sh
```

Expected: ALL tests pass across all test_*.sh files.

- [ ] **Step 2: Manual end-to-end smoke test in a real directory**

Create a throwaway test environment to verify behavior outside the test harness:

```bash
TEST_DIR=$(mktemp -d -t claude-personas-e2e-XXXX)
cd "$TEST_DIR"

# Fake project repo
mkdir my-app && cd my-app
git init -q
git commit --allow-empty -q -m "initial"

# Clone of v2 claude-personas (from current branch)
cd "$TEST_DIR"
git clone /Users/jin-holee/Documents/GitHub/Jin-HoMLee/claude-personas claude-personas-my-app
git -C claude-personas-my-app checkout v2-dev

# Run init for one role
cd "$TEST_DIR/my-app"
"$TEST_DIR/claude-personas-my-app/scripts/init-worktree.sh" pm ../my-app-pm

# Verify wiring
ls -la "$HOME/.claude/projects/" | grep "$TEST_DIR" || echo "WARN: no entries for test dir"
"$TEST_DIR/claude-personas-my-app/scripts/list-roles.sh"

# Cleanup
rm -rf "$TEST_DIR"
# Manual cleanup of the fake hash dirs (since they were created in $HOME):
ls "$HOME/.claude/projects/" | grep -E "tmp|claude-personas-e2e" | xargs -I {} rm -rf "$HOME/.claude/projects/{}"
```

Expected: init runs without errors; symlinks visible at `~/.claude/projects/<hash>/memory`; list-roles reports the wiring.

- [ ] **Step 3: Push v2-dev branch for CI run**

```bash
git push origin v2-dev
```

Wait for GitHub Actions CI to complete. Verify all jobs pass.

- [ ] **Step 4: If CI passes, merge v2-dev to main**

```bash
git checkout main
git merge --no-ff v2-dev -m "Merge v2-dev: claude-personas v2.0.0 — symlink-based wiring"
git push origin main
```

- [ ] **Step 5: Tag v2.0.0**

```bash
git tag -a v2.0.0 -m "claude-personas v2.0.0 — replaces autoMemoryDirectory with native symlinks"
git push origin v2.0.0
```

- [ ] **Step 6: Create GitHub release**

Use the GitHub UI or `gh release create v2.0.0 --notes-from-tag` (if `gh` is configured) to create a release pointing at the v2.0.0 tag, with release notes mirroring CHANGELOG.md's v2.0.0 section.
