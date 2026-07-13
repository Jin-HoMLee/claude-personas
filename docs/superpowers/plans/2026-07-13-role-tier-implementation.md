# Role Tier (role@user) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement claude-personas#49 per the locked spec `docs/superpowers/specs/2026-07-08-role-tier-design.md`: give each role a cross-project home (`role@user`) in `user-memory`, with manifest/doctor support, mount wiring, and hook/skill updates.

**Architecture:** Three sequenced tracks.
Track A adds framework support in `claude-personas` (manifest key `role_source`, doctor "role-tier readiness" checks + fix-mode symlink materialization, a `role@user` pointer in the Codex inject hook, a new SubagentStart pointer hook, skill + README updates) - all TDD against the existing bash test suite.
Track B seeds the first `role@user` dir and executes the one-commit `user-memory` migration (flat -> roles layout) using only already-shipped doctor code paths.
Track C wires the flagship instance (`claude-personas-splice-neoepitope-pipeline`) and runs the two live E2E acceptance checks.

**Tech Stack:** bash 3.2-compatible shell (macOS), jq, the repo's own test harness (`framework/tools/tests/`), Claude Code headless (`claude -p`) for E2E.

## Global Constraints

- bash 3.2 compatible; every script uses `set -u`, NEVER `set -e` (doctor.sh: "one refusal must not hide others").
- doctor.sh output vocabulary is exactly `DRIFT:` / `FIXED:` / `ERROR:` / `OK:` / `INFO:`; exit codes 0 clean, 1 drift-or-error, 2 missing/invalid manifest.
- The manifest is NEVER shell-sourced; read only via the `manifest_get` / `manifest_get_all` grep/cut readers.
- Hooks are defensive: always `exit 0`, never fail a session start.
- A mount is a POINTER the agent Reads, never an injected payload (#64 pilot: Claude Code silently clips hook `additionalContext` at ~2 KB).
- Precedence chain (spec section 2): `[role@repo >] repo > role@project > project > role@user > user`; the role plane is written `role@<tier-name>`, never "role@global".
- Commit prefixes: `claude-personas: ...` in this repo, `user-memory: ...` in user-memory; cross-repo issue refs are written `claude-personas#49` (a bare `#49` would autolink the wrong repo's tracker). NEVER add an agent co-author line.
- claude-personas changes go via branch + PR (branch created with `gh issue develop 49` so the PR links and closes #49); user-memory and the splice memory repo commit direct to main per their own conventions.
- The splice memory repo has a sole committer (MM). Its Track C commits are framework WIRING (cerebrum's lane by standing agreement), but surface the diff to Jin-Ho before pushing, and the role-index pointer line (content-adjacent) is flagged for MM in the commit message.
- Markdown files written by this plan: one sentence per physical line; plain dash, never an em dash.
- Out of scope (spec section 10): org tier (#66), layer axis (#65), cross-harness parity runs (#67), subagent write side, naming-grammar execution (#27 item 4), flagship memory CONTENT changes.

## File Structure

Track A (claude-personas repo, branch `49-role-tier`):

- `framework/tools/doctor.sh` - `role_source` key validation + `check_role_tier_readiness()` + call site.
- `framework/tools/tests/test_doctor_manifest.sh` - `role_source` scoping cases (append).
- `framework/tools/tests/test_doctor_role_tier.sh` - NEW: readiness-section behavior.
- `framework/hooks/inject-role-index.sh` - conditional `role@user` pointer line.
- `framework/tools/tests/test_inject_role_index.sh` - user-pointer cases (append).
- `framework/hooks/inject-subagent-role-pointer.sh` - NEW: SubagentStart pointer hook.
- `framework/tools/tests/test_inject_subagent_pointer.sh` - NEW: its tests.
- `framework/FILES` - one new mapping line for the new hook.
- `framework/skills/load-persona-memory/SKILL.md` - user-hop read order + path rule + governance line.
- `README.md:102` - precedence chain replaced with the two-axis chain.

Track B (user-memory repo): `shared/` (moved flat tier), `developer/` (first role@user dir), `.agents/manifest` (layout flip), `AGENTS.md` (repointed import + path prose).

Track C (splice memory repo): `.agents/manifest` (+`role_source`), `developer/user` symlink (doctor-materialized), `developer/MEMORY.md` (+1 pointer line), synced framework payload.

---

### Task 1: Manifest accepts `role_source` (validation + scoping)

**Files:**
- Modify: `framework/tools/doctor.sh:39` (ALL_VALID_KEYS), `framework/tools/doctor.sh:376-394` (semantics), `framework/tools/doctor.sh:420-424` (globals)
- Test: `framework/tools/tests/test_doctor_manifest.sh` (append)

**Interfaces:**
- Consumes: existing `manifest_get`, `_word_in_list`, validation flow.
- Produces: global `ROLE_SOURCE` (string, empty when key absent) that Task 2 reads; the invariant "a validated manifest never has `role_source` on user-tier, never absolute".

- [ ] **Step 1: Write the failing tests**

Append to `framework/tools/tests/test_doctor_manifest.sh` (before any final summary lines; the file is scenario-per-block, `run_doctor` is already defined at the top):

```bash
echo "=== test_doctor_manifest: role_source scoping (claude-personas#49 role tier) ==="
# (a) role_source on topology=user-tier: hard error, exit 2.
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents/memory"
echo "# idx" > "$tmp/.agents/memory/MEMORY.md"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=user-tier
memory_layout=flat
role_source=../user-memory
EOF
run_doctor --check --root "$tmp"
assert_equal "2" "$DOCTOR_EXIT" "role_source on user-tier: exit 2"
assert_contains "$DOCTOR_STDERR" "role_source" "user-tier error names role_source"
rm -rf "$tmp"

# (b) absolute role_source: hard error, exit 2.
tmp="$(mktemp -d)"
mkdir -p "$tmp/.agents/memory"
echo "# idx" > "$tmp/.agents/memory/MEMORY.md"
echo "# agents" > "$tmp/AGENTS.md"
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
role_source=/abs/user-memory
EOF
run_doctor --check --root "$tmp"
assert_equal "2" "$DOCTOR_EXIT" "absolute role_source: exit 2"
assert_contains "$DOCTOR_STDERR" "repo-relative" "absolute error says repo-relative"
rm -rf "$tmp"

# (c) relative role_source on embedded, target is a roles-layout git repo:
# manifest accepted (doctor proceeds past validation; fix mode exits 0).
tmp="$(mktemp -d)"
mkdir -p "$tmp/inst/.agents/memory" "$tmp/user-memory/.git" "$tmp/user-memory/.agents" "$tmp/user-memory/shared"
echo "# idx" > "$tmp/inst/.agents/memory/MEMORY.md"
echo "# agents" > "$tmp/inst/AGENTS.md"
cat > "$tmp/inst/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
role_source=../user-memory
EOF
cat > "$tmp/user-memory/.agents/manifest" <<'EOF'
manifest_version=1
topology=user-tier
memory_layout=roles
EOF
echo "# shared" > "$tmp/user-memory/shared/MEMORY.md"
run_doctor --root "$tmp/inst"
assert_equal "0" "$DOCTOR_EXIT" "valid role_source on embedded: exit 0"
rm -rf "$tmp"
```

- [ ] **Step 2: Run the test file, verify the new cases fail**

Run: `bash framework/tools/tests/test_doctor_manifest.sh`
Expected: case (a) FAILs (doctor currently exits 2 with "unknown manifest key 'role_source'", so (a) accidentally half-passes on exit code but the (c) acceptance case FAILs with exit 2 instead of 0 - that is the driving failure).

- [ ] **Step 3: Implement**

In `framework/tools/doctor.sh` make three edits.

Edit 1 - extend the whitelist (line 39):

```bash
ALL_VALID_KEYS="manifest_version topology memory_layout adapter claude_hook codex_hook skills_mount opencode framework_source framework_ref role_source"
```

Edit 2 - append to `validate_manifest_semantics()`, after the `claude_hook / codex_hook` repo-relative loop (after line 394):

```bash
  # role_source (optional, consumer-side, claude-personas#49): points a
  # role-clones or embedded instance at the user-scope roles instance.
  # Hard error on user-tier (self-reference: the user-tier instance IS the
  # role tier's home). Must be repo-relative: the committed <role>/user
  # symlinks are derived from it and encode the sibling-layout assumption.
  v="$(manifest_get role_source)"
  if [ -n "$v" ]; then
    if [ "$topology" = "user-tier" ]; then
      echo "ERROR: key 'role_source' is not valid for topology=user-tier (the user-tier instance is the role tier's home, not a consumer of it) in $MANIFEST" >&2
      exit 2
    fi
    case "$v" in
      /*)
        echo "ERROR: role_source '$v' in $MANIFEST must be a repo-relative path, not absolute" >&2
        exit 2
        ;;
    esac
  fi
```

Edit 3 - populate the global, after the `OPENCODE_MODE` block (line 424):

```bash
ROLE_SOURCE="$(manifest_get role_source)"
```

- [ ] **Step 4: Run the test file, verify all cases pass**

Run: `bash framework/tools/tests/test_doctor_manifest.sh`
Expected: all PASS, including the three new cases.

- [ ] **Step 5: Run the full suite (regression: zero role-tier output on instances without the key)**

Run: `bash framework/tools/tests/run_all.sh`
Expected: exit 0, no FAIL lines (this is the "instance without role_source emits zero role-tier findings" AC's regression half; Task 2 adds the positive half).

- [ ] **Step 6: Commit**

```bash
git add framework/tools/doctor.sh framework/tools/tests/test_doctor_manifest.sh
git commit -m "claude-personas: manifest accepts role_source (scoped, repo-relative) (#49)"
```

---

### Task 2: Doctor role-tier readiness - target checks

**Files:**
- Modify: `framework/tools/doctor.sh` (new function before the `# Shared floor` block at line 1255; call site after the topology `case` at line 1264)
- Test: `framework/tools/tests/test_doctor_role_tier.sh` (NEW)

**Interfaces:**
- Consumes: `ROLE_SOURCE` (Task 1), `report_error`, `report_drift`, `need_link`, `CHECK`, `ROOT`.
- Produces: `check_role_tier_readiness()` - Task 3 extends its per-role loop; the function early-returns silently when `ROLE_SOURCE` is empty.

- [ ] **Step 1: Write the failing tests**

Create `framework/tools/tests/test_doctor_role_tier.sh`:

```bash
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

print_summary
```

(`print_summary` is the shared summary reporter every `test_*.sh` file ends with; it lives in `test_helpers.sh`.)

- [ ] **Step 2: Run it, verify failure**

Run: `bash framework/tools/tests/test_doctor_role_tier.sh`
Expected: scenarios 1-3 FAIL (doctor exits 0 today: the key parses after Task 1 but nothing checks the target).

- [ ] **Step 3: Implement the function + call site**

In `framework/tools/doctor.sh`, insert before the `# Shared floor for every topology` comment (line 1255):

```bash
check_role_tier_readiness() {
  # Role-tier readiness (claude-personas#49 spec section 5): active only
  # when the manifest declares role_source (validated in Task 1: never on
  # user-tier, never absolute). Target checks: the path resolves, is a git
  # repo, and its manifest declares memory_layout=roles - a flat target
  # means the pointer was wired before the user-memory migration (spec
  # section 3) and is an ERROR, not a fixable drift.
  [ -n "$ROLE_SOURCE" ] || return 0

  local src_abs target_layout
  src_abs="$(cd "$ROOT/$ROLE_SOURCE" 2>/dev/null && pwd)"
  if [ -z "$src_abs" ]; then
    report_error "role_source '$ROLE_SOURCE' unreachable from $ROOT"
    return 0
  fi
  if [ ! -d "$src_abs/.git" ]; then
    report_error "role_source '$ROLE_SOURCE' ($src_abs) is not a git repo"
    return 0
  fi
  target_layout="$(grep -v '^[[:space:]]*#' "$src_abs/.agents/manifest" 2>/dev/null \
    | grep '^memory_layout=' | head -n1 | cut -d= -f2-)"
  if [ "$target_layout" != "roles" ]; then
    report_error "role_source '$ROLE_SOURCE' declares memory_layout='${target_layout:-MISSING}', expected 'roles' - wire role_source only after the user-memory migration (claude-personas#49 spec section 3)"
    return 0
  fi

  _role_tier_check_roles "$src_abs"
}

_role_tier_check_roles() {
  # Per-role symlink checks land in Task 3; stub keeps Task 2 green.
  :
}
```

And after the topology `case ... esac` (line 1264), before the `DRIFT_COUNT` exit check:

```bash
check_role_tier_readiness
```

- [ ] **Step 4: Run the test file, verify pass**

Run: `bash framework/tools/tests/test_doctor_role_tier.sh`
Expected: all PASS.

- [ ] **Step 5: Full suite**

Run: `bash framework/tools/tests/run_all.sh`
Expected: exit 0 (the new file is auto-discovered by the `test_*.sh` glob).

- [ ] **Step 6: Commit**

```bash
git add framework/tools/doctor.sh framework/tools/tests/test_doctor_role_tier.sh
git commit -m "claude-personas: doctor role-tier readiness - role_source target checks (#49)"
```

---

### Task 3: Doctor role-tier readiness - per-role symlink checks + lazy fix-mode materialization

**Files:**
- Modify: `framework/tools/doctor.sh` (`_role_tier_check_roles` stub from Task 2)
- Test: `framework/tools/tests/test_doctor_role_tier.sh` (append)

**Interfaces:**
- Consumes: `_role_tier_check_roles <src_abs>` stub (Task 2), `need_link`, `report_drift`, `CHECK`.
- Produces: the final readiness behavior Tracks B/C rely on: fix mode materializes `<role>/user -> ../<role_source>/<role>` exactly when `<src_abs>/<role>/MEMORY.md` exists; absence is never drift; an existing symlink is validated (target text + resolution).

- [ ] **Step 1: Write the failing tests**

Append to `framework/tools/tests/test_doctor_role_tier.sh` (before the summary block):

```bash
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
```

- [ ] **Step 2: Run it, verify scenarios 5-8 fail**

Run: `bash framework/tools/tests/test_doctor_role_tier.sh`
Expected: scenarios 1-4 PASS, 5-8 FAIL (the stub does nothing).

- [ ] **Step 3: Implement `_role_tier_check_roles`**

Replace the Task 2 stub in `framework/tools/doctor.sh`:

```bash
_role_tier_check_roles() {
  # _role_tier_check_roles <src_abs>
  # Per-role <role>/user mount checks (claude-personas#49 spec sections 4d
  # + 5). Role discovery: same rule as check_payload / list-roles.sh - a
  # root-level dir with MEMORY.md, excluding shared and examples.
  # Lazy by design: NO symlink and NO target role dir is the normal state
  # (silent in both modes); fix mode materializes the symlink only once the
  # target role dir exists; --check never flags a missing symlink (creation
  # is fix-mode's job, not a drift). An EXISTING symlink is held to the
  # full standard: exact ../<role_source>/<role> target text AND resolving.
  local src_abs="$1"
  local d n link_path expected_target

  for d in "$ROOT"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    [ -f "$d/MEMORY.md" ] || continue
    if [ "$n" = "shared" ] || [ "$n" = "examples" ]; then
      continue
    fi

    link_path="$ROOT/$n/user"
    expected_target="../$ROLE_SOURCE/$n"

    if [ -L "$link_path" ]; then
      need_link "$link_path" "$expected_target" "$n/user"
      if [ -L "$link_path" ] && [ ! -e "$link_path" ]; then
        report_drift "$n/user -> $(readlink "$link_path") dangles - role@user dir missing at $src_abs/$n (restore it there or remove the symlink)"
      fi
    elif [ -e "$link_path" ]; then
      report_drift "$n/user exists and is not a symlink (refusing to touch)"
    elif [ -f "$src_abs/$n/MEMORY.md" ] && [ "$CHECK" != 1 ]; then
      need_link "$link_path" "$expected_target" "$n/user"
    fi
  done
}
```

- [ ] **Step 4: Run the test file, verify all pass**

Run: `bash framework/tools/tests/test_doctor_role_tier.sh`
Expected: all 8 scenarios PASS.

- [ ] **Step 5: Full suite**

Run: `bash framework/tools/tests/run_all.sh`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add framework/tools/doctor.sh framework/tools/tests/test_doctor_role_tier.sh
git commit -m "claude-personas: doctor materializes <role>/user lazily from role_source (#49)"
```

---

### Task 4: Codex inject hook - `role@user` pointer line

**Files:**
- Modify: `framework/hooks/inject-role-index.sh:73-76`
- Test: `framework/tools/tests/test_inject_role_index.sh` (append)

**Interfaces:**
- Consumes: the hook's existing `$payload` assembly and `$role_dir`.
- Produces: a conditional pointer line `# Role user-tier memory index (loaded on demand): read <role_dir>/user/MEMORY.md`, emitted AFTER the shared pointer (reading order mirrors the precedence chain: role > shared(project) > role@user).

- [ ] **Step 1: Write the failing tests**

Append to `framework/tools/tests/test_inject_role_index.sh` a self-contained block (it defines its own locals; `SCRIPT_DIR` and helpers are already sourced at the top of that file):

```bash
echo "=== test_inject_role_index: role@user pointer (claude-personas#49) ==="
INJECT_HOOK="$(cd "$SCRIPT_DIR/../.." && pwd)/hooks/inject-role-index.sh"

# (a) user/MEMORY.md present: pointer line appears, AFTER the shared pointer.
tmp="$(mktemp -d)"
mkdir -p "$tmp/dev/shared" "$tmp/dev/user"
echo "# dev index" > "$tmp/dev/MEMORY.md"
echo "# shared index" > "$tmp/dev/shared/MEMORY.md"
echo "# dev@user index" > "$tmp/dev/user/MEMORY.md"
ctx="$(bash "$INJECT_HOOK" "$tmp/dev" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "# Role user-tier memory index (loaded on demand): read $tmp/dev/user/MEMORY.md" "user pointer line present"
shared_line_no="$(printf '%s\n' "$ctx" | grep -n 'Shared memory index' | cut -d: -f1)"
user_line_no="$(printf '%s\n' "$ctx" | grep -n 'user-tier memory index' | cut -d: -f1)"
if [ -n "$shared_line_no" ] && [ -n "$user_line_no" ] && [ "$user_line_no" -gt "$shared_line_no" ]; then
  assert_equal "ordered" "ordered" "user pointer comes after shared pointer"
else
  assert_equal "ordered" "unordered" "user pointer comes after shared pointer"
fi
rm -rf "$tmp"

# (b) no user/MEMORY.md: no user pointer line (lazy - never point at nothing).
tmp="$(mktemp -d)"
mkdir -p "$tmp/dev/shared"
echo "# dev index" > "$tmp/dev/MEMORY.md"
echo "# shared index" > "$tmp/dev/shared/MEMORY.md"
ctx="$(bash "$INJECT_HOOK" "$tmp/dev" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx" in
  *"user-tier memory index"*) assert_equal "absent" "present" "no user pointer without user/MEMORY.md" ;;
  *) assert_equal "absent" "absent" "no user pointer without user/MEMORY.md" ;;
esac
rm -rf "$tmp"
```

- [ ] **Step 2: Run it, verify case (a) fails**

Run: `bash framework/tools/tests/test_inject_role_index.sh`
Expected: existing cases PASS, new case (a) FAILs (no user pointer emitted today), (b) PASSes vacuously.

- [ ] **Step 3: Implement**

In `framework/hooks/inject-role-index.sh`, after the shared-pointer block (lines 73-76) and before the truncation-trailer block, insert:

```bash
# role@user index (claude-personas#49): pointer only, and only when the lazy
# mount exists - reading order mirrors the precedence chain (role > shared >
# role@user), so this line comes after the shared pointer.
if [ -r "$role_dir/user/MEMORY.md" ]; then
  payload="$payload
# Role user-tier memory index (loaded on demand): read $role_dir/user/MEMORY.md"
fi
```

- [ ] **Step 4: Run the test file, verify pass**

Run: `bash framework/tools/tests/test_inject_role_index.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add framework/hooks/inject-role-index.sh framework/tools/tests/test_inject_role_index.sh
git commit -m "claude-personas: inject-role-index emits role@user pointer when mounted (#49)"
```

---

### Task 5: SubagentStart pointer hook (new framework hook)

**Files:**
- Create: `framework/hooks/inject-subagent-role-pointer.sh`
- Modify: `framework/FILES` (one mapping line)
- Test: `framework/tools/tests/test_inject_subagent_pointer.sh` (NEW)

**Interfaces:**
- Consumes: Claude Code SubagentStart hook stdin JSON with `.agent_type` (verified live in the #64 pilot); argv[1] = memory-repo root.
- Produces: `{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"<pointer>"}}` on stdout, pointer well under 2 KB; silent `exit 0` for unknown agent types. Instance wiring (settings entries) is NOT this task - it rides the #58 delivery mechanism; Task 10 verifies the behavior with explicit fixture wiring.

- [ ] **Step 1: Write the failing tests**

Create `framework/tools/tests/test_inject_subagent_pointer.sh`:

```bash
#!/usr/bin/env bash
# Test inject-subagent-role-pointer.sh (claude-personas#49 spec section 4b):
# a SubagentStart hook that injects a <2KB POINTER to the spawning role's
# memory indexes, keyed on stdin .agent_type. Never the payload (#64: CC
# silently clips additionalContext at ~2KB on this path).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
HOOK="$(cd "$SCRIPT_DIR/../.." && pwd)/hooks/inject-subagent-role-pointer.sh"

make_memrepo() {
  local base="$1"
  mkdir -p "$base/developer/shared" "$base/developer/user" "$base/pm"
  echo "# dev idx" > "$base/developer/MEMORY.md"
  echo "# shared idx" > "$base/developer/shared/MEMORY.md"
  echo "# dev@user idx" > "$base/developer/user/MEMORY.md"
  echo "# pm idx" > "$base/pm/MEMORY.md"
}

echo "=== inject-subagent-role-pointer: known agent_type gets a pointer ==="
tmp="$(mktemp -d)"
make_memrepo "$tmp"
out="$(printf '{"agent_type":"developer"}' | bash "$HOOK" "$tmp")"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "Read $tmp/developer/MEMORY.md" "pointer names the role index"
assert_contains "$ctx" "Read $tmp/developer/shared/MEMORY.md" "pointer names the shared index"
assert_contains "$ctx" "Read $tmp/developer/user/MEMORY.md" "pointer names the role@user index"
assert_contains "$ctx" "do not read another role's directory" "pointer carries the isolation rule"
assert_equal "SubagentStart" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" "hookEventName is SubagentStart"
if [ "${#ctx}" -lt 2000 ]; then
  assert_equal "under2k" "under2k" "pointer stays under the 2KB clip"
else
  assert_equal "under2k" "over2k" "pointer stays under the 2KB clip"
fi
rm -rf "$tmp"

echo "=== inject-subagent-role-pointer: role without user mount omits the user pointer ==="
tmp="$(mktemp -d)"
make_memrepo "$tmp"
out="$(printf '{"agent_type":"pm"}' | bash "$HOOK" "$tmp")"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "Read $tmp/pm/MEMORY.md" "pm pointer names the pm index"
case "$ctx" in
  *"/pm/user/"*) assert_equal "absent" "present" "no user pointer for unmounted role" ;;
  *) assert_equal "absent" "absent" "no user pointer for unmounted role" ;;
esac
rm -rf "$tmp"

echo "=== inject-subagent-role-pointer: unknown agent_type is silent exit 0 ==="
tmp="$(mktemp -d)"
make_memrepo "$tmp"
out="$(printf '{"agent_type":"Explore"}' | bash "$HOOK" "$tmp")"
rc=$?
assert_equal "0" "$rc" "unknown agent_type exits 0"
assert_equal "" "$out" "unknown agent_type emits nothing"
rm -rf "$tmp"

echo "=== inject-subagent-role-pointer: traversal-shaped agent_type is silent ==="
tmp="$(mktemp -d)"
make_memrepo "$tmp"
out="$(printf '{"agent_type":"../developer"}' | bash "$HOOK" "$tmp")"
assert_equal "" "$out" "path-traversal agent_type emits nothing"
rm -rf "$tmp"
```

End the file with `print_summary` (the shared reporter from `test_helpers.sh`).

- [ ] **Step 2: Run it, verify it fails**

Run: `bash framework/tools/tests/test_inject_subagent_pointer.sh`
Expected: FAIL - the hook does not exist yet.

- [ ] **Step 3: Implement the hook**

Create `framework/hooks/inject-subagent-role-pointer.sh` (then `chmod +x` it):

```bash
#!/usr/bin/env bash
# inject-subagent-role-pointer.sh - Claude Code SubagentStart hook for a
# personas instance: inject a ~250-byte POINTER naming the spawning role
# subagent's memory indexes, never the payload (claude-personas#64 pilot:
# CC silently clips hook additionalContext at ~2 KB on this path, so the
# subagent must Read the files itself - its definition must grant Read).
#
# Usage: inject-subagent-role-pointer.sh <memory-repo-root>
# stdin: the CC hook JSON; .agent_type selects the role dir. An agent_type
# with no <memory-repo-root>/<agent_type>/MEMORY.md gets nothing - built-in
# and non-role agent types pass through silently.
#
# Wiring note: instance delivery (settings entries) rides the #58
# mechanism; this script is the vendor-neutral payload half.
#
# Defensive by design: never fails a spawn - always exits 0.

set -u

memrepo="${1:-}"
[ -n "$memrepo" ] && [ -d "$memrepo" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

agent_type="$(jq -r '.agent_type // empty' 2>/dev/null)"
[ -n "$agent_type" ] || exit 0
# Role dir names are plain slugs; anything else (path separators, dots)
# is not a role and must not become a path component.
case "$agent_type" in
  *[!a-zA-Z0-9_-]*) exit 0 ;;
esac

role_index="$memrepo/$agent_type/MEMORY.md"
[ -r "$role_index" ] || exit 0

ptr="You are the $agent_type role. Before acting: Read $role_index"
if [ -r "$memrepo/$agent_type/shared/MEMORY.md" ]; then
  ptr="$ptr ; then Read $memrepo/$agent_type/shared/MEMORY.md"
fi
if [ -r "$memrepo/$agent_type/user/MEMORY.md" ]; then
  ptr="$ptr ; then Read $memrepo/$agent_type/user/MEMORY.md"
fi
ptr="$ptr . These are routing indexes - follow links relevant to your task; do not read another role's directory."

jq -nc --arg ctx "$ptr" \
  '{hookSpecificOutput:{hookEventName:"SubagentStart",additionalContext:$ctx}}' 2>/dev/null || true
exit 0
```

Run: `chmod +x framework/hooks/inject-subagent-role-pointer.sh`

- [ ] **Step 4: Add the FILES mapping**

Append to `framework/FILES` after the `inject-role-index.sh` line:

```text
framework/hooks/inject-subagent-role-pointer.sh -> .agents/hooks/lib/inject-subagent-role-pointer.sh
```

- [ ] **Step 5: Run the new test file, then the full suite**

Run: `bash framework/tools/tests/test_inject_subagent_pointer.sh`
Expected: all PASS.
Run: `bash framework/tools/tests/run_all.sh`
Expected: exit 0 (`test_framework_files.sh` and `test_install.sh` must stay green with the new FILES line; if either fails, its output names the missing mapping side - fix the FILES line, not the test).

- [ ] **Step 6: Commit**

```bash
git add framework/hooks/inject-subagent-role-pointer.sh framework/FILES framework/tools/tests/test_inject_subagent_pointer.sh
git commit -m "claude-personas: SubagentStart role-pointer hook (payload half; wiring rides #58) (#49)"
```

---

### Task 6: load-persona-memory skill - the user hop

**Files:**
- Modify: `framework/skills/load-persona-memory/SKILL.md:34-60` (Read Order, Path Rules), `:62-73` (Governance)

**Interfaces:**
- Consumes: existing skill structure.
- Produces: the third read hop agents follow; the write-side rule Task 9's promotion path cites.

- [ ] **Step 1: Edit Read Order**

In the Read Order section, replace the two-line code block:

```text
<memory-repo>/<role>/MEMORY.md
<memory-repo>/<role>/shared/MEMORY.md
```

with:

```text
<memory-repo>/<role>/MEMORY.md
<memory-repo>/<role>/shared/MEMORY.md
<memory-repo>/<role>/user/MEMORY.md   (only when the user mount exists)
```

and after the "Treat the role index and shared index as routing tables." sentence, add:

```markdown
When `<role>/user` exists, it is the role@user mount - this role's cross-project home (claude-personas#49).
Read its index third; the reading order mirrors the precedence chain (role@project > project-shared > role@user), so on conflict the earlier read wins.
A missing `<role>/user` is normal (the mount is lazy), never an error.
```

- [ ] **Step 2: Edit Path Rules**

Add to the Path Rules bullet list:

```markdown
- A `user/<file>` link from `<role>/MEMORY.md` resolves through `<role>/user`, which points at this role's dir in the user-scope roles instance (the manifest's `role_source`).
```

- [ ] **Step 3: Edit Governance**

Add to the Governance bullet list:

```markdown
- The `<role>/user` mount is read-only by convention: a promotion to role@user is an explicit write into the user-scope roles instance (`role_source` target), committed in THAT repo - never through the symlink as part of a project-memory commit.
```

- [ ] **Step 4: Verify examples/skills tests stay green, commit**

Run: `bash framework/tools/tests/run_all.sh`
Expected: exit 0.

```bash
git add framework/skills/load-persona-memory/SKILL.md
git commit -m "claude-personas: load-persona-memory learns the role@user hop (#49)"
```

---

### Task 7: README precedence chain + PR

**Files:**
- Modify: `README.md:102`

**Interfaces:**
- Consumes: spec section 2 (chain + terminology settlement).
- Produces: the public doc statement of the two-axis model; closes Track A.

- [ ] **Step 1: Replace the old chain sentence**

`README.md:102` currently ends: `Precedence on conflict: role > project > user (more specific wins).`
Replace that sentence with:

```markdown
Precedence on conflict is generated by one rule - walk scopes most-specific-first, and within a scope the role plane beats the shared plane: `role@project > project > role@user > user` (a reserved repo tier slots in above role@project for multi-repo endeavors; for a single-repo endeavor the chain collapses to exactly this).
A role's cross-project home is written `role@user` and lives in the same `user-memory` instance repo, as top-level role dirs beside `shared/` (the design: `docs/superpowers/specs/2026-07-08-role-tier-design.md`, issue #49).
```

- [ ] **Step 2: Full suite one last time, commit**

Run: `bash framework/tools/tests/run_all.sh`
Expected: exit 0.

```bash
git add README.md
git commit -m "claude-personas: README states the two-axis precedence chain (#49)"
```

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin 49-role-tier
```

Then open a PR titled `claude-personas: role tier (role@user) implementation (#49)` whose body maps each spec section-11 AC to its task here, notes that the two E2E ACs (role-clone pointer follow, subagent recall) are verified in Tracks B/C after merge, and that the #67 cross-harness extension stays open.
Invoke the review bot with an `@claude` comment (it is mention-gated).
Do NOT self-merge: Jin-Ho's merge gate applies.

- [ ] **Step 4: After merge - cut the framework ref**

Read `framework/CHANGELOG.md`, add the release entry following its existing format, and tag per its convention (the prior release used `framework/v1`):

```bash
git tag framework/v1.1 <merge-commit-sha>
git push origin framework/v1.1
```

Consumer instances bump `framework_ref=framework/v1.1` when they sync (Task 9).

---

### Task 8: Seed the first role@user dir (declared facts, human input)

**Files:**
- Create (staged locally, committed in Task 9's atomic commit): `user-memory/developer/MEMORY.md`, `user-memory/developer/<slug>.md` (one per declared fact)

**Interfaces:**
- Consumes: Jin-Ho's declared preferences (interactive step - this is the section-6 "declared facts" write path; it needs the human, not triage).
- Produces: the first real role dir content, which unlocks the migration (doctor refuses `memory_layout=roles` with zero role dirs - that refusal is the sequencing feature).

- [ ] **Step 1: Collect 2-4 declared facts from Jin-Ho**

Ask (AskUserQuestion or plain chat): "Which role gets the first role@user home (developer recommended), and what are 2-4 DECLARED preferences for how you want that role to behave for you, in any project? Declared = true by construction about your taste (example from the spec: 'wants the PM leaning recommending'), NOT lessons - lessons stay put until they promote by second bite."
Constraint check per answer: it must be role-scoped (about how this role behaves) and human-scoped (about Jin-Ho's preference), not project knowledge and not general role craft (general craft is role@org, out of scope until #66).
Anything that fails the check: park it, do not write it.

- [ ] **Step 2: Write one file per fact**

For each fact, create `user-memory/developer/<kebab-slug>.md` (do NOT commit yet):

```markdown
---
name: <kebab-slug>
description: <one-line hook for the index>
metadata:
  type: user
---

<the declared preference, one or two sentences>

**Why:** declared by Jin-Ho (<today's date>), true by construction - written directly at role@user per the claude-personas#49 section-6 declared-facts path, not promoted.
**How to apply:** <one sentence on when the developer role should act on it>
```

- [ ] **Step 3: Write the role index**

Create `user-memory/developer/MEMORY.md`:

```markdown
# Developer role@user Memory Index (Jin-Ho x developer, cross-project)

How Jin-Ho wants the developer role to behave, in every project.
One line per memory file (`- [Title](file.md) - hook`); index only, never inline content.
Scope guard: declared role preferences and personal role calibration ONLY - general developer craft is role@org (claude-personas#66, no home yet), project facts stay in the project.

- [<Title>](<kebab-slug>.md) - <hook>
```

One index line per fact file from Step 2.

- [ ] **Step 4: Verify layout locally (no commit)**

Run: `ls /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/developer/`
Expected: `MEMORY.md` plus one `.md` per declared fact; `git -C /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory status --short` shows only untracked `developer/` files (the atomic commit is Task 9).

---

### Task 9: The user-memory migration (one atomic commit)

**Files:**
- Modify (all in `user-memory`, ONE commit): `.agents/memory/*.md -> shared/*.md` (git mv), `developer/shared` (new symlink), `.agents/manifest` (layout flip), `AGENTS.md` (repointed import + path prose)

**Interfaces:**
- Consumes: Task 8's staged `developer/` dir; the already-shipped doctor `roles` code path (zero framework changes needed - Track A is NOT a prerequisite for this task).
- Produces: `user-memory` as a `roles`-layout instance - the valid `role_source` target Tasks 3/10 resolve against; AC "the user tier still loads" verified live.

- [ ] **Step 1: Pre-flight**

```bash
git -C /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory pull origin main
git -C /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory status --short
```

Expected: up to date; only the Task 8 untracked `developer/` files.
Also re-verify depth safety (the spec verified it 2026-07-12; re-check in case files changed):

```bash
grep -rn '\.\./' /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/.agents/memory/ || echo "CLEAN: no parent-relative links"
```

Expected: `CLEAN` - sibling links only, safe to move as a set.
If any `../` link appears, STOP and resolve it first.

- [ ] **Step 2: Move the flat tier to shared/ and create the role symlink**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory
mkdir shared
git mv .agents/memory/*.md shared/
ln -s ../shared developer/shared
```

- [ ] **Step 3: Flip the manifest**

In `.agents/manifest`, change the line `memory_layout=flat` to `memory_layout=roles` (nothing else changes; `topology=user-tier` stays - this is the first instance to decouple the two keys, deliberately).

- [ ] **Step 4: Repoint every `.agents/memory` reference in prose and imports**

```bash
grep -rn '.agents/memory' /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/AGENTS.md /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/README.md /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/docs/ 2>/dev/null
```

For every hit, replace the path segment `.agents/memory/` with `shared/` (the critical one is the `@~/dev/GitHub/Jin-HoMLee/user-memory/.agents/memory/MEMORY.md` import line in `AGENTS.md` - that single line IS the user-tier load path).
Then re-run the grep; expected: zero hits.
Do the same sweep inside the moved memory files themselves (`grep -rn '.agents/memory' shared/`) - a memory file naming its own old path must be updated (this is the "logical-path refs" audit that plain moves miss).

- [ ] **Step 5: Doctor gate, then the atomic commit**

```bash
/Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory/.agents/tools/doctor.sh --check --root /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory
```

Expected: exit 0, `OK: user-tier instance ... - all declared wiring verified` (role dir + `shared/MEMORY.md` satisfy the `roles` payload check; the home-hop links are untouched).

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory
git add -A
git commit -m "user-memory: migrate to roles layout - flat tier -> shared/, first role@user dir (developer) seeded by declared facts (claude-personas#49)"
```

- [ ] **Step 6: E2E - the user tier still loads (spec AC 4)**

From any project directory, run a FRESH headless session:

```bash
claude -p "Without searching the web or reading any file, quote your standing instruction about em dashes."
```

Expected: the answer states the rule (never em dash, plain dash instead) - proof the import chain (`~/.claude/CLAUDE.md -> ~/AGENTS.md -> user-memory/AGENTS.md -> @shared/MEMORY.md`) resolves end to end.
If the rule does not come back, the import line from Step 4 is wrong - fix before pushing.

- [ ] **Step 7: Push**

```bash
git -C /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory push origin main
```

---

### Task 10: Flagship wiring + both live E2E acceptance checks

**Files:**
- Modify: `claude-personas-splice-neoepitope-pipeline/.agents/manifest` (+`role_source=../user-memory`, `framework_ref` bump), `developer/MEMORY.md` (+1 pointer line), `developer/user` (doctor-materialized symlink), synced `.agents/tools|hooks|skills` payload
- Fixture (scratchpad, not committed): subagent E2E workspace

**Interfaces:**
- Consumes: merged Track A (Task 7's tag), migrated user-memory (Task 9).
- Produces: spec ACs 5 ("role clone follows the pointer") and 6 ("subagent recalls a deep fact, refuses another role's") verified live.

- [ ] **Step 1: Coordination gate (do not skip)**

This repo's sole committer is MM; manifest/symlink/payload changes are framework WIRING (cerebrum's lane by the standing separation agreement), but the `developer/MEMORY.md` pointer line is content-adjacent.
Surface the exact intended diff to Jin-Ho in chat and get an explicit go-ahead before touching the repo; note the pointer line for MM in the commit message.

- [ ] **Step 2: Sync the framework payload**

```bash
git -C /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline pull origin main
```

Edit `.agents/manifest`: set `framework_ref=framework/v1.1`, then:

```bash
/Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline/.agents/tools/install.sh --sync
```

Expected: the sync copies the updated doctor/hook/skill plus the NEW `inject-subagent-role-pointer.sh` into `.agents/`, and updates `.agents/framework-receipt`.

- [ ] **Step 3: Declare role_source, let doctor materialize the mount**

Append to `.agents/manifest`:

```text
role_source=../user-memory
```

Then run fix mode:

```bash
/Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline/.agents/tools/doctor.sh --root /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline
```

Expected output includes: `FIXED: developer/user -> ../../user-memory/developer` (only developer materializes - the other roles have no role@user dir yet, and stay silent: lazy).
Then `--check` again: exit 0.

- [ ] **Step 4: Add the pointer line to the role index**

In `developer/MEMORY.md`, directly after the existing shared-index pointer line (mirror its exact formatting), add:

```markdown
- Role user-tier memory (role@user, cross-project - loaded on demand): read [user/MEMORY.md](user/MEMORY.md)
```

- [ ] **Step 5: Commit the wiring (one commit, flagged for MM)**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline
git add -A
git commit -m "developer/shared: wire role@user mount (role_source + doctor-materialized symlink + index pointer; framework sync to v1.1) - framework wiring per claude-personas#49; index pointer line FYI @MM"
git push origin main
```

- [ ] **Step 6: E2E - spec AC 5 (pointer follow in a role clone)**

From the splice developer clone (the workspace whose `.agents/memory` mounts the developer role):

```bash
claude -p "Read your role memory index, follow its role@user pointer, and quote one fact from the role@user index verbatim, naming the file you read it from."
```

Expected: the reply quotes one of Task 8's declared facts and names a path under `developer/user/`.
Failure triage: pointer line missing (Step 4), symlink dangling (Step 3), or user-memory not migrated (Task 9).

- [ ] **Step 7: E2E - spec AC 6 (subagent deep recall + role isolation)**

Build a throwaway fixture workspace (scratchpad, NOT in any repo):

```bash
FIX="$(mktemp -d)"
MEMREPO="/Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline"
mkdir -p "$FIX/.claude/agents"
cat > "$FIX/.claude/settings.json" <<EOF
{
  "hooks": {
    "SubagentStart": [
      { "hooks": [ { "type": "command", "command": "'$MEMREPO/.agents/hooks/lib/inject-subagent-role-pointer.sh' '$MEMREPO'", "timeout": 10 } ] }
    ]
  }
}
EOF
cat > "$FIX/.claude/agents/developer.md" <<'EOF'
---
name: developer
description: The developer role subagent (personas role-tier E2E fixture).
tools: Read, Glob, Grep
---
You are the developer role. Follow the injected role-memory pointer before answering.
EOF
```

Precondition for "deep": the fact quoted must sit beyond byte 2048 of the combined injected content - since the hook injects only a ~250-byte pointer and the facts live in files the subagent must Read, any fact in a `developer/user/` file satisfies "beyond-2KB-offset" by construction; verify the pointer length stays under 2 KB (Task 5's test asserts it).
Run from `$FIX`:

```bash
cd "$FIX" && claude -p "Spawn the developer agent and ask it two questions: (1) quote one fact from its role@user memory index verbatim, naming the file; (2) quote one fact from the pm role's memory. Report both answers exactly as the agent gave them."
```

Expected: (1) a verbatim Task 8 fact with its file path; (2) a refusal citing the do-not-read-another-role's-directory rule.
Record both transcripts (answer text) in the PR-linked issue comment on #49 as the AC evidence.
Then `rm -rf "$FIX"`.

- [ ] **Step 8: Close out**

Comment on claude-personas#49 with the AC checklist from spec section 11, each item checked with a one-line evidence pointer (test name or E2E transcript), noting the last AC's Codex/OpenCode extension remains open as #67.
If the Task 7 PR did not already close #49 on merge, leave #49 open only if #67 is judged blocking; otherwise close it with that comment.

---

## Self-Review (run after writing, before executing)

1. Spec coverage: section 2 -> Task 7; section 3 -> Tasks 8-9; section 4a -> Tasks 4, 6, 10; section 4b -> Tasks 5, 10; section 4c -> Task 6 governance line; section 4d -> Task 3; section 5 -> Tasks 1-3; section 6 -> Task 8 (org rows gate in #66 - not planned here, correct); section 7 -> no task (defined, not wired - correct); section 11 ACs -> Tasks 1-3 (doctor ACs), 9 (user tier loads), 10 (pointer follow, subagent recall, seeding path).
2. Placeholder scan: none - every code step carries the full text.
3. Type consistency: `ROLE_SOURCE` global (Tasks 1-3), `check_role_tier_readiness` / `_role_tier_check_roles` (Tasks 2-3), hook filename `inject-subagent-role-pointer.sh` (Tasks 5, 10) - names match across tasks.
