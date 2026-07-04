#!/usr/bin/env bash
# Test init-clone.sh happy path for developer (claims no-suffix slot).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
INIT_CLONE="$(cd "$SCRIPT_DIR/.." && pwd)/init-clone.sh"

echo "=== test_init_clone happy path (developer = no-suffix) ==="

tmp="$(mktemp -d)"
make_clone_test_fixture "$tmp"
mkdir -p "$tmp/home"

# Rename memory-repo to claude-personas-myapp to match real naming
mv "$tmp/memory-repo" "$tmp/claude-personas-myapp"

# Run init-clone.sh developer with --project-url
( cd "$tmp/claude-personas-myapp" && \
  HOME="$tmp/home" bash "$INIT_CLONE" developer --project-url "$tmp/project-repo.git" )

assert_exists "$tmp/myapp" "developer clone landed at no-suffix path"
assert_exists "$tmp/myapp/.git" "developer clone is a real git repo"
assert_symlink "$tmp/myapp/.agents/memory" "../../claude-personas-myapp/developer" "vendor-neutral mount points to developer/"
assert_symlink "$tmp/myapp/.claude/memory" "../.agents/memory" "Claude Code hop points to .agents/memory"
assert_exists "$tmp/myapp/.claude/memory/MEMORY.md" "MEMORY.md resolves through the two-hop chain"

# Untracked-ness is behavior, not a .gitignore line: the wired clone must be clean.
if [ -z "$( cd "$tmp/myapp" && git status --porcelain )" ]; then
  echo "  PASS: wired clone is git-clean (exclude entries work)"
else
  echo "  FAIL: wired clone is dirty:"; ( cd "$tmp/myapp" && git status --porcelain )
  exit 1
fi

# .gitignore is no longer touched on a fresh clone.
if [ -f "$tmp/myapp/.gitignore" ] && grep -qE '^/?\.claude/memory/?$' "$tmp/myapp/.gitignore"; then
  echo "  FAIL: .gitignore was modified on a fresh clone (should use .git/info/exclude)"
  exit 1
else
  echo "  PASS: .gitignore not modified on fresh clone"
fi

# Exclude entries present.
for pat in "/.agents/memory" "/.claude/memory"; do
  if grep -qxF "$pat" "$tmp/myapp/.git/info/exclude"; then
    echo "  PASS: $pat in .git/info/exclude"
  else
    echo "  FAIL: $pat missing from .git/info/exclude"
    exit 1
  fi
done

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
mkdir -p "$tmp2/home"
mv "$tmp2/memory-repo" "$tmp2/claude-personas-myapp"

# Unknown role should fail
if ( cd "$tmp2/claude-personas-myapp" && \
     HOME="$tmp2/home" bash "$INIT_CLONE" nonexistentrole --project-url "$tmp2/project-repo.git" ) 2>/dev/null; then
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
mkdir -p "$tmp3/home"
mv "$tmp3/memory-repo" "$tmp3/claude-personas-myapp"

# Pre-seed project.txt with a WRONG url
mkdir -p "$tmp3/claude-personas-myapp/.claude-personas"
echo "/this/does/not/exist.git" > "$tmp3/claude-personas-myapp/.claude-personas/project.txt"

# --project-url flag should override the file
( cd "$tmp3/claude-personas-myapp" && \
  HOME="$tmp3/home" bash "$INIT_CLONE" developer --project-url "$tmp3/project-repo.git" )

assert_exists "$tmp3/myapp" "flag overrode project.txt; clone landed"

# project.txt should NOT be overwritten by the flag (only created if missing)
saved_url="$(cat "$tmp3/claude-personas-myapp/.claude-personas/project.txt")"
assert_equal "/this/does/not/exist.git" "$saved_url" "project.txt preserved (not overwritten by flag)"

cleanup_clone_test_fixture "$tmp3"

# --- URL from project.txt when no flag ---
echo "=== test_init_clone URL from project.txt ==="
tmp4="$(mktemp -d)"
make_clone_test_fixture "$tmp4"
mkdir -p "$tmp4/home"
mv "$tmp4/memory-repo" "$tmp4/claude-personas-myapp"

mkdir -p "$tmp4/claude-personas-myapp/.claude-personas"
echo "$tmp4/project-repo.git" > "$tmp4/claude-personas-myapp/.claude-personas/project.txt"

( cd "$tmp4/claude-personas-myapp" && HOME="$tmp4/home" bash "$INIT_CLONE" pm )

assert_exists "$tmp4/myapp-pm" "URL read from project.txt; pm clone landed (suffixed)"

cleanup_clone_test_fixture "$tmp4"

# --- --main flag claims no-suffix slot for non-default role ---
echo "=== test_init_clone --main flag ==="
tmp5="$(mktemp -d)"
make_clone_test_fixture "$tmp5"
mkdir -p "$tmp5/home"
mv "$tmp5/memory-repo" "$tmp5/claude-personas-myapp"

( cd "$tmp5/claude-personas-myapp" && \
  HOME="$tmp5/home" bash "$INIT_CLONE" pm --main --project-url "$tmp5/project-repo.git" )

assert_exists "$tmp5/myapp" "pm with --main landed at no-suffix path"
assert_symlink "$tmp5/myapp/.agents/memory" "../../claude-personas-myapp/pm" "mount points to pm/"
assert_symlink "$tmp5/myapp/.claude/memory" "../.agents/memory" "hop points to .agents/memory"

cleanup_clone_test_fixture "$tmp5"

# --- main-role.txt overrides default 'developer' ---
echo "=== test_init_clone main-role.txt override ==="
tmp6="$(mktemp -d)"
make_clone_test_fixture "$tmp6"
mkdir -p "$tmp6/home"
mv "$tmp6/memory-repo" "$tmp6/claude-personas-myapp"

mkdir -p "$tmp6/claude-personas-myapp/.claude-personas"
echo "scientist" > "$tmp6/claude-personas-myapp/.claude-personas/main-role.txt"

( cd "$tmp6/claude-personas-myapp" && \
  HOME="$tmp6/home" bash "$INIT_CLONE" scientist --project-url "$tmp6/project-repo.git" )

assert_exists "$tmp6/myapp" "scientist landed at no-suffix path (main-role.txt)"
assert_symlink "$tmp6/myapp/.agents/memory" "../../claude-personas-myapp/scientist" "mount points to scientist/"
assert_symlink "$tmp6/myapp/.claude/memory" "../.agents/memory" "hop points to .agents/memory"

# Now running developer should NOT claim no-suffix (already taken)
( cd "$tmp6/claude-personas-myapp" && \
  HOME="$tmp6/home" bash "$INIT_CLONE" developer --project-url "$tmp6/project-repo.git" )

assert_exists "$tmp6/myapp-developer" "developer fell back to suffixed path"

cleanup_clone_test_fixture "$tmp6"


# --- --force on existing same-project clone rewires memory only ---
echo "=== test_init_clone --force on same-project clone ==="
tmp7="$(mktemp -d)"
make_clone_test_fixture "$tmp7"
mkdir -p "$tmp7/home"
mv "$tmp7/memory-repo" "$tmp7/claude-personas-myapp"

# First init creates the clone
( cd "$tmp7/claude-personas-myapp" && \
  HOME="$tmp7/home" bash "$INIT_CLONE" developer --project-url "$tmp7/project-repo.git" )

# Break the memory symlink
rm "$tmp7/myapp/.claude/memory" "$tmp7/myapp/.agents/memory"
ln -s /nonexistent "$tmp7/myapp/.claude/memory"
ln -s /nonexistent "$tmp7/myapp/.agents/memory"

# --force should detect, back up, re-wire
( cd "$tmp7/claude-personas-myapp" && \
  HOME="$tmp7/home" bash "$INIT_CLONE" developer --force --project-url "$tmp7/project-repo.git" )

assert_symlink "$tmp7/myapp/.agents/memory" "../../claude-personas-myapp/developer" "mount re-wired"
assert_symlink "$tmp7/myapp/.claude/memory" "../.agents/memory" "hop re-wired"
backup_count="$(find "$tmp7/myapp/.claude" -maxdepth 1 -name "memory.backup-*" | wc -l | tr -d ' ')"
assert_equal "1" "$backup_count" "exactly one .claude backup created"
agents_backup_count="$(find "$tmp7/myapp/.agents" -maxdepth 1 -name "memory.backup-*" | wc -l | tr -d ' ')"
assert_equal "1" "$agents_backup_count" "exactly one .agents backup created"

cleanup_clone_test_fixture "$tmp7"

# --- --force on wrong-project clone should fail ---
echo "=== test_init_clone --force on wrong-project clone ==="
tmp8="$(mktemp -d)"
make_clone_test_fixture "$tmp8"
mkdir -p "$tmp8/home"
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
     HOME="$tmp8/home" bash "$INIT_CLONE" developer --force --project-url "$tmp8/project-repo.git" ) 2>/dev/null; then
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
mkdir -p "$tmp9/home"
mv "$tmp9/memory-repo" "$tmp9/claude-personas-myapp"

mkdir "$tmp9/myapp"  # block the no-suffix path

if ( cd "$tmp9/claude-personas-myapp" && \
     HOME="$tmp9/home" bash "$INIT_CLONE" developer --project-url "$tmp9/project-repo.git" ) 2>/dev/null; then
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
mkdir -p "$tmp10/home"
mv "$tmp10/memory-repo" "$tmp10/claude-personas-myapp"

( cd "$tmp10/claude-personas-myapp" && \
  HOME="$tmp10/home" bash "$INIT_CLONE" developer --project-url "$tmp10/project-repo.git" )

count1="$(grep -cxF '/.claude/memory' "$tmp10/myapp/.git/info/exclude" || true)"

# Re-run with --force
( cd "$tmp10/claude-personas-myapp" && \
  HOME="$tmp10/home" bash "$INIT_CLONE" developer --force --project-url "$tmp10/project-repo.git" )

count2="$(grep -cxF '/.claude/memory' "$tmp10/myapp/.git/info/exclude" || true)"
assert_equal "$count1" "$count2" "exclude line count unchanged after --force re-run"
assert_equal "1" "$count2" "exactly one /.claude/memory line in exclude"

cleanup_clone_test_fixture "$tmp10"

# --- --main on taken no-suffix path must fail (no silent suffix fallback) ---
echo "=== test_init_clone --main with taken no-suffix path fails hard ==="
tmp11="$(mktemp -d)"
make_clone_test_fixture "$tmp11"
mkdir -p "$tmp11/home"
mv "$tmp11/memory-repo" "$tmp11/claude-personas-myapp"

# Block the no-suffix slot with developer first
( cd "$tmp11/claude-personas-myapp" && \
  HOME="$tmp11/home" bash "$INIT_CLONE" developer --project-url "$tmp11/project-repo.git" )

# Now pm --main should fail (no-suffix taken, no --force)
if ( cd "$tmp11/claude-personas-myapp" && \
     HOME="$tmp11/home" bash "$INIT_CLONE" pm --main --project-url "$tmp11/project-repo.git" ) 2>/dev/null; then
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
mkdir -p "$tmp12/home"
mv "$tmp12/memory-repo" "$tmp12/claude-personas-myapp"

custom="$tmp12/custom-clone-path"

( cd "$tmp12/claude-personas-myapp" && \
  HOME="$tmp12/home" bash "$INIT_CLONE" developer --target "$custom" --project-url "$tmp12/project-repo.git" )

assert_exists "$custom" "developer landed at --target custom path"
assert_exists "$custom/.git" "--target clone is a real git repo"
assert_symlink "$custom/.agents/memory" "../../claude-personas-myapp/developer" "mount in --target clone"
assert_symlink "$custom/.claude/memory" "../.agents/memory" "hop in --target clone"
# Default paths should NOT have been created
assert_not_exists "$tmp12/myapp" "default no-suffix path NOT created when --target given"
assert_not_exists "$tmp12/myapp-developer" "default suffix path NOT created when --target given"

cleanup_clone_test_fixture "$tmp12"

# --- --force on a plain non-git directory at TARGET refuses ---
echo "=== test_init_clone --force on non-git directory refuses ==="
tmp13="$(mktemp -d)"
make_clone_test_fixture "$tmp13"
mkdir -p "$tmp13/home"
mv "$tmp13/memory-repo" "$tmp13/claude-personas-myapp"

# Create a plain (non-git) directory at the no-suffix path
mkdir "$tmp13/myapp"
touch "$tmp13/myapp/some-existing-file"

if ( cd "$tmp13/claude-personas-myapp" && \
     HOME="$tmp13/home" bash "$INIT_CLONE" developer --force --project-url "$tmp13/project-repo.git" ) 2>/dev/null; then
  echo "  FAIL: --force should have refused on non-git directory"
  exit 1
else
  echo "  PASS: --force refused non-git directory at TARGET"
fi

# Should not have clobbered the existing file or created a .claude/memory symlink
assert_exists "$tmp13/myapp/some-existing-file" "non-git directory contents preserved"
assert_not_exists "$tmp13/myapp/.claude/memory" ".claude/memory NOT created in refused dir"

cleanup_clone_test_fixture "$tmp13"

# --- v3.0 -> v3.1 migration via --force ---
echo "=== test_init_clone v3.0 -> v3.1 migration ==="
tmp14="$(mktemp -d)"
make_clone_test_fixture "$tmp14"
mkdir -p "$tmp14/home"
mv "$tmp14/memory-repo" "$tmp14/claude-personas-myapp"

# Arrange: clone the project, then plant a LEGACY v3.0 layout by hand
# (root-level memory/ symlink + /memory/ gitignore line)
git clone --quiet "$tmp14/project-repo.git" "$tmp14/myapp"
ln -s "../claude-personas-myapp/developer" "$tmp14/myapp/memory"
printf "\n# legacy v3.0 marker\n/memory/\n" >> "$tmp14/myapp/.gitignore"

# Act: run --force, which should detect the legacy layout and migrate
( cd "$tmp14/claude-personas-myapp" && \
  HOME="$tmp14/home" bash "$INIT_CLONE" developer --force --project-url "$tmp14/project-repo.git" )

# Assert: new layout exists
assert_symlink "$tmp14/myapp/.agents/memory" "../../claude-personas-myapp/developer" "new mount created"
assert_symlink "$tmp14/myapp/.claude/memory" "../.agents/memory" "new hop created"
assert_exists "$tmp14/myapp/.claude/memory/MEMORY.md" "MEMORY.md resolves through new symlink"

# Assert: legacy root symlink removed
assert_not_exists "$tmp14/myapp/memory" "legacy root memory/ symlink removed"

# Assert: legacy /memory/ line removed from .gitignore
if grep -qE '^/?memory/?$' "$tmp14/myapp/.gitignore"; then
  echo "  FAIL: legacy /memory/ line still in .gitignore"
  exit 1
else
  echo "  PASS: legacy /memory/ line removed from .gitignore"
fi

# Exclude entries present (replaces the old .gitignore-line assertion).
for pat in "/.agents/memory" "/.claude/memory"; do
  if grep -qxF "$pat" "$tmp14/myapp/.git/info/exclude"; then
    echo "  PASS: $pat in .git/info/exclude"
  else
    echo "  FAIL: $pat missing from .git/info/exclude"
    exit 1
  fi
done

cleanup_clone_test_fixture "$tmp14"

# --- v3.0 -> v3.1 migration when .gitignore contains ONLY the legacy line ---
echo "=== test_init_clone v3.0 -> v3.1 migration, single-line .gitignore ==="
tmp15="$(mktemp -d)"
make_clone_test_fixture "$tmp15"
mkdir -p "$tmp15/home"
mv "$tmp15/memory-repo" "$tmp15/claude-personas-myapp"

# Arrange: clone the project, plant the v3.0 layout, but make .gitignore
# contain ONLY the legacy /memory/ line (no other content).
git clone --quiet "$tmp15/project-repo.git" "$tmp15/myapp"
ln -s "../claude-personas-myapp/developer" "$tmp15/myapp/memory"
printf "/memory/\n" > "$tmp15/myapp/.gitignore"

# Act
( cd "$tmp15/claude-personas-myapp" && \
  HOME="$tmp15/home" bash "$INIT_CLONE" developer --force --project-url "$tmp15/project-repo.git" )

# Assert legacy /memory/ removed from .gitignore (regression: grep -v exited 1
# when no lines survived, the && short-circuited mv, silently leaving the line)
if grep -qE '^/?memory/?$' "$tmp15/myapp/.gitignore"; then
  echo "  FAIL: legacy /memory/ still present in single-line .gitignore after --force"
  exit 1
else
  echo "  PASS: legacy /memory/ removed from single-line .gitignore"
fi

# Exclude entries present (replaces the old .gitignore-line assertion).
for pat in "/.agents/memory" "/.claude/memory"; do
  if grep -qxF "$pat" "$tmp15/myapp/.git/info/exclude"; then
    echo "  PASS: $pat in .git/info/exclude"
  else
    echo "  FAIL: $pat missing from .git/info/exclude"
    exit 1
  fi
done

# Assert no orphaned .gitignore.tmp file
assert_not_exists "$tmp15/myapp/.gitignore.tmp" ".gitignore.tmp cleaned up"

cleanup_clone_test_fixture "$tmp15"

# --- rollback: fresh clone removed if ln -s fails (issue #7) ---
echo "=== test_init_clone rollback on ln -s failure (fresh clone) ==="
tmp16="$(mktemp -d)"
make_clone_test_fixture "$tmp16"
mkdir -p "$tmp16/home"
mv "$tmp16/memory-repo" "$tmp16/claude-personas-myapp"

# Inject an ln failure via a PATH shim. This simulates the race/permission
# failure the spec's error-table row guards against. NOTE: the issue body's
# suggested injection — pre-creating the symlink target as a file — would trip
# the pre-existing -e guard (MEMORY_LINK already exists) and exit BEFORE
# reaching ln -s, so a PATH shim is the correct way to exercise that line.
shimbin16="$tmp16/shim-bin"
mkdir -p "$shimbin16"
printf '#!/usr/bin/env bash\necho "ln: simulated failure (test shim)" >&2\nexit 1\n' > "$shimbin16/ln"
chmod +x "$shimbin16/ln"

if ( cd "$tmp16/claude-personas-myapp" && \
     HOME="$tmp16/home" PATH="$shimbin16:$PATH" bash "$INIT_CLONE" developer --project-url "$tmp16/project-repo.git" ) 2>/dev/null; then
  echo "  FAIL: should have exited nonzero when ln -s failed"
  exit 1
else
  echo "  PASS: exited nonzero when ln -s failed"
fi

# The freshly-created clone must be rolled back (spec: "rollback by removing
# the target clone if we created it this run").
assert_not_exists "$tmp16/myapp" "fresh clone rolled back after ln -s failure"

cleanup_clone_test_fixture "$tmp16"

# --- rollback safety: --force must NOT delete a pre-existing clone (issue #7) ---
echo "=== test_init_clone rollback safety: --force preserves existing clone on ln -s failure ==="
tmp17="$(mktemp -d)"
make_clone_test_fixture "$tmp17"
mkdir -p "$tmp17/home"
mv "$tmp17/memory-repo" "$tmp17/claude-personas-myapp"

# First, create the clone normally (real ln).
( cd "$tmp17/claude-personas-myapp" && \
  HOME="$tmp17/home" bash "$INIT_CLONE" developer --project-url "$tmp17/project-repo.git" )
assert_exists "$tmp17/myapp/.git" "precondition: clone created in first run"

# Re-run with --force but inject an ln failure. Because the clone was NOT
# created this run, rollback must NOT remove it.
shimbin17="$tmp17/shim-bin"
mkdir -p "$shimbin17"
printf '#!/usr/bin/env bash\necho "ln: simulated failure (test shim)" >&2\nexit 1\n' > "$shimbin17/ln"
chmod +x "$shimbin17/ln"

if ( cd "$tmp17/claude-personas-myapp" && \
     HOME="$tmp17/home" PATH="$shimbin17:$PATH" bash "$INIT_CLONE" developer --force --project-url "$tmp17/project-repo.git" ) 2>/dev/null; then
  echo "  FAIL: --force should have exited nonzero when ln -s failed"
  exit 1
else
  echo "  PASS: --force exited nonzero when ln -s failed"
fi

# The user's pre-existing clone must be preserved (we did not create it this run).
assert_exists "$tmp17/myapp" "pre-existing clone preserved on --force ln -s failure"
assert_exists "$tmp17/myapp/.git" "pre-existing clone's .git preserved"

cleanup_clone_test_fixture "$tmp17"

# --- rollback: fresh clone removed if mkdir of .claude fails (issue #7) ---
# The post-clone wiring window is more than just `ln -s`: `mkdir -p .claude`
# runs first and can also fail under `set -e`, leaving an unwired clone. Guard
# the whole window, not only the symlink.
echo "=== test_init_clone rollback on mkdir failure (fresh clone) ==="
tmp18="$(mktemp -d)"
make_clone_test_fixture "$tmp18"
mkdir -p "$tmp18/home"
mv "$tmp18/memory-repo" "$tmp18/claude-personas-myapp"

# Inject a failure when the script creates the .claude wiring dir, AFTER the
# clone succeeds. The shim fails ONLY for a path ending in /.claude and
# delegates everything else to the real mkdir, so git clone (which does not
# shell out to /bin/mkdir for local clones anyway) and any other setup still
# work — guaranteeing the clone is created before the failure (no false green).
shimbin18="$tmp18/shim-bin"
mkdir -p "$shimbin18"
cat > "$shimbin18/mkdir" <<'SHIM'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    */.claude) echo "mkdir: simulated failure (test shim)" >&2; exit 1 ;;
  esac
done
exec /bin/mkdir "$@"
SHIM
chmod +x "$shimbin18/mkdir"

if ( cd "$tmp18/claude-personas-myapp" && \
     HOME="$tmp18/home" PATH="$shimbin18:$PATH" bash "$INIT_CLONE" developer --project-url "$tmp18/project-repo.git" ) 2>/dev/null; then
  echo "  FAIL: should have exited nonzero when mkdir of .claude failed"
  exit 1
else
  echo "  PASS: exited nonzero when mkdir of .claude failed"
fi

# Rolled back even though it was the mkdir (not the ln -s) that failed.
assert_not_exists "$tmp18/myapp" "fresh clone rolled back after mkdir failure"

cleanup_clone_test_fixture "$tmp18"

# --- rollback: fresh clone removed if the CLONED repo already ships
# .claude/memory, hitting the "already exists" exit before ln -s (issue #7) ---
# This exit is reachable only on a fresh clone (with FORCE=0, an existing
# target would have exited earlier), so it must also roll back. Found by the
# @claude review on PR #22; no PATH shim needed — the collision is real.
echo "=== test_init_clone rollback when cloned repo ships .claude/memory (fresh clone) ==="
tmp19="$(mktemp -d)"
make_clone_test_fixture "$tmp19"
mkdir -p "$tmp19/home"
mv "$tmp19/memory-repo" "$tmp19/claude-personas-myapp"

# Make the PROJECT repo ship a committed .claude/memory (uncommon but legal).
seed19="$(mktemp -d)"
git clone --quiet "$tmp19/project-repo.git" "$seed19"
mkdir -p "$seed19/.claude"
echo "pre-existing" > "$seed19/.claude/memory"
( cd "$seed19" && \
  git -c user.email=t@x -c user.name=T add -A && \
  git -c user.email=t@x -c user.name=T commit --quiet -m "ship .claude/memory" && \
  git push --quiet origin HEAD )
rm -rf "$seed19"

# Fresh, non--force run: clone succeeds, mkdir .claude succeeds (it exists from
# the clone), then MEMORY_LINK already exists → script errors. The
# freshly-created clone must still be rolled back.
if ( cd "$tmp19/claude-personas-myapp" && \
     HOME="$tmp19/home" bash "$INIT_CLONE" developer --project-url "$tmp19/project-repo.git" ) 2>/dev/null; then
  echo "  FAIL: should have exited nonzero when cloned repo already has .claude/memory"
  exit 1
else
  echo "  PASS: exited nonzero when cloned repo already has .claude/memory"
fi

assert_not_exists "$tmp19/myapp" "fresh clone rolled back when .claude/memory pre-exists in the clone"

cleanup_clone_test_fixture "$tmp19"

print_summary
