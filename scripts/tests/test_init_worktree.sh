#!/usr/bin/env bash
# Smoke + integration tests for scripts/init-worktree.sh
# Each test creates an isolated temp environment.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERSONAS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INIT_SCRIPT="$PERSONAS_ROOT/scripts/init-worktree.sh"

source "$SCRIPT_DIR/test_helpers.sh"

# Build a fresh test fixture (filesystem only): a fake project repo + a fake
# claude-personas clone + a fake home dir. Returns the fixture's tmp path.
#
# Note: this function does NOT export HOME. It runs inside `$(...)` command
# substitution which forks a subshell, so any `export` here would evaporate
# when the subshell exits. The caller must `export HOME="$env_dir/home"` in
# the parent shell after capturing the returned path.
make_test_fixture() {
  local test_name="$1"
  local tmp
  tmp="$(mktemp -d -t "claude-personas-test-${test_name}-XXXXXX")"
  # Resolve to physical path so test-side compute_hash matches what
  # init-worktree.sh (which uses pwd -P) computes.
  tmp="$(cd "$tmp" && pwd -P)"

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

  # Pre-create the fake-home claude-projects dir. Use $tmp/home directly —
  # this function does not touch $HOME (see header comment).
  mkdir -p "$tmp/home/.claude/projects"

  echo "$tmp"
}

# Tear down the fixture's temp dir. Caller is responsible for restoring HOME.
cleanup_test_fixture() {
  rm -rf "$1"
}

ORIGINAL_HOME="$HOME"
# Defensive: ensure HOME is restored if the script exits unexpectedly mid-test
# (e.g. a future refactor flipping `set -e` and having an assertion abort).
# In current shape this is mostly a no-op since the script has no early-exit
# paths, but it costs nothing and protects against future drift.
trap 'export HOME="$ORIGINAL_HOME"' EXIT

# ---- Test 1: Basic init creates expected symlinks ----
echo "Test 1: Basic init creates role-hash symlink + main-hash dir + shared symlink"

env_dir="$(make_test_fixture "basic")"
export HOME="$env_dir/home"
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

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 2: No project-side files created ----
echo ""
echo "Test 2: No .claude/settings.local.json or CLAUDE.local.md created in worktree"

env_dir="$(make_test_fixture "no-project-files")"
export HOME="$env_dir/home"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-dev"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" developer "$worktree" >/dev/null 2>&1)

assert_not_exists "$worktree/.claude/settings.local.json" "settings.local.json not created"
assert_not_exists "$worktree/CLAUDE.local.md" "CLAUDE.local.md not created"

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 3: Idempotent re-run with same role ----
echo ""
echo "Test 3: Re-running init for same role is idempotent (no error)"

env_dir="$(make_test_fixture "idempotent")"
export HOME="$env_dir/home"
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

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 4: Second role in same project — shared symlink already correct, skip migration ----
echo ""
echo "Test 4: Second role init skips shared-folder migration but creates role symlink"

env_dir="$(make_test_fixture "second-role")"
export HOME="$env_dir/home"
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

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 5: Refuses if memory dir already exists as real dir ----
echo ""
echo "Test 5: Init fails if <role-hash>/memory exists as real dir (without --force)"

env_dir="$(make_test_fixture "preexisting-real")"
export HOME="$env_dir/home"
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

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 6: --force flag backs up and overwrites ----
echo ""
echo "Test 6: --force flag backs up existing memory and creates symlink"

env_dir="$(make_test_fixture "force-flag")"
export HOME="$env_dir/home"
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

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 7: Refuses to use clone wired to a different project ----
echo ""
echo "Test 7: Init fails if clone's shared/ is symlinked to a different main-hash"

env_dir="$(make_test_fixture "wrong-clone")"
export HOME="$env_dir/home"
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

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 8: Worktree is created (git worktree add succeeds) ----
echo ""
echo "Test 8: git worktree is actually created"

env_dir="$(make_test_fixture "worktree-created")"
export HOME="$env_dir/home"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree" >/dev/null 2>&1)

assert_exists "$worktree/.git" "worktree's .git exists"

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 9: Unknown role exits with error ----
echo ""
echo "Test 9: Unknown role rejected"

env_dir="$(make_test_fixture "bad-role")"
export HOME="$env_dir/home"
project="$env_dir/project"
clone="$env_dir/clone"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" nonexistent "$env_dir/project-x" >/dev/null 2>&1)
status=$?
assert_equal "1" "$status" "init exits non-zero on unknown role"

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 10: --force on a correctly-wired symlink leaves it intact ----
# Regression test for: --force unconditionally rm'd the symlink, and the
# recreate guard then skipped because ROLE_LINK_PRE_EXISTS=1, leaving the
# role with no memory symlink at all.
echo ""
echo "Test 10: --force on a correctly-wired symlink leaves it intact"

env_dir="$(make_test_fixture "force-correct")"
export HOME="$env_dir/home"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"

# First init: creates the symlink correctly
(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree" >/dev/null 2>&1)

# Drop the worktree but keep the symlink so init can recompute the same hash
git -C "$project" worktree remove --force "$worktree" >/dev/null 2>&1
rm -rf "$worktree"
git -C "$project" branch -D pm/workspace >/dev/null 2>&1 || true

role_hash="$(compute_hash "$worktree")"

# Re-run with --force — symlink correctly points, should be a no-op
(cd "$project" && bash "$clone/scripts/init-worktree.sh" --force pm "$worktree" >/dev/null 2>&1)
status=$?
assert_equal "0" "$status" "--force on correctly-wired symlink succeeds"
assert_symlink "$HOME/.claude/projects/$role_hash/memory" "$clone/pm/" "symlink still points to role after --force re-run"

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 11: --force replaces a mispointing symlink ----
# The canonical --force use case: an existing role-hash/memory symlink that
# points somewhere wrong (not to $ROLE_DIR/). Without --force, init aborts.
# With --force, init removes the bad symlink and recreates pointing at the role.
echo ""
echo "Test 11: --force replaces a mispointing symlink"

env_dir="$(make_test_fixture "force-mispointing")"
export HOME="$env_dir/home"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"

# Pre-create a mispointing symlink: role-hash/memory → some unrelated path
role_hash="$(compute_hash "$worktree")"
mkdir -p "$HOME/.claude/projects/$role_hash"
mkdir -p "$env_dir/wrong-target"
ln -s "$env_dir/wrong-target" "$HOME/.claude/projects/$role_hash/memory"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" --force pm "$worktree" >/dev/null 2>&1)
status=$?
assert_equal "0" "$status" "--force on mispointing symlink succeeds"
assert_symlink "$HOME/.claude/projects/$role_hash/memory" "$clone/pm/" "symlink replaced to point at correct role"

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 12: 3rd-arg branch name overrides default <role>/workspace ----
echo ""
echo "Test 12: 3rd-arg branch name overrides default <role>/workspace"

env_dir="$(make_test_fixture "custom-branch")"
export HOME="$env_dir/home"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"
custom_branch="experiment/foo-bar"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree" "$custom_branch" >/dev/null 2>&1)
status=$?
assert_equal "0" "$status" "init succeeds with custom branch"

git -C "$project" show-ref --verify --quiet "refs/heads/$custom_branch"
custom_ok=$?
assert_equal "0" "$custom_ok" "custom branch '$custom_branch' was created"

git -C "$project" show-ref --verify --quiet "refs/heads/pm/workspace"
default_check=$?
assert_equal "1" "$default_check" "default 'pm/workspace' branch was NOT created"

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 13: Init fails when worktree path already exists ----
echo ""
echo "Test 13: Init fails when worktree path already exists"

env_dir="$(make_test_fixture "wt-exists")"
export HOME="$env_dir/home"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"

# Pre-create the worktree path as a regular directory
mkdir -p "$worktree"
echo "stuff" > "$worktree/some-file"

(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree" >/dev/null 2>&1)
status=$?
assert_equal "1" "$status" "init exits non-zero when worktree path already exists"
assert_exists "$worktree/some-file" "pre-existing content was not touched"

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 14: --force on an empty memory dir backs up and replaces ----
# Edge case between Test 5 (real dir with content, no --force, fails) and
# Test 6 (real dir with content, --force, succeeds + backup). Even though
# the source dir is empty, --force still creates a backup-DATE/ marker.
echo ""
echo "Test 14: --force on empty memory dir backs up and replaces with symlink"

env_dir="$(make_test_fixture "force-empty")"
export HOME="$env_dir/home"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"

role_hash="$(compute_hash "$worktree")"
mkdir -p "$HOME/.claude/projects/$role_hash/memory"
# Note: no files inside — empty dir

(cd "$project" && bash "$clone/scripts/init-worktree.sh" --force pm "$worktree" >/dev/null 2>&1)
status=$?
assert_equal "0" "$status" "--force on empty memory dir succeeds"
assert_symlink "$HOME/.claude/projects/$role_hash/memory" "$clone/pm/" "role symlink created"
backup_count=$(find "$HOME/.claude/projects/$role_hash" -maxdepth 1 -name 'memory.backup-*' -type d 2>/dev/null | wc -l)
assert_equal "1" "$(echo "$backup_count" | tr -d ' ')" "backup dir created (even though source was empty)"

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

# ---- Test 15: Re-init fails when worktree is still mounted ----
# Locks in current behavior: the WORKTREE_PATH-exists guard at the top of
# init-worktree.sh fires before any wiring checks, so even a correctly-wired
# worktree can't be re-init'd in place. Test 3 covers the case where the
# worktree was removed between runs (idempotent wiring); this covers the
# subtly different "worktree still mounted" case where init aborts early.
echo ""
echo "Test 15: Re-init fails when worktree is still mounted"

env_dir="$(make_test_fixture "rerun-mounted")"
export HOME="$env_dir/home"
project="$env_dir/project"
clone="$env_dir/clone"
worktree="$env_dir/project-pm"

# First init succeeds
(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree" >/dev/null 2>&1)

# Second init WITHOUT removing the worktree
(cd "$project" && bash "$clone/scripts/init-worktree.sh" pm "$worktree" >/dev/null 2>&1)
status=$?
assert_equal "1" "$status" "re-init with mounted worktree exits non-zero"

# Original wiring should be intact (failed re-init shouldn't have mutated state)
role_hash="$(compute_hash "$worktree")"
assert_symlink "$HOME/.claude/projects/$role_hash/memory" "$clone/pm/" "original symlink still intact after failed re-init"

export HOME="$ORIGINAL_HOME"
cleanup_test_fixture "$env_dir"

print_summary
exit $?
