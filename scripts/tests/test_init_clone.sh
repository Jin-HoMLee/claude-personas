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
     HOME="$tmp9/home" bash "$INIT_CLONE" developer --project-url "$tmp9/project-repo.git" ) 2>/dev/null || [ $? -eq 2 ]; then
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

# --- external Claude Code hop created under $HOME/.claude/projects (spec: CC adapter) ---
echo "=== test_init_clone external CC hop ==="
tmp20="$(mktemp -d)"
make_clone_test_fixture "$tmp20"
mv "$tmp20/memory-repo" "$tmp20/claude-personas-myapp"
mkdir -p "$tmp20/home"

( cd "$tmp20/claude-personas-myapp" && \
  HOME="$tmp20/home" bash "$INIT_CLONE" developer --project-url "$tmp20/project-repo.git" )

clone_abs="$(cd "$tmp20/myapp" && pwd -P)"
slug="$(compute_hash "$clone_abs")"
ext="$tmp20/home/.claude/projects/$slug/memory"
assert_symlink "$ext" "$clone_abs/.claude/memory" "external hop points at the clone's .claude/memory"
assert_exists "$ext/MEMORY.md" "MEMORY.md resolves through the external hop"

cleanup_clone_test_fixture "$tmp20"

# --- external hop: real directory with content is refused but script continues ---
echo "=== test_init_clone external CC hop refuses real dir with content ==="
tmp21="$(mktemp -d)"
make_clone_test_fixture "$tmp21"
mv "$tmp21/memory-repo" "$tmp21/claude-personas-myapp"
mkdir -p "$tmp21/home"

# Pre-create the slug dir as a REAL directory with content. The slug depends
# on the clone path, which is deterministic: $tmp21/myapp.
predicted_slug="$(compute_hash "$(cd "$tmp21" && pwd -P)/myapp")"
mkdir -p "$tmp21/home/.claude/projects/$predicted_slug/memory"
echo "user data" > "$tmp21/home/.claude/projects/$predicted_slug/memory/user_note.md"

# This file deliberately runs without errexit (set -uo pipefail only), so the
# failing subshell doesn't abort the run and $? can be captured directly.
( cd "$tmp21/claude-personas-myapp" && \
  HOME="$tmp21/home" bash "$INIT_CLONE" developer --project-url "$tmp21/project-repo.git" ) 2>"$tmp21/stderr.log"
status=$?
assert_equal "2" "$status" "exits 2 when a vendor warning fired"
if grep -q "WARN:" "$tmp21/stderr.log"; then
  echo "  PASS: WARN emitted for real dir with content"
else
  echo "  FAIL: no WARN emitted"; exit 1
fi
assert_exists "$tmp21/home/.claude/projects/$predicted_slug/memory/user_note.md" "real dir content untouched"
# Core mount must still be wired despite the vendor warning.
assert_symlink "$tmp21/myapp/.agents/memory" "../../claude-personas-myapp/developer" "core mount wired despite CC warning"

cleanup_clone_test_fixture "$tmp21"

# --- external hop: wrong existing symlink is repaired ---
echo "=== test_init_clone external CC hop repairs wrong symlink ==="
tmp22="$(mktemp -d)"
make_clone_test_fixture "$tmp22"
mv "$tmp22/memory-repo" "$tmp22/claude-personas-myapp"
mkdir -p "$tmp22/home"

predicted_slug22="$(compute_hash "$(cd "$tmp22" && pwd -P)/myapp")"
mkdir -p "$tmp22/home/.claude/projects/$predicted_slug22"
ln -s /nonexistent "$tmp22/home/.claude/projects/$predicted_slug22/memory"

( cd "$tmp22/claude-personas-myapp" && \
  HOME="$tmp22/home" bash "$INIT_CLONE" developer --project-url "$tmp22/project-repo.git" )

clone_abs22="$(cd "$tmp22/myapp" && pwd -P)"
assert_symlink "$tmp22/home/.claude/projects/$predicted_slug22/memory" "$clone_abs22/.claude/memory" "wrong external symlink repaired"

cleanup_clone_test_fixture "$tmp22"

# --- Codex adapter: generated per-clone hooks.json (spec: Codex adapter) ---
echo "=== test_init_clone Codex hooks.json generation ==="
tmp23="$(mktemp -d)"
make_clone_test_fixture "$tmp23"
mv "$tmp23/memory-repo" "$tmp23/claude-personas-myapp"
mkdir -p "$tmp23/home"
# The inject script ships in the memory repo's scripts/ (template convention).
mkdir -p "$tmp23/claude-personas-myapp/scripts"
cp "$(cd "$SCRIPT_DIR/.." && pwd)/inject-role-index.sh" "$tmp23/claude-personas-myapp/scripts/"
chmod +x "$tmp23/claude-personas-myapp/scripts/inject-role-index.sh"

( cd "$tmp23/claude-personas-myapp" && \
  HOME="$tmp23/home" bash "$INIT_CLONE" developer --project-url "$tmp23/project-repo.git" )

hooks="$tmp23/myapp/.codex/hooks.json"
assert_exists "$hooks" ".codex/hooks.json generated"
if jq -e . "$hooks" >/dev/null 2>&1; then
  echo "  PASS: hooks.json is valid JSON"
else
  echo "  FAIL: hooks.json is not valid JSON"; exit 1
fi
cmd="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$hooks")"
# NOTE: pwd (not pwd -P) - matches how init-clone.sh derives MEMORY_REPO
# (plain `pwd` at script top). Using -P here would diverge on macOS, where
# $TMPDIR (/var/folders/...) is itself a symlink to /private/var/folders/...;
# the two forms are equally valid, OS-resolved paths, not a functional bug.
memrepo_abs="$(cd "$tmp23/claude-personas-myapp" && pwd)"
assert_equal "'$memrepo_abs/scripts/inject-role-index.sh' '$memrepo_abs/developer'" "$cmd" "hook command calls inject script with the role dir"
if grep -qxF "/.codex/hooks.json" "$tmp23/myapp/.git/info/exclude"; then
  echo "  PASS: /.codex/hooks.json in exclude"
else
  echo "  FAIL: /.codex/hooks.json missing from exclude"; exit 1
fi

cleanup_clone_test_fixture "$tmp23"

# --- Codex adapter: missing inject script warns but does not kill other wiring ---
echo "=== test_init_clone Codex warns when inject script missing ==="
tmp24="$(mktemp -d)"
make_clone_test_fixture "$tmp24"
mv "$tmp24/memory-repo" "$tmp24/claude-personas-myapp"
mkdir -p "$tmp24/home"
# NOTE: no scripts/inject-role-index.sh in this fixture memory repo.

( cd "$tmp24/claude-personas-myapp" && \
  HOME="$tmp24/home" bash "$INIT_CLONE" developer --project-url "$tmp24/project-repo.git" ) 2>"$tmp24/stderr.log"
status=$?
assert_equal "2" "$status" "exits 2 on Codex warning"
if grep -q "WARN: Codex" "$tmp24/stderr.log"; then
  echo "  PASS: Codex WARN emitted"
else
  echo "  FAIL: no Codex WARN"; exit 1
fi
assert_not_exists "$tmp24/myapp/.codex/hooks.json" "hooks.json not generated without inject script"
assert_symlink "$tmp24/myapp/.agents/memory" "../../claude-personas-myapp/developer" "core mount still wired"

cleanup_clone_test_fixture "$tmp24"

# --- Codex adapter: pre-existing hooks.json is preserved without --force, regenerated with it ---
echo "=== test_init_clone Codex hooks.json overwrite policy ==="
tmp25="$(mktemp -d)"
make_clone_test_fixture "$tmp25"
mv "$tmp25/memory-repo" "$tmp25/claude-personas-myapp"
mkdir -p "$tmp25/home"
mkdir -p "$tmp25/claude-personas-myapp/scripts"
cp "$(cd "$SCRIPT_DIR/.." && pwd)/inject-role-index.sh" "$tmp25/claude-personas-myapp/scripts/"
chmod +x "$tmp25/claude-personas-myapp/scripts/inject-role-index.sh"

( cd "$tmp25/claude-personas-myapp" && \
  HOME="$tmp25/home" bash "$INIT_CLONE" developer --project-url "$tmp25/project-repo.git" )
# Simulate a user-customized hooks.json.
echo '{"hooks":{}}' > "$tmp25/myapp/.codex/hooks.json"

( cd "$tmp25/claude-personas-myapp" && \
  HOME="$tmp25/home" bash "$INIT_CLONE" developer --project-url "$tmp25/project-repo.git" ) >/dev/null 2>&1 || true
assert_equal '{"hooks":{}}' "$(cat "$tmp25/myapp/.codex/hooks.json")" "non---force run preserved custom hooks.json"

( cd "$tmp25/claude-personas-myapp" && \
  HOME="$tmp25/home" bash "$INIT_CLONE" developer --force --project-url "$tmp25/project-repo.git" )
cmd25="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$tmp25/myapp/.codex/hooks.json")"
case "$cmd25" in *inject-role-index.sh*) echo "  PASS: --force regenerated hooks.json";; *) echo "  FAIL: --force did not regenerate"; exit 1;; esac
backup25="$(find "$tmp25/myapp/.codex" -maxdepth 1 -name "hooks.json.backup-*" | wc -l | tr -d ' ')"
assert_equal "1" "$backup25" "custom hooks.json backed up on --force"

cleanup_clone_test_fixture "$tmp25"

# --- Codex adapter: project repo SHIPS a committed .codex/hooks.json -> the
# function's own "already exists" WARN branch fires on a FRESH clone (no
# --force). This is the only real-world path to that branch: a plain re-run
# hits init-clone's earlier generic "target already exists" exit 1 and never
# reaches wire_codex_adapter (same reachability shape as tmp19's seeded
# .claude/memory collision). ---
echo "=== test_init_clone Codex WARN when cloned repo ships .codex/hooks.json ==="
tmp26="$(mktemp -d)"
make_clone_test_fixture "$tmp26"
mv "$tmp26/memory-repo" "$tmp26/claude-personas-myapp"
mkdir -p "$tmp26/home"
# Codex adapter is otherwise wireable: inject script present in the memory repo.
mkdir -p "$tmp26/claude-personas-myapp/scripts"
cp "$(cd "$SCRIPT_DIR/.." && pwd)/inject-role-index.sh" "$tmp26/claude-personas-myapp/scripts/"
chmod +x "$tmp26/claude-personas-myapp/scripts/inject-role-index.sh"

# Make the PROJECT repo ship a committed .codex/hooks.json (uncommon but legal).
seed26="$(mktemp -d)"
git clone --quiet "$tmp26/project-repo.git" "$seed26"
mkdir -p "$seed26/.codex"
echo '{"hooks":{}}' > "$seed26/.codex/hooks.json"
( cd "$seed26" && \
  git -c user.email=t@x -c user.name=T add -A && \
  git -c user.email=t@x -c user.name=T commit --quiet -m "ship .codex/hooks.json" && \
  git push --quiet origin HEAD )
rm -rf "$seed26"

# Fresh, non---force run: everything else wires fine, but wire_codex_adapter's
# own guard must WARN and preserve the shipped file, not regenerate it.
( cd "$tmp26/claude-personas-myapp" && \
  HOME="$tmp26/home" bash "$INIT_CLONE" developer --project-url "$tmp26/project-repo.git" ) \
  >"$tmp26/stdout.log" 2>"$tmp26/stderr.log"
status=$?
assert_equal "2" "$status" "exits 2 on Codex already-exists warning"
if grep -q "WARN: Codex" "$tmp26/stderr.log" && grep -q "already exists" "$tmp26/stderr.log"; then
  echo "  PASS: Codex already-exists WARN emitted"
else
  echo "  FAIL: no Codex already-exists WARN"; exit 1
fi
assert_equal '{"hooks":{}}' "$(cat "$tmp26/myapp/.codex/hooks.json")" "shipped hooks.json preserved, not regenerated"
# Sanity: the success path must NOT have run (would print the Generated line).
if grep -q "Generated .codex/hooks.json" "$tmp26/stdout.log"; then
  echo "  FAIL: hooks.json was (re)generated despite pre-existing file"; exit 1
else
  echo "  PASS: no 'Generated .codex/hooks.json' line (WARN branch taken)"
fi
assert_symlink "$tmp26/myapp/.agents/memory" "../../claude-personas-myapp/developer" "core mount still wired"

cleanup_clone_test_fixture "$tmp26"

# --- OpenCode: default prints the one-time global step, writes no per-clone file ---
echo "=== test_init_clone OpenCode default (global instructions note) ==="
tmp27="$(mktemp -d)"
make_clone_test_fixture "$tmp27"
mv "$tmp27/memory-repo" "$tmp27/claude-personas-myapp"
mkdir -p "$tmp27/home"

out27="$( cd "$tmp27/claude-personas-myapp" && \
  HOME="$tmp27/home" bash "$INIT_CLONE" developer --project-url "$tmp27/project-repo.git" 2>/dev/null )" || true
assert_not_exists "$tmp27/myapp/opencode.json" "no per-clone opencode.json by default"
case "$out27" in
  *".agents/memory/MEMORY.md"*opencode*|*opencode*".agents/memory/MEMORY.md"*)
    echo "  PASS: one-time global OpenCode step printed";;
  *) echo "  FAIL: global OpenCode step not printed"; exit 1;;
esac

cleanup_clone_test_fixture "$tmp27"

# --- OpenCode: --opencode-per-clone writes the absolute-path fallback ---
echo "=== test_init_clone OpenCode per-clone fallback ==="
tmp28="$(mktemp -d)"
make_clone_test_fixture "$tmp28"
mv "$tmp28/memory-repo" "$tmp28/claude-personas-myapp"
mkdir -p "$tmp28/home"

( cd "$tmp28/claude-personas-myapp" && \
  HOME="$tmp28/home" bash "$INIT_CLONE" developer --opencode-per-clone --project-url "$tmp28/project-repo.git" ) || [ $? -eq 2 ]

oc="$tmp28/myapp/opencode.json"
assert_exists "$oc" "per-clone opencode.json written"
clone_abs28="$(cd "$tmp28/myapp" && pwd -P)"
got="$(jq -r '.instructions[0]' "$oc")"
assert_equal "$clone_abs28/.agents/memory/MEMORY.md" "$got" "instructions entry is the absolute resolved path"
if grep -qxF "/opencode.json" "$tmp28/myapp/.git/info/exclude"; then
  echo "  PASS: /opencode.json in exclude"
else
  echo "  FAIL: /opencode.json missing from exclude"; exit 1
fi

cleanup_clone_test_fixture "$tmp28"

# --- JSON writers refuse quote/backslash paths (refuse-and-warn, no escaper) ---
# Both JSON writers embed paths verbatim: Codex embeds the MEMORY REPO's
# inject-script + role-dir paths, OpenCode embeds the CLONE's absolute path.
# A weird --target alone would never reach the Codex guard (its embedded
# strings come from the memory repo, not the clone), so the WHOLE fixture
# lives under a quote-bearing parent - that makes both guards fire.
echo "=== test_init_clone JSON writers refuse quote/backslash paths ==="
tmp29="$(mktemp -d)"
weird29="$tmp29/we\"ird"
mkdir -p "$weird29"
make_clone_test_fixture "$weird29"
mv "$weird29/memory-repo" "$weird29/claude-personas-myapp"
mkdir -p "$weird29/home"
# Codex adapter is otherwise wireable: inject script present in the memory repo.
mkdir -p "$weird29/claude-personas-myapp/scripts"
cp "$(cd "$SCRIPT_DIR/.." && pwd)/inject-role-index.sh" "$weird29/claude-personas-myapp/scripts/"
chmod +x "$weird29/claude-personas-myapp/scripts/inject-role-index.sh"

weird_clone29="$weird29/we\"ird-clone"
( cd "$weird29/claude-personas-myapp" && \
  HOME="$weird29/home" bash "$INIT_CLONE" developer --opencode-per-clone \
    --target "$weird_clone29" --project-url "$weird29/project-repo.git" ) \
  >"$tmp29/stdout.log" 2>"$tmp29/stderr.log"
status=$?
assert_equal "2" "$status" "exits 2 when JSON writers refuse quote-bearing paths"
if grep -q "WARN:.*quote or backslash" "$tmp29/stderr.log"; then
  echo "  PASS: WARN mentions quote/backslash"
else
  echo "  FAIL: no quote/backslash WARN"; exit 1
fi
assert_not_exists "$weird_clone29/.codex/hooks.json" "no hooks.json written for quote-bearing memory-repo path"
assert_not_exists "$weird_clone29/opencode.json" "no opencode.json written for quote-bearing clone path"
# Symlinks don't care about quotes: the core mount must still be wired.
assert_symlink "$weird_clone29/.agents/memory" "../../claude-personas-myapp/developer" "core mount wired despite quote-bearing paths"

cleanup_clone_test_fixture "$tmp29"

# --- v3.1 -> two-hop migration via --force (spec: CC adapter, last paragraph) ---
echo "=== test_init_clone v3.1 -> two-hop migration ==="
tmp30="$(mktemp -d)"
make_clone_test_fixture "$tmp30"
mv "$tmp30/memory-repo" "$tmp30/claude-personas-myapp"
mkdir -p "$tmp30/home"

# Plant a v3.1-shaped clone BY HAND: direct .claude/memory symlink + gitignore line.
git clone --quiet "$tmp30/project-repo.git" "$tmp30/myapp"
mkdir -p "$tmp30/myapp/.claude"
ln -s "../../claude-personas-myapp/developer" "$tmp30/myapp/.claude/memory"
printf "\n# claude-personas role-memory symlink\n/.claude/memory/\n" >> "$tmp30/myapp/.gitignore"

( cd "$tmp30/claude-personas-myapp" && \
  HOME="$tmp30/home" bash "$INIT_CLONE" developer --force --project-url "$tmp30/project-repo.git" ) || [ $? -eq 2 ]

assert_symlink "$tmp30/myapp/.agents/memory" "../../claude-personas-myapp/developer" "mount created on migration"
assert_symlink "$tmp30/myapp/.claude/memory" "../.agents/memory" "direct v3.1 symlink rewired into the hop"
assert_exists "$tmp30/myapp/.claude/memory/MEMORY.md" "MEMORY.md resolves after migration"
mig_backup="$(find "$tmp30/myapp/.claude" -maxdepth 1 -name "memory.backup-*" | wc -l | tr -d ' ')"
assert_equal "1" "$mig_backup" "old direct symlink backed up (existing backup semantics)"

# Existing v3.1 .gitignore line is LEFT ALONE (spec: "keep working; stop adding").
if grep -qE '^/?\.claude/memory/?$' "$tmp30/myapp/.gitignore"; then
  echo "  PASS: existing v3.1 .gitignore line preserved"
else
  echo "  FAIL: v3.1 .gitignore line was removed"; exit 1
fi

# External hop created for the migrated clone too.
mig_slug="$(compute_hash "$(cd "$tmp30/myapp" && pwd -P)")"
assert_exists "$tmp30/home/.claude/projects/$mig_slug/memory" "external hop created on migration"

cleanup_clone_test_fixture "$tmp30"

# --- --self: wire the memory repo itself as the Memory Manager workspace (issue #39) ---
# The MM's identity is DECLARED like every role's: an untracked self-mount
# .agents/memory -> ../memory_manager (relative to .agents/, so it resolves to
# the repo's own memory_manager/ dir), never inferred from repo shape.
echo "=== test_init_clone --self happy path (MM self-mount) ==="
tmp31="$(mktemp -d)"
make_clone_test_fixture "$tmp31"
mkdir -p "$tmp31/home"
mv "$tmp31/memory-repo" "$tmp31/claude-personas-myapp"

# Add a real memory_manager role dir (MM is a role like any other) and the
# inject script, committed so the git-clean assertion below is meaningful.
mkdir -p "$tmp31/claude-personas-myapp/memory_manager"
printf "# Memory Index - memory_manager\n" > "$tmp31/claude-personas-myapp/memory_manager/MEMORY.md"
( cd "$tmp31/claude-personas-myapp/memory_manager" && ln -s ../shared shared )
mkdir -p "$tmp31/claude-personas-myapp/scripts"
cp "$(cd "$SCRIPT_DIR/.." && pwd)/inject-role-index.sh" "$tmp31/claude-personas-myapp/scripts/"
chmod +x "$tmp31/claude-personas-myapp/scripts/inject-role-index.sh"
( cd "$tmp31/claude-personas-myapp" && \
  git -c user.email=t@x -c user.name=T add -A && \
  git -c user.email=t@x -c user.name=T commit --quiet -m "add memory_manager role" )

( cd "$tmp31/claude-personas-myapp" && \
  HOME="$tmp31/home" bash "$INIT_CLONE" --self )
status=$?
assert_equal "0" "$status" "--self exits 0 on full wiring"

memrepo31="$tmp31/claude-personas-myapp"
assert_symlink "$memrepo31/.agents/memory" "../memory_manager" "self-mount points at the repo's own memory_manager/"
assert_symlink "$memrepo31/.claude/memory" "../.agents/memory" "Claude Code hop wired in the memory repo"
assert_exists "$memrepo31/.claude/memory/MEMORY.md" "MEMORY.md resolves through the self-mount chain"

# Untracked-ness: the wired memory repo must be git-clean.
if [ -z "$( cd "$memrepo31" && git status --porcelain )" ]; then
  echo "  PASS: wired memory repo is git-clean (exclude entries work)"
else
  echo "  FAIL: wired memory repo is dirty:"; ( cd "$memrepo31" && git status --porcelain )
  exit 1
fi
for pat in "/.agents/memory" "/.claude/memory" "/.codex/hooks.json"; do
  if grep -qxF "$pat" "$memrepo31/.git/info/exclude"; then
    echo "  PASS: $pat in .git/info/exclude"
  else
    echo "  FAIL: $pat missing from .git/info/exclude"
    exit 1
  fi
done

# External CC hop points at the MEMORY REPO's .claude/memory.
memrepo31_abs="$(cd "$memrepo31" && pwd -P)"
slug31="$(compute_hash "$memrepo31_abs")"
ext31="$tmp31/home/.claude/projects/$slug31/memory"
assert_symlink "$ext31" "$memrepo31_abs/.claude/memory" "external hop points at the memory repo's .claude/memory"
assert_exists "$ext31/MEMORY.md" "MEMORY.md resolves through the external hop"

# Codex adapter targets the memory_manager role dir.
hooks31="$memrepo31/.codex/hooks.json"
assert_exists "$hooks31" ".codex/hooks.json generated in the memory repo"
if jq -e . "$hooks31" >/dev/null 2>&1; then
  echo "  PASS: hooks.json is valid JSON"
else
  echo "  FAIL: hooks.json is not valid JSON"; exit 1
fi
memrepo31_pwd="$(cd "$memrepo31" && pwd)"
cmd31="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$hooks31")"
assert_equal "'$memrepo31_pwd/scripts/inject-role-index.sh' '$memrepo31_pwd/memory_manager'" "$cmd31" "hook command injects the memory_manager index"

# No clone-mode side effects: nothing cloned, no project.txt invented.
assert_not_exists "$tmp31/myapp" "no clone created by --self"
assert_not_exists "$tmp31/myapp-memory_manager" "no suffixed clone created by --self"
assert_not_exists "$memrepo31/.claude-personas/project.txt" "no project.txt created by --self"

cleanup_clone_test_fixture "$tmp31"

# --- --self without a memory_manager/ role dir must fail, wiring nothing ---
echo "=== test_init_clone --self requires memory_manager role dir ==="
tmp32="$(mktemp -d)"
make_clone_test_fixture "$tmp32"
mkdir -p "$tmp32/home"
mv "$tmp32/memory-repo" "$tmp32/claude-personas-myapp"
# NOTE: fixture has developer/pm/scientist/designer but NO memory_manager.

if ( cd "$tmp32/claude-personas-myapp" && \
     HOME="$tmp32/home" bash "$INIT_CLONE" --self ) 2>/dev/null; then
  echo "  FAIL: --self should exit nonzero without memory_manager/"
  exit 1
else
  echo "  PASS: --self rejected without memory_manager/ role dir"
fi
assert_not_exists "$tmp32/claude-personas-myapp/.agents/memory" "no self-mount created on refusal"
assert_exists "$tmp32/claude-personas-myapp/.git" "memory repo untouched on refusal"

cleanup_clone_test_fixture "$tmp32"

# --- --self flag/role incompatibilities; bare memory_manager role arg redirects to --self ---
echo "=== test_init_clone --self incompatibilities ==="
tmp33="$(mktemp -d)"
make_clone_test_fixture "$tmp33"
mkdir -p "$tmp33/home"
mv "$tmp33/memory-repo" "$tmp33/claude-personas-myapp"
mkdir -p "$tmp33/claude-personas-myapp/memory_manager"
printf "# Memory Index - memory_manager\n" > "$tmp33/claude-personas-myapp/memory_manager/MEMORY.md"

for bad in "--self --project-url $tmp33/project-repo.git" \
           "--self --target $tmp33/elsewhere" \
           "--self --main" \
           "--self developer"; do
  if ( cd "$tmp33/claude-personas-myapp" && \
       HOME="$tmp33/home" bash "$INIT_CLONE" $bad ) 2>/dev/null; then
    echo "  FAIL: should have rejected: $bad"
    exit 1
  else
    echo "  PASS: rejected: $bad"
  fi
done

# A project clone wired as memory_manager makes no sense - the MM's workspace
# IS the memory repo. The role arg without --self must error and point there.
if ( cd "$tmp33/claude-personas-myapp" && \
     HOME="$tmp33/home" bash "$INIT_CLONE" memory_manager --project-url "$tmp33/project-repo.git" ) 2>"$tmp33/stderr.log"; then
  echo "  FAIL: bare memory_manager role arg should be rejected"
  exit 1
else
  echo "  PASS: bare memory_manager role arg rejected"
fi
if grep -q -- "--self" "$tmp33/stderr.log"; then
  echo "  PASS: rejection message points at --self"
else
  echo "  FAIL: rejection message does not mention --self"
  exit 1
fi
assert_not_exists "$tmp33/claude-personas-myapp/.agents/memory" "no self-mount from rejected invocations"
assert_not_exists "$tmp33/myapp" "no clone from rejected invocations"
assert_not_exists "$tmp33/myapp-memory_manager" "no suffixed clone from rejected invocations"

cleanup_clone_test_fixture "$tmp33"

# --- --self re-run: refuse without --force, back up and re-wire with it ---
echo "=== test_init_clone --self re-run / --force ==="
tmp34="$(mktemp -d)"
make_clone_test_fixture "$tmp34"
mkdir -p "$tmp34/home"
mv "$tmp34/memory-repo" "$tmp34/claude-personas-myapp"
mkdir -p "$tmp34/claude-personas-myapp/memory_manager"
printf "# Memory Index - memory_manager\n" > "$tmp34/claude-personas-myapp/memory_manager/MEMORY.md"
( cd "$tmp34/claude-personas-myapp" && \
  git -c user.email=t@x -c user.name=T add -A && \
  git -c user.email=t@x -c user.name=T commit --quiet -m "add memory_manager role" )

( cd "$tmp34/claude-personas-myapp" && \
  HOME="$tmp34/home" bash "$INIT_CLONE" --self ) >/dev/null 2>&1 || [ $? -eq 2 ]

if ( cd "$tmp34/claude-personas-myapp" && \
     HOME="$tmp34/home" bash "$INIT_CLONE" --self ) >/dev/null 2>&1; then
  echo "  FAIL: --self re-run without --force should refuse (mounts exist)"
  exit 1
else
  echo "  PASS: --self re-run without --force refused"
fi

( cd "$tmp34/claude-personas-myapp" && \
  HOME="$tmp34/home" bash "$INIT_CLONE" --self --force ) >/dev/null 2>&1 || [ $? -eq 2 ]

memrepo34="$tmp34/claude-personas-myapp"
assert_symlink "$memrepo34/.agents/memory" "../memory_manager" "self-mount re-wired by --self --force"
assert_symlink "$memrepo34/.claude/memory" "../.agents/memory" "hop re-wired by --self --force"
ab34="$(find "$memrepo34/.agents" -maxdepth 1 -name "memory.backup-*" | wc -l | tr -d ' ')"
assert_equal "1" "$ab34" "exactly one .agents backup created"
cb34="$(find "$memrepo34/.claude" -maxdepth 1 -name "memory.backup-*" | wc -l | tr -d ' ')"
assert_equal "1" "$cb34" "exactly one .claude backup created"
ex34="$(grep -cxF '/.agents/memory' "$memrepo34/.git/info/exclude" || true)"
assert_equal "1" "$ex34" "exactly one /.agents/memory exclude line after re-runs"

cleanup_clone_test_fixture "$tmp34"

print_summary
