#!/usr/bin/env bash
# Test doctor.sh's role-clones topology catalog: role discovery + candidate
# walk (memory-repo self-mount, no-suffix clone, suffixed clone - same order
# as list-roles.sh) and, per claimed workspace, the two-hop mount
# (.agents/memory, .claude/memory) and the .git/info/exclude entries
# init-clone.sh owns. This task's slice stops at the FIRST claimant per role
# (Task 7 makes the walk exhaustive) and does not yet check vendor wiring
# (external CC hop / codex hooks.json / opencode - Task 6).
#
# The fixture is wired by RUNNING the real init-clone.sh (never hand-rolled),
# on top of make_clone_test_fixture, mirroring test_init_clone.sh's and
# test_list_roles.sh's invocation pattern. init-clone.sh runs may exit 2
# (vendor WARN, e.g. no scripts/inject-role-index.sh in this fixture) - that
# is tolerated, the core mount is still wired.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
DOCTOR="$(cd "$SCRIPT_DIR/.." && pwd)/doctor.sh"
INIT_CLONE="$(cd "$SCRIPT_DIR/.." && pwd)/init-clone.sh"

# Runs doctor.sh with $1=HOME and the remaining args passed through; sets
# DOCTOR_STDOUT, DOCTOR_STDERR, DOCTOR_EXIT. Never lets doctor.sh's own
# set -u kill this test script.
run_doctor() {
  local home="$1"
  shift
  local errfile
  errfile="$(mktemp)"
  DOCTOR_STDOUT="$(HOME="$home" bash "$DOCTOR" "$@" 2>"$errfile")"
  DOCTOR_EXIT=$?
  DOCTOR_STDERR="$(cat "$errfile")"
  rm -f "$errfile"
}

# repo_abs <path> - canonical (pwd -P) absolute path, matching how doctor.sh
# itself resolves ROOT (and, from there, the parent dir it walks candidate
# paths against) - see test_doctor_embedded.sh's identical helper. mktemp's
# dir is itself a symlink on macOS (/var/folders/... -> /private/var/...),
# so DOCTOR_STDOUT's paths only match a resolved path, not the raw fixture
# variable.
repo_abs() {
  ( cd "$1" && pwd -P )
}

# Sets up a wired constellation fixture at $1: developer (no-suffix), pm
# (suffixed), memory_manager via --self, plus the untouched scientist/designer
# role dirs make_clone_test_fixture already seeds (left unwired on purpose -
# covers the INFO "no workspace wired" case for free). Writes the manifest
# into the memory repo. Leaves globals MEMREPO / DEVCLONE / PMCLONE / HOME_DIR
# (raw fixture paths, for filesystem operations) and MEMREPO_ABS / DEVCLONE_ABS
# / PMCLONE_ABS (pwd -P resolved, for matching doctor.sh's own output) set for
# the caller.
setup_wired_fixture() {
  local base="$1"
  make_clone_test_fixture "$base"
  mkdir -p "$base/home"
  mv "$base/memory-repo" "$base/claude-personas-myapp"

  MEMREPO="$base/claude-personas-myapp"
  DEVCLONE="$base/myapp"
  PMCLONE="$base/myapp-pm"
  HOME_DIR="$base/home"

  # memory_manager is a role like any other: a real role dir, committed.
  mkdir -p "$MEMREPO/memory_manager"
  printf "# Memory Index - memory_manager\n" > "$MEMREPO/memory_manager/MEMORY.md"
  ( cd "$MEMREPO/memory_manager" && ln -s ../shared shared )
  ( cd "$MEMREPO" && \
    git -c user.email=t@x -c user.name=T add -A && \
    git -c user.email=t@x -c user.name=T commit --quiet -m "add memory_manager role" )

  ( cd "$MEMREPO" && HOME="$HOME_DIR" bash "$INIT_CLONE" developer --project-url "$base/project-repo.git" ) \
    >/dev/null 2>&1 || [ $? -eq 2 ]
  ( cd "$MEMREPO" && HOME="$HOME_DIR" bash "$INIT_CLONE" pm --project-url "$base/project-repo.git" ) \
    >/dev/null 2>&1 || [ $? -eq 2 ]
  ( cd "$MEMREPO" && HOME="$HOME_DIR" bash "$INIT_CLONE" --self ) \
    >/dev/null 2>&1 || [ $? -eq 2 ]

  MEMREPO_ABS="$(repo_abs "$MEMREPO")"
  DEVCLONE_ABS="$(repo_abs "$DEVCLONE")"
  PMCLONE_ABS="$(repo_abs "$PMCLONE")"

  cat > "$MEMREPO/.agents/manifest" <<'EOF'
manifest_version=1
topology=role-clones
memory_layout=roles
adapter=claude-code
adapter=codex
adapter=opencode
opencode=global
EOF
}

echo "=== test_doctor_role_clones: clean wired constellation - --check exits 0, unwired roles are INFO not DRIFT ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "clean wired constellation: --check exit 0"
assert_contains "$DOCTOR_STDOUT" "INFO: role designer - no workspace wired" "unwired designer role reported INFO, not DRIFT"
assert_contains "$DOCTOR_STDOUT" "INFO: role scientist - no workspace wired" "unwired scientist role reported INFO, not DRIFT"
case "$DOCTOR_STDOUT" in
  *"DRIFT:"*) echo "  FAIL: unexpected DRIFT in a clean fixture:"; echo "$DOCTOR_STDOUT" | grep "DRIFT:"; exit 1 ;;
  *) echo "  PASS: no DRIFT lines in the clean fixture" ;;
esac
assert_contains "$DOCTOR_STDOUT" "OK:" "clean --check prints the OK: line"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: drift (a) deleted .agents/memory mount in the suffixed pm clone - DRIFT, fix repairs, re-check clean ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"
rm -f "$PMCLONE/.agents/memory"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "deleted pm mount: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: $PMCLONE_ABS/.agents/memory -> MISSING, expected ../../claude-personas-myapp/pm" "deleted pm mount named in DRIFT"

run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "fix mode repairs the deleted pm mount: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: $PMCLONE_ABS/.agents/memory -> ../../claude-personas-myapp/pm" "fix mode reports FIXED for the pm mount"
assert_symlink "$PMCLONE/.agents/memory" "../../claude-personas-myapp/pm" "pm mount recreated correctly"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "re-check after repair: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: drift (b) repointed .claude/memory hop in the no-suffix developer clone - DRIFT, fix repairs, re-check clean ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"
ln -sfn /nonexistent "$DEVCLONE/.claude/memory"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "repointed developer hop: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: $DEVCLONE_ABS/.claude/memory -> /nonexistent, expected ../.agents/memory" "repointed developer hop named in DRIFT"

run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "fix mode repairs the developer hop: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: $DEVCLONE_ABS/.claude/memory -> ../.agents/memory" "fix mode reports FIXED for the developer hop"
assert_symlink "$DEVCLONE/.claude/memory" "../.agents/memory" "developer hop repointed correctly"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "re-check after repair: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: drift (c) stripped exclude line in the pm clone - DRIFT, fix appends (append-only), re-check clean ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"
exclude="$PMCLONE/.git/info/exclude"
before_other_lines="$(grep -vxF '/.agents/memory' "$exclude")"
grep -vxF '/.agents/memory' "$exclude" > "$exclude.tmp" && mv "$exclude.tmp" "$exclude"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "stripped pm exclude line: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: $PMCLONE_ABS/.git/info/exclude missing '/.agents/memory'" "stripped exclude line named in DRIFT"

run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "fix mode appends the missing exclude line: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: $PMCLONE_ABS/.git/info/exclude appended '/.agents/memory'" "fix mode reports FIXED for the exclude append"
if grep -qxF '/.agents/memory' "$exclude"; then
  echo "  PASS: /.agents/memory line restored in pm's exclude"
else
  echo "  FAIL: /.agents/memory line missing from pm's exclude after fix"; exit 1
fi
after_other_lines="$(grep -vxF '/.agents/memory' "$exclude")"
assert_equal "$before_other_lines" "$after_other_lines" "append-only: every other exclude line is untouched"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "re-check after repair: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: memory repo name without the claude-personas- prefix is DRIFT (do-not-guess), not a crash ==="
tmp="$(mktemp -d)"
make_clone_test_fixture "$tmp"
mkdir -p "$tmp/home"
# Deliberately leave the repo named "memory-repo" (no claude-personas- prefix).
mkdir -p "$tmp/memory-repo/.agents"
cat > "$tmp/memory-repo/.agents/manifest" <<'EOF'
manifest_version=1
topology=role-clones
memory_layout=roles
adapter=claude-code
adapter=codex
adapter=opencode
EOF

run_doctor "$tmp/home" --check --root "$tmp/memory-repo"
assert_equal "1" "$DOCTOR_EXIT" "non-prefixed memory repo name: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: memory repo dir name 'memory-repo' does not start with 'claude-personas-'" "naming-convention violation named in DRIFT"
rm -rf "$tmp"

print_summary
