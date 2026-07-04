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

# assert_contains lives in test_helpers.sh (shared across scripts/tests/*.sh).

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
  if [ "$topo" = "role-clones" ]; then
    # Task 5 landed a real role-clones catalog: its first check is the
    # claude-personas-<project> naming convention on the memory-repo dir
    # name (do-not-guess), so a bare mktemp dir now DRIFTs before ever
    # reaching payload sanity. Rename in place to satisfy it.
    renamed="$(dirname "$tmp")/claude-personas-$(basename "$tmp")"
    mv "$tmp" "$renamed"
    tmp="$renamed"
  fi
  run_doctor --init "$topo" --root "$tmp"
  assert_equal "0" "$DOCTOR_EXIT" "--init $topo exits 0"
  assert_exists "$tmp/.agents/manifest" "--init $topo writes .agents/manifest"

  # A freshly --init'd manifest declares a topology but seeds no payload;
  # check_payload (Task 2) is now wired into the main flow, so give it the
  # minimal index its declared memory_layout requires before re-checking.
  case "$topo" in
    role-clones)
      mkdir -p "$tmp/dev" "$tmp/shared"
      echo "# dev" > "$tmp/dev/MEMORY.md"
      echo "# shared" > "$tmp/shared/MEMORY.md"
      ;;
    embedded)
      mkdir -p "$tmp/.agents/memory"
      echo "# index" > "$tmp/.agents/memory/MEMORY.md"
      echo "# AGENTS" > "$tmp/AGENTS.md"
      # opencode.json's instructions check (Task 4) is report-only - never
      # fixed - so unlike the in-repo links and the external CC hop, it must
      # be seeded correctly up front for this starter to ever reach clean.
      echo '{"instructions": [".agents/memory/MEMORY.md"]}' > "$tmp/opencode.json"
      ;;
    user-tier)
      mkdir -p "$tmp/.agents/memory"
      echo "# index" > "$tmp/.agents/memory/MEMORY.md"
      echo "# AGENTS" > "$tmp/AGENTS.md"
      ;;
  esac

  topo_home=""
  if [ "$topo" = "user-tier" ] || [ "$topo" = "embedded" ]; then
    # Both topologies' real check catalogs (Tasks 3-4) touch $HOME-relative
    # paths (user-tier's canonical home hop + gated adapters; embedded's
    # external CC auto-memory hop). Give each an isolated, empty HOME and
    # wire it once in fix mode before the generic re-check below, so this
    # loop keeps testing --init/payload sanity instead of incidentally
    # reading the real machine's HOME. (role-clones's Task 5 slice - role
    # walk + mounts - has no $HOME-relative checks yet; those land with the
    # vendor wiring in Task 6, so no isolation is needed here yet.)
    topo_home="$(mktemp -d)"
    HOME="$topo_home" bash "$DOCTOR" --root "$tmp" > /dev/null 2>&1
    DOCTOR_STDOUT="$(HOME="$topo_home" bash "$DOCTOR" --check --root "$tmp" 2>/dev/null)"
    DOCTOR_EXIT=$?
  else
    run_doctor --check --root "$tmp"
  fi
  assert_equal "0" "$DOCTOR_EXIT" "--check on fresh $topo starter proceeds past manifest stage"
  assert_contains "$DOCTOR_STDOUT" "OK:" "--check on fresh $topo starter prints OK:"
  rm -rf "$tmp"
  [ -n "$topo_home" ] && rm -rf "$topo_home"
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
# topology=role-clones, not embedded/user-tier: this is a generic
# manifest-parsing test with no isolated HOME. Both user-tier (Task 3) and
# embedded (Task 4) wired real $HOME-relative / in-repo-link checks onto
# their topologies; role-clones's Task 5 slice (role walk + mounts) has none
# yet (those land with Task 6's vendor wiring), and memory_layout isn't
# restricted to a specific topology, so it can carry memory_layout=flat here
# without leaking into the real machine's HOME or tripping embedded's own
# link checks. The dir still needs the claude-personas- prefix Task 5's
# candidate walk requires (do-not-guess naming convention).
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-personas-XXXXXX")"
mkdir -p "$tmp/.agents/memory"
echo "# index" > "$tmp/.agents/memory/MEMORY.md"
cat > "$tmp/.agents/manifest" <<'EOF'
# this is a comment

manifest_version=1

topology=role-clones
memory_layout=flat
# trailing comment
EOF
run_doctor --check --root "$tmp"
assert_equal "0" "$DOCTOR_EXIT" "comments/blank lines ignored: exit 0"
assert_contains "$DOCTOR_STDOUT" "OK:" "prints OK: with comments/blanks present"
rm -rf "$tmp"

echo "=== test_doctor_manifest: indented comment lines are ignored too ==="
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-personas-XXXXXX")"
mkdir -p "$tmp/.agents/memory"
echo "# index" > "$tmp/.agents/memory/MEMORY.md"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=role-clones
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

# --- Task 2: shared check core (need_link, check_payload, check_hook_scripts, require_jq) ---

echo "=== test_doctor_manifest: check_payload - flat layout missing MEMORY.md is DRIFT + exit 1 ==="
# topology=embedded, not user-tier: same reasoning as the comments/blanks
# test above - keep this generic check_payload test off Task 3's real
# $HOME-touching user-tier catalog.
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
EOF
run_doctor --check --root "$tmp"
assert_equal "1" "$DOCTOR_EXIT" "flat layout, missing payload: exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: .agents/memory/MEMORY.md missing" "stdout names the missing payload"
rm -rf "$tmp"

echo "=== test_doctor_manifest: check_payload - flat layout present is clean ==="
# topology=role-clones (not embedded): memory_layout isn't restricted to a
# specific topology; this keeps the test targeting check_payload's
# flat-layout branch generically, without incidentally exercising embedded's
# own in-repo-link/adapter checks (Task 4). Task 5's own role-clones catalog
# needs the claude-personas- prefixed dir name (do-not-guess naming
# convention) and finds zero role dirs here, so it stays a silent no-op.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-personas-XXXXXX")"
mkdir -p "$tmp/.agents/memory"
echo "# index" > "$tmp/.agents/memory/MEMORY.md"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=role-clones
memory_layout=flat
EOF
run_doctor --check --root "$tmp"
assert_equal "0" "$DOCTOR_EXIT" "flat layout, payload present: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_manifest: check_payload - roles layout with zero role dirs is DRIFT + exit 1 ==="
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-personas-XXXXXX")"
mkdir -p "$tmp/.agents" "$tmp/shared"
echo "# shared" > "$tmp/shared/MEMORY.md"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=role-clones
memory_layout=roles
EOF
run_doctor --check --root "$tmp"
assert_equal "1" "$DOCTOR_EXIT" "roles layout, zero role dirs: exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: roles layout declared but no role dirs found" "stdout names the missing role dirs"
rm -rf "$tmp"

echo "=== test_doctor_manifest: check_payload - roles layout missing shared/MEMORY.md is DRIFT + exit 1 ==="
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-personas-XXXXXX")"
mkdir -p "$tmp/.agents" "$tmp/dev"
echo "# dev" > "$tmp/dev/MEMORY.md"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=role-clones
memory_layout=roles
EOF
run_doctor --check --root "$tmp"
assert_equal "1" "$DOCTOR_EXIT" "roles layout, missing shared/MEMORY.md: exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: shared/MEMORY.md missing" "stdout names the missing shared index"
rm -rf "$tmp"

echo "=== test_doctor_manifest: check_payload - roles layout excludes 'shared' and 'examples' from role-dir count ==="
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-personas-XXXXXX")"
mkdir -p "$tmp/.agents" "$tmp/shared" "$tmp/examples"
echo "# shared" > "$tmp/shared/MEMORY.md"
echo "# examples" > "$tmp/examples/MEMORY.md"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=role-clones
memory_layout=roles
EOF
run_doctor --check --root "$tmp"
assert_equal "1" "$DOCTOR_EXIT" "roles layout, only shared+examples present: still zero role dirs"
assert_contains "$DOCTOR_STDOUT" "DRIFT: roles layout declared but no role dirs found" "stdout names the missing role dirs (shared/examples excluded)"
rm -rf "$tmp"

echo "=== test_doctor_manifest: check_payload - roles layout fully present is clean ==="
# The lone "dev" role dir has no clone/self-mount claiming it (no .git
# anywhere in this fixture), so Task 5's role-clones catalog reports it as
# an informative "no workspace wired" (not DRIFT) - the roles-layout payload
# check itself is still clean, which is what this test targets.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-personas-XXXXXX")"
mkdir -p "$tmp/.agents" "$tmp/dev" "$tmp/shared"
echo "# dev" > "$tmp/dev/MEMORY.md"
echo "# shared" > "$tmp/shared/MEMORY.md"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=role-clones
memory_layout=roles
EOF
run_doctor --check --root "$tmp"
assert_equal "0" "$DOCTOR_EXIT" "roles layout, fully present: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_manifest: check_hook_scripts - missing claude_hook is DRIFT + exit 1 ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents/memory"
echo "# index" > "$tmp/.agents/memory/MEMORY.md"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
claude_hook=scripts/some-hook.sh
EOF
run_doctor --check --root "$tmp"
assert_equal "1" "$DOCTOR_EXIT" "missing claude_hook script: exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: claude_hook 'scripts/some-hook.sh' missing at" "stdout names the missing hook as missing (not conflated with non-executable)"
rm -rf "$tmp"

echo "=== test_doctor_manifest: check_hook_scripts - non-executable codex_hook is DRIFT + exit 1 ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents/memory" "$tmp/scripts"
echo "# index" > "$tmp/.agents/memory/MEMORY.md"
echo '#!/usr/bin/env bash' > "$tmp/scripts/some-hook.sh"
chmod -x "$tmp/scripts/some-hook.sh"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
codex_hook=scripts/some-hook.sh
EOF
run_doctor --check --root "$tmp"
assert_equal "1" "$DOCTOR_EXIT" "non-executable codex_hook script: exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: codex_hook 'scripts/some-hook.sh' not executable at" "stdout names the hook as not executable (not conflated with missing)"
rm -rf "$tmp"

echo "=== test_doctor_manifest: check_hook_scripts - existing + executable hooks are clean ==="
# claude_hook/codex_hook are embedded-only keys, so this test can't dodge
# Task 4's own in-repo-link checks (.claude/memory, CLAUDE.md - unconditional
# regardless of which adapters are declared) the way the generic
# check_payload tests above do by switching to role-clones. No adapter=
# lines are declared here, so the per-adapter (settings.json/hooks.json/
# opencode.json/external-hop) checks stay off; only the two unconditional
# links need pre-wiring.
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents/memory" "$tmp/scripts" "$tmp/.claude"
echo "# index" > "$tmp/.agents/memory/MEMORY.md"
echo '#!/usr/bin/env bash' > "$tmp/scripts/claude-hook.sh"
echo '#!/usr/bin/env bash' > "$tmp/scripts/codex-hook.sh"
chmod +x "$tmp/scripts/claude-hook.sh" "$tmp/scripts/codex-hook.sh"
echo "# AGENTS" > "$tmp/AGENTS.md"
( cd "$tmp" && ln -s AGENTS.md CLAUDE.md )
( cd "$tmp/.claude" && ln -s ../.agents/memory memory )
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
claude_hook=scripts/claude-hook.sh
codex_hook=scripts/codex-hook.sh
EOF
run_doctor --check --root "$tmp"
assert_equal "0" "$DOCTOR_EXIT" "existing + executable hooks: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_manifest: multiple DRIFTs don't hide each other (payload + hook both reported) ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
claude_hook=scripts/missing-hook.sh
EOF
run_doctor --check --root "$tmp"
assert_equal "1" "$DOCTOR_EXIT" "payload + hook both missing: exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: .agents/memory/MEMORY.md missing" "stdout still names the missing payload"
assert_contains "$DOCTOR_STDOUT" "DRIFT: claude_hook 'scripts/missing-hook.sh' missing at" "stdout still names the missing hook"
rm -rf "$tmp"

echo "=== test_doctor_manifest: need_link + require_jq (direct function-extraction tests) ==="
# Neither function has a CLI-reachable consumer yet: need_link's topology
# callers land in Task 3+, require_jq's jq-dependent callers in Tasks 4-6.
# Rather than reimplement their logic here (which would drift from the real
# functions), extract the literal source text out of doctor.sh and eval it,
# so these tests exercise the actual shipped code, not a copy of it.
extract_function() {
  # extract_function <func_name> <file> - print a top-level bash function
  # definition of the form 'name() {' ... '}' (closing brace alone on its
  # own line), matched by exact function name.
  # BRITTLE BY DESIGN: this assumes doctor.sh's exact brace style ('name() {'
  # opener, '^}$' closer). Reformatting a function there (e.g. 'function
  # name {' or an indented closing brace) silently truncates the extraction;
  # the assert_contains guards below catch a fully-missed function but not a
  # partial one - keep the style or update this matcher with it.
  local name="$1" file="$2"
  awk -v name="$name" '
    $0 == name"() {" { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
  ' "$file"
}

need_link_src="$(extract_function need_link "$DOCTOR")"
assert_contains "$need_link_src" "need_link" "extract_function finds need_link in doctor.sh"

report_drift_src="$(extract_function report_drift "$DOCTOR")"
report_fixed_src="$(extract_function report_fixed "$DOCTOR")"
report_error_src="$(extract_function report_error "$DOCTOR")"
eval "$report_drift_src"
eval "$report_fixed_src"
eval "$report_error_src"
eval "$need_link_src"

nl_tmp="$(mktemp -d)"
nl_outfile="$(mktemp)"
# need_link is called via redirection into a file rather than "$(...)"
# capture, for the same reason as require_jq above: command substitution
# forks a subshell, so DRIFT_COUNT mutations inside it never reach this
# script's copy of the variable.

# Correct symlink: silent, no drift.
ln -s "correct-target" "$nl_tmp/good_link"
DRIFT_COUNT=0
CHECK=1 need_link "$nl_tmp/good_link" "correct-target" "good_link" > "$nl_outfile"
assert_equal "" "$(cat "$nl_outfile")" "need_link: silent when the symlink already points at the target"
assert_equal "0" "$DRIFT_COUNT" "need_link: no drift for a correct symlink"

# Real (non-symlink) file at the path: DRIFT in both modes, never touched.
echo "real file" > "$nl_tmp/real_file"
DRIFT_COUNT=0
CHECK=1 need_link "$nl_tmp/real_file" "some-target" "real_file" > "$nl_outfile"
assert_contains "$(cat "$nl_outfile")" "DRIFT: real_file exists and is not a symlink (refusing to touch)" \
  "need_link: --check refuses a real file at the link path"
assert_equal "1" "$DRIFT_COUNT" "need_link: real file counts as drift in --check"
DRIFT_COUNT=0
CHECK=0 need_link "$nl_tmp/real_file" "some-target" "real_file" > "$nl_outfile"
assert_contains "$(cat "$nl_outfile")" "DRIFT: real_file exists and is not a symlink (refusing to touch)" \
  "need_link: fix mode also refuses a real file at the link path"
assert_equal "real file" "$(cat "$nl_tmp/real_file")" "need_link: fix mode left the real file's contents untouched"

# Missing symlink, --check mode: reports drift, creates nothing.
DRIFT_COUNT=0
CHECK=1 need_link "$nl_tmp/missing_link" "some-target" "missing_link" > "$nl_outfile"
assert_contains "$(cat "$nl_outfile")" "DRIFT: missing_link -> MISSING, expected some-target" \
  "need_link: --check names MISSING + expected target for an absent link"
assert_equal "1" "$DRIFT_COUNT" "need_link: missing link counts as drift in --check"
assert_not_exists "$nl_tmp/missing_link" "need_link: --check mode created nothing"

# Missing symlink, fix mode: mkdir -p's the parent, creates the symlink.
DRIFT_COUNT=0
CHECK=0 need_link "$nl_tmp/nested/deep/new_link" "some-target" "nested/deep/new_link" > "$nl_outfile"
assert_contains "$(cat "$nl_outfile")" "FIXED: nested/deep/new_link -> some-target" \
  "need_link: fix mode reports FIXED for a newly created link"
assert_symlink "$nl_tmp/nested/deep/new_link" "some-target" "need_link: fix mode created the symlink with the right target"

# ERROR branch: fix mode where the link cannot be created (read-only parent).
# root ignores file modes, so these failures cannot be forced when running
# as root - skip loudly rather than assert vacuously.
if [ "$(id -u)" -eq 0 ]; then
  echo "  SKIP: need_link ERROR-branch tests (running as root; chmod 555 cannot block root)"
else
  nl_errfile="$(mktemp)"
  mkdir -p "$nl_tmp/ro"
  chmod 555 "$nl_tmp/ro"

  # ln -sfn fails: the parent dir exists (mkdir -p succeeds) but is read-only.
  DRIFT_COUNT=0
  CHECK=0 need_link "$nl_tmp/ro/link" "some-target" "ro/link" > "$nl_outfile" 2>"$nl_errfile"
  assert_contains "$(cat "$nl_outfile")" "ERROR: could not create ro/link -> some-target" \
    "need_link: ln failure in fix mode reports the contractual ERROR line"
  assert_equal "1" "$DRIFT_COUNT" "need_link: ln failure counts as drift (drives exit 1)"
  assert_not_exists "$nl_tmp/ro/link" "need_link: no link materialized on ln failure"

  # mkdir -p fails: creating the parent itself is blocked by the read-only
  # grandparent. This is the path where mkdir's own stderr would leak if it
  # were not suppressed the same way ln's is.
  DRIFT_COUNT=0
  CHECK=0 need_link "$nl_tmp/ro/sub/link" "some-target" "ro/sub/link" > "$nl_outfile" 2>"$nl_errfile"
  assert_contains "$(cat "$nl_outfile")" "ERROR: could not create ro/sub/link -> some-target" \
    "need_link: mkdir failure in fix mode reports the contractual ERROR line"
  assert_equal "1" "$DRIFT_COUNT" "need_link: mkdir failure counts as drift (drives exit 1)"
  assert_equal "" "$(cat "$nl_errfile")" "need_link: mkdir failure leaks nothing to stderr (symmetric with ln)"

  chmod 755 "$nl_tmp/ro"
  rm -f "$nl_errfile"
fi

rm -f "$nl_outfile"
rm -rf "$nl_tmp"

# report_drift is already defined (extracted + eval'd above); only require_jq
# is new here.
require_jq_src="$(extract_function require_jq "$DOCTOR")"
assert_contains "$require_jq_src" "require_jq" "extract_function finds require_jq in doctor.sh"
eval "$require_jq_src"

# Redirect to a file rather than capture via "$(...)" - command substitution
# forks a subshell, which would run require_jq's DRIFT_COUNT mutation in a
# copy that never propagates back, making that assertion always pass/fail
# vacuously. A plain redirection runs the function inline.
jq_outfile="$(mktemp)"

DRIFT_COUNT=0
PATH="/nonexistent" require_jq "test purpose" > "$jq_outfile"
jq_masked_rc=$?
jq_masked_out="$(cat "$jq_outfile")"
assert_contains "$jq_masked_out" "DRIFT: jq not installed (needed for test purpose) - skipping those checks" \
  "require_jq: DRIFT line naming the purpose when jq is absent from PATH"
assert_equal "1" "$jq_masked_rc" "require_jq: returns 1 (skip loudly) when jq is absent"
assert_equal "1" "$DRIFT_COUNT" "require_jq: increments DRIFT_COUNT when jq is absent"

DRIFT_COUNT=0
require_jq "test purpose" > "$jq_outfile"
jq_present_rc=$?
jq_present_out="$(cat "$jq_outfile")"
assert_equal "" "$jq_present_out" "require_jq: silent when jq is present on PATH"
assert_equal "0" "$jq_present_rc" "require_jq: returns 0 when jq is present"
assert_equal "0" "$DRIFT_COUNT" "require_jq: does not increment DRIFT_COUNT when jq is present"
rm -f "$jq_outfile"

print_summary
