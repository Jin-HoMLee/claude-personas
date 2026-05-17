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
assert_symlink "$tmp/myapp/.claude/memory" "../../claude-personas-myapp/developer" "memory symlink points to developer/"
assert_exists "$tmp/myapp/.claude/memory/MEMORY.md" "MEMORY.md resolves through symlink"

# memory/ added to .gitignore
if grep -qE '^/?\.claude/memory/?$' "$tmp/myapp/.gitignore" 2>/dev/null; then
  echo "  PASS: .claude/memory/ in .gitignore"
else
  echo "  FAIL: .claude/memory/ not in .gitignore (or .gitignore missing)"
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

# --- --main flag claims no-suffix slot for non-default role ---
echo "=== test_init_clone --main flag ==="
tmp5="$(mktemp -d)"
make_clone_test_fixture "$tmp5"
mv "$tmp5/memory-repo" "$tmp5/claude-personas-myapp"

( cd "$tmp5/claude-personas-myapp" && \
  bash "$INIT_CLONE" pm --main --project-url "$tmp5/project-repo.git" )

assert_exists "$tmp5/myapp" "pm with --main landed at no-suffix path"
assert_symlink "$tmp5/myapp/.claude/memory" "../../claude-personas-myapp/pm" "memory points to pm/"

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
assert_symlink "$tmp6/myapp/.claude/memory" "../../claude-personas-myapp/scientist" "memory points to scientist/"

# Now running developer should NOT claim no-suffix (already taken)
( cd "$tmp6/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --project-url "$tmp6/project-repo.git" )

assert_exists "$tmp6/myapp-developer" "developer fell back to suffixed path"

cleanup_clone_test_fixture "$tmp6"


# --- --force on existing same-project clone rewires memory only ---
echo "=== test_init_clone --force on same-project clone ==="
tmp7="$(mktemp -d)"
make_clone_test_fixture "$tmp7"
mv "$tmp7/memory-repo" "$tmp7/claude-personas-myapp"

# First init creates the clone
( cd "$tmp7/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --project-url "$tmp7/project-repo.git" )

# Break the memory symlink
rm "$tmp7/myapp/.claude/memory"
ln -s /nonexistent "$tmp7/myapp/.claude/memory"

# --force should detect, back up, re-wire
( cd "$tmp7/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --force --project-url "$tmp7/project-repo.git" )

assert_symlink "$tmp7/myapp/.claude/memory" "../../claude-personas-myapp/developer" "memory re-wired"
backup_count="$(find "$tmp7/myapp/.claude" -maxdepth 1 -name "memory.backup-*" | wc -l | tr -d ' ')"
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

count1="$(grep -cE '^\/?\.claude\/memory\/?$' "$tmp10/myapp/.gitignore" || true)"

# Re-run with --force
( cd "$tmp10/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --force --project-url "$tmp10/project-repo.git" )

count2="$(grep -cE '^\/?\.claude\/memory\/?$' "$tmp10/myapp/.gitignore" || true)"
assert_equal "$count1" "$count2" ".claude/memory/ line count unchanged after --force re-run"
assert_equal "1" "$count2" "exactly one .claude/memory/ line in .gitignore"

cleanup_clone_test_fixture "$tmp10"

# --- --main on taken no-suffix path must fail (no silent suffix fallback) ---
echo "=== test_init_clone --main with taken no-suffix path fails hard ==="
tmp11="$(mktemp -d)"
make_clone_test_fixture "$tmp11"
mv "$tmp11/memory-repo" "$tmp11/claude-personas-myapp"

# Block the no-suffix slot with developer first
( cd "$tmp11/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --project-url "$tmp11/project-repo.git" )

# Now pm --main should fail (no-suffix taken, no --force)
if ( cd "$tmp11/claude-personas-myapp" && \
     bash "$INIT_CLONE" pm --main --project-url "$tmp11/project-repo.git" ) 2>/dev/null; then
  echo "  FAIL: --main should have errored when no-suffix path was taken without --force"
  exit 1
else
  echo "  PASS: --main errored when no-suffix path was taken without --force"
fi

# Importantly: pm should NOT have been written to the suffix path
assert_not_exists "$tmp11/myapp-pm" "pm did NOT silently fall back to suffix path"

cleanup_clone_test_fixture "$tmp11"

# --- --target explicit path overrides suffix logic ---
echo "=== test_init_clone --target overrides suffix logic ==="
tmp12="$(mktemp -d)"
make_clone_test_fixture "$tmp12"
mv "$tmp12/memory-repo" "$tmp12/claude-personas-myapp"

custom="$tmp12/custom-clone-path"

( cd "$tmp12/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --target "$custom" --project-url "$tmp12/project-repo.git" )

assert_exists "$custom" "developer landed at --target custom path"
assert_exists "$custom/.git" "--target clone is a real git repo"
assert_symlink "$custom/.claude/memory" "../../claude-personas-myapp/developer" "memory symlink in --target clone"
# Default paths should NOT have been created
assert_not_exists "$tmp12/myapp" "default no-suffix path NOT created when --target given"
assert_not_exists "$tmp12/myapp-developer" "default suffix path NOT created when --target given"

cleanup_clone_test_fixture "$tmp12"

# --- --force on a plain non-git directory at TARGET refuses ---
echo "=== test_init_clone --force on non-git directory refuses ==="
tmp13="$(mktemp -d)"
make_clone_test_fixture "$tmp13"
mv "$tmp13/memory-repo" "$tmp13/claude-personas-myapp"

# Create a plain (non-git) directory at the no-suffix path
mkdir "$tmp13/myapp"
touch "$tmp13/myapp/some-existing-file"

if ( cd "$tmp13/claude-personas-myapp" && \
     bash "$INIT_CLONE" developer --force --project-url "$tmp13/project-repo.git" ) 2>/dev/null; then
  echo "  FAIL: --force should have refused on non-git directory"
  exit 1
else
  echo "  PASS: --force refused non-git directory at TARGET"
fi

# Should not have clobbered the existing file or created a .claude/memory symlink
assert_exists "$tmp13/myapp/some-existing-file" "non-git directory contents preserved"
assert_not_exists "$tmp13/myapp/.claude/memory" ".claude/memory NOT created in refused dir"

cleanup_clone_test_fixture "$tmp13"

print_summary
