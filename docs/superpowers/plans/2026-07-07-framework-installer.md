# Framework Installer (install.sh) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land `framework/tools/install.sh` (install/sync of the framework payload against a recorded pin), the doctor's staleness line, the three deferred #57 review findings, and the identity-switch docs - closing issue #55.

**Architecture:** install.sh copies exactly the `framework/FILES` set out of a framework clone's *git content at a ref* (never the working tree) into an instance's `.agents/` layout, and stamps `framework_source` + `framework_ref` in `.agents/manifest`. Refusal semantics are report-never-clobber. doctor.sh learns the two new manifest keys plus one staleness check. All behavior is TDD'd on the existing bash-fixture harness with new synthetic framework/instance fixtures in `test_helpers.sh`.

**Tech Stack:** bash 3.2-compatible shell (macOS default), git plumbing (`show`, `ls-tree`, `rev-list`, `tag`), the repo's own `test_helpers.sh` assert harness. No jq, no network beyond `git fetch`.

## Global Constraints

- Spec of record: `docs/superpowers/specs/2026-07-06-framework-distribution-design.md` sections 3, 8, 10. Deferred findings: https://github.com/Jin-HoMLee/claude-personas/issues/55#issuecomment-4902962265
- Landing paths (spec section 2): `framework/tools/* -> .agents/tools/`, `framework/hooks/* -> .agents/hooks/lib/`, `framework/skills/<name>/ -> .agents/skills/<name>/`.
- install.sh wires NO symlinks - adapter wiring stays doctor.sh fix-mode's job ("exactly one place creates symlinks").
- Sync never touches `.agents/memory/`, manifest values other than `framework_ref`, instance skills, or anything not in `FILES`.
- Exit contract (doctor convention): 0 = clean/up-to-date, 1 = refusals or pending `--check` changes reported, 2 = fatal (missing manifest/source/pin, malformed FILES).
- bash 3.2: no associative arrays; guard `"${#ARR[@]}" -gt 0` before expanding possibly-empty arrays under `set -u`.
- No `sed -i ''` in tests (BSD/GNU divergence - the PR #46 lesson); rewrite fixture files with heredocs or awk-to-tmp+mv.
- Runtime messages must be instance-durable: no GitHub issue numbers inside install.sh/doctor.sh output.
- Never use the em dash "—" in any new text; plain "-" only. New/edited long Markdown: one sentence per physical line.
- Commit prefix `claude-personas:`; never add an agent co-author line.
- Run the suite with `bash framework/tools/tests/run_all.sh` from the repo root; single file: `bash framework/tools/tests/test_install.sh`.

---

### Task 1: Test-helper consolidation (deferred finding 3)

**Files:**
- Modify: `framework/tools/tests/test_helpers.sh` (append at end)
- Modify: `framework/tools/tests/test_init_clone.sh` (6 staging blocks at ~lines 636-639, 697-699, 731-733, 824-826, 898-900, 1108-1110)
- Modify: `framework/tools/tests/test_doctor_role_clones.sh` (INJECT_SCRIPT at line 22, staging block at ~lines 79-83)
- Modify: `framework/tools/tests/test_inject_role_index.sh` (INJECT at line 13)

**Interfaces:**
- Produces: `INJECT_SRC` (absolute path to `framework/hooks/inject-role-index.sh`, set by sourcing test_helpers.sh) and `stage_inject_script <memrepo>` (creates `<memrepo>/.agents/hooks/lib/inject-role-index.sh`, executable). Both available to every test file that sources test_helpers.sh.

- [ ] **Step 1: Add the helper + constant to test_helpers.sh**

Append at the end of `framework/tools/tests/test_helpers.sh`:

```bash
# --- framework payload staging (shared by init-clone/doctor/inject tests) ---

# Absolute path to the repo's real inject script. test_helpers.sh lives in
# framework/tools/tests/, so the hooks dir is two levels up + /hooks.
INJECT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../hooks" && pwd)/inject-role-index.sh"

# stage_inject_script <memrepo>
# Places the inject script at the installed-payload location the wiring
# expects (<memrepo>/.agents/hooks/lib/), executable.
stage_inject_script() {
  mkdir -p "$1/.agents/hooks/lib"
  cp "$INJECT_SRC" "$1/.agents/hooks/lib/inject-role-index.sh"
  chmod +x "$1/.agents/hooks/lib/inject-role-index.sh"
}
```

- [ ] **Step 2: Replace the 6 inline staging blocks in test_init_clone.sh**

Each block has this shape (with `$tmp23`, `$tmp25`, `$tmp26`, `$weird29`, `$tmp31`, `$tmp36`):

```bash
mkdir -p "$tmp23/claude-personas-myapp/.agents/hooks/lib"
cp "$(cd "$SCRIPT_DIR/../../hooks" && pwd)/inject-role-index.sh" "$tmp23/claude-personas-myapp/.agents/hooks/lib/"
chmod +x "$tmp23/claude-personas-myapp/.agents/hooks/lib/inject-role-index.sh"
```

Replace each 3-line block with one call (keep any comment line above it):

```bash
stage_inject_script "$tmp23/claude-personas-myapp"
```

- [ ] **Step 3: Replace the block in test_doctor_role_clones.sh and both file-local constants**

In `test_doctor_role_clones.sh`: delete line 22 (`INJECT_SCRIPT="$(cd "$SCRIPT_DIR/../../hooks" && pwd)/inject-role-index.sh"`) and replace the setup_wired_fixture staging block (mkdir/cp/chmod using `$INJECT_SCRIPT`) with `stage_inject_script "$MEMREPO"`. If `$INJECT_SCRIPT` appears anywhere else in the file, replace those uses with `$INJECT_SRC`.

In `test_inject_role_index.sh`: replace line 13 with `INJECT="$INJECT_SRC"` (the file sources test_helpers.sh on line 12, so the constant is already set).

- [ ] **Step 4: Run the full suite**

Run: `bash framework/tools/tests/run_all.sh`
Expected: exit 0, same PASS count as before (500), 0 FAIL.

- [ ] **Step 5: Commit**

```bash
git add framework/tools/tests/
git commit -m "claude-personas: consolidate inject-script staging into test_helpers (stage_inject_script + INJECT_SRC)"
```

---

### Task 2: FILES consistency test (deferred finding 1)

**Files:**
- Create: `framework/tools/tests/test_framework_files.sh` (executable)

**Interfaces:**
- Consumes: `framework/FILES` format `"<src> -> <landing>"`, `#`-comments and blank lines ignored.
- Produces: nothing for later tasks; Task 4 extends `framework/FILES` with the install.sh entry and this test must stay green then.

- [ ] **Step 1: Write the test**

Create `framework/tools/tests/test_framework_files.sh`:

```bash
#!/usr/bin/env bash
# framework/FILES is the declared framework/content boundary. This test keeps
# the declaration honest: every source exists (+x for scripts), nothing
# instance-owned or example-owned is listed, and the one landing path that is
# ALSO hardcoded in doctor.sh/init-clone.sh (the inject hook) matches the
# manifest - the #57 review's drift-risk finding.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
FILES="$REPO_ROOT/framework/FILES"

echo "=== test_framework_files: every declared source exists, scripts executable ==="
entry_count=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  case "$line" in
    *' -> '*) ;;
    *) echo "  FAIL: malformed FILES line: '$line'"; TESTS_FAILED=$((TESTS_FAILED+1)); continue ;;
  esac
  src="${line%% -> *}"
  landing="${line##* -> }"
  entry_count=$((entry_count+1))
  assert_exists "$REPO_ROOT/$src" "source exists: $src"
  case "$src" in
    *.sh|*.py)
      if [ -x "$REPO_ROOT/$src" ]; then
        echo "  PASS: executable: $src"
      else
        echo "  FAIL: not executable: $src"; TESTS_FAILED=$((TESTS_FAILED+1))
      fi ;;
  esac
  case "$src" in
    framework/*) echo "  PASS: source under framework/: $src" ;;
    *) echo "  FAIL: source outside framework/: $src"; TESTS_FAILED=$((TESTS_FAILED+1)) ;;
  esac
  case "$landing" in
    .agents/*) echo "  PASS: landing under .agents/: $landing" ;;
    *) echo "  FAIL: landing outside .agents/: $landing"; TESTS_FAILED=$((TESTS_FAILED+1)) ;;
  esac
done < "$FILES"
assert_equal "0" "$([ "$entry_count" -ge 6 ] && echo 0 || echo 1)" "FILES has at least the 6 reshuffle entries (found $entry_count)"

echo "=== test_framework_files: inject-hook landing matches the doctor/init-clone literals ==="
declared="$(awk -F' -> ' '/inject-role-index.sh/ && !/^#/ {print $2}' "$FILES")"
assert_equal ".agents/hooks/lib/inject-role-index.sh" "$declared" "FILES declares the canonical inject landing"
if grep -q "\.agents/hooks/lib/inject-role-index\.sh" "$REPO_ROOT/framework/tools/doctor.sh"; then
  echo "  PASS: doctor.sh embeds the declared landing"
else
  echo "  FAIL: doctor.sh does not embed '$declared'"; TESTS_FAILED=$((TESTS_FAILED+1))
fi
if grep -q "\.agents/hooks/lib/inject-role-index\.sh" "$REPO_ROOT/framework/tools/init-clone.sh"; then
  echo "  PASS: init-clone.sh embeds the declared landing"
else
  echo "  FAIL: init-clone.sh does not embed '$declared'"; TESTS_FAILED=$((TESTS_FAILED+1))
fi
stale_doctor="$(grep -c "scripts/inject-role-index\.sh" "$REPO_ROOT/framework/tools/doctor.sh" || true)"
assert_equal "0" "$stale_doctor" "doctor.sh has no stale scripts/ inject literal"

echo "=== test_framework_files: nothing under examples/ is distributed ==="
bad="$(awk -F' -> ' '!/^#/ && NF==2 && $1 ~ /^examples\// {print}' "$FILES" | wc -l | tr -d ' ')"
assert_equal "0" "$bad" "no examples/ entry in FILES"

print_summary
```

Check the exact names of the assert helpers before writing: `grep -n "^assert_" framework/tools/tests/test_helpers.sh`. Use whatever exists (`assert_equal`, `assert_exists`, `assert_contains`); if `assert_exists` does not exist, use the `[ -e ]`-with-PASS/FAIL-echo pattern shown above for executability. Match `print_summary` / `TESTS_FAILED` conventions from a neighboring test file.

- [ ] **Step 2: chmod + run it**

Run: `chmod +x framework/tools/tests/test_framework_files.sh && bash framework/tools/tests/test_framework_files.sh`
Expected: exit 0, all PASS (6 entries, all sources exist, literals match).

- [ ] **Step 3: Run the full suite (run_all.sh picks the new file up via its test_*.sh glob)**

Run: `bash framework/tools/tests/run_all.sh`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add framework/tools/tests/test_framework_files.sh
git commit -m "claude-personas: add FILES consistency test (sources exist, inject landing matches doctor/init-clone literals)"
```

---

### Task 3: Derive validate.yml's executable list (deferred finding 2)

**Files:**
- Modify: `.github/workflows/validate.yml:30-44` (the "framework scripts are executable" step)

- [ ] **Step 1: Replace the hand-enumerated loop**

Replace the whole `framework scripts are executable` step with:

```yaml
      - name: framework scripts are executable
        run: |
          # Derived, not enumerated: every tracked shell/python file under
          # framework/ must be executable (they ship as runnable payload or
          # test harness). A new tool added to framework/ is covered
          # automatically - no list to forget to update.
          fail=0
          for s in $(git ls-files 'framework/*.sh' 'framework/*.py'); do
            if [ ! -x "$s" ]; then
              echo "FAIL: $s is not executable"
              fail=1
            else
              echo "OK: $s is executable"
            fi
          done
          exit $fail
```

Note: `git ls-files 'framework/*.sh'` matches recursively (git pathspec glob crosses `/`); verify locally that the file list covers all 15 current files.

- [ ] **Step 2: Verify locally**

Run: `cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas && for s in $(git ls-files 'framework/*.sh' 'framework/*.py'); do [ -x "$s" ] || echo "MISS: $s"; done | wc -l`
Expected: `0` misses, and `git ls-files 'framework/*.sh' 'framework/*.py' | wc -l` >= 15.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/validate.yml
git commit -m "claude-personas: derive CI executable check from git ls-files instead of a hand list"
```

---

### Task 4: install.sh core + `--into` happy path

**Files:**
- Create: `framework/tools/install.sh` (executable)
- Modify: `framework/FILES` (add the install.sh entry)
- Modify: `framework/tools/tests/test_helpers.sh` (append fixture builders)
- Create: `framework/tools/tests/test_install.sh` (executable)

**Interfaces:**
- Produces (CLI): `install.sh --into <target> [--ref <ref>] [--check]` and `install.sh --sync [--ref <ref>] [--check] [--force-file <landing>]... [--prune]`; exit 0/1/2 per Global Constraints.
- Produces (manifest keys): `framework_source=<path>` (relative `../<name>` for a sibling source, `.` for self-install, absolute otherwise; written by `--into` only) and `framework_ref=<tag-or-sha>` (written by both modes). Task 8's doctor validation must accept exactly these two key names.
- Produces (fixtures in test_helpers.sh): `make_framework_fixture <dir>` (creates `<dir>/fw`, tagged `framework/v1`), `advance_framework_fixture <dir>` (v2: tool-a changed + tool-b added, tagged `framework/v2`), `drop_hook_framework_fixture <dir>` (v3: hook-x removed from FILES, tagged `framework/v3`), `make_instance_fixture <dir> <name>` (embedded-manifest instance with a memory canary).
- Produces (report vocabulary, asserted by later tasks): `INSTALLED:`, `SYNCED:`, `FORCED:`, `PRUNED:`, `PINNED:`, `SHADOWED:`, `MODIFIED:`, `ORPHANED:`, `WOULD-INSTALL:`, `WOULD-SYNC:`, `WARN:`, `ERROR:`.

- [ ] **Step 1: Add fixture builders to test_helpers.sh**

Append to `framework/tools/tests/test_helpers.sh`:

```bash
# --- installer fixtures (test_install.sh, doctor staleness tests) ---

# make_framework_fixture <dir>
# Synthetic framework clone at <dir>/fw: 3-entry FILES (tool, hook, skill),
# one commit, annotated tag framework/v1.
make_framework_fixture() {
  local fw="$1/fw"
  mkdir -p "$fw/framework/tools" "$fw/framework/hooks" "$fw/framework/skills/demo-skill"
  printf '#!/usr/bin/env bash\necho tool-a v1\n' > "$fw/framework/tools/tool-a.sh"
  chmod +x "$fw/framework/tools/tool-a.sh"
  printf '#!/usr/bin/env bash\necho hook-x v1\n' > "$fw/framework/hooks/hook-x.sh"
  chmod +x "$fw/framework/hooks/hook-x.sh"
  printf -- '---\nname: demo-skill\n---\nv1\n' > "$fw/framework/skills/demo-skill/SKILL.md"
  cat > "$fw/framework/FILES" <<'EOF'
# fixture FILES
framework/tools/tool-a.sh -> .agents/tools/tool-a.sh
framework/hooks/hook-x.sh -> .agents/hooks/lib/hook-x.sh
framework/skills/demo-skill/SKILL.md -> .agents/skills/demo-skill/SKILL.md
EOF
  ( cd "$fw" && git init --quiet \
    && git -c user.email=t@x -c user.name=T add -A \
    && git -c user.email=t@x -c user.name=T commit --quiet -m "fw v1" \
    && git -c user.email=t@x -c user.name=T tag -a framework/v1 -m v1 )
}

# advance_framework_fixture <dir>
# v2: tool-a content changes, tool-b appears in FILES. hook-x stays.
advance_framework_fixture() {
  local fw="$1/fw"
  printf '#!/usr/bin/env bash\necho tool-a v2\n' > "$fw/framework/tools/tool-a.sh"
  printf '#!/usr/bin/env bash\necho tool-b v2\n' > "$fw/framework/tools/tool-b.sh"
  chmod +x "$fw/framework/tools/tool-b.sh"
  cat > "$fw/framework/FILES" <<'EOF'
framework/tools/tool-a.sh -> .agents/tools/tool-a.sh
framework/tools/tool-b.sh -> .agents/tools/tool-b.sh
framework/hooks/hook-x.sh -> .agents/hooks/lib/hook-x.sh
framework/skills/demo-skill/SKILL.md -> .agents/skills/demo-skill/SKILL.md
EOF
  ( cd "$fw" && git -c user.email=t@x -c user.name=T add -A \
    && git -c user.email=t@x -c user.name=T commit --quiet -m "fw v2" \
    && git -c user.email=t@x -c user.name=T tag -a framework/v2 -m v2 )
}

# drop_hook_framework_fixture <dir>
# v3: hook-x leaves FILES (and the tree) - the orphan case.
drop_hook_framework_fixture() {
  local fw="$1/fw"
  rm "$fw/framework/hooks/hook-x.sh"
  cat > "$fw/framework/FILES" <<'EOF'
framework/tools/tool-a.sh -> .agents/tools/tool-a.sh
framework/tools/tool-b.sh -> .agents/tools/tool-b.sh
framework/skills/demo-skill/SKILL.md -> .agents/skills/demo-skill/SKILL.md
EOF
  ( cd "$fw" && git -c user.email=t@x -c user.name=T add -A \
    && git -c user.email=t@x -c user.name=T commit --quiet -m "fw v3" \
    && git -c user.email=t@x -c user.name=T tag -a framework/v3 -m v3 )
}

# make_instance_fixture <dir> <name>
# Embedded-topology instance with a committed manifest and a memory canary
# that install/sync must never touch.
make_instance_fixture() {
  local inst="$1/$2"
  mkdir -p "$inst/.agents/memory"
  printf '# Memory Index\n- canary\n' > "$inst/.agents/memory/MEMORY.md"
  cat > "$inst/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
EOF
  ( cd "$inst" && git init --quiet \
    && git -c user.email=t@x -c user.name=T add -A \
    && git -c user.email=t@x -c user.name=T commit --quiet -m "instance init" )
}
```

- [ ] **Step 2: Write the failing tests (happy path + fatals)**

Create `framework/tools/tests/test_install.sh`:

```bash
#!/usr/bin/env bash
# install.sh - distribution mechanics (issue #55, spec section 3).
# Fixtures: synthetic framework clone (fw) + embedded instance, built by
# test_helpers.sh. All copies come from git content at a ref, so fixtures
# commit + tag every state.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
INSTALL="$(cd "$SCRIPT_DIR/.." && pwd)/install.sh"

echo "=== test_install: --into with no target manifest is fatal (exit 2) ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
mkdir -p "$tmp/bare"
( cd "$tmp/bare" && git init --quiet )
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/bare" 2>&1)"
status=$?
assert_equal "2" "$status" "no manifest: exit 2"
assert_contains "$out" "no manifest at" "no-manifest error names the path"
rm -rf "$tmp"

echo "=== test_install: --into happy path copies the declared set + stamps the pin ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" 2>&1)"
status=$?
assert_equal "0" "$status" "clean install exits 0"
assert_exists "$tmp/inst/.agents/tools/tool-a.sh" "tool landed in .agents/tools/"
assert_exists "$tmp/inst/.agents/hooks/lib/hook-x.sh" "hook landed in .agents/hooks/lib/"
assert_exists "$tmp/inst/.agents/skills/demo-skill/SKILL.md" "skill landed in .agents/skills/"
if [ -x "$tmp/inst/.agents/tools/tool-a.sh" ]; then
  echo "  PASS: executable bit preserved"
else
  echo "  FAIL: tool-a.sh not executable"; TESTS_FAILED=$((TESTS_FAILED+1))
fi
assert_contains "$out" "INSTALLED: .agents/tools/tool-a.sh" "reports the installed tool"
assert_contains "$(cat "$tmp/inst/.agents/manifest")" "framework_ref=framework/v1" "pin stamped with the newest framework/v* tag"
assert_contains "$(cat "$tmp/inst/.agents/manifest")" "framework_source=../fw" "sibling source recorded relative"
assert_equal "$(printf '# Memory Index\n- canary\n')" "$(cat "$tmp/inst/.agents/memory/MEMORY.md")" "memory canary untouched"
extra="$(find "$tmp/inst/.agents/tools" -type f | grep -cv 'tool-a.sh')"
assert_equal "0" "$extra" "exactly the declared set landed in .agents/tools/"

echo "=== test_install: second --into run is idempotent (identical content = up to date) ==="
out2="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" 2>&1)"
assert_equal "0" "$?" "re-install on identical content exits 0"
rm -rf "$tmp"

echo "=== test_install: unknown argument is fatal ==="
out="$(bash "$INSTALL" --bogus 2>&1)"
assert_equal "2" "$?" "unknown arg: exit 2"

print_summary
```

Adjust helper names to what test_helpers.sh actually provides (same note as Task 2). Note on `$?` after `out="$(...)"`: command substitution in an assignment preserves the exit status - keep the `status=$?` capture on the line immediately after, as shown.

- [ ] **Step 3: Run to verify failure**

Run: `chmod +x framework/tools/tests/test_install.sh && bash framework/tools/tests/test_install.sh`
Expected: FAIL (install.sh does not exist).

- [ ] **Step 4: Write install.sh**

Create `framework/tools/install.sh` (complete file):

```bash
#!/usr/bin/env bash
# install.sh - get/refresh the framework payload in an instance.
#
# Part of the distributable payload (listed in framework/FILES), so installed
# instances self-update with their own copy. Distribution ONLY: copies exactly
# the framework/FILES set from the SOURCE CLONE'S GIT CONTENT AT A REF (never
# the working tree) and stamps the pin. It wires no symlinks - adapter wiring
# stays doctor.sh fix-mode's job, so exactly one place creates symlinks.
#
# Refusals are report-never-clobber:
#   SHADOWED  (--into)  destination exists and differs - kept, instance-owned
#   MODIFIED  (--sync)  destination differs from the PINNED copy - kept,
#                       override per file with --force-file <landing>
#   ORPHANED  (--sync)  pinned FILES entry dropped upstream - kept, remove
#                       with --prune (unmodified orphans only)
#
# Exit: 0 clean/up-to-date; 1 refusals or pending --check changes; 2 fatal.

set -u

usage() {
  cat <<'EOF'
Usage:
  install.sh --into <target> [--ref <ref>] [--check]
  install.sh --sync [--ref <ref>] [--check] [--force-file <landing>]... [--prune]

  --into <target>    First install. Run from inside a framework clone; copies
                     the framework/FILES set into <target>/.agents/... and
                     stamps framework_source + framework_ref in the target's
                     .agents/manifest.
  --sync             Update. Run from inside an installed instance; re-resolves
                     the framework source, re-copies the declared set at the
                     new ref, updates framework_ref (and nothing else).
  --check            Dry-run: report what would change, write nothing.
  --ref <ref>        Pin this tag/SHA instead of the newest framework/v* tag.
  --force-file <p>   (sync) Overwrite this locally-modified landing path.
  --prune            (sync) Delete orphaned framework files that still match
                     the pinned copy.
EOF
}

MODE= TARGET= CHECK=0 PRUNE=0 REF_OVERRIDE= REF=
FORCE_FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --into)
      [ $# -ge 2 ] || { echo "ERROR: --into needs a target path" >&2; exit 2; }
      MODE=into; TARGET="$2"; shift 2 ;;
    --sync) MODE=sync; shift ;;
    --check) CHECK=1; shift ;;
    --prune) PRUNE=1; shift ;;
    --force-file)
      [ $# -ge 2 ] || { echo "ERROR: --force-file needs a landing path" >&2; exit 2; }
      FORCE_FILES+=("$2"); shift 2 ;;
    --ref)
      [ $# -ge 2 ] || { echo "ERROR: --ref needs a value" >&2; exit 2; }
      REF_OVERRIDE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done
if [ -z "$MODE" ]; then usage >&2; exit 2; fi

PENDING=0
APPLIED=0
report_apply()   { echo "$1"; APPLIED=$((APPLIED + 1)); }
report_pending() { echo "$1"; PENDING=$((PENDING + 1)); }
warn()  { echo "WARN: $1" >&2; }
fatal() { echo "ERROR: $1" >&2; exit 2; }

# --- resolve source clone (SRC) and instance (TARGET) ---

if [ "$MODE" = into ]; then
  SRC="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$SRC" ] && [ -f "$SRC/framework/FILES" ] \
    || fatal "--into must run from inside a framework clone (no framework/FILES at the git toplevel)"
  [ -d "$TARGET" ] || fatal "target '$TARGET' does not exist"
  TARGET="$(cd "$TARGET" && pwd)"
else
  TARGET="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$TARGET" ] || fatal "--sync must run from inside the instance (a git repo)"
fi

MANIFEST="$TARGET/.agents/manifest"
[ -f "$MANIFEST" ] || fatal "no manifest at $MANIFEST - declare the instance first (doctor.sh --init <topology>)"

# manifest_get <key>: first value wins (same semantics as doctor.sh).
manifest_get() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$1="*) printf '%s\n' "${line#"$1"=}"; return 0 ;;
    esac
  done < "$MANIFEST"
  return 0
}

PIN=
if [ "$MODE" = sync ]; then
  PIN="$(manifest_get framework_ref)"
  [ -n "$PIN" ] || fatal "no framework_ref in $MANIFEST - not installed yet (run install.sh --into <this-instance> from a framework clone)"
  SRC="$(manifest_get framework_source)"
  if [ -n "$SRC" ]; then
    case "$SRC" in
      /*) ;;
      *) SRC="$TARGET/$SRC" ;;
    esac
    [ -d "$SRC" ] || fatal "framework_source '$SRC' (from manifest) does not exist"
  else
    parent="$(dirname "$TARGET")"
    if [ -f "$parent/agent-personas/framework/FILES" ]; then
      SRC="$parent/agent-personas"
    elif [ -f "$parent/claude-personas/framework/FILES" ]; then
      SRC="$parent/claude-personas"
    else
      fatal "no framework_source in $MANIFEST and no sibling agent-personas/claude-personas clone next to $TARGET - set framework_source explicitly"
    fi
  fi
  SRC="$(cd "$SRC" && pwd)"
  [ -f "$SRC/framework/FILES" ] || fatal "'$SRC' is not a framework clone (no framework/FILES)"
  git -C "$SRC" fetch --tags --quiet 2>/dev/null || true
fi

# --- resolve the ref to pin ---

if [ -n "$REF_OVERRIDE" ]; then
  git -C "$SRC" rev-parse --verify --quiet "$REF_OVERRIDE^{commit}" >/dev/null \
    || fatal "ref '$REF_OVERRIDE' not found in $SRC"
  case "$REF_OVERRIDE" in
    framework/v*) ;;
    *) warn "pinning '$REF_OVERRIDE' - prefer a framework/v* tag" ;;
  esac
  REF="$REF_OVERRIDE"
else
  REF="$(git -C "$SRC" tag -l 'framework/v*' --sort=-v:refname | head -n 1)"
  if [ -z "$REF" ]; then
    REF="$(git -C "$SRC" rev-parse HEAD)"
    warn "no framework/v* tag in $SRC - pinning bare SHA $REF (prefer tags)"
  fi
fi

# --- read FILES at the refs ---

NEW_FILES="$(git -C "$SRC" show "$REF:framework/FILES" 2>/dev/null)" \
  || fatal "framework/FILES not found at ref '$REF' in $SRC"
PIN_FILES=""
if [ "$MODE" = sync ]; then
  PIN_FILES="$(git -C "$SRC" show "$PIN:framework/FILES" 2>/dev/null)" \
    || fatal "framework/FILES not found at pinned ref '$PIN' in $SRC - fetch the source or fix the pin"
fi

# parse_files: stdin FILES text -> "src<TAB>landing" lines; fatal on malformed.
parse_files() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      *' -> '*) printf '%s\t%s\n' "${line%% -> *}" "${line##* -> }" ;;
      *) return 1 ;;
    esac
  done
  return 0
}
NEW_TAB="$(printf '%s\n' "$NEW_FILES" | parse_files)" || fatal "malformed framework/FILES at '$REF'"
PIN_TAB=""
if [ "$MODE" = sync ]; then
  PIN_TAB="$(printf '%s\n' "$PIN_FILES" | parse_files)" || fatal "malformed framework/FILES at pin '$PIN'"
fi

pin_src_for_landing() {
  printf '%s\n' "$PIN_TAB" | awk -F'\t' -v l="$1" '$2 == l { print $1; exit }'
}
new_has_landing() {
  printf '%s\n' "$NEW_TAB" | awk -F'\t' -v l="$1" '$2 == l { found = 1 } END { exit found ? 0 : 1 }'
}
is_forced() {
  local f
  if [ "${#FORCE_FILES[@]}" -gt 0 ]; then
    for f in "${FORCE_FILES[@]}"; do
      [ "$f" = "$1" ] && return 0
    done
  fi
  return 1
}

# --- copy machinery ---

write_from_ref() { # write_from_ref <src_path> <landing> <label>
  local src_path="$1" landing="$2" label="$3" dest="$TARGET/$2" tmp mode
  if [ "$CHECK" = 1 ]; then
    case "$label" in
      INSTALLED) report_pending "WOULD-INSTALL: $landing (from $src_path @ $REF)" ;;
      *)         report_pending "WOULD-SYNC: $landing (from $src_path @ $REF)" ;;
    esac
    return 0
  fi
  tmp="$(mktemp 2>/dev/null)" || fatal "mktemp failed"
  if ! git -C "$SRC" show "$REF:$src_path" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    fatal "cannot read '$src_path' at '$REF' from $SRC (is it in framework/FILES but not committed?)"
  fi
  mkdir -p "$(dirname "$dest")" || { rm -f "$tmp"; fatal "cannot create $(dirname "$dest")"; }
  mv "$tmp" "$dest" || { rm -f "$tmp"; fatal "cannot write $dest"; }
  mode="$(git -C "$SRC" ls-tree "$REF" -- "$src_path" 2>/dev/null | awk '{ print $1 }')"
  if [ "$mode" = "100755" ]; then chmod +x "$dest"; fi
  report_apply "$label: $landing"
}

blob_at() { git -C "$SRC" show "$1:$2" 2>/dev/null; }

process_into() { # process_into <src_path> <landing>
  local src_path="$1" landing="$2" dest="$TARGET/$2"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$(cat "$dest" 2>/dev/null)" = "$(blob_at "$REF" "$src_path")" ]; then
      return 0   # identical content: already installed, idempotent re-run
    fi
    report_pending "SHADOWED: $landing exists and differs - kept, instance-owned (install never overwrites)"
  else
    write_from_ref "$src_path" "$landing" INSTALLED
  fi
}

process_sync() { # process_sync <src_path> <landing>
  local src_path="$1" landing="$2" dest="$TARGET/$2" new_blob cur pin_src pinned_blob
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    write_from_ref "$src_path" "$landing" INSTALLED
    return 0
  fi
  new_blob="$(blob_at "$REF" "$src_path")"
  cur="$(cat "$dest" 2>/dev/null)"
  if [ "$cur" = "$new_blob" ]; then
    return 0   # up to date
  fi
  pin_src="$(pin_src_for_landing "$landing")"
  pinned_blob=""
  if [ -n "$pin_src" ]; then
    pinned_blob="$(blob_at "$PIN" "$pin_src")"
  fi
  if [ "$cur" = "$pinned_blob" ]; then
    write_from_ref "$src_path" "$landing" SYNCED
  elif is_forced "$landing"; then
    write_from_ref "$src_path" "$landing" FORCED
  else
    report_pending "MODIFIED: $landing differs from the pinned copy - kept (override: --force-file $landing)"
  fi
}

process_orphans() {
  local line src_path landing dest cur pinned_blob
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    src_path="${line%%$'\t'*}"
    landing="${line##*$'\t'}"
    if new_has_landing "$landing"; then continue; fi
    dest="$TARGET/$landing"
    if [ ! -e "$dest" ]; then continue; fi
    cur="$(cat "$dest" 2>/dev/null)"
    pinned_blob="$(blob_at "$PIN" "$src_path")"
    if [ "$PRUNE" = 1 ] && [ "$CHECK" = 0 ]; then
      if [ "$cur" = "$pinned_blob" ]; then
        rm "$dest" && report_apply "PRUNED: $landing" || fatal "cannot remove $dest"
      else
        report_pending "MODIFIED ORPHAN: $landing differs from the pinned copy - kept, delete by hand"
      fi
    else
      report_pending "ORPHANED: $landing no longer in framework/FILES - kept (remove with --prune)"
    fi
  done <<EOF_ORPHANS
$PIN_TAB
EOF_ORPHANS
}

# --- walk the declared set ---

while IFS= read -r line; do
  [ -n "$line" ] || continue
  src_path="${line%%$'\t'*}"
  landing="${line##*$'\t'}"
  case "$landing" in
    .agents/*) ;;
    *) fatal "FILES declares a landing outside .agents/: '$landing' - refusing" ;;
  esac
  if [ "$MODE" = into ]; then
    process_into "$src_path" "$landing"
  else
    process_sync "$src_path" "$landing"
  fi
done <<EOF_ENTRIES
$NEW_TAB
EOF_ENTRIES

if [ "$MODE" = sync ]; then
  process_orphans
fi

# --- stamp the pin (never in --check) ---

if [ "$CHECK" = 0 ]; then
  if [ "$MODE" = into ]; then
    if [ "$SRC" = "$TARGET" ]; then
      SOURCE_VALUE="."
    elif [ "$(dirname "$SRC")" = "$(dirname "$TARGET")" ]; then
      SOURCE_VALUE="../$(basename "$SRC")"
    else
      SOURCE_VALUE="$SRC"
    fi
  fi
  if [ "$(manifest_get framework_ref)" != "$REF" ] \
     || { [ "$MODE" = into ] && [ "$(manifest_get framework_source)" != "${SOURCE_VALUE:-}" ]; }; then
    tmp="$(mktemp 2>/dev/null)" || fatal "mktemp failed"
    awk -F= -v mode="$MODE" '
      $1 == "framework_ref" { next }
      $1 == "framework_source" && mode == "into" { next }
      { print }
    ' "$MANIFEST" > "$tmp" || { rm -f "$tmp"; fatal "cannot rewrite $MANIFEST"; }
    if [ "$MODE" = into ]; then
      printf 'framework_source=%s\n' "$SOURCE_VALUE" >> "$tmp"
    fi
    printf 'framework_ref=%s\n' "$REF" >> "$tmp"
    mv "$tmp" "$MANIFEST" || fatal "cannot write $MANIFEST"
    report_apply "PINNED: framework_ref=$REF"
  fi
fi

if [ "$PENDING" -gt 0 ]; then
  exit 1
fi
if [ "$APPLIED" -gt 0 ]; then
  echo "OK: framework payload at $REF in $TARGET ($APPLIED change(s))"
else
  echo "OK: framework payload up to date at $REF in $TARGET"
fi
exit 0
```

- [ ] **Step 5: Add install.sh to framework/FILES**

In `framework/FILES`, add below the doctor.sh line, and update the header comment line "Consumed by framework/tools/install.sh (issue #55)" to "Consumed by framework/tools/install.sh.":

```text
framework/tools/install.sh -> .agents/tools/install.sh
```

- [ ] **Step 6: chmod, run the new test, then the full suite**

Run: `chmod +x framework/tools/install.sh && bash framework/tools/tests/test_install.sh && bash framework/tools/tests/run_all.sh`
Expected: test_install.sh all PASS; full suite exit 0 (test_framework_files still green with 7 entries).

- [ ] **Step 7: Commit**

```bash
git add framework/tools/install.sh framework/FILES framework/tools/tests/
git commit -m "claude-personas: install.sh --into with FILES-driven copy from git ref + manifest pin"
```

---

### Task 5: `--into` shadow refusal + `--check` dry-run

**Files:**
- Modify: `framework/tools/tests/test_install.sh` (append test blocks before `print_summary`)
- Modify: `framework/tools/install.sh` (only if a test exposes a defect - the Task 4 code already implements both behaviors)

**Interfaces:**
- Consumes: report vocabulary and fixtures from Task 4.

- [ ] **Step 1: Append the failing/verifying tests**

Append to `framework/tools/tests/test_install.sh` before `print_summary`:

```bash
echo "=== test_install: --into refuses a shadowing file (kept, exit 1) ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
mkdir -p "$tmp/inst/.agents/tools"
printf 'instance-owned tool-a\n' > "$tmp/inst/.agents/tools/tool-a.sh"
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" 2>&1)"
status=$?
assert_equal "1" "$status" "shadowed install exits 1"
assert_contains "$out" "SHADOWED: .agents/tools/tool-a.sh" "names the shadowed landing"
assert_equal "instance-owned tool-a" "$(cat "$tmp/inst/.agents/tools/tool-a.sh")" "shadowed file kept byte-identical"
assert_exists "$tmp/inst/.agents/hooks/lib/hook-x.sh" "non-shadowed files still installed"
rm -rf "$tmp"

echo "=== test_install: --into --check reports, writes nothing, stamps nothing ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" --check 2>&1)"
status=$?
assert_equal "1" "$status" "--check with pending installs exits 1"
assert_contains "$out" "WOULD-INSTALL: .agents/tools/tool-a.sh" "dry-run names pending installs"
assert_not_exists "$tmp/inst/.agents/tools/tool-a.sh" "--check wrote no files"
case "$(cat "$tmp/inst/.agents/manifest")" in
  *framework_ref*) echo "  FAIL: --check stamped the pin"; TESTS_FAILED=$((TESTS_FAILED+1)) ;;
  *) echo "  PASS: --check did not stamp the pin" ;;
esac
rm -rf "$tmp"
```

(If `assert_not_exists` is not in test_helpers.sh, use the `[ ! -e ]`-with-PASS/FAIL-echo pattern.)

- [ ] **Step 2: Run, fix install.sh only if RED**

Run: `bash framework/tools/tests/test_install.sh`
Expected: all PASS (Task 4's code covers this); if any FAIL, fix install.sh minimally and re-run.

- [ ] **Step 3: Commit**

```bash
git add framework/tools/tests/test_install.sh framework/tools/install.sh
git commit -m "claude-personas: pin install.sh shadow-refusal + --check dry-run behavior"
```

---

### Task 6: `--sync` happy path + source resolution

**Files:**
- Modify: `framework/tools/tests/test_install.sh` (append before `print_summary`)
- Modify: `framework/tools/install.sh` (only on RED)

**Interfaces:**
- Consumes: `advance_framework_fixture` (v2 tag), Task 4 CLI + vocabulary.

- [ ] **Step 1: Append the tests**

```bash
echo "=== test_install: --sync without a pin is fatal ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync 2>&1)"
assert_equal "2" "$?" "sync without framework_ref exits 2"
rm -rf "$tmp"

echo "=== test_install: --sync happy path (upstream v2: update + new file + pin bump, manifest otherwise untouched) ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
manifest_before_nopin="$(grep -v '^framework_ref=' "$tmp/inst/.agents/manifest")"
advance_framework_fixture "$tmp"
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync 2>&1)"
status=$?
assert_equal "0" "$status" "clean sync exits 0"
assert_contains "$out" "SYNCED: .agents/tools/tool-a.sh" "changed framework file re-copied"
assert_contains "$(cat "$tmp/inst/.agents/tools/tool-a.sh")" "tool-a v2" "tool-a now at v2 content"
assert_exists "$tmp/inst/.agents/tools/tool-b.sh" "new upstream file installed on sync"
assert_contains "$(cat "$tmp/inst/.agents/manifest")" "framework_ref=framework/v2" "pin bumped to v2"
assert_equal "$manifest_before_nopin" "$(grep -v '^framework_ref=' "$tmp/inst/.agents/manifest")" "sync touched no manifest value except framework_ref"
assert_equal "$(printf '# Memory Index\n- canary\n')" "$(cat "$tmp/inst/.agents/memory/MEMORY.md")" "memory canary untouched by sync"
rm -rf "$tmp"

echo "=== test_install: --sync default sibling source resolution (no framework_source key) ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
mv "$tmp/fw" "$tmp/claude-personas"
make_instance_fixture "$tmp" inst
( cd "$tmp/claude-personas" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
# strip the framework_source line to force default resolution (awk-to-tmp, no sed -i)
awk '!/^framework_source=/' "$tmp/inst/.agents/manifest" > "$tmp/m" && mv "$tmp/m" "$tmp/inst/.agents/manifest"
advance_framework_fixture_named "$tmp" claude-personas
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync 2>&1)"
assert_equal "0" "$?" "default sibling claude-personas resolved"
assert_contains "$(cat "$tmp/inst/.agents/manifest")" "framework_ref=framework/v2" "pin bumped via default source"
rm -rf "$tmp"

echo "=== test_install: --sync with no source anywhere is fatal ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
awk '!/^framework_source=/' "$tmp/inst/.agents/manifest" > "$tmp/m" && mv "$tmp/m" "$tmp/inst/.agents/manifest"
rm -rf "$tmp/fw"
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync 2>&1)"
assert_equal "2" "$?" "no source resolvable exits 2"
assert_contains "$out" "no framework_source" "error explains the fix"
rm -rf "$tmp"
```

The third block needs a small fixture variant; add to `framework/tools/tests/test_helpers.sh` next to `advance_framework_fixture`:

```bash
# advance_framework_fixture_named <dir> <clone-name>
# Same v2 advance, for a framework clone not named fw.
advance_framework_fixture_named() {
  local fw="$1/$2"
  printf '#!/usr/bin/env bash\necho tool-a v2\n' > "$fw/framework/tools/tool-a.sh"
  printf '#!/usr/bin/env bash\necho tool-b v2\n' > "$fw/framework/tools/tool-b.sh"
  chmod +x "$fw/framework/tools/tool-b.sh"
  cat > "$fw/framework/FILES" <<'EOF'
framework/tools/tool-a.sh -> .agents/tools/tool-a.sh
framework/tools/tool-b.sh -> .agents/tools/tool-b.sh
framework/hooks/hook-x.sh -> .agents/hooks/lib/hook-x.sh
framework/skills/demo-skill/SKILL.md -> .agents/skills/demo-skill/SKILL.md
EOF
  ( cd "$fw" && git -c user.email=t@x -c user.name=T add -A \
    && git -c user.email=t@x -c user.name=T commit --quiet -m "fw v2" \
    && git -c user.email=t@x -c user.name=T tag -a framework/v2 -m v2 )
}
```

(Refactor `advance_framework_fixture` to call `advance_framework_fixture_named "$1" fw` so the body exists once.)

- [ ] **Step 2: Run, fix on RED**

Run: `bash framework/tools/tests/test_install.sh`
Expected: all PASS. Likely defects to check if RED: `framework_source=../fw` resolution when the manifest key is present (relative-to-TARGET join), and the `manifest_before_nopin` comparison (stamp must rewrite ONLY the framework_ref line - note the awk in Task 4 keeps all other lines verbatim, but appends framework_ref at the END, so the comparison via `grep -v` is order-insensitive by construction; keep it that way).

- [ ] **Step 3: Commit**

```bash
git add framework/tools/tests/ framework/tools/install.sh
git commit -m "claude-personas: install.sh --sync happy path + source resolution semantics"
```

---

### Task 7: `--sync` refusal paths (modified / force-file / orphan / prune / SHA warn)

**Files:**
- Modify: `framework/tools/tests/test_install.sh` (append before `print_summary`)
- Modify: `framework/tools/install.sh` (only on RED)

**Interfaces:**
- Consumes: `drop_hook_framework_fixture` (v3 drops hook-x), Task 4 vocabulary.

- [ ] **Step 1: Append the tests**

```bash
echo "=== test_install: --sync keeps a locally-modified framework file; --force-file overrides ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
printf '#!/usr/bin/env bash\necho locally hacked\n' > "$tmp/inst/.agents/tools/tool-a.sh"
advance_framework_fixture "$tmp"
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync 2>&1)"
status=$?
assert_equal "1" "$status" "modified file: sync exits 1"
assert_contains "$out" "MODIFIED: .agents/tools/tool-a.sh" "modified file named with the override hint"
assert_contains "$(cat "$tmp/inst/.agents/tools/tool-a.sh")" "locally hacked" "modified file kept"
assert_contains "$(cat "$tmp/inst/.agents/manifest")" "framework_ref=framework/v2" "pin still advances (modified file stays flagged next run)"
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync --force-file .agents/tools/tool-a.sh 2>&1)"
assert_equal "0" "$?" "--force-file run exits 0"
assert_contains "$out" "FORCED: .agents/tools/tool-a.sh" "forced overwrite reported"
assert_contains "$(cat "$tmp/inst/.agents/tools/tool-a.sh")" "tool-a v2" "forced file now upstream content"
rm -rf "$tmp"

echo "=== test_install: orphan reported not deleted; --prune deletes unmodified only ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
advance_framework_fixture "$tmp"
( cd "$tmp/inst" && bash "$INSTALL" --sync ) >/dev/null
drop_hook_framework_fixture "$tmp"
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync 2>&1)"
status=$?
assert_equal "1" "$status" "orphan present: exit 1"
assert_contains "$out" "ORPHANED: .agents/hooks/lib/hook-x.sh" "orphan named with --prune hint"
assert_exists "$tmp/inst/.agents/hooks/lib/hook-x.sh" "orphan NOT auto-deleted"
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync --prune 2>&1)"
assert_equal "0" "$?" "--prune run exits 0"
assert_contains "$out" "PRUNED: .agents/hooks/lib/hook-x.sh" "prune reported"
assert_not_exists "$tmp/inst/.agents/hooks/lib/hook-x.sh" "orphan removed by --prune"
rm -rf "$tmp"

echo "=== test_install: --prune refuses a modified orphan ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
advance_framework_fixture "$tmp"
( cd "$tmp/inst" && bash "$INSTALL" --sync ) >/dev/null
drop_hook_framework_fixture "$tmp"
printf 'hand-tuned hook\n' > "$tmp/inst/.agents/hooks/lib/hook-x.sh"
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync --prune 2>&1)"
assert_equal "1" "$?" "modified orphan under --prune: exit 1"
assert_contains "$out" "MODIFIED ORPHAN: .agents/hooks/lib/hook-x.sh" "modified orphan named"
assert_equal "hand-tuned hook" "$(cat "$tmp/inst/.agents/hooks/lib/hook-x.sh")" "modified orphan kept"
rm -rf "$tmp"

echo "=== test_install: --ref bare SHA warns, framework/v* tag does not ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
sha="$(git -C "$tmp/fw" rev-parse HEAD)"
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" --ref "$sha" 2>&1)"
assert_equal "0" "$?" "SHA-pinned install exits 0"
assert_contains "$out" "prefer a framework/v* tag" "bare SHA warns"
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" --ref framework/v1 2>&1)"
case "$out" in
  *"prefer a framework/v* tag"*) echo "  FAIL: tag ref warned"; TESTS_FAILED=$((TESTS_FAILED+1)) ;;
  *) echo "  PASS: tag ref does not warn" ;;
esac
rm -rf "$tmp"
```

Note the pin-advance-with-refusals decision pinned by the first block: sync stamps the new pin even when some files were refused; the refused file stays MODIFIED on every future run (it matches neither old nor new pin), so nothing is lost and re-runs converge. This is deliberate - document it in the install.sh header comment if it is not already there.

- [ ] **Step 2: Run, fix on RED**

Run: `bash framework/tools/tests/test_install.sh`
Expected: all PASS. Watch: the second `--into ... --ref` call in the SHA test runs against an already-installed instance - the idempotence path must hold for identical content pinned by a different ref name (content comparison, not ref comparison, decides).

- [ ] **Step 3: Run full suite + commit**

```bash
bash framework/tools/tests/run_all.sh
git add framework/tools/tests/test_install.sh framework/tools/install.sh
git commit -m "claude-personas: install.sh sync refusal semantics (modified/force-file/orphan/prune/SHA warn)"
```

---

### Task 8: doctor.sh - new manifest keys + staleness line

**Files:**
- Modify: `framework/tools/doctor.sh:39` (ALL_VALID_KEYS)
- Modify: `framework/tools/doctor.sh:1215-1217` (shared floor - add the staleness call)
- Modify: `framework/tools/doctor.sh` (new function `check_framework_staleness`, place it next to `check_hook_scripts`)
- Modify: `framework/tools/tests/test_doctor_manifest.sh` (append tests)

**Interfaces:**
- Consumes: manifest keys `framework_source`/`framework_ref` exactly as Task 4 writes them; `manifest_get`, `report_drift`, `$ROOT` from doctor.sh.

- [ ] **Step 1: Write the failing tests**

Append to `framework/tools/tests/test_doctor_manifest.sh` before its summary/end (mirror the file's existing fixture pattern - embedded fixture with `.claude/memory` symlink etc., copy an existing passing embedded block as the base):

```bash
echo "=== test_doctor_manifest: framework_source/framework_ref are valid keys ==="
# <embedded fixture setup copied from the nearest passing block above>
cat > "$tmp/.agents/manifest" <<EOF
manifest_version=1
topology=embedded
memory_layout=flat
framework_source=../fw
framework_ref=framework/v1
EOF
# fixture framework clone next to the instance so staleness resolves
make_framework_fixture "$(dirname "$tmp")"   # only if $tmp's parent is the fixture dir; otherwise create a wrapper dir - match the surrounding fixture structure
run_doctor_check_here   # use the file's existing invocation helper/pattern
assert_not_contains "$DOCTOR_STDOUT" "unknown manifest key 'framework_source'" "framework_source accepted"
assert_not_contains "$DOCTOR_STDOUT" "unknown manifest key 'framework_ref'" "framework_ref accepted"

echo "=== test_doctor_manifest: staleness INFO when pin is behind source HEAD ==="
advance_framework_fixture "<fixture-parent>"
run_doctor_check_here
assert_contains "$DOCTOR_STDOUT" "commit(s) behind pinned source" "staleness line printed"
assert_equal "0" "$DOCTOR_EXIT" "staleness alone is INFO, not DRIFT (exit 0 when wiring is clean)"

echo "=== test_doctor_manifest: DRIFT when the pin is not found in the source ==="
cat > "$tmp/.agents/manifest" <<EOF
manifest_version=1
topology=embedded
memory_layout=flat
framework_source=../fw
framework_ref=framework/v9999
EOF
run_doctor_check_here
assert_contains "$DOCTOR_STDOUT" "not found in source" "bad pin named"
assert_equal "1" "$DOCTOR_EXIT" "bad pin is DRIFT (exit 1)"
```

The exact fixture scaffolding (`run_doctor_check_here`, dir layout) must be adapted to test_doctor_manifest.sh's real local pattern - read the file's first passing embedded test block and clone its structure. The three ASSERTIONS above are the contract; keep them verbatim. If `assert_not_contains` does not exist in test_helpers.sh, use a `case` non-match with PASS/FAIL echo.

- [ ] **Step 2: Run to verify RED**

Run: `bash framework/tools/tests/test_doctor_manifest.sh`
Expected: FAIL with `unknown manifest key 'framework_source'`.

- [ ] **Step 3: Implement in doctor.sh**

Line 39, extend the whitelist:

```bash
ALL_VALID_KEYS="manifest_version topology memory_layout adapter claude_hook codex_hook skills_mount opencode framework_source framework_ref"
```

Add the function (place it directly after `check_hook_scripts`):

```bash
check_framework_staleness() {
  # Staleness of the installed framework payload vs its pinned source
  # (spec section 3). Being BEHIND is INFO (wiring is intact; an update is
  # available); a pin the source cannot resolve, or an unreachable source,
  # is DRIFT (the recorded provenance is broken). Read-only, best effort:
  # no framework_ref key means not installed via install.sh - silent.
  local pin src parent n
  pin="$(manifest_get framework_ref)"
  [ -n "$pin" ] || return 0
  src="$(manifest_get framework_source)"
  if [ -n "$src" ]; then
    case "$src" in
      /*) ;;
      *) src="$ROOT/$src" ;;
    esac
  else
    parent="$(dirname "$ROOT")"
    if [ -f "$parent/agent-personas/framework/FILES" ]; then
      src="$parent/agent-personas"
    elif [ -f "$parent/claude-personas/framework/FILES" ]; then
      src="$parent/claude-personas"
    else
      report_drift "framework_ref is pinned but no framework_source is set and no sibling framework clone exists - set framework_source in the manifest"
      return 0
    fi
  fi
  if [ ! -d "$src" ]; then
    report_drift "framework_source '$src' unreachable"
    return 0
  fi
  if ! git -C "$src" rev-parse --verify --quiet "$pin^{commit}" >/dev/null 2>&1; then
    report_drift "framework_ref '$pin' not found in source $src - fetch the source or fix the pin"
    return 0
  fi
  n="$(git -C "$src" rev-list --count "$pin..HEAD" 2>/dev/null || echo 0)"
  if [ "$n" -gt 0 ]; then
    echo "INFO: framework payload $n commit(s) behind pinned source $src (run install.sh --sync)"
  fi
}
```

Wire it into the shared floor at lines 1215-1217:

```bash
# Shared floor for every topology, run before the topology-specific catalog.
check_payload
check_hook_scripts
check_framework_staleness
```

- [ ] **Step 4: Run the doctor tests, then the full suite**

Run: `bash framework/tools/tests/test_doctor_manifest.sh && bash framework/tools/tests/run_all.sh`
Expected: all PASS, suite exit 0.

- [ ] **Step 5: Commit**

```bash
git add framework/tools/doctor.sh framework/tools/tests/
git commit -m "claude-personas: doctor validates framework pin keys + staleness line (behind=INFO, broken pin=DRIFT)"
```

---

### Task 9: Identity-switch docs (framework CHANGELOG, root CHANGELOG freeze, README/MIGRATION flows)

**Files:**
- Create: `framework/CHANGELOG.md`
- Modify: `CHANGELOG.md` (one final entry at the top of the entries; read the file first and match its keep-a-changelog format)
- Modify: `README.md` (quick-start step 3, multi-vendor wiring note)
- Modify: `MIGRATION.md` ("scripts/ -> framework/ layout (2026-07)" section)

Note on the user rule "never manually modify CHANGELOG.md": this repo's CHANGELOG is hand-maintained (no generator) and the merged spec (section 8) explicitly mandates the freeze entry - the spec wins here; surface this tension in the PR body.

- [ ] **Step 1: Create framework/CHANGELOG.md**

```markdown
# framework payload changelog

One entry per `framework/v*` tag: what breaks / what to do.
The payload = the file set declared in [FILES](FILES); instances consume it via `install.sh` against the recorded `framework_ref` pin.

## framework/v1 - 2026-07-07

First versioned payload: doctor.sh, memory_cliff.py, init-clone.sh, list-roles.sh, install.sh, inject-role-index.sh, the load-persona-memory skill.
Breaks: the payload moved out of `scripts/` and root `skills/` into `framework/`, and the wiring now expects the inject hook at `<instance>/.agents/hooks/lib/inject-role-index.sh`.
Do: run `install.sh --into <instance>` once (then `install.sh --sync` on updates), then `doctor.sh`; existing instances see MIGRATION.md "scripts/ -> framework/ layout".
```

- [ ] **Step 2: Freeze the root CHANGELOG**

Read `CHANGELOG.md` first. Add one final entry ABOVE the `[3.1.0]` entry, matching the existing header style:

```markdown
## [frozen] - 2026-07-07

This file versioned the template era and ends here.
The repo is now an installable framework: payload changes are tracked in [framework/CHANGELOG.md](framework/CHANGELOG.md) against `framework/v*` tags (a disjoint namespace from the template-era `v1.0`-`v3.1.0` tags, which remain).
Post-switch changes outside the payload (examples, docs) are not changelogged; git history suffices.
```

- [ ] **Step 3: README - replace the interim staging step with the installer flow**

In `README.md` quick start, replace step 3 (the "Stage the framework payload ... interim step until install.sh ships" block including its `mkdir/cp/git add` code fence) with:

```markdown
3. Declare the topology and install the framework payload (once per memory repo):
   ```sh
   cd claude-personas-<my-app>
   ./framework/tools/doctor.sh --init role-clones   # writes .agents/manifest
   ./framework/tools/install.sh --into .            # installs the payload + stamps the pin
   git add .agents && git commit -m "install framework payload"
   ```
   Later updates: `./framework/tools/install.sh --sync` (or `.agents/tools/install.sh --sync` once installed), then re-run the doctor.
```

Also in the multi-vendor wiring section, update the `.codex/hooks.json` bullet's parenthetical "(the installed framework payload; see the quick start's staging step)" to "(the installed framework payload; see the quick start's install step)".

- [ ] **Step 4: MIGRATION - point the layout section at the installer**

In `MIGRATION.md`, section "scripts/ -> framework/ layout (2026-07)", replace the manual `mkdir -p / cp / git add` block with:

```markdown
```bash
cd ~/path/to/claude-personas-<app>
./framework/tools/doctor.sh --init role-clones   # skip if .agents/manifest already exists
./framework/tools/install.sh --into .
git add .agents && git commit -m "install framework payload"
```
```

Keep the following paragraph about regenerating `.codex/hooks.json` (doctor or `init-clone.sh --force`) and the `/hooks` re-approval unchanged. Also update Step 4 of the v2->v3 migration (the staging block added by #57) the same way.

- [ ] **Step 5: Verify + commit**

Run: `bash framework/tools/tests/run_all.sh` (docs changes must not break anything) and `grep -n "interim" README.md MIGRATION.md` (expect no leftover "interim step" wording).

```bash
git add framework/CHANGELOG.md CHANGELOG.md README.md MIGRATION.md
git commit -m "claude-personas: identity-switch docs (framework changelog, frozen root changelog, installer flows)"
```

---

### Task 10: Live smoke + PR

**Files:**
- No new files; PR creation.

- [ ] **Step 1: Full suite**

Run: `bash framework/tools/tests/run_all.sh`
Expected: exit 0, 0 FAIL.

- [ ] **Step 2: Live smoke - scratch constellation with the REAL repo as source**

```bash
S=$(mktemp -d)
mkdir -p "$S/inst/.agents/memory" && printf '# canary\n' > "$S/inst/.agents/memory/MEMORY.md"
( cd "$S/inst" && git init --quiet && printf 'manifest_version=1\ntopology=embedded\nmemory_layout=flat\n' > .agents/manifest )
( cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas && bash framework/tools/install.sh --into "$S/inst" --ref HEAD )
ls -la "$S/inst/.agents/tools" "$S/inst/.agents/hooks/lib"
bash "$S/inst/.agents/tools/install.sh" --help >/dev/null && echo "installed install.sh runs"
cat "$S/inst/.agents/manifest"
rm -rf "$S"
```

Expected: 7 payload files land, WARN about bare SHA only if `--ref HEAD` (expected, tag comes post-merge), pin stamped, canary intact, self-hosted install.sh executable.

- [ ] **Step 3: Live smoke - read-only doctor --check on cerebrum and user-memory**

```bash
bash /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas/framework/tools/doctor.sh --check --root /Users/jin-holee/dev/GitHub/Jin-HoMLee/cerebrum
bash /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas/framework/tools/doctor.sh --check --root /Users/jin-holee/dev/GitHub/Jin-HoMLee/user-memory
```

Expected: both behave exactly as their pinned doctors do today (no staleness line - neither manifest has `framework_ref` yet; adoption is a follow-up on epic #27). Read-only: `--check` never writes. Record both outputs for the PR body.

- [ ] **Step 4: Push and open the PR**

PR on `55-framework-installer`, title `claude-personas: framework installer (install.sh), doctor staleness, identity switch`, body must include: `Closes #55. Refs #43.`, AC-by-AC traceability to the issue checkboxes, the live-smoke outputs, the CHANGELOG-rule tension note (Task 9), and this post-merge release checklist:

```markdown
## Post-merge release steps (on the squash commit, in order)
1. `git tag -a framework/v1 -m "framework payload v1" <squash-sha> && git push origin framework/v1`
2. `gh api -X PATCH repos/Jin-HoMLee/claude-personas -F is_template=false`
3. Adoption follow-ups (epic #27): cerebrum + user-memory re-install via install.sh, manifest provenance headers retire; splice = MM's call.
```

Do NOT merge; the merge gate is Jin-Ho. In-session /code-review runs BEFORE the PR is announced, findings stay in chat (two-track split); the on-PR review is `@claude review`, triggered by Jin-Ho or on his ask.

---

## Self-review notes (kept for the executor)

- Spec coverage: section 3 (install/sync commands, refusal semantics, source resolution, manifest keys, staleness line, sync-never-touches list) = Tasks 4-8; section 8 (tags, framework CHANGELOG, root freeze, SHA-warn) = Tasks 7 (warn) + 9 + post-merge steps; section 10 (fixture tests per contract, refusal paths, live smoke) = Tasks 4-8 + 10. Deferred #57 findings 1/2/3 = Tasks 2/3/1. `is_template` off = post-merge checklist (spec: "when the installer ships").
- Role-tier readiness (spec section 3): install.sh operates only on declared FILES entries and never assumes a fixed number of content sources; the manifest keys are namespaced `framework_*`, leaving `role_source`-style keys free. No task hardcodes the two-axis model away.
- Type consistency: report vocabulary defined once in Task 4 and consumed verbatim by Tasks 5-7 assertions; fixture names defined in Task 4 Step 1 and consumed by Tasks 6-8; `stage_inject_script`/`INJECT_SRC` (Task 1) are independent of the installer fixtures.
- Known simplifications (deliberate, documented in code comments): content comparison via `$(cat)` ignores a trailing-newline-only difference; mode drift (chmod) on an otherwise identical file is not re-synced; `--into` re-runs are idempotent on identical content.
