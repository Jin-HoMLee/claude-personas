#!/usr/bin/env bash
# Test doctor.sh's role-tier readiness section (claude-personas#49 spec
# section 5): target checks (this file, scenarios 1-4) and per-role
# <role>/user symlink checks + lazy fix-mode materialization (scenarios 5+,
# Task 3). Fixtures are embedded-topology instances with memory_layout=roles
# to keep vendor wiring out of the picture (no adapter= lines declared).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
DOCTOR="$(cd "$SCRIPT_DIR/.." && pwd)/doctor.sh"

run_doctor() {
  local errfile
  errfile="$(mktemp)"
  DOCTOR_STDOUT="$(bash "$DOCTOR" "$@" 2>"$errfile")"
  DOCTOR_EXIT=$?
  DOCTOR_STDERR="$(cat "$errfile")"
  rm -f "$errfile"
}

# make_consumer <base> [role_source_value]
# Embedded instance with one role dir (developer) + shared, roles layout,
# role_source declared. No adapter= lines: vendor checks stay dormant.
# The two in-repo embedded links are pre-created so a fresh fixture has
# ZERO non-role-tier drift in --check mode (need_link compares link text
# only, so .claude/memory may dangle harmlessly - no .agents/memory dir
# exists under memory_layout=roles).
make_consumer() {
  local base="$1" src="${2:-../user-memory}"
  mkdir -p "$base/inst/.agents" "$base/inst/.claude" "$base/inst/developer" "$base/inst/shared"
  echo "# dev idx" > "$base/inst/developer/MEMORY.md"
  echo "# shared idx" > "$base/inst/shared/MEMORY.md"
  echo "# agents" > "$base/inst/AGENTS.md"
  ln -s ../.agents/memory "$base/inst/.claude/memory"
  ln -s AGENTS.md "$base/inst/CLAUDE.md"
  cat > "$base/inst/.agents/manifest" <<EOF
manifest_version=1
topology=embedded
memory_layout=roles
role_source=$src
EOF
}

# make_target <base> <layout> - sibling user-memory repo fixture.
make_target() {
  local base="$1" layout="$2"
  mkdir -p "$base/user-memory/.git" "$base/user-memory/.agents" "$base/user-memory/shared"
  echo "# user shared idx" > "$base/user-memory/shared/MEMORY.md"
  cat > "$base/user-memory/.agents/manifest" <<EOF
manifest_version=1
topology=user-tier
memory_layout=$layout
EOF
}

echo "=== test_doctor_role_tier: (1) unreachable role_source is ERROR ==="
tmp="$(mktemp -d)"
make_consumer "$tmp" "../nonexistent"
run_doctor --check --root "$tmp/inst"
assert_equal "1" "$DOCTOR_EXIT" "unreachable role_source: exit 1"
assert_contains "$DOCTOR_STDOUT" "ERROR: role_source '../nonexistent' unreachable" "unreachable named in ERROR"
rm -rf "$tmp"

echo "=== test_doctor_role_tier: (2) non-git target is ERROR ==="
tmp="$(mktemp -d)"
make_consumer "$tmp"
make_target "$tmp" roles
rm -rf "$tmp/user-memory/.git"
run_doctor --check --root "$tmp/inst"
assert_equal "1" "$DOCTOR_EXIT" "non-git target: exit 1"
assert_contains "$DOCTOR_STDOUT" "not a git repo" "non-git target named in ERROR"
rm -rf "$tmp"

echo "=== test_doctor_role_tier: (3) flat target is ERROR (wired before migration) ==="
tmp="$(mktemp -d)"
make_consumer "$tmp"
make_target "$tmp" flat
run_doctor --check --root "$tmp/inst"
assert_equal "1" "$DOCTOR_EXIT" "flat target: exit 1"
assert_contains "$DOCTOR_STDOUT" "memory_layout='flat', expected 'roles'" "flat target names the layout mismatch"
rm -rf "$tmp"

echo "=== test_doctor_role_tier: (4) roles target, lazy state (no symlink, no target role dir): clean ==="
tmp="$(mktemp -d)"
make_consumer "$tmp"
make_target "$tmp" roles
run_doctor --check --root "$tmp/inst"
assert_equal "0" "$DOCTOR_EXIT" "lazy state: --check exit 0"
run_doctor --root "$tmp/inst"
assert_equal "0" "$DOCTOR_EXIT" "lazy state: fix mode exit 0 (no target role dir, nothing materialized)"
assert_equal "" "$(readlink "$tmp/inst/developer/user" 2>/dev/null)" "lazy state: no symlink created"
rm -rf "$tmp"

echo "=== test_doctor_role_tier: (5) target role dir exists - fix mode materializes, check mode stays silent ==="
tmp="$(mktemp -d)"
make_consumer "$tmp"
make_target "$tmp" roles
mkdir -p "$tmp/user-memory/developer"
echo "# dev@user idx" > "$tmp/user-memory/developer/MEMORY.md"
run_doctor --check --root "$tmp/inst"
assert_equal "0" "$DOCTOR_EXIT" "missing symlink is not drift even when target exists: --check exit 0"
run_doctor --root "$tmp/inst"
assert_equal "0" "$DOCTOR_EXIT" "fix mode materializes: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: developer/user -> ../../user-memory/developer" "fix mode reports the materialized symlink"
assert_symlink "$tmp/inst/developer/user" "../../user-memory/developer" "symlink target is ../<role_source>/<role>"
run_doctor --check --root "$tmp/inst"
assert_equal "0" "$DOCTOR_EXIT" "re-check after materialization: clean"
rm -rf "$tmp"

echo "=== test_doctor_role_tier: (6) wrong-target symlink - DRIFT in check, repaired in fix ==="
tmp="$(mktemp -d)"
make_consumer "$tmp"
make_target "$tmp" roles
mkdir -p "$tmp/user-memory/developer"
echo "# dev@user idx" > "$tmp/user-memory/developer/MEMORY.md"
ln -s "../../elsewhere/developer" "$tmp/inst/developer/user"
run_doctor --check --root "$tmp/inst"
assert_equal "1" "$DOCTOR_EXIT" "wrong-target symlink: exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: developer/user -> ../../elsewhere/developer, expected ../../user-memory/developer" "wrong target named"
case "$DOCTOR_STDOUT" in
  *"dangles"*) assert_equal "no-dangle-line" "dangle-line" "wrong-target check emits no second (dangling) DRIFT line" ;;
  *) assert_equal "no-dangle-line" "no-dangle-line" "wrong-target check emits no second (dangling) DRIFT line" ;;
esac
run_doctor --root "$tmp/inst"
assert_symlink "$tmp/inst/developer/user" "../../user-memory/developer" "fix repoints the symlink"
rm -rf "$tmp"

echo "=== test_doctor_role_tier: (7) dangling symlink (target role dir gone) is DRIFT, report-only ==="
tmp="$(mktemp -d)"
make_consumer "$tmp"
make_target "$tmp" roles
ln -s "../../user-memory/developer" "$tmp/inst/developer/user"
run_doctor --check --root "$tmp/inst"
assert_equal "1" "$DOCTOR_EXIT" "dangling symlink: exit 1"
assert_contains "$DOCTOR_STDOUT" "dangles" "dangling symlink named in DRIFT"
rm -rf "$tmp"

echo "=== test_doctor_role_tier: (8) real dir at <role>/user - DRIFT, never touched ==="
tmp="$(mktemp -d)"
make_consumer "$tmp"
make_target "$tmp" roles
mkdir -p "$tmp/inst/developer/user"
run_doctor --root "$tmp/inst"
assert_equal "1" "$DOCTOR_EXIT" "real dir at <role>/user: exit 1 even in fix mode"
assert_contains "$DOCTOR_STDOUT" "not a symlink" "real dir named, refused"
rm -rf "$tmp"

print_summary
