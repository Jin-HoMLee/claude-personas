#!/usr/bin/env bash
# Test doctor.sh's role-clones topology catalog: role discovery + candidate
# walk (memory-repo self-mount, no-suffix clone, suffixed clone - same order
# as list-roles.sh); per claimed workspace, the two-hop mount (.agents/memory,
# .claude/memory), the .git/info/exclude entries init-clone.sh owns, and the
# three vendor checks (external CC hop, .codex/hooks.json, OpenCode per the
# declared mode). This task's slice stops at the FIRST claimant per role
# (Task 7 makes the walk exhaustive); the orphan sweep is Task 8.
#
# The fixture is wired by RUNNING the real init-clone.sh (never hand-rolled),
# on top of make_clone_test_fixture, mirroring test_init_clone.sh's and
# test_list_roles.sh's invocation pattern. The fixture ships a real
# .agents/hooks/lib/inject-role-index.sh (copied from this repo) so init-clone.sh's
# Codex adapter actually wires .codex/hooks.json instead of WARN-and-skip;
# with that in place init-clone.sh exits 0, but the runs below still tolerate
# exit 2 defensively.
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
# into the memory repo. Also seeds the machine-wide (fixture-HOME)
# ~/.config/opencode/opencode.json WITH the relative memory-index entry, so
# the default opencode=global manifest is genuinely clean out of the box -
# init-clone.sh's own OpenCode wiring is a one-time manual step it can only
# print a reminder for, never script (see wire_opencode_adapter). Leaves
# globals MEMREPO / DEVCLONE / PMCLONE / HOME_DIR (raw fixture paths, for
# filesystem operations) and MEMREPO_ABS / DEVCLONE_ABS / PMCLONE_ABS (pwd -P
# resolved, for matching doctor.sh's own output) set for the caller.
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

  # Ship a real .agents/hooks/lib/inject-role-index.sh (the installed-payload
  # location) so init-clone.sh's Codex adapter actually generates
  # .codex/hooks.json for every workspace below, instead of the WARN-and-skip
  # path this fixture used to hit.
  stage_inject_script "$MEMREPO"

  ( cd "$MEMREPO" && \
    git -c user.email=t@x -c user.name=T add -A && \
    git -c user.email=t@x -c user.name=T commit --quiet -m "add memory_manager role + inject-role-index.sh" )

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

  mkdir -p "$HOME_DIR/.config/opencode"
  cat > "$HOME_DIR/.config/opencode/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": [".agents/memory/MEMORY.md"]
}
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

echo "=== test_doctor_role_clones: drift (d) dangling external CC hop for the developer clone - DRIFT, fix repairs, re-check clean ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"
ext_dev="$HOME_DIR/.claude/projects/$(compute_hash "$DEVCLONE_ABS")/memory"
ln -sfn /nonexistent "$ext_dev"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "dangling developer external hop: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: external CC hop for role developer -> /nonexistent, expected $DEVCLONE_ABS/.claude/memory" "dangling developer external hop named in DRIFT"

run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "fix mode repairs the dangling developer external hop: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: external CC hop for role developer -> $DEVCLONE_ABS/.claude/memory" "fix mode reports FIXED for developer external hop"
assert_symlink "$ext_dev" "$DEVCLONE_ABS/.claude/memory" "developer external hop repointed correctly"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "re-check after repair: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: drift (e) pm .codex/hooks.json carries another machine's memory-repo prefix - DRIFT despite plausible shape, fix regenerates, re-check clean ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"
cat > "$PMCLONE/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'/Users/other/dev/claude-personas-myapp/.agents/hooks/lib/inject-role-index.sh' '/Users/other/dev/claude-personas-myapp/pm'",
            "timeout": 10,
            "statusMessage": "Injecting role memory index…"
          }
        ]
      }
    ]
  }
}
EOF

# NOTE: the codex-check's memory-repo path is deliberately the LOGICAL $(pwd)
# of --root (matching init-clone.sh's own $MEMORY_REPO="$(pwd)" convention -
# see doctor.sh's _role_clones_check_codex_hooks_json comment), not the
# canonical MEMREPO_ABS used everywhere else in this file. Since this test
# invokes doctor.sh with --root "$MEMREPO" (the raw fixture path), doctor's
# own logical resolution reproduces that same raw string - assert against
# $MEMREPO, not $MEMREPO_ABS, for this one piece of the message.
run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "pm hooks.json with foreign prefix: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: $PMCLONE_ABS/.codex/hooks.json does not exactly wire role pm's inject-role-index.sh for this memory repo ($MEMREPO)" "foreign-prefix hooks.json named in DRIFT"

run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "fix mode regenerates pm hooks.json: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: $PMCLONE_ABS/.codex/hooks.json regenerated for role pm" "fix mode reports FIXED for pm hooks.json regeneration"
assert_equal "0" "$(jq empty "$PMCLONE/.codex/hooks.json" >/dev/null 2>&1; echo $?)" "regenerated pm hooks.json is valid JSON"
regen_cmd="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$PMCLONE/.codex/hooks.json")"
assert_equal "'$MEMREPO/.agents/hooks/lib/inject-role-index.sh' '$MEMREPO/pm'" "$regen_cmd" "regenerated pm hooks.json command is exact"
if grep -qxF '/.codex/hooks.json' "$PMCLONE/.git/info/exclude"; then
  echo "  PASS: /.codex/hooks.json exclude line present after regeneration"
else
  echo "  FAIL: /.codex/hooks.json exclude line missing after regeneration"; exit 1
fi

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "re-check after repair: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: drift (f) opencode=global with the fixture-home global file lacking the entry - report-only DRIFT in both modes, file untouched ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"
global_oc="$HOME_DIR/.config/opencode/opencode.json"
cat > "$global_oc" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": []
}
EOF
before_global="$(cksum "$global_oc")"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "global opencode.json lacking entry: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: $global_oc missing or its instructions lack \".agents/memory/MEMORY.md\"" "global opencode DRIFT names the exact line to add (check mode)"

run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "global opencode.json lacking entry: fix mode also exits 1 (report-only)"
assert_contains "$DOCTOR_STDOUT" "DRIFT: $global_oc missing or its instructions lack \".agents/memory/MEMORY.md\"" "global opencode DRIFT persists in fix mode (report-only)"
after_global="$(cksum "$global_oc")"
assert_equal "$before_global" "$after_global" "fix mode never touches the global opencode.json"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: opencode=global with the entry already present - clean (no DRIFT) ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"
# setup_wired_fixture already seeds the global opencode.json WITH the entry.
run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "global opencode.json with the entry present: --check exit 0"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: opencode=per-clone - wrong absolute path in developer's opencode.json is DRIFT, fix regenerates, re-check clean ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"
cat > "$MEMREPO/.agents/manifest" <<'EOF'
manifest_version=1
topology=role-clones
memory_layout=roles
adapter=claude-code
adapter=codex
adapter=opencode
opencode=per-clone
EOF
cat > "$DEVCLONE/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": ["/Users/other/dev/myapp/.agents/memory/MEMORY.md"]
}
EOF

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "developer per-clone opencode.json with wrong path: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: $DEVCLONE_ABS/opencode.json instructions[0] is not \"$DEVCLONE_ABS/.agents/memory/MEMORY.md\" for role developer" "wrong per-clone opencode.json named in DRIFT"

run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "fix mode regenerates developer's opencode.json: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: $DEVCLONE_ABS/opencode.json regenerated for role developer" "fix mode reports FIXED for developer opencode.json regeneration"
regen_instr="$(jq -r '.instructions[0]' "$DEVCLONE/opencode.json")"
assert_equal "$DEVCLONE_ABS/.agents/memory/MEMORY.md" "$regen_instr" "regenerated developer opencode.json has the exact absolute path"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "re-check after repair: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: multi-candidate flag (g) stale pre-#40 suffixed memory_manager clone alongside the --self mount - ONE DRIFT naming both paths, report-only, other roles' checks still run ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"

# Hand-plant a stale pre-#40-style suffixed memory_manager clone: a v3.1-shaped
# direct .claude/memory symlink (no .agents/memory two-hop), NOT wired via
# init-clone.sh - it refuses a bare "memory_manager" role arg (see
# init-clone.sh's guard: "Run '$(basename "$0") --self' ... instead").
STALECLONE="$tmp/myapp-memory_manager"
git clone --quiet "$tmp/project-repo.git" "$STALECLONE"
mkdir -p "$STALECLONE/.claude"
ln -s "../../claude-personas-myapp/memory_manager" "$STALECLONE/.claude/memory"
STALECLONE_ABS="$(repo_abs "$STALECLONE")"
stale_link_before="$(readlink "$STALECLONE/.claude/memory")"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "multi-candidate memory_manager: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: role memory_manager claimed by more than one workspace: $MEMREPO_ABS $STALECLONE_ABS - retire or re-wire one (doctor will not pick)" "multi-candidate DRIFT names both memory_manager claimants"
mc_drift_count="$(echo "$DOCTOR_STDOUT" | grep -c "claimed by more than one workspace")"
assert_equal "1" "$mc_drift_count" "exactly one multi-candidate DRIFT line, not one per candidate"

run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "fix mode: multi-candidate flag is report-only, exit stays 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: role memory_manager claimed by more than one workspace: $MEMREPO_ABS $STALECLONE_ABS - retire or re-wire one (doctor will not pick)" "multi-candidate DRIFT persists in fix mode"
stale_link_after="$(readlink "$STALECLONE/.claude/memory")"
assert_equal "$stale_link_before" "$stale_link_after" "fix mode never touches the stale clone's v3.1 symlink"
assert_not_exists "$STALECLONE/.agents/memory" "fix mode never creates an .agents/memory hop on the stale (non-first) claimant"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "re-check after fix: still exit 1 (multi-candidate flag has nothing to fix)"
assert_contains "$DOCTOR_STDOUT" "DRIFT: role memory_manager claimed by more than one workspace: $MEMREPO_ABS $STALECLONE_ABS - retire or re-wire one (doctor will not pick)" "multi-candidate DRIFT still present on re-check"

# Single-claimant roles stay clean and their own per-workspace checks still
# run: inject a real mount drift on pm in the same multi-candidate state and
# assert BOTH drifts appear together - the memory_manager refusal must not
# hide pm's real drift, nor vice versa.
rm -f "$PMCLONE/.agents/memory"
run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "multi-candidate + pm mount drift together: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: role memory_manager claimed by more than one workspace: $MEMREPO_ABS $STALECLONE_ABS - retire or re-wire one (doctor will not pick)" "memory_manager multi-candidate DRIFT still present alongside pm's drift"
assert_contains "$DOCTOR_STDOUT" "DRIFT: $PMCLONE_ABS/.agents/memory -> MISSING, expected ../../claude-personas-myapp/pm" "pm mount DRIFT also present - one refusal does not hide the other"
assert_contains "$DOCTOR_STDOUT" "INFO: role designer - no workspace wired" "unrelated unwired roles unaffected by the memory_manager multi-candidate state"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: external-hop orphan sweep (h) dangling sibling slug (moved-clone signature) alongside the constellation's own live hops, a real dir, and an unrelated live symlink - --check names ONLY the dangling one, fix removes ONLY it, re-check clean ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"

# The live hops setup_wired_fixture's own init-clone.sh calls already wired
# for developer and pm - captured before, reasserted untouched after.
dev_ext="$HOME_DIR/.claude/projects/$(compute_hash "$DEVCLONE_ABS")/memory"
pm_ext="$HOME_DIR/.claude/projects/$(compute_hash "$PMCLONE_ABS")/memory"
dev_ext_target_before="$(readlink "$dev_ext")"
pm_ext_target_before="$(readlink "$pm_ext")"

# (1) A dangling symlink under an unrelated slug - the moved-or-deleted-clone
# signature: its target is never created, so it can never resolve.
old_slug="old-moved-clone-slug"
mkdir -p "$HOME_DIR/.claude/projects/$old_slug"
ln -s "$tmp/old-moved-clone/.claude/memory" "$HOME_DIR/.claude/projects/$old_slug/memory"

# (3) A real directory (never a symlink) with a file under another slug.
other_slug="other-real-dir-slug"
mkdir -p "$HOME_DIR/.claude/projects/$other_slug/memory"
printf 'real memory content - never touch\n' > "$HOME_DIR/.claude/projects/$other_slug/memory/note.md"
other_sum_before="$(cksum "$HOME_DIR/.claude/projects/$other_slug/memory/note.md")"

# (4) An unrelated LIVE symlink pointing at a real dir outside the constellation entirely.
unrelated_target="$tmp/unrelated-real-dir"
mkdir -p "$unrelated_target"
unrelated_slug="unrelated-slug"
mkdir -p "$HOME_DIR/.claude/projects/$unrelated_slug"
ln -s "$unrelated_target" "$HOME_DIR/.claude/projects/$unrelated_slug/memory"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "dangling sibling slug present: --check exit 1"
assert_contains "$DOCTOR_STDOUT" "DRIFT: orphan external hop $HOME_DIR/.claude/projects/$old_slug/memory -> $tmp/old-moved-clone/.claude/memory (target gone - moved or deleted clone)" "dangling sibling slug named in DRIFT"
orphan_drift_count="$(echo "$DOCTOR_STDOUT" | grep -c "orphan external hop")"
assert_equal "1" "$orphan_drift_count" "exactly one orphan DRIFT line - live hops, the real dir, and the unrelated live symlink are not named"
case "$DOCTOR_STDOUT" in
  *"$other_slug"*) echo "  FAIL: the real directory's slug appeared in orphan-sweep output"; exit 1 ;;
  *) echo "  PASS: the real directory's slug not named" ;;
esac
case "$DOCTOR_STDOUT" in
  *"$unrelated_slug"*) echo "  FAIL: the unrelated live symlink's slug appeared in orphan-sweep output"; exit 1 ;;
  *) echo "  PASS: the unrelated live symlink's slug not named" ;;
esac

run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "fix mode removes the dangling sibling slug's symlink: exit 0"
assert_contains "$DOCTOR_STDOUT" "FIXED: removed orphan external hop $HOME_DIR/.claude/projects/$old_slug/memory" "fix mode reports FIXED for the orphan removal"
assert_not_exists "$HOME_DIR/.claude/projects/$old_slug/memory" "the orphan symlink itself is gone"
assert_exists "$HOME_DIR/.claude/projects/$old_slug" "the slug directory is NOT removed, only the symlink inside it"

dev_ext_target_after="$(readlink "$dev_ext")"
pm_ext_target_after="$(readlink "$pm_ext")"
assert_equal "$dev_ext_target_before" "$dev_ext_target_after" "developer's live external hop untouched by the sweep"
assert_equal "$pm_ext_target_before" "$pm_ext_target_after" "pm's live external hop untouched by the sweep"

other_sum_after="$(cksum "$HOME_DIR/.claude/projects/$other_slug/memory/note.md")"
assert_equal "$other_sum_before" "$other_sum_after" "the real directory's file stays byte-identical after fix"
assert_symlink "$HOME_DIR/.claude/projects/$unrelated_slug/memory" "$unrelated_target" "the unrelated live symlink is untouched by the sweep"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "re-check after orphan removal: exit 0"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: unembeddable constellation path (apostrophe) - codex regen REFUSED with ERROR; per-clone opencode regen (JSON-only embed) still works ==="
tmp="$(mktemp -d)"
base="$tmp/it's lab"
mkdir -p "$base"
setup_wired_fixture "$base"
# init-clone.sh's own codex adapter refuses apostrophe paths (WARN-and-skip),
# so no workspace has a .codex/hooks.json - each is a codex DRIFT the doctor's
# fix mode will try to regen. The apostrophe is fine inside a JSON string, so
# opencode per-clone regen must still succeed (guard precision, not blanket).
cat > "$MEMREPO/.agents/manifest" <<'EOF'
manifest_version=1
topology=role-clones
memory_layout=roles
adapter=claude-code
adapter=codex
adapter=opencode
opencode=per-clone
EOF

run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "unembeddable path: fix mode exits 1 (codex refusals)"
assert_contains "$DOCTOR_STDOUT" "cannot embed safely in hooks.json" "codex regen refusal ERROR printed"
assert_not_exists "$DEVCLONE/.codex/hooks.json" "no hooks.json written in the developer clone"
assert_contains "$DOCTOR_STDOUT" "opencode.json regenerated for role developer" "per-clone opencode.json still regenerated (apostrophe is JSON-safe)"
assert_exists "$DEVCLONE/opencode.json" "developer per-clone opencode.json exists"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: missing framework payload - matching hooks.json is a dead target (DRIFT, no rewrite); mismatched hooks.json regen REFUSED with ERROR ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"
# Simulate an instance whose payload was never installed (or was removed):
# every hooks.json still carries the exact expected command string.
rm "$MEMREPO/.agents/hooks/lib/inject-role-index.sh"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "dead-target hooks.json: --check exits 1"
assert_contains "$DOCTOR_STDOUT" "missing or not executable - install the framework payload" "DRIFT names the missing payload, not the hooks.json string"

hooks_before="$(cat "$DEVCLONE/.codex/hooks.json")"
run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "dead-target hooks.json: fix mode exits 1 (not fixable here)"
assert_equal "$hooks_before" "$(cat "$DEVCLONE/.codex/hooks.json")" "fix mode did not rewrite hooks.json to a dangling command"

# Mismatched hooks.json + missing payload: regen must REFUSE with ERROR, not
# write a command pointing at the absent script.
printf '{\n  "hooks": {}\n}\n' > "$PMCLONE/.codex/hooks.json"
run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "1" "$DOCTOR_EXIT" "mismatch + missing payload: fix mode exits 1"
assert_contains "$DOCTOR_STDOUT" "not regenerated: $MEMREPO/.agents/hooks/lib/inject-role-index.sh missing or not executable" "regen refusal ERROR names the missing script"
assert_contains "$(cat "$PMCLONE/.codex/hooks.json")" '"hooks": {}' "pm hooks.json left untouched by the refused regen"
rm -rf "$tmp"

echo "=== test_doctor_role_clones: aliased clone (i) developer canonicalized on .agents with .claude -> .agents (#78) - a WORKING mount survives fix mode, --check stays clean, never a self-loop ==="
tmp="$(mktemp -d)"
setup_wired_fixture "$tmp"

# Re-shape the developer clone to the flagship consumer's committed layout:
# one real .agents/ dir, .claude a compatibility symlink to it. Both hop
# paths are then ONE inode, so doctor's two per-workspace link expectations
# collapse onto the same file - the #78 trigger. Starting state is a
# CORRECT, working mount; doctor must never degrade it.
rm -rf "$DEVCLONE/.claude"
ln -s .agents "$DEVCLONE/.claude"
mount_head_before="$(head -1 "$DEVCLONE/.agents/memory/MEMORY.md")"
assert_contains "$mount_head_before" "developer" "aliased developer clone starts with a WORKING mount"

run_doctor "$HOME_DIR" --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "aliased clone: fix mode exit 0 (nothing to fix)"
assert_symlink "$DEVCLONE/.agents/memory" "../../claude-personas-myapp/developer" "fix mode left the .agents/memory mount on the role dir (no self-loop)"
assert_equal "$mount_head_before" "$(head -1 "$DEVCLONE/.agents/memory/MEMORY.md" 2>/dev/null || echo UNREADABLE)" "mount still RESOLVES after fix mode (no ELOOP)"

run_doctor "$HOME_DIR" --check --root "$MEMREPO"
assert_equal "0" "$DOCTOR_EXIT" "aliased clone: --check after fix exit 0"
case "$DOCTOR_STDOUT" in
  *"DRIFT:"*) echo "  FAIL: unexpected DRIFT on the aliased layout:"; echo "$DOCTOR_STDOUT" | grep "DRIFT:"; exit 1 ;;
  *) echo "  PASS: no DRIFT lines on the aliased layout" ;;
esac
case "$DOCTOR_STDOUT" in
  *"INFO: role developer - no workspace wired"*) echo "  FAIL: aliased developer clone lost its role claim after fix mode"; exit 1 ;;
  *) echo "  PASS: developer role still claimed by the aliased clone" ;;
esac
rm -rf "$tmp"

print_summary
