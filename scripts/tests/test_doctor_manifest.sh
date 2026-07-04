#!/usr/bin/env bash
# Test doctor.sh's skeleton: arg parsing, manifest parser/validation
# whitelist, refusal on no/invalid manifest, and --init starters.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
DOCTOR="$(cd "$SCRIPT_DIR/.." && pwd)/doctor.sh"

# Runs doctor.sh with the given args; sets DOCTOR_STDOUT, DOCTOR_STDERR,
# DOCTOR_EXIT. Never lets doctor.sh's own set -u kill this test script.
run_doctor() {
  local errfile
  errfile="$(mktemp)"
  DOCTOR_STDOUT="$(bash "$DOCTOR" "$@" 2>"$errfile")"
  DOCTOR_EXIT=$?
  DOCTOR_STDERR="$(cat "$errfile")"
  rm -f "$errfile"
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$haystack" in
    *"$needle"*)
      TESTS_PASSED=$((TESTS_PASSED + 1))
      echo "  PASS: $msg"
      ;;
    *)
      TESTS_FAILED=$((TESTS_FAILED + 1))
      FAILED_TESTS+=("$msg")
      echo "  FAIL: $msg"
      echo "    expected to find: $needle"
      echo "    in: $haystack"
      ;;
  esac
}

echo "=== test_doctor_manifest: no manifest refuses, names all 3 topologies + --init ==="
tmp="$(mktemp -d)"
run_doctor --check --root "$tmp"
assert_equal "2" "$DOCTOR_EXIT" "no manifest: exit 2"
assert_contains "$DOCTOR_STDERR" "role-clones" "stderr names role-clones"
assert_contains "$DOCTOR_STDERR" "embedded" "stderr names embedded"
assert_contains "$DOCTOR_STDERR" "user-tier" "stderr names user-tier"
assert_contains "$DOCTOR_STDERR" "--init" "stderr names --init"
rm -rf "$tmp"

echo "=== test_doctor_manifest: --init writes a starter that immediately re-parses ==="
for topo in role-clones embedded user-tier; do
  tmp="$(mktemp -d)"
  run_doctor --init "$topo" --root "$tmp"
  assert_equal "0" "$DOCTOR_EXIT" "--init $topo exits 0"
  assert_exists "$tmp/.agents/manifest" "--init $topo writes .agents/manifest"

  run_doctor --check --root "$tmp"
  assert_equal "0" "$DOCTOR_EXIT" "--check on fresh $topo starter proceeds past manifest stage"
  assert_contains "$DOCTOR_STDOUT" "OK:" "--check on fresh $topo starter prints OK:"
  rm -rf "$tmp"
done

echo "=== test_doctor_manifest: --init refuses to overwrite an existing manifest ==="
tmp="$(mktemp -d)"
run_doctor --init embedded --root "$tmp"
assert_equal "0" "$DOCTOR_EXIT" "first --init succeeds"
before="$(cat "$tmp/.agents/manifest")"

run_doctor --init embedded --root "$tmp"
assert_equal "2" "$DOCTOR_EXIT" "second --init refuses: exit 2"

after="$(cat "$tmp/.agents/manifest")"
assert_equal "$before" "$after" "manifest unchanged after refused re-init"
rm -rf "$tmp"

echo "=== test_doctor_manifest: unknown topology= refuses, names the offender ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=bogus-topology
memory_layout=flat
EOF
run_doctor --check --root "$tmp"
assert_equal "2" "$DOCTOR_EXIT" "unknown topology: exit 2"
assert_contains "$DOCTOR_STDERR" "bogus-topology" "stderr names the offending topology"
rm -rf "$tmp"

echo "=== test_doctor_manifest: unknown key refuses, names the offender ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
frobnicate=1
EOF
run_doctor --check --root "$tmp"
assert_equal "2" "$DOCTOR_EXIT" "unknown key: exit 2"
assert_contains "$DOCTOR_STDERR" "frobnicate" "stderr names the offending key"
rm -rf "$tmp"

echo "=== test_doctor_manifest: unsupported manifest_version refuses, names the offender ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=99
topology=embedded
memory_layout=flat
EOF
run_doctor --check --root "$tmp"
assert_equal "2" "$DOCTOR_EXIT" "unsupported manifest_version: exit 2"
assert_contains "$DOCTOR_STDERR" "99" "stderr names the offending version"
rm -rf "$tmp"

echo "=== test_doctor_manifest: missing required key refuses, names the offender ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
EOF
run_doctor --check --root "$tmp"
assert_equal "2" "$DOCTOR_EXIT" "missing required key: exit 2"
assert_contains "$DOCTOR_STDERR" "memory_layout" "stderr names the missing key"
rm -rf "$tmp"

echo "=== test_doctor_manifest: 'key = value' with spaces around = is invalid ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology = embedded
memory_layout=flat
EOF
run_doctor --check --root "$tmp"
assert_equal "2" "$DOCTOR_EXIT" "spaces around = is invalid: exit 2"
rm -rf "$tmp"

echo "=== test_doctor_manifest: # comments and blank lines are ignored ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents"
cat > "$tmp/.agents/manifest" <<'EOF'
# this is a comment

manifest_version=1

topology=user-tier
memory_layout=flat
# trailing comment
EOF
run_doctor --check --root "$tmp"
assert_equal "0" "$DOCTOR_EXIT" "comments/blank lines ignored: exit 0"
assert_contains "$DOCTOR_STDOUT" "OK:" "prints OK: with comments/blanks present"
rm -rf "$tmp"

echo "=== test_doctor_manifest: indented comment lines are ignored too ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
  # an indented comment line
	# a tab-indented comment line
EOF
run_doctor --check --root "$tmp"
assert_equal "0" "$DOCTOR_EXIT" "indented comment lines ignored: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_manifest: topology-scoped key used on the wrong topology refuses ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=role-clones
memory_layout=roles
claude_hook=scripts/foo.sh
EOF
run_doctor --check --root "$tmp"
assert_equal "2" "$DOCTOR_EXIT" "claude_hook outside embedded: exit 2"
assert_contains "$DOCTOR_STDERR" "claude_hook" "stderr names the offending key"
rm -rf "$tmp"

tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
opencode=global
EOF
run_doctor --check --root "$tmp"
assert_equal "2" "$DOCTOR_EXIT" "opencode outside role-clones: exit 2"
assert_contains "$DOCTOR_STDERR" "opencode" "stderr names the offending key"
rm -rf "$tmp"

print_summary
