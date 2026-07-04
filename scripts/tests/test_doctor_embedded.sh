#!/usr/bin/env bash
# Test doctor.sh's embedded topology catalog: in-repo links (.claude/memory,
# CLAUDE.md, .claude/skills), the claude-code adapter's settings.json hook
# wiring (report-only) + external CC auto-memory hop (fixable), the codex
# adapter's hooks.json (regenerated wholesale in fix mode, exact-match
# guarded against another machine's absolute prefix), and the opencode
# adapter's instructions entry (report-only). Generalizes cerebrum's
# sync.sh. Mirrors test_doctor_user_tier.sh's run_doctor idiom; every
# scenario points HOME at a fixture dir (never the real home).
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
  DOCTOR_STDERR="$(cat "$errfile")"
  rm -f "$errfile"
}

# repo_abs <repo-path> - canonical (pwd -P) absolute path, matching how
# doctor.sh itself resolves ROOT for the codex hooks.json + external CC hop
# checks (both go through `cd ... && pwd -P`, not the logical `pwd` used for
# the plain --root argument).
repo_abs() {
  ( cd "$1" && pwd -P )
}

# external_hop <repo-abs> <home> - the external CC auto-memory hop path for
# this repo under this fixture HOME, using the same tr rule as doctor.sh's
# slug computation (cross-checked against compute_hash in this file).
external_hop() {
  local slug
  slug="$(compute_hash "$1")"
  printf '%s/.claude/projects/%s/memory\n' "$2" "$slug"
}

echo "=== test_doctor_embedded: clean fixture (fix wires the external hop, then --check is clean) ==="
tmp="$(mktemp -d)"
make_embedded_fixture "$tmp"
repo="$tmp/embedded-repo"
home="$tmp/home"
root_abs="$(repo_abs "$repo")"
ext="$(external_hop "$root_abs" "$home")"

run_doctor "$home" --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "fix mode on the pre-wired fixture: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: $ext -> $root_abs/.claude/memory" "fix mode creates the external CC hop"
assert_symlink "$ext" "$root_abs/.claude/memory" "external hop points at ROOT/.claude/memory"

run_doctor "$home" --check --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "--check after fix: exit 0"
assert_contains "$DOCTOR_STDOUT" "OK:" "--check after fix prints the OK: line"
rm -rf "$tmp"

echo "=== test_doctor_embedded: drift (a) deleted .claude/memory - DRIFT, fix repairs, re-check clean ==="
tmp="$(mktemp -d)"
make_embedded_fixture "$tmp"
repo="$tmp/embedded-repo"
home="$tmp/home"
run_doctor "$home" --root "$repo"
rm -f "$repo/.claude/memory"

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "deleted .claude/memory: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: .claude/memory -> MISSING, expected ../.agents/memory" "deleted .claude/memory named in DRIFT"

run_doctor "$home" --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "fix mode repairs .claude/memory: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: .claude/memory -> ../.agents/memory" "fix mode reports FIXED for .claude/memory"
assert_symlink "$repo/.claude/memory" "../.agents/memory" ".claude/memory recreated correctly"

run_doctor "$home" --check --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "re-check after repair: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_embedded: drift (b) wrong CLAUDE.md target - DRIFT, fix repairs, re-check clean ==="
tmp="$(mktemp -d)"
make_embedded_fixture "$tmp"
repo="$tmp/embedded-repo"
home="$tmp/home"
run_doctor "$home" --root "$repo"
ln -sfn /nonexistent "$repo/CLAUDE.md"

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "wrong CLAUDE.md target: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: CLAUDE.md -> /nonexistent, expected AGENTS.md" "wrong CLAUDE.md target named in DRIFT"

run_doctor "$home" --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "fix mode repairs CLAUDE.md: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: CLAUDE.md -> AGENTS.md" "fix mode reports FIXED for CLAUDE.md"
assert_symlink "$repo/CLAUDE.md" "AGENTS.md" "CLAUDE.md repointed correctly"

run_doctor "$home" --check --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "re-check after repair: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_embedded: drift (c) .codex/hooks.json with another machine's absolute prefix - DRIFT (exact-match, not substring), fix regenerates, re-check clean ==="
tmp="$(mktemp -d)"
make_embedded_fixture "$tmp"
repo="$tmp/embedded-repo"
home="$tmp/home"
root_abs="$(repo_abs "$repo")"
run_doctor "$home" --root "$repo"

# Plant a hooks.json that is well-formed (right shape, both hooks present)
# but rooted at a DIFFERENT machine's absolute path. A naive substring check
# (e.g. grep -q on just the hook's relative suffix) would wrongly accept
# this; doctor.sh's grep -qxF exact-match on the full '<root>/<hook>' string
# must reject it.
stale_root="/Users/other/dev/GitHub/Jin-HoMLee/claude-personas/embedded-repo"
cat > "$repo/.codex/hooks.json" <<EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'$stale_root/.agents/hooks/hook-a.sh'",
            "timeout": 10,
            "statusMessage": "Running hook-a.sh…"
          },
          {
            "type": "command",
            "command": "'$stale_root/.agents/hooks/hook-b.sh'",
            "timeout": 10,
            "statusMessage": "Running hook-b.sh…"
          }
        ]
      }
    ]
  }
}
EOF

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "stale absolute prefix in .codex/hooks.json: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: .codex/hooks.json does not wire all declared codex_hook entries for this root ($root_abs)" "stale prefix named in DRIFT despite matching shape"

run_doctor "$home" --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "fix mode regenerates .codex/hooks.json: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: .codex/hooks.json regenerated for $root_abs" "fix mode reports FIXED for hooks.json regeneration"
assert_equal "0" "$(jq empty "$repo/.codex/hooks.json" >/dev/null 2>&1; echo $?)" "regenerated .codex/hooks.json is valid JSON"
regen_cmds="$(jq -r '.hooks.SessionStart[]?.hooks[]?.command' "$repo/.codex/hooks.json")"
assert_contains "$regen_cmds" "'$root_abs/.agents/hooks/hook-a.sh'" "regenerated hooks.json wires hook-a for this root exactly"
assert_contains "$regen_cmds" "'$root_abs/.agents/hooks/hook-b.sh'" "regenerated hooks.json wires hook-b for this root exactly"

run_doctor "$home" --check --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "re-check after regeneration: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_embedded: drift (d) settings.json missing the declared claude_hook - DRIFT (report-only), fix mode never touches settings.json ==="
tmp="$(mktemp -d)"
make_embedded_fixture "$tmp"
repo="$tmp/embedded-repo"
home="$tmp/home"
run_doctor "$home" --root "$repo"
cat > "$repo/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": []
      }
    ]
  }
}
EOF
before_settings="$(cksum "$repo/.claude/settings.json")"

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "settings.json missing claude_hook: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: .claude/settings.json does not wire claude_hook '.agents/hooks/hook-a.sh' via \$CLAUDE_PROJECT_DIR" "missing settings.json wiring named in DRIFT"

run_doctor "$home" --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "fix mode also reports the drift: exit 1 (report-only, never fixed)"
assert_contains "$DOCTOR_STDOUT" "DRIFT: .claude/settings.json does not wire claude_hook '.agents/hooks/hook-a.sh' via \$CLAUDE_PROJECT_DIR" "fix mode still names the drift"
after_settings="$(cksum "$repo/.claude/settings.json")"
assert_equal "$before_settings" "$after_settings" "fix mode left settings.json byte-identical"

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "re-check: drift persists (report-only, nothing to fix)"
rm -rf "$tmp"

echo "=== test_doctor_embedded: drift (e) opencode.json without the memory-index entry - DRIFT (report-only) ==="
tmp="$(mktemp -d)"
make_embedded_fixture "$tmp"
repo="$tmp/embedded-repo"
home="$tmp/home"
run_doctor "$home" --root "$repo"
cat > "$repo/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": []
}
EOF
before_opencode="$(cksum "$repo/opencode.json")"

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "opencode.json missing the entry: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: opencode.json missing or its instructions lack \".agents/memory/MEMORY.md\"" "missing opencode entry named in DRIFT"

run_doctor "$home" --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "fix mode also reports the drift: exit 1 (report-only, never fixed)"
after_opencode="$(cksum "$repo/opencode.json")"
assert_equal "$before_opencode" "$after_opencode" "fix mode left opencode.json byte-identical"

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "re-check: drift persists (report-only, nothing to fix)"
rm -rf "$tmp"

echo "=== test_doctor_embedded: drift (f) missing external hop - DRIFT, fix creates, re-check clean ==="
tmp="$(mktemp -d)"
make_embedded_fixture "$tmp"
repo="$tmp/embedded-repo"
home="$tmp/home"
root_abs="$(repo_abs "$repo")"
ext="$(external_hop "$root_abs" "$home")"
run_doctor "$home" --root "$repo"
rm -f "$ext"

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "missing external hop: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: external CC auto-memory symlink missing ($ext)" "missing external hop named in DRIFT"

run_doctor "$home" --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "fix mode recreates the external hop: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: $ext -> $root_abs/.claude/memory" "fix mode reports FIXED for the external hop"
assert_symlink "$ext" "$root_abs/.claude/memory" "external hop recreated correctly"

run_doctor "$home" --check --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "re-check after repair: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_embedded: drift (g) REAL directory with a file at the external hop - DRIFT persists in both modes, content untouched ==="
tmp="$(mktemp -d)"
make_embedded_fixture "$tmp"
repo="$tmp/embedded-repo"
home="$tmp/home"
root_abs="$(repo_abs "$repo")"
ext="$(external_hop "$root_abs" "$home")"
run_doctor "$home" --root "$repo"
rm -f "$ext"
mkdir -p "$ext"
printf 'a real, hand-written memory file - never touch this\n' > "$ext/hand-written.md"
before_sum="$(cksum "$ext/hand-written.md")"

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "real dir at external hop: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: $ext is a real directory - Claude Code may have written memories there; reconcile by hand" "real dir named in DRIFT (check mode)"

run_doctor "$home" --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "real dir at external hop: fix mode also refuses, exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: $ext is a real directory - Claude Code may have written memories there; reconcile by hand" "real dir named in DRIFT (fix mode)"
after_sum="$(cksum "$ext/hand-written.md")"
assert_equal "$before_sum" "$after_sum" "fix mode left the real directory's content byte-identical"

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "real dir drift persists on a subsequent --check"
rm -rf "$tmp"

echo "=== test_doctor_embedded: fix-mode pass repairs all fixables at once; re-check leaves only the report-only DRIFTs standing ==="
tmp="$(mktemp -d)"
make_embedded_fixture "$tmp"
repo="$tmp/embedded-repo"
home="$tmp/home"
root_abs="$(repo_abs "$repo")"
ext="$(external_hop "$root_abs" "$home")"
run_doctor "$home" --root "$repo"

# Inject every fixable drift simultaneously.
rm -f "$repo/.claude/memory"
ln -sfn /nonexistent "$repo/CLAUDE.md"
stale_root="/Users/other/dev/GitHub/Jin-HoMLee/claude-personas/embedded-repo"
cat > "$repo/.codex/hooks.json" <<EOF
{"hooks":{"SessionStart":[{"hooks":[
  {"type":"command","command":"'$stale_root/.agents/hooks/hook-a.sh'","timeout":10,"statusMessage":"x"},
  {"type":"command","command":"'$stale_root/.agents/hooks/hook-b.sh'","timeout":10,"statusMessage":"x"}
]}]}}
EOF
rm -f "$ext"

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "combined fixable drifts: --check exit 1 before fixing"

run_doctor "$home" --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "fix-mode pass repairs every fixable drift at once: exit 0"
assert_symlink "$repo/.claude/memory" "../.agents/memory" "combined pass: .claude/memory repaired"
assert_symlink "$repo/CLAUDE.md" "AGENTS.md" "combined pass: CLAUDE.md repaired"
assert_symlink "$ext" "$root_abs/.claude/memory" "combined pass: external hop recreated"
assert_equal "0" "$(jq empty "$repo/.codex/hooks.json" >/dev/null 2>&1; echo $?)" "combined pass: regenerated hooks.json is valid JSON"
combined_cmds="$(jq -r '.hooks.SessionStart[]?.hooks[]?.command' "$repo/.codex/hooks.json")"
assert_contains "$combined_cmds" "'$root_abs/.agents/hooks/hook-a.sh'" "combined pass: hooks.json wires hook-a exactly for this root"
assert_contains "$combined_cmds" "'$root_abs/.agents/hooks/hook-b.sh'" "combined pass: hooks.json wires hook-b exactly for this root"

run_doctor "$home" --check --root "$repo"
assert_equal "0" "$DOCTOR_EXIT" "re-check after the combined fix pass: exit 0 (nothing left standing)"

# Now re-inject the three report-only drifts (settings.json, opencode.json,
# a real dir at the external hop) and confirm --check names ONLY those.
cat > "$repo/.claude/settings.json" <<'EOF'
{"hooks":{"SessionStart":[{"hooks":[]}]}}
EOF
cat > "$repo/opencode.json" <<'EOF'
{"$schema": "https://opencode.ai/config.json", "instructions": []}
EOF
rm -f "$ext"
mkdir -p "$ext"
printf 'hand-written, never touch\n' > "$ext/note.md"
before_final_sum="$(cksum "$ext/note.md")"

run_doctor "$home" --check --root "$repo"
assert_equal "1" "$DOCTOR_EXIT" "re-injected report-only drifts: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: .claude/settings.json does not wire claude_hook '.agents/hooks/hook-a.sh' via \$CLAUDE_PROJECT_DIR" "final check names the settings.json drift"
assert_contains "$DOCTOR_STDOUT" "DRIFT: opencode.json missing or its instructions lack \".agents/memory/MEMORY.md\"" "final check names the opencode.json drift"
assert_contains "$DOCTOR_STDOUT" "DRIFT: $ext is a real directory - Claude Code may have written memories there; reconcile by hand" "final check names the real-dir drift"
# Nothing else should have regressed: no in-repo link / codex / external-hop
# drift text should reappear now that the fixable set was already repaired.
case "$DOCTOR_STDOUT" in
  *"DRIFT: .claude/memory"*) echo "  FAIL: .claude/memory drift resurfaced after the combined fix pass" ;;
  *) : ;;
esac
after_final_sum="$(cksum "$ext/note.md")"
assert_equal "$before_final_sum" "$after_final_sum" "real-dir content stays byte-identical across the final --check"
rm -rf "$tmp"

print_summary
