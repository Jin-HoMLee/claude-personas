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

print_summary
