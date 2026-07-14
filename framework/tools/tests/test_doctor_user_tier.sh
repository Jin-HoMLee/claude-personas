#!/usr/bin/env bash
# Test doctor.sh's user-tier topology catalog: the canonical home hop, the
# three gated per-tool adapters, and the tier's extra AGENTS.md payload
# check. Mirrors test_doctor_manifest.sh's run_doctor idiom but every
# scenario also points HOME at a fixture dir (never the real home).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
DOCTOR="$(cd "$SCRIPT_DIR/.." && pwd)/doctor.sh"

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
  # shellcheck disable=SC2034  # DOCTOR_STDERR is part of run_doctor's documented contract; consumed ad hoc when debugging failures
  DOCTOR_STDERR="$(cat "$errfile")"
  rm -f "$errfile"
}

echo "=== test_doctor_user_tier: clean-after-fix baseline (fix wires an empty HOME, then --check is clean) ==="
tmp="$(mktemp -d)"
make_user_tier_fixture "$tmp"

run_doctor "$tmp/home" --root "$tmp/user-repo"
assert_equal "0" "$DOCTOR_EXIT" "fix mode on an empty fixture HOME: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: ~/AGENTS.md -> $tmp/user-repo/AGENTS.md" "fix mode creates the home hop"
assert_contains "$DOCTOR_STDOUT" "FIXED: ~/.claude/CLAUDE.md -> $tmp/home/AGENTS.md" "fix mode creates the claude-code adapter"
assert_contains "$DOCTOR_STDOUT" "FIXED: ~/.codex/AGENTS.md -> $tmp/home/AGENTS.md" "fix mode creates the codex adapter"
assert_contains "$DOCTOR_STDOUT" "FIXED: ~/.config/opencode/AGENTS.md -> $tmp/home/AGENTS.md" "fix mode creates the opencode adapter"
assert_symlink "$tmp/home/AGENTS.md" "$tmp/user-repo/AGENTS.md" "home hop symlink points at ROOT/AGENTS.md"
assert_symlink "$tmp/home/.claude/CLAUDE.md" "$tmp/home/AGENTS.md" "claude-code adapter symlink points at the home hop"
assert_symlink "$tmp/home/.codex/AGENTS.md" "$tmp/home/AGENTS.md" "codex adapter symlink points at the home hop"
assert_symlink "$tmp/home/.config/opencode/AGENTS.md" "$tmp/home/AGENTS.md" "opencode adapter symlink points at the home hop"

run_doctor "$tmp/home" --check --root "$tmp/user-repo"
assert_equal "0" "$DOCTOR_EXIT" "--check after fix: exit 0"
assert_contains "$DOCTOR_STDOUT" "OK:" "--check after fix prints the OK: line"
rm -rf "$tmp"

echo "=== test_doctor_user_tier: drift (a) deleted home hop - DRIFT, fix repairs, re-check clean ==="
tmp="$(mktemp -d)"
make_user_tier_fixture "$tmp"
run_doctor "$tmp/home" --root "$tmp/user-repo"
rm -f "$tmp/home/AGENTS.md"

run_doctor "$tmp/home" --check --root "$tmp/user-repo"
assert_equal "1" "$DOCTOR_EXIT" "deleted home hop: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: ~/AGENTS.md -> MISSING, expected $tmp/user-repo/AGENTS.md" "deleted home hop named in DRIFT"

run_doctor "$tmp/home" --root "$tmp/user-repo"
assert_equal "0" "$DOCTOR_EXIT" "fix mode repairs the deleted home hop: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: ~/AGENTS.md -> $tmp/user-repo/AGENTS.md" "fix mode reports FIXED for the home hop"
assert_symlink "$tmp/home/AGENTS.md" "$tmp/user-repo/AGENTS.md" "home hop recreated correctly"

run_doctor "$tmp/home" --check --root "$tmp/user-repo"
assert_equal "0" "$DOCTOR_EXIT" "re-check after repair: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_user_tier: drift (b) wrong-target adapter link - DRIFT, fix repairs, re-check clean ==="
tmp="$(mktemp -d)"
make_user_tier_fixture "$tmp"
run_doctor "$tmp/home" --root "$tmp/user-repo"
ln -sfn /nonexistent "$tmp/home/.claude/CLAUDE.md"

run_doctor "$tmp/home" --check --root "$tmp/user-repo"
assert_equal "1" "$DOCTOR_EXIT" "wrong-target adapter link: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: ~/.claude/CLAUDE.md -> /nonexistent, expected $tmp/home/AGENTS.md" "wrong-target link named in DRIFT"

run_doctor "$tmp/home" --root "$tmp/user-repo"
assert_equal "0" "$DOCTOR_EXIT" "fix mode repairs the wrong-target link: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: ~/.claude/CLAUDE.md -> $tmp/home/AGENTS.md" "fix mode reports FIXED for the adapter link"
assert_symlink "$tmp/home/.claude/CLAUDE.md" "$tmp/home/AGENTS.md" "adapter link repointed correctly"

run_doctor "$tmp/home" --check --root "$tmp/user-repo"
assert_equal "0" "$DOCTOR_EXIT" "re-check after repair: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_user_tier: drift (c) REAL file at adapter path - DRIFT persists in both modes, content untouched ==="
tmp="$(mktemp -d)"
make_user_tier_fixture "$tmp"
run_doctor "$tmp/home" --root "$tmp/user-repo"
rm -f "$tmp/home/.claude/CLAUDE.md"
printf 'a real, hand-edited file - never touch this\n' > "$tmp/home/.claude/CLAUDE.md"
before_sum="$(cksum "$tmp/home/.claude/CLAUDE.md")"

run_doctor "$tmp/home" --check --root "$tmp/user-repo"
assert_equal "1" "$DOCTOR_EXIT" "real file at adapter path: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: ~/.claude/CLAUDE.md exists and is not a symlink (refusing to touch)" "real file named in DRIFT (check mode)"

run_doctor "$tmp/home" --root "$tmp/user-repo"
assert_equal "1" "$DOCTOR_EXIT" "real file at adapter path: fix mode also refuses, exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: ~/.claude/CLAUDE.md exists and is not a symlink (refusing to touch)" "real file named in DRIFT (fix mode)"
after_sum="$(cksum "$tmp/home/.claude/CLAUDE.md")"
assert_equal "$before_sum" "$after_sum" "fix mode left the real file's contents byte-identical"

run_doctor "$tmp/home" --check --root "$tmp/user-repo"
assert_equal "1" "$DOCTOR_EXIT" "real file drift persists on a subsequent --check"
rm -rf "$tmp"

echo "=== test_doctor_user_tier: undeclared adapter is neither checked nor created ==="
tmp="$(mktemp -d)"
make_user_tier_fixture "$tmp"
# Rewrite the manifest without adapter=codex.
cat > "$tmp/user-repo/.agents/manifest" <<EOF
manifest_version=1
topology=user-tier
memory_layout=flat
adapter=claude-code
adapter=opencode
EOF

run_doctor "$tmp/home" --root "$tmp/user-repo"
assert_equal "0" "$DOCTOR_EXIT" "fix mode with an undeclared codex adapter: exit 0"
assert_not_exists "$tmp/home/.codex/AGENTS.md" "undeclared codex adapter is not created"
assert_symlink "$tmp/home/.claude/CLAUDE.md" "$tmp/home/AGENTS.md" "declared claude-code adapter is still created"

run_doctor "$tmp/home" --check --root "$tmp/user-repo"
assert_equal "0" "$DOCTOR_EXIT" "--check with an undeclared adapter still exits 0"
rm -rf "$tmp"

echo "=== test_doctor_user_tier: zero declared adapters - only the home hop is wired, no crash under bash 3.2 set -u ==="
# ADAPTERS=() is a valid empty array (adapter= is repeatable/optional per
# validate_manifest_semantics); bash 3.2's set -u treats an empty array as
# unbound on "${ADAPTERS[@]}" expansion without a length guard first - this
# is the regression test for that guard in topology_user_tier_checks.
tmp="$(mktemp -d)"
make_user_tier_fixture "$tmp"
cat > "$tmp/user-repo/.agents/manifest" <<'EOF'
manifest_version=1
topology=user-tier
memory_layout=flat
EOF

run_doctor "$tmp/home" --root "$tmp/user-repo"
assert_equal "0" "$DOCTOR_EXIT" "fix mode with zero declared adapters: exit 0 (no unbound-variable crash)"
assert_symlink "$tmp/home/AGENTS.md" "$tmp/user-repo/AGENTS.md" "home hop still wired with zero adapters"
assert_not_exists "$tmp/home/.claude/CLAUDE.md" "no adapter links created with zero adapters declared"
assert_not_exists "$tmp/home/.codex/AGENTS.md" "no adapter links created with zero adapters declared"
assert_not_exists "$tmp/home/.config/opencode/AGENTS.md" "no adapter links created with zero adapters declared"

run_doctor "$tmp/home" --check --root "$tmp/user-repo"
assert_equal "0" "$DOCTOR_EXIT" "--check with zero declared adapters: exit 0"

# Also exercise /bin/bash directly (bash 3.2 on macOS, the strictest set -u
# behavior around empty arrays): a length-guard regression could otherwise
# hide behind whatever shell happens to run the test suite via $BASH.
if [ -x /bin/bash ]; then
  bash3_out="$(HOME="$tmp/home" /bin/bash "$DOCTOR" --check --root "$tmp/user-repo" 2>&1)"
  bash3_rc=$?
  assert_equal "0" "$bash3_rc" "/bin/bash (system bash) --check with zero adapters: exit 0, no unbound-variable crash"
  assert_contains "$bash3_out" "OK:" "/bin/bash --check with zero adapters prints OK:"
else
  echo "  SKIP: /bin/bash direct invocation (not present on this machine)"
fi
rm -rf "$tmp"

echo "=== test_doctor_user_tier: extra payload sanity - missing ROOT/AGENTS.md is DRIFT ==="
tmp="$(mktemp -d)"
make_user_tier_fixture "$tmp"
run_doctor "$tmp/home" --root "$tmp/user-repo"
rm -f "$tmp/user-repo/AGENTS.md"

run_doctor "$tmp/home" --check --root "$tmp/user-repo"
assert_equal "1" "$DOCTOR_EXIT" "missing ROOT/AGENTS.md: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: AGENTS.md missing" "missing ROOT/AGENTS.md named in DRIFT"
rm -rf "$tmp"

echo "=== test_doctor_user_tier: CLI-level ERROR path - read-only HOME subdir forces a fix-mode failure ==="
# need_link's ERROR branch got a unit-level test in Task 2 (extract_function);
# this task gives it its first CLI-reachable caller, so exercise the real
# failure through the actual doctor.sh binary. root ignores file modes, so
# this cannot be forced when running as root - skip loudly rather than pass
# vacuously (same guard as the Task 2 unit test).
if [ "$(id -u)" -eq 0 ]; then
  echo "  SKIP: CLI ERROR-path test (running as root; chmod 555 cannot block root)"
else
  tmp="$(mktemp -d)"
  make_user_tier_fixture "$tmp"
  mkdir -p "$tmp/home/.claude"
  chmod 555 "$tmp/home/.claude"

  run_doctor "$tmp/home" --root "$tmp/user-repo"
  assert_equal "1" "$DOCTOR_EXIT" "read-only ~/.claude blocks the adapter link: fix mode exit 1"
  assert_contains "$DOCTOR_STDOUT" "ERROR: could not create ~/.claude/CLAUDE.md -> $tmp/home/AGENTS.md" "fix mode reports the contractual ERROR line"
  assert_symlink "$tmp/home/AGENTS.md" "$tmp/user-repo/AGENTS.md" "home hop still created despite the adapter ERROR (one refusal doesn't hide others)"
  assert_symlink "$tmp/home/.codex/AGENTS.md" "$tmp/home/AGENTS.md" "codex adapter still created despite the claude-code adapter ERROR"

  chmod 755 "$tmp/home/.claude"
  rm -rf "$tmp"
fi

print_summary
