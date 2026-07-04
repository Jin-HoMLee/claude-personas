# Per-Vendor Adapters (Template) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize the three-vendor adapter pattern (Claude Code, Codex, OpenCode) for role clones created by `init-clone.sh`, per the approved spec `docs/superpowers/specs/2026-07-03-per-vendor-adapters-template-design.md` (issue #32).

**Architecture:** Role clones get a vendor-neutral untracked mount `.agents/memory -> ../../<memory-repo>/<role>` (the role signal) plus a `.claude/memory -> ../.agents/memory` hop; Claude Code additionally needs an external `~/.claude/projects/<slug>/memory` symlink; Codex gets a generated per-clone `.codex/hooks.json` calling an inject script that ships in the memory repo; OpenCode is wired by one global `instructions` entry (per-clone absolute-path fallback behind a flag). All per-clone artifacts are untracked via `.git/info/exclude`, never `.gitignore`. Per-vendor wiring failures warn and continue; only core-mount failures roll back a fresh clone.

**Tech Stack:** bash (macOS bash 3.2 compatible - no associative arrays), jq, the existing `scripts/tests/` bash harness (`test_helpers.sh` assertions, `run_all.sh` runner, CI via `.github/workflows/validate.yml`).

## Global Constraints

- Spec is the contract: `docs/superpowers/specs/2026-07-03-per-vendor-adapters-template-design.md`. Deviations must be recorded in the caveats doc.
- No changes to the splice instance (`claude-personas-splice-neoepitope-pipeline`) - MM is sole committer there.
- No memory-repo layout restructure; no generalized `sync`/`doctor` (sub-project 3); no rename (sub-project 4).
- Untracked-ness via `.git/info/exclude` only; the script stops adding `.gitignore` lines (existing v3.1 lines are left alone).
- Fresh-clone rollback contract is unchanged: any core-mount failure removes a clone created this run (`CREATED_CLONE` / `rollback_fresh_clone`), and `--force` never deletes a pre-existing clone.
- Per-vendor wiring failures (external hop, Codex, OpenCode) report `WARN:` and continue; script exits 0 when clean, 2 when any vendor warning fired.
- The skill frontmatter uses ONLY agentskills.io standard fields: `name`, `description`.
- Commit prefix `claude-personas: ...`, one commit per task, never chain commit and push, no agent co-author line.
- All new/changed scripts must stay executable (CI checks `-x`) and pass `bash scripts/tests/run_all.sh`.
- Claude Code slug derivation: absolute physical path with `/` and `.` each replaced by `-` (helper `compute_hash` in `scripts/tests/test_helpers.sh` already encodes this); live test 4 re-verifies it against a live loader.
- Long Markdown files: one sentence per physical line; plain dash, never an em dash.

## File Structure

- `scripts/inject-role-index.sh` - NEW. Codex SessionStart inject script (ships in every memory repo instantiated from the template).
- `scripts/init-clone.sh` - MODIFY. Two-hop mount, exclude entries, external CC hop, Codex hooks.json generation, OpenCode step, per-vendor warn-and-continue, `--force` v3.1 migration, `--opencode-per-clone` flag.
- `scripts/list-roles.sh` - MODIFY (in Task 2, together with the mount change - `test_list_roles.sh` wires its fixtures through `init-clone.sh`, so the suite would go red between separate tasks). Resolve roles through `.agents/memory` first (two-hop), fall back to `.claude/memory` (v3.1).
- `skills/load-persona-memory/SKILL.md` - NEW. Generalized vendor-neutral skill (absorbs splice PR 93, convention-walking only).
- `examples/substrate/` - NEW. Embedded-topology adapter set: `README.md`, `.claude/settings.json`, `.codex/hooks.json`, `opencode.json`.
- `docs/vendor-caveats.md` - NEW. Dated per-vendor caveats + live-test results.
- `README.md` - MODIFY. New "Multi-vendor wiring" section.
- `.github/workflows/validate.yml` - MODIFY. Add `scripts/inject-role-index.sh` to the executable check.
- Tests: `scripts/tests/test_inject_role_index.sh` (NEW), `scripts/tests/test_init_clone.sh` (MODIFY - existing assertions change with the layout), `scripts/tests/test_list_roles.sh` (MODIFY).

Task order matters: Task 2 rewrites the wiring core that Tasks 3-6 extend, and existing tests are updated in the same task that changes the behavior they pin.

---

### Task 1: Codex inject script (`inject-role-index.sh`)

**Files:**
- Create: `scripts/inject-role-index.sh`
- Test: `scripts/tests/test_inject_role_index.sh`
- Modify: `.github/workflows/validate.yml` (executable check list)

**Interfaces:**
- Consumes: nothing (standalone; adapted from cerebrum's `.agents/hooks/inject-memory-index.sh`).
- Produces: `inject-role-index.sh <absolute-role-dir>` printing a Codex SessionStart `additionalContext` JSON envelope on stdout; always exits 0. Task 4's generated `.codex/hooks.json` calls it with `$ROLE_DIR` as the single argument.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/test_inject_role_index.sh` (chmod +x):

```bash
#!/usr/bin/env bash
# Test inject-role-index.sh - Codex SessionStart payload for a role dir.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
INJECT="$(cd "$SCRIPT_DIR/.." && pwd)/inject-role-index.sh"

echo "=== test_inject_role_index happy path (role + shared) ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/memory-repo/developer" "$tmp/memory-repo/shared"
printf "# Role index canary-role-line\n" > "$tmp/memory-repo/developer/MEMORY.md"
printf "# Shared index canary-shared-line\n" > "$tmp/memory-repo/shared/MEMORY.md"
( cd "$tmp/memory-repo/developer" && ln -s ../shared shared )

out="$(bash "$INJECT" "$tmp/memory-repo/developer")"
assert_equal "0" "$?" "exits 0 on happy path"

ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
assert_equal "SessionStart" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" "envelope is a SessionStart hook output"
case "$ctx" in *canary-role-line*) echo "  PASS: role index in payload";; *) echo "  FAIL: role index missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctx" in *canary-shared-line*) echo "  PASS: shared index in payload";; *) echo "  FAIL: shared index missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctx" in *TRUNCATED*) echo "  FAIL: unexpected truncation trailer"; TESTS_FAILED=$((TESTS_FAILED+1));; *) echo "  PASS: no truncation trailer on small indices";; esac
rm -rf "$tmp"

echo "=== test_inject_role_index truncation trailer on oversized index ==="
tmp2="$(mktemp -d)"
mkdir -p "$tmp2/memory-repo/developer" "$tmp2/memory-repo/shared"
# 400 lines x ~60 chars = ~24k chars, far over the 9000-char cap
for i in $(seq 1 400); do
  printf -- "- [entry %03d](file_%03d.md) - padding padding padding padding\n" "$i" "$i"
done > "$tmp2/memory-repo/developer/MEMORY.md"
printf "# Shared index\n" > "$tmp2/memory-repo/shared/MEMORY.md"
( cd "$tmp2/memory-repo/developer" && ln -s ../shared shared )

ctx2="$(bash "$INJECT" "$tmp2/memory-repo/developer" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx2" in *TRUNCATED*) echo "  PASS: truncation trailer present";; *) echo "  FAIL: truncation trailer missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctx2" in *"entry 001"*) echo "  PASS: top of index survives the cut";; *) echo "  FAIL: top of index missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
if [ "${#ctx2}" -le 9600 ]; then
  echo "  PASS: payload bounded (~9000 chars + trailer)"
else
  echo "  FAIL: payload not bounded (${#ctx2} chars)"; TESTS_FAILED=$((TESTS_FAILED+1))
fi
rm -rf "$tmp2"

echo "=== test_inject_role_index defensive exits ==="
assert_equal "0" "$( bash "$INJECT" "/nonexistent/role/dir" >/dev/null 2>&1; echo $? )" "exits 0 on missing role dir"
assert_equal "0" "$( bash "$INJECT" >/dev/null 2>&1; echo $? )" "exits 0 with no argument"
assert_equal "" "$( bash "$INJECT" "/nonexistent/role/dir" 2>/dev/null )" "prints nothing on missing role dir"

print_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test_inject_role_index.sh`
Expected: FAIL (script does not exist yet; the first `bash "$INJECT"` invocations error).

- [ ] **Step 3: Write the implementation**

Create `scripts/inject-role-index.sh` (chmod +x):

```bash
#!/usr/bin/env bash
# inject-role-index.sh - Codex SessionStart hook payload for a role clone:
# inject the role's always-loaded memory indices (role + shared) as
# additionalContext. Ships in the memory repo; the per-clone generated
# .codex/hooks.json (see init-clone.sh) calls it with the absolute role dir.
#
# Usage: inject-role-index.sh <absolute-role-dir>
#
# Codex truncates hook additionalContext hard (live test 2 in
# docs/vendor-caveats.md records the current ceiling), so this script bounds
# its own payload: whole lines only, role index first, then shared index,
# with an explicit [TRUNCATED ...] trailer when it cuts - the cut is curated
# instead of Codex slicing arbitrarily through the middle.
# Defensive by design: never fails the session start - always exits 0.

set -u

role_dir="${1:-}"
[ -n "$role_dir" ] && [ -d "$role_dir" ] || exit 0
command -v jq >/dev/null 2>&1 || {
  echo "inject-role-index: jq not found - index NOT injected; read $role_dir/MEMORY.md manually" >&2
  exit 0
}

cap=9000
payload=""
truncated=0

# Append $2 as a header, then whole lines of file $1 until the cap.
append_bounded() {
  local f="$1" hdr="$2" remaining chunk kept total
  [ -r "$f" ] || return 0
  remaining=$(( cap - ${#payload} - ${#hdr} ))
  if [ "$remaining" -le 0 ]; then truncated=1; return 0; fi
  payload="$payload$hdr"
  total="$(wc -l < "$f" | tr -d ' ')"
  chunk="$(awk -v cap="$remaining" '{n += length($0) + 1; if (n > cap) exit} {print}' "$f")"
  kept="$(printf '%s\n' "$chunk" | wc -l | tr -d ' ')"
  payload="$payload$chunk
"
  [ "$kept" -lt "$total" ] && truncated=1
}

append_bounded "$role_dir/MEMORY.md" "# Role memory index
"
append_bounded "$role_dir/shared/MEMORY.md" "
# Shared memory index
"

[ -n "$payload" ] || exit 0
if [ "$truncated" -eq 1 ]; then
  payload="$payload
[TRUNCATED by the Codex adapter - read $role_dir/MEMORY.md and $role_dir/shared/MEMORY.md for the full indices]"
fi

jq -nc --arg ctx "$payload" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' 2>/dev/null || true
exit 0
```

Run: `chmod +x scripts/inject-role-index.sh scripts/tests/test_inject_role_index.sh`

- [ ] **Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test_inject_role_index.sh`
Expected: all PASS, `print_summary` reports 0 failed.

- [ ] **Step 5: Add the script to CI's executable check**

In `.github/workflows/validate.yml`, extend the `scripts are executable` list:

```yaml
          for s in scripts/init-clone.sh scripts/list-roles.sh scripts/memory_cliff.py \
                   scripts/inject-role-index.sh \
                   scripts/tests/run_all.sh scripts/tests/test_memory_cliff.sh; do
```

- [ ] **Step 6: Run the whole suite and commit**

Run: `bash scripts/tests/run_all.sh`
Expected: all test files pass (existing tests untouched).

```bash
git add scripts/inject-role-index.sh scripts/tests/test_inject_role_index.sh .github/workflows/validate.yml
git commit -m "claude-personas: add Codex inject-role-index.sh (bounded role+shared payload) with tests"
```

---

### Task 2: Two-hop core mount + `.git/info/exclude` + two-hop-aware `list-roles.sh`

**Files:**
- Modify: `scripts/init-clone.sh:154-221` (the post-clone wiring section)
- Modify: `scripts/list-roles.sh:40-59` (candidate matching - changes together with the layout, else the suite goes red)
- Modify: `scripts/tests/test_init_clone.sh` (layout assertions change everywhere)
- Modify: `scripts/tests/test_list_roles.sh` (`HOME=` overrides on every `$INIT_CLONE` invocation)

**Interfaces:**
- Consumes: existing `TARGET`, `MEMORY_REPO_NAME`, `ROLE`, `FORCE`, `CREATED_CLONE`, `rollback_fresh_clone`.
- Produces: symlinks `.agents/memory -> ../../<memory-repo>/<role>` and `.claude/memory -> ../.agents/memory`; helper `add_exclude <pattern>` (idempotent append to `$TARGET/.git/info/exclude`); helpers `vendor_warn <msg>` / counter `VENDOR_WARNINGS` used by Tasks 3-5.

- [ ] **Step 1: Update the tests to pin the new layout (failing first)**

In `scripts/tests/test_init_clone.sh`, make these changes:

(a) Happy path (currently lines 20-31) - replace the symlink and .gitignore assertions:

```bash
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
```

(b) Every other `assert_symlink ".../.claude/memory" "../../claude-personas-myapp/<role>"` in the file becomes a pair - the mount assertion on `.agents/memory` plus the hop assertion. Affected blocks: `--main` (line 108), `main-role.txt` (line 125), `--force` rewire (line 154), `--target` (line 264), v3.0 migration (line 312). Example for the `--main` block:

```bash
assert_symlink "$tmp5/myapp/.agents/memory" "../../claude-personas-myapp/pm" "mount points to pm/"
assert_symlink "$tmp5/myapp/.claude/memory" "../.agents/memory" "hop points to .agents/memory"
```

(c) The `--force` rewire test (line 147) plants the broken symlink at `.claude/memory`; extend it to also break `.agents/memory` the same way, and assert exactly one `memory.backup-*` under EACH of `.claude/` and `.agents/`:

```bash
rm "$tmp7/myapp/.claude/memory" "$tmp7/myapp/.agents/memory"
ln -s /nonexistent "$tmp7/myapp/.claude/memory"
ln -s /nonexistent "$tmp7/myapp/.agents/memory"
```

and after the re-run:

```bash
assert_symlink "$tmp7/myapp/.agents/memory" "../../claude-personas-myapp/developer" "mount re-wired"
assert_symlink "$tmp7/myapp/.claude/memory" "../.agents/memory" "hop re-wired"
backup_count="$(find "$tmp7/myapp/.claude" -maxdepth 1 -name "memory.backup-*" | wc -l | tr -d ' ')"
assert_equal "1" "$backup_count" "exactly one .claude backup created"
agents_backup_count="$(find "$tmp7/myapp/.agents" -maxdepth 1 -name "memory.backup-*" | wc -l | tr -d ' ')"
assert_equal "1" "$agents_backup_count" "exactly one .agents backup created"
```

(d) The `.gitignore` idempotency test (tmp10) is repurposed as exclude idempotency:

```bash
count1="$(grep -cxF '/.claude/memory' "$tmp10/myapp/.git/info/exclude" || true)"
# Re-run with --force
( cd "$tmp10/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --force --project-url "$tmp10/project-repo.git" )
count2="$(grep -cxF '/.claude/memory' "$tmp10/myapp/.git/info/exclude" || true)"
assert_equal "$count1" "$count2" "exclude line count unchanged after --force re-run"
assert_equal "1" "$count2" "exactly one /.claude/memory line in exclude"
```

(e) The v3.0 migration tests (tmp14, tmp15) keep their legacy-line-removed assertions but drop the "new /.claude/memory/ line present in .gitignore" assertion, replacing it with the exclude assertion from (a).

(f) The "cloned repo ships .claude/memory" rollback test (tmp19) stays as-is (the collision now happens at the hop-creation step; behavior is identical).

NOTE for all blocks that invoke `$INIT_CLONE`: prefix every invocation with `HOME="$tmpN/home"` after `mkdir -p "$tmpN/home"`, so Task 3's external hop (which writes under `$HOME/.claude/projects/`) never touches the real home. Add the `mkdir -p` next to each `make_clone_test_fixture` call. This is inert for Task 2 and required from Task 3 on; doing it now avoids touching every block twice.

- [ ] **Step 2: Run tests to verify the new assertions fail**

Run: `bash scripts/tests/test_init_clone.sh`
Expected: FAIL on the new `.agents/memory` assertions (old code creates only the direct `.claude/memory` symlink).

- [ ] **Step 3: Rewrite the wiring section of `init-clone.sh`**

Replace lines 154-211 (from the `# Wire memory symlink under .claude/.` comment through the `.gitignore` block) with:

```bash
# --- Helpers for wiring ------------------------------------------------------

# Idempotently append a line to the clone's .git/info/exclude (per-clone
# untracked-ness that never dirties the project repo - spec decision log).
EXCLUDE_FILE="$TARGET/.git/info/exclude"
add_exclude() {
  mkdir -p "$(dirname "$EXCLUDE_FILE")"
  touch "$EXCLUDE_FILE"
  grep -qxF "$1" "$EXCLUDE_FILE" 2>/dev/null || printf '%s\n' "$1" >> "$EXCLUDE_FILE"
}

# Per-vendor failures report and continue - one vendor's problem must not
# kill the other two (spec: init-clone.sh changes, last bullet).
VENDOR_WARNINGS=0
vendor_warn() {
  echo "WARN: $*" >&2
  VENDOR_WARNINGS=$((VENDOR_WARNINGS + 1))
}

# --- Core mount (vendor-neutral, rollback-protected) --------------------------
# .agents/memory -> ../../<memory-repo>/<role>   (the single role signal)
# .claude/memory -> ../.agents/memory            (Claude Code in-repo hop)
# A failure anywhere in this window must roll back a clone we created this run.

if ! mkdir -p "$TARGET/.agents" "$TARGET/.claude"; then
  echo "Error: failed to create $TARGET/.agents or $TARGET/.claude" >&2
  rollback_fresh_clone
  exit 1
fi
AGENTS_LINK="$TARGET/.agents/memory"
MEMORY_LINK="$TARGET/.claude/memory"

# Migrate v3.0 layout: legacy root symlink -> back up under .claude/
LEGACY_LINK="$TARGET/memory"
if [[ "$FORCE" -eq 1 && ( -L "$LEGACY_LINK" || -e "$LEGACY_LINK" ) ]]; then
  LEGACY_BACKUP="$TARGET/.claude/memory.legacy-backup-$(date +%Y%m%d-%H%M%S)"
  mv "$LEGACY_LINK" "$LEGACY_BACKUP"
  echo "✓ Migrated legacy root memory/ → $LEGACY_BACKUP"
fi

# Back up whatever sits at either mount point (v3.1 direct symlink on a
# --force migration, or artifacts from a prior run).
for link in "$AGENTS_LINK" "$MEMORY_LINK"; do
  if [[ -e "$link" || -L "$link" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then
      BACKUP="$link.backup-$(date +%Y%m%d-%H%M%S)"
      mv "$link" "$BACKUP"
      echo "✓ Backed up existing ${link#"$TARGET"/} → ${BACKUP#"$TARGET"/}"
    else
      echo "Error: $link already exists. Use --force to back up." >&2
      rollback_fresh_clone
      exit 1
    fi
  fi
done

if ! ln -s "../../$MEMORY_REPO_NAME/$ROLE" "$AGENTS_LINK"; then
  echo "Error: failed to create memory mount $AGENTS_LINK" >&2
  rollback_fresh_clone
  exit 1
fi
echo "✓ Symlinked .agents/memory → ../../$MEMORY_REPO_NAME/$ROLE"

if ! ln -s "../.agents/memory" "$MEMORY_LINK"; then
  echo "Error: failed to create Claude Code hop $MEMORY_LINK" >&2
  rollback_fresh_clone
  exit 1
fi
echo "✓ Symlinked .claude/memory → ../.agents/memory"

# Untracked-ness via exclude, NOT .gitignore. Existing committed v3.1
# .gitignore lines keep working; we just stop adding new ones. NOTE the
# entries have no trailing slash: a trailing slash matches only real
# directories, and these paths are symlinks.
add_exclude "# claude-personas vendor wiring (per-clone, untracked)"
add_exclude "/.agents/memory"
add_exclude "/.claude/memory"

# Remove legacy /memory/ line on --force (v3.0 -> v3.1 migration) - unchanged.
GITIGNORE="$TARGET/.gitignore"
if [[ "$FORCE" -eq 1 && -f "$GITIGNORE" ]] && grep -qE '^/?memory/?$' "$GITIGNORE"; then
  grep -vE '^/?memory/?$' "$GITIGNORE" > "$GITIGNORE.tmp" || true
  mv "$GITIGNORE.tmp" "$GITIGNORE"
  echo "✓ Removed legacy /memory/ from $GITIGNORE"
fi
```

Note the old unconditional `touch "$GITIGNORE"` is gone (fresh clones no longer get a `.gitignore`), and the `.claude/memory` gitignore-append block is deleted entirely.

- [ ] **Step 4: Update the final message**

Replace the closing two lines (`echo ""` / `echo "Done. Open $TARGET in Claude Code..."`) with a summary that Tasks 3-5 will extend:

```bash
echo ""
if [[ "$VENDOR_WARNINGS" -gt 0 ]]; then
  echo "Done with $VENDOR_WARNINGS vendor warning(s) - see WARN lines above. Core mount is wired."
  exit 2
fi
echo "Done. Open $TARGET in Claude Code → role memory loads via .claude/memory → .agents/memory."
```

- [ ] **Step 5: Make `list-roles.sh` two-hop aware (same commit - its tests wire fixtures through `init-clone.sh`)**

In `scripts/list-roles.sh`, replace the inner candidate loop (lines 44-59) with:

```bash
  for cand in "${candidates[@]}"; do
    if [[ ! -d "$cand/.git" ]]; then continue; fi
    # Prefer the vendor-neutral mount (two-hop layout); fall back to the
    # v3.1 direct .claude/memory symlink.
    link=""
    if [[ -L "$cand/.agents/memory" ]]; then
      link="$cand/.agents/memory"
    elif [[ -L "$cand/.claude/memory" ]]; then
      link="$cand/.claude/memory"
    else
      continue
    fi
    target="$(readlink "$link")"
    # Match if symlink target ends with /<role> (handles both healthy and broken symlinks)
    if [[ "$target" == *"/$role" || "$target" == "$role" ]]; then
      found_clone="$cand"
      break
    fi
    # Also claim the role-suffix clone even if symlink points elsewhere (broken re-wire)
    if [[ "$cand" == *"-$role" ]]; then
      found_clone="$cand"
      break
    fi
  done
```

The health check below it (`resolved="$found_clone/.claude/memory/MEMORY.md"`, line 68) stays - it resolves through the hop in the new layout and directly in the old one, so it is layout-agnostic.
The drift simulation in `test_list_roles.sh` (breaking `.claude/memory`, lines 22-23) keeps working: the role is now found via the healthy `.agents/memory` mount and the health check still sees the broken hop → BROKEN.

- [ ] **Step 6: Add `HOME=` overrides to `test_list_roles.sh`**

Every `bash "$INIT_CLONE"` invocation in `scripts/tests/test_list_roles.sh` (lines 17, 19, 65) gets a `HOME` override, with a `mkdir -p "$tmpN/home"` after the fixture call - inert until Task 3's external hop lands, exactly like the `test_init_clone.sh` treatment:

```bash
( cd "$tmp/claude-personas-myapp" && \
  HOME="$tmp/home" bash "$INIT_CLONE" developer --project-url "$tmp/project-repo.git" )
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `bash scripts/tests/test_init_clone.sh && bash scripts/tests/test_list_roles.sh && bash scripts/tests/run_all.sh`
Expected: all PASS - the whole suite is green at this commit.

- [ ] **Step 8: Commit**

```bash
git add scripts/init-clone.sh scripts/list-roles.sh scripts/tests/test_init_clone.sh scripts/tests/test_list_roles.sh
git commit -m "claude-personas: init-clone two-hop mount + .git/info/exclude; list-roles two-hop aware"
```

---

### Task 3: External Claude Code hop in `init-clone.sh`

**Files:**
- Modify: `scripts/init-clone.sh` (add `wire_cc_external_hop` after the core mount, call it before the final summary)
- Modify: `scripts/tests/test_init_clone.sh` (new test blocks)

**Interfaces:**
- Consumes: `TARGET`, `vendor_warn`, `HOME` (tests override it).
- Produces: `~/.claude/projects/<slug>/memory -> <clone-abs>/.claude/memory` where `<slug>` = physical clone path with `/` and `.` replaced by `-` (same rule as `compute_hash` in `test_helpers.sh`).

- [ ] **Step 1: Write the failing tests**

Append to `scripts/tests/test_init_clone.sh` (before `print_summary`):

```bash
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

set +e
( cd "$tmp21/claude-personas-myapp" && \
  HOME="$tmp21/home" bash "$INIT_CLONE" developer --project-url "$tmp21/project-repo.git" ) 2>"$tmp21/stderr.log"
status=$?
set -e 2>/dev/null || true
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/tests/test_init_clone.sh`
Expected: the three new blocks FAIL (no external hop is created yet).

- [ ] **Step 3: Implement `wire_cc_external_hop`**

In `scripts/init-clone.sh`, after the exclude block and before the final summary, add:

```bash
# --- Claude Code external hop -------------------------------------------------
# CC's auto-memory loader reads ~/.claude/projects/<slug>/memory, NOT the
# in-repo path (latent v3.1 gap found in spec self-review). <slug> is CC's
# own derivation of the clone's absolute physical path: '/' and '.' each
# become '-' (live test 4 in docs/vendor-caveats.md re-verifies this).
# Report-and-continue: a refusal here must not kill Codex/OpenCode wiring.
wire_cc_external_hop() {
  local clone_abs slug proj_dir ext expected
  clone_abs="$(cd "$TARGET" && pwd -P)" || { vendor_warn "Claude Code: cannot resolve clone path"; return 0; }
  slug="$(printf '%s' "$clone_abs" | tr '/.' '-')"
  proj_dir="$HOME/.claude/projects"
  ext="$proj_dir/$slug/memory"
  expected="$clone_abs/.claude/memory"

  if [[ -L "$ext" ]]; then
    if [[ "$(readlink "$ext")" == "$expected" ]]; then
      echo "✓ External Claude Code hop already wired: $ext"
    elif ln -sfn "$expected" "$ext"; then
      echo "✓ Repaired external Claude Code hop: $ext → $expected"
    else
      vendor_warn "Claude Code: could not repair external hop $ext"
    fi
  elif [[ -d "$ext" ]]; then
    if [[ -z "$(ls -A "$ext")" ]] && rmdir "$ext" 2>/dev/null && ln -s "$expected" "$ext"; then
      echo "✓ Replaced empty directory with external Claude Code hop: $ext"
    else
      vendor_warn "Claude Code: $ext is a real directory with content - refusing to touch; reconcile by hand (auto-memory may have been written there), then re-run with --force"
    fi
  elif [[ -e "$ext" ]]; then
    vendor_warn "Claude Code: $ext exists and is neither symlink nor directory - refusing to touch"
  else
    if mkdir -p "$proj_dir/$slug" && ln -s "$expected" "$ext"; then
      echo "✓ Symlinked external Claude Code hop: $ext → $expected"
    else
      vendor_warn "Claude Code: could not create external hop $ext"
    fi
  fi
  return 0
}

wire_cc_external_hop
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/tests/test_init_clone.sh`
Expected: all PASS. Double-check no test invokes `$INIT_CLONE` without `HOME=` override (grep: `grep -n 'bash "\$INIT_CLONE"' scripts/tests/test_init_clone.sh` - every hit must have `HOME=` on the invocation or in the block).

- [ ] **Step 5: Commit**

```bash
git add scripts/init-clone.sh scripts/tests/test_init_clone.sh
git commit -m "claude-personas: init-clone creates/repairs the external CC auto-memory hop (v3.1 gap fix)"
```

---

### Task 4: Codex adapter generation in `init-clone.sh`

**Files:**
- Modify: `scripts/init-clone.sh` (add `wire_codex_adapter` + one-time trust-steps note)
- Modify: `scripts/tests/test_init_clone.sh`

**Interfaces:**
- Consumes: `MEMORY_REPO`, `ROLE_DIR` (absolute role dir - set at line 49), `TARGET`, `FORCE`, `add_exclude`, `vendor_warn`; Task 1's `scripts/inject-role-index.sh`.
- Produces: `$TARGET/.codex/hooks.json` whose single SessionStart command is `'<memory-repo>/scripts/inject-role-index.sh' '<role-dir>'`.

- [ ] **Step 1: Write the failing tests**

Append to `scripts/tests/test_init_clone.sh`:

```bash
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
memrepo_abs="$(cd "$tmp23/claude-personas-myapp" && pwd -P)"
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

set +e
( cd "$tmp24/claude-personas-myapp" && \
  HOME="$tmp24/home" bash "$INIT_CLONE" developer --project-url "$tmp24/project-repo.git" ) 2>"$tmp24/stderr.log"
status=$?
set -e 2>/dev/null || true
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

set +e
( cd "$tmp25/claude-personas-myapp" && \
  HOME="$tmp25/home" bash "$INIT_CLONE" developer --project-url "$tmp25/project-repo.git" ) >/dev/null 2>&1
set -e 2>/dev/null || true
assert_equal '{"hooks":{}}' "$(cat "$tmp25/myapp/.codex/hooks.json")" "non---force run preserved custom hooks.json"

( cd "$tmp25/claude-personas-myapp" && \
  HOME="$tmp25/home" bash "$INIT_CLONE" developer --force --project-url "$tmp25/project-repo.git" )
cmd25="$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$tmp25/myapp/.codex/hooks.json")"
case "$cmd25" in *inject-role-index.sh*) echo "  PASS: --force regenerated hooks.json";; *) echo "  FAIL: --force did not regenerate"; exit 1;; esac
backup25="$(find "$tmp25/myapp/.codex" -maxdepth 1 -name "hooks.json.backup-*" | wc -l | tr -d ' ')"
assert_equal "1" "$backup25" "custom hooks.json backed up on --force"

cleanup_clone_test_fixture "$tmp25"
```

Caveat on the middle block of tmp25: a plain re-run without `--force` exits 1 early ("target already exists"), never reaching Codex wiring - which also preserves the file, so the assertion holds either way; the behavioral contract being pinned is "non---force never clobbers".

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/tests/test_init_clone.sh`
Expected: new blocks FAIL (no `.codex/hooks.json` generated yet). NOTE: earlier tests now get a Codex WARN (fixtures lack the inject script) and `exit 2`; where an existing block asserts plain success, wrap the invocation to tolerate exit 2 - change `( cd ... && bash "$INIT_CLONE" ... )` to `( cd ... && HOME=... bash "$INIT_CLONE" ... ) || [ $? -eq 2 ]`. Apply that to every pre-Task-4 block that runs a successful wiring.

- [ ] **Step 3: Implement `wire_codex_adapter`**

Add after `wire_cc_external_hop` (function and call), plus the trust-steps note flag:

```bash
# --- Codex adapter -------------------------------------------------------------
# Per-clone generated hooks.json with ABSOLUTE paths (cerebrum pattern); the
# inject script ships in the memory repo so all of that project's clones share
# one copy. Trust is two-layer and NOT scriptable: repo trust + per-hook
# /hooks review, re-triggered whenever the generated file changes.
CODEX_WIRED=0
wire_codex_adapter() {
  local inject="$MEMORY_REPO/scripts/inject-role-index.sh"
  local hooks="$TARGET/.codex/hooks.json"
  if [[ ! -x "$inject" ]]; then
    vendor_warn "Codex: $inject missing or not executable (update the memory repo from the template) - .codex/hooks.json not generated"
    return 0
  fi
  if [[ -e "$hooks" && "$FORCE" -ne 1 ]]; then
    vendor_warn "Codex: $hooks already exists - re-run with --force to back up and regenerate"
    return 0
  fi
  if [[ -e "$hooks" ]]; then
    mv "$hooks" "$hooks.backup-$(date +%Y%m%d-%H%M%S)"
    echo "✓ Backed up existing .codex/hooks.json"
  fi
  if ! mkdir -p "$TARGET/.codex"; then
    vendor_warn "Codex: cannot create $TARGET/.codex"
    return 0
  fi
  if ! cat > "$hooks" <<EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'$inject' '$ROLE_DIR'",
            "timeout": 10,
            "statusMessage": "Injecting role memory index…"
          }
        ]
      }
    ]
  }
}
EOF
  then
    vendor_warn "Codex: could not write $hooks"
    return 0
  fi
  add_exclude "/.codex/hooks.json"
  echo "✓ Generated .codex/hooks.json (role: $ROLE)"
  CODEX_WIRED=1
  return 0
}

wire_codex_adapter
```

And extend the final summary (before the exit logic) with the one-time steps:

```bash
if [[ "$CODEX_WIRED" -eq 1 ]]; then
  echo ""
  echo "Codex one-time steps (not scriptable):"
  echo "  1. Open Codex in $TARGET and accept the repo trust prompt."
  echo "  2. Run /hooks in Codex and approve the generated SessionStart hook."
  echo "     (Re-approval is required whenever .codex/hooks.json changes.)"
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/tests/test_init_clone.sh && bash scripts/tests/run_all.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/init-clone.sh scripts/tests/test_init_clone.sh
git commit -m "claude-personas: init-clone generates per-clone .codex/hooks.json calling the memory repo's inject script"
```

---

### Task 5: OpenCode wiring in `init-clone.sh`

**Files:**
- Modify: `scripts/init-clone.sh` (flag `--opencode-per-clone`, `wire_opencode_adapter`, one-time note)
- Modify: `scripts/tests/test_init_clone.sh`

**Interfaces:**
- Consumes: `TARGET`, `FORCE`, `add_exclude`, `vendor_warn`.
- Produces: default = printed one-time global instruction; with `--opencode-per-clone` = `$TARGET/opencode.json` with the absolute `instructions` path. Live test 1 (Task 12) may flip which is default; the flip procedure is documented there.

- [ ] **Step 1: Write the failing tests**

Append to `scripts/tests/test_init_clone.sh`:

```bash
# --- OpenCode: default prints the one-time global step, writes no per-clone file ---
echo "=== test_init_clone OpenCode default (global instructions note) ==="
tmp26="$(mktemp -d)"
make_clone_test_fixture "$tmp26"
mv "$tmp26/memory-repo" "$tmp26/claude-personas-myapp"
mkdir -p "$tmp26/home"

out26="$( cd "$tmp26/claude-personas-myapp" && \
  HOME="$tmp26/home" bash "$INIT_CLONE" developer --project-url "$tmp26/project-repo.git" 2>/dev/null )" || true
assert_not_exists "$tmp26/myapp/opencode.json" "no per-clone opencode.json by default"
case "$out26" in
  *".agents/memory/MEMORY.md"*opencode*|*opencode*".agents/memory/MEMORY.md"*)
    echo "  PASS: one-time global OpenCode step printed";;
  *) echo "  FAIL: global OpenCode step not printed"; exit 1;;
esac

cleanup_clone_test_fixture "$tmp26"

# --- OpenCode: --opencode-per-clone writes the absolute-path fallback ---
echo "=== test_init_clone OpenCode per-clone fallback ==="
tmp27="$(mktemp -d)"
make_clone_test_fixture "$tmp27"
mv "$tmp27/memory-repo" "$tmp27/claude-personas-myapp"
mkdir -p "$tmp27/home"

( cd "$tmp27/claude-personas-myapp" && \
  HOME="$tmp27/home" bash "$INIT_CLONE" developer --opencode-per-clone --project-url "$tmp27/project-repo.git" ) || [ $? -eq 2 ]

oc="$tmp27/myapp/opencode.json"
assert_exists "$oc" "per-clone opencode.json written"
clone_abs27="$(cd "$tmp27/myapp" && pwd -P)"
got="$(jq -r '.instructions[0]' "$oc")"
assert_equal "$clone_abs27/.agents/memory/MEMORY.md" "$got" "instructions entry is the absolute resolved path"
if grep -qxF "/opencode.json" "$tmp27/myapp/.git/info/exclude"; then
  echo "  PASS: /opencode.json in exclude"
else
  echo "  FAIL: /opencode.json missing from exclude"; exit 1
fi

cleanup_clone_test_fixture "$tmp27"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash scripts/tests/test_init_clone.sh`
Expected: the two new blocks FAIL (`--opencode-per-clone` is an unknown flag; no note printed).

- [ ] **Step 3: Implement flag + `wire_opencode_adapter`**

(a) In the arg parser (line 34-44), add:

```bash
    --opencode-per-clone) OPENCODE_PER_CLONE=1; shift ;;
```

and initialize `OPENCODE_PER_CLONE=0` next to `MAIN=0` / `FORCE=0`; document the flag in `usage()`:

```
  --opencode-per-clone  Write a per-clone opencode.json (absolute path) instead of
                        relying on the one-time global ~/.config/opencode/opencode.json
                        instructions entry. Use when OpenCode cannot glob through the
                        .agents/memory symlink (see docs/vendor-caveats.md).
```

(b) Add after `wire_codex_adapter` (function and call):

```bash
# --- OpenCode adapter ----------------------------------------------------------
# Preferred wiring is GLOBAL and one-time (spec decision log): a relative
# "instructions" entry resolves against each session's project dir, so a
# single entry serves every wired clone. Gated on OpenCode's symlink-glob
# behavior (live test 1) - the per-clone absolute-path file is the fallback.
OPENCODE_GLOBAL_NOTE=0
wire_opencode_adapter() {
  if [[ "$OPENCODE_PER_CLONE" -ne 1 ]]; then
    OPENCODE_GLOBAL_NOTE=1
    return 0
  fi
  local oc="$TARGET/opencode.json" clone_abs
  clone_abs="$(cd "$TARGET" && pwd -P)" || { vendor_warn "OpenCode: cannot resolve clone path"; return 0; }
  if [[ -e "$oc" && "$FORCE" -ne 1 ]]; then
    vendor_warn "OpenCode: $oc already exists - re-run with --force to back up and regenerate"
    return 0
  fi
  if [[ -e "$oc" ]]; then
    mv "$oc" "$oc.backup-$(date +%Y%m%d-%H%M%S)"
    echo "✓ Backed up existing opencode.json"
  fi
  if ! printf '{\n  "$schema": "https://opencode.ai/config.json",\n  "instructions": ["%s"]\n}\n' "$clone_abs/.agents/memory/MEMORY.md" > "$oc"; then
    vendor_warn "OpenCode: could not write $oc"
    return 0
  fi
  add_exclude "/opencode.json"
  echo "✓ Wrote per-clone opencode.json (absolute instructions path)"
  return 0
}

wire_opencode_adapter
```

(c) Extend the final summary (next to the Codex note):

```bash
if [[ "$OPENCODE_GLOBAL_NOTE" -eq 1 ]]; then
  echo ""
  echo "OpenCode one-time step (per machine, serves every wired clone):"
  echo "  Add \".agents/memory/MEMORY.md\" to the \"instructions\" array in"
  echo "  ~/.config/opencode/opencode.json"
  echo "  (If OpenCode does not load it through the symlink, re-run with"
  echo "   --opencode-per-clone; see docs/vendor-caveats.md.)"
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash scripts/tests/test_init_clone.sh && bash scripts/tests/run_all.sh`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/init-clone.sh scripts/tests/test_init_clone.sh
git commit -m "claude-personas: init-clone OpenCode wiring - global one-time note by default, --opencode-per-clone fallback"
```

---

### Task 6: v3.1 → two-hop `--force` migration test

Task 2's backup loop already implements the migration mechanics; this task pins the end-to-end migration behavior the spec promises ("v3.1 clones migrate by re-running `init-clone.sh --force`").

**Files:**
- Modify: `scripts/tests/test_init_clone.sh`

**Interfaces:**
- Consumes: Task 2's mount code, Task 3's external hop.
- Produces: a regression test named `v3.1 -> two-hop migration`.

- [ ] **Step 1: Write the test (expected to pass already - it is a contract pin, verify honestly)**

Append to `scripts/tests/test_init_clone.sh`:

```bash
# --- v3.1 -> two-hop migration via --force (spec: CC adapter, last paragraph) ---
echo "=== test_init_clone v3.1 -> two-hop migration ==="
tmp28="$(mktemp -d)"
make_clone_test_fixture "$tmp28"
mv "$tmp28/memory-repo" "$tmp28/claude-personas-myapp"
mkdir -p "$tmp28/home"

# Plant a v3.1-shaped clone BY HAND: direct .claude/memory symlink + gitignore line.
git clone --quiet "$tmp28/project-repo.git" "$tmp28/myapp"
mkdir -p "$tmp28/myapp/.claude"
ln -s "../../claude-personas-myapp/developer" "$tmp28/myapp/.claude/memory"
printf "\n# claude-personas role-memory symlink\n/.claude/memory/\n" >> "$tmp28/myapp/.gitignore"

( cd "$tmp28/claude-personas-myapp" && \
  HOME="$tmp28/home" bash "$INIT_CLONE" developer --force --project-url "$tmp28/project-repo.git" ) || [ $? -eq 2 ]

assert_symlink "$tmp28/myapp/.agents/memory" "../../claude-personas-myapp/developer" "mount created on migration"
assert_symlink "$tmp28/myapp/.claude/memory" "../.agents/memory" "direct v3.1 symlink rewired into the hop"
assert_exists "$tmp28/myapp/.claude/memory/MEMORY.md" "MEMORY.md resolves after migration"
mig_backup="$(find "$tmp28/myapp/.claude" -maxdepth 1 -name "memory.backup-*" | wc -l | tr -d ' ')"
assert_equal "1" "$mig_backup" "old direct symlink backed up (existing backup semantics)"

# Existing v3.1 .gitignore line is LEFT ALONE (spec: "keep working; stop adding").
if grep -qE '^/?\.claude/memory/?$' "$tmp28/myapp/.gitignore"; then
  echo "  PASS: existing v3.1 .gitignore line preserved"
else
  echo "  FAIL: v3.1 .gitignore line was removed"; exit 1
fi

# External hop created for the migrated clone too.
mig_slug="$(compute_hash "$(cd "$tmp28/myapp" && pwd -P)")"
assert_exists "$tmp28/home/.claude/projects/$mig_slug/memory" "external hop created on migration"

cleanup_clone_test_fixture "$tmp28"
```

- [ ] **Step 2: Run the test and inspect the results honestly**

Run: `bash scripts/tests/test_init_clone.sh`
Expected: PASS if Tasks 2-3 are correct; a FAIL here is a real bug in the migration path - fix `init-clone.sh`, not the test.

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_init_clone.sh
git commit -m "claude-personas: pin v3.1 -> two-hop --force migration behavior"
```

---

### Task 7: `list-roles.sh` still detects unmigrated v3.1 clones (regression pin)

Task 2 implemented the fallback; this pins it so a later cleanup cannot silently drop v3.1 detection while unmigrated instances exist in the wild.

**Files:**
- Modify: `scripts/tests/test_list_roles.sh`

**Interfaces:**
- Consumes: Task 2's `list-roles.sh` fallback branch.
- Produces: a regression test named `v3.1 direct-symlink clone still detected`.

- [ ] **Step 1: Write the test (expected to pass already - a contract pin, verify honestly)**

Append to `scripts/tests/test_list_roles.sh` (before `print_summary`):

```bash
# --- v3.1 direct-symlink clone still detected (fallback branch) ---
echo "=== test_list_roles v3.1 direct-symlink clone still detected ==="
tmp4="$(mktemp -d)"
make_clone_test_fixture "$tmp4"
mv "$tmp4/memory-repo" "$tmp4/claude-personas-myapp"

# Hand-plant a v3.1-shaped clone: direct .claude/memory symlink, NO .agents/memory.
git clone --quiet "$tmp4/project-repo.git" "$tmp4/myapp"
mkdir -p "$tmp4/myapp/.claude"
ln -s "../../claude-personas-myapp/developer" "$tmp4/myapp/.claude/memory"

output="$( cd "$tmp4/claude-personas-myapp" && bash "$LIST_ROLES" 2>&1 || true )"
if echo "$output" | grep -q "developer.*OK"; then
  echo "  PASS: v3.1 developer clone reported OK via fallback"
else
  echo "  FAIL: v3.1 developer clone not detected"
  echo "$output"
  exit 1
fi

cleanup_clone_test_fixture "$tmp4"
```

- [ ] **Step 2: Run the test and inspect the results honestly**

Run: `bash scripts/tests/test_list_roles.sh`
Expected: PASS if Task 2's fallback branch is correct; a FAIL here is a real bug in `list-roles.sh` - fix the script, not the test.

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/test_list_roles.sh
git commit -m "claude-personas: pin v3.1 direct-symlink detection in list-roles"
```

---

### Task 8: Generalized `load-persona-memory` skill

**Files:**
- Create: `skills/load-persona-memory/SKILL.md`

**Interfaces:**
- Consumes: the layout conventions from Tasks 2-5 and the spec's 5-step resolution algorithm (spec "The generalized load-persona-memory skill", including the candidate-enumeration rule added in the review fixes).
- Produces: the skill file; installed per-machine by users via the README steps (Task 11). No instance-specific content - splice's hardcoded mappings and Codex-specific frontmatter are deliberately absent.

- [ ] **Step 1: Write the skill file**

Create `skills/load-persona-memory/SKILL.md` with exactly this content:

```markdown
---
name: load-persona-memory
description: Use when working in a repo wired to a personas memory repo (role clones or the memory repo itself), especially requests to load or refresh role/shared memory, follow MEMORY.md links, or resolve which role this workspace is - works identically from Claude Code, Codex, and OpenCode.
---

# Load Persona Memory

## Purpose

Read repo-backed persona memory (the claude-personas pattern) from any of the three supported tools.
The memory repo is the source of truth.
Do not mirror memory into tool-native stores (Codex `~/.codex/memories/`, etc.) and do not treat tool-generated memories as persona guidance.

## Discovery

Resolve the memory repo and role before reading memory, in this order - first hit wins.

1. Read the workspace's `.agents/memory` symlink target: the target directory name is the role, the target path is the memory repo.
2. Else read `.claude/memory` the same way (v3.1 legacy direct symlink).
3. Else enumerate candidates: every sibling directory of the workspace (same parent dir) containing a `.claude-personas/project.txt` marker.
   Verify each by comparing the workspace's `origin` remote against that `project.txt`.
   Normalize both sides to a canonical `owner/repo` before comparing: strip a leading `git@<host>:`, `ssh://git@<host>/`, or `https://<host>/` prefix and any trailing `.git`, so the scp-like SSH, scheme SSH, and HTTPS forms of the same remote compare equal.
   Exactly one match wins; zero or multiple matches fail with a report, never a guess.
4. If the workspace is itself the memory repo (it has `.claude-personas/` and role dirs with `MEMORY.md` files), the role is `memory_manager`.
5. Last resort: clone-naming conventions as implemented by `scripts/init-clone.sh` - the no-suffix clone is the main role (`.claude-personas/main-role.txt` when present, else `developer`); suffix clones are `<project>-<role>`.

Validate that `<memory-repo>/<role>/MEMORY.md` exists before proceeding.

## Read Order

Every time persona memory is needed, issue fresh file-read tool calls.
Do not rely on prior same-session reads.

Read these two indices first:

```text
<memory-repo>/<role>/MEMORY.md
<memory-repo>/<role>/shared/MEMORY.md
```

Treat the role index and shared index as routing tables.
Read linked files only when relevant to the current task.

## Path Rules

Persona memory paths are file-relative.

- A bare filename in `<role>/MEMORY.md` resolves inside `<role>/`.
- A `shared/<file>` link from `<role>/MEMORY.md` resolves through `<role>/shared`, which points at `../shared`.
- A bare filename in `shared/MEMORY.md` resolves inside `shared/`.
- `<!-- src: ... -->` annotations follow the same file-relative rule.

Do not invent paths under tool-native memory stores when the repo-backed path is available.

## Governance

Reading persona memory is always allowed.

Do not edit, commit, or push a memory repo unless the user explicitly asks for that action.
If editing is requested, respect the memory repo governance:

- A role session may edit its own `<role>/` directory and `shared/` when explicitly requested.
- If the project has a Memory Manager, the Memory Manager is the sole committer and pusher of the memory repo.
- Do not touch another role's directory from a role session unless the user explicitly asks and the change is mechanical or stewardship-oriented.

If the memory repo has unrelated dirty changes, leave them alone.

## Per-Tool Role of This Skill

- Claude Code: mid-session refresh (re-read the indices from disk when memory may have changed) and the escape hatch from unwired directories.
- Codex: the lazy-read complement to the SessionStart index injection, and the fallback when the `.codex/` hooks layer is not yet trusted.
- OpenCode: the lazy-read complement to the `instructions`-loaded index.

For a memory freshness check: fresh-read the role and shared indices, report only meaningful changes, and respond exactly `Memory check complete` when no meaningful changes are found.
```

- [ ] **Step 2: Verify frontmatter is standard-only and the algorithm matches the spec**

Run: `head -5 skills/load-persona-memory/SKILL.md`
Expected: exactly `name` and `description` fields.
Then diff the Discovery section against spec lines "Role resolution drops splice's hardcoded mappings..." - the 5 steps must match one-to-one.

- [ ] **Step 3: Commit**

```bash
git add skills/load-persona-memory/SKILL.md
git commit -m "claude-personas: generalized load-persona-memory skill (convention-walking, vendor-neutral)"
```

---

### Task 9: `examples/substrate/` embedded-topology templates

**Files:**
- Create: `examples/substrate/README.md`
- Create: `examples/substrate/.claude/settings.json`
- Create: `examples/substrate/.codex/hooks.json`
- Create: `examples/substrate/opencode.json`

**Interfaces:**
- Consumes: cerebrum's live adapter set (already verified by running - spec sub-project 1).
- Produces: copy-and-adapt files; symlinks are documented as commands in the README, NOT committed (a committed dangling symlink would trip OpenCode's snapshot bug and confuse copiers - record this deviation-from-spec-letter in the README itself).

- [ ] **Step 1: Write the four files**

`examples/substrate/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": [".agents/memory/MEMORY.md"]
}
```

`examples/substrate/.codex/hooks.json` (placeholder per spec):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'<ABSOLUTE-REPO-PATH>/.agents/hooks/inject-memory-index.sh'",
            "timeout": 10,
            "statusMessage": "Injecting memory index…"
          }
        ]
      }
    ]
  }
}
```

`examples/substrate/.claude/settings.json`:

```json
{
  "permissions": {
    "ask": [
      "Write(.agents/hooks/**)",
      "Edit(.agents/hooks/**)",
      "Write(.agents/skills/**)",
      "Edit(.agents/skills/**)"
    ]
  }
}
```

`examples/substrate/README.md`:

```markdown
# Embedded-topology substrate (copy-and-adapt)

This directory carries the adapter set for the EMBEDDED topology: memory lives inside the same repo under `.agents/memory/`, and three thin vendor adapters point at it.
It is the pattern proven on the cerebrum instance (see the per-vendor caveats doc: `../../docs/vendor-caveats.md`).

## Which topology am I?

Boundary test: does a decision recorded in repo A change what an agent does in repo B?

- No - single-repo project: use THIS embedded layout (`.agents/` in the repo).
- Yes - multi-repo endeavor, or multiple concurrent role sessions: use the role-clones topology (`scripts/init-clone.sh` and a separate memory repo) instead.

## Files here

- `opencode.json` - copy to the repo root as-is (OpenCode adapter).
- `.codex/hooks.json` - copy, then replace `<ABSOLUTE-REPO-PATH>` with this clone's absolute path.
  Absolute paths make the file per-clone; regeneration tooling is sub-project 3.
- `.claude/settings.json` - copy the `permissions.ask` stanza if you want write-prompts on executing artifacts.

## Symlinks to create (not committed here - create them in YOUR repo)

Committed dangling symlinks confuse copiers and trip OpenCode's snapshot bug, so create these by hand or with your instance's sync script:

```bash
ln -s ../.agents/memory .claude/memory
ln -s ../.agents/skills .claude/skills   # only if you keep skills in .agents/skills/
ln -s AGENTS.md CLAUDE.md                # Claude Code does not read AGENTS.md natively
```

Payload layout expected by the adapters:

```text
.agents/memory/MEMORY.md      # always-loaded index
.agents/memory/<topic>.md     # one fact per file
.agents/hooks/                # hook scripts called by the adapters (single copy)
```
```

- [ ] **Step 2: Verify JSON validity**

Run: `jq . examples/substrate/opencode.json examples/substrate/.codex/hooks.json examples/substrate/.claude/settings.json`
Expected: all three parse.

- [ ] **Step 3: Commit**

```bash
git add examples/substrate/
git commit -m "claude-personas: examples/substrate embedded-topology adapter templates"
```

---

### Task 10: Per-vendor caveats doc

**Files:**
- Create: `docs/vendor-caveats.md`

**Interfaces:**
- Consumes: the spec's Caveats section (verbatim content basis).
- Produces: the doc Task 12's live tests write their results into (its "Live-test results" table).

- [ ] **Step 1: Write the doc**

Create `docs/vendor-caveats.md`:

```markdown
# Per-vendor caveats

Dated, verified sharp edges of the three supported tools.
Re-verify anything volatile before relying on it; each line carries the date it was last checked.

## Claude Code

- Does NOT read `AGENTS.md` natively (docs explicit; symlink or `@` import required). (2026-07-03)
- Scans only `.claude/skills`, not `.agents/skills`. (2026-07-03)
- Auto-memory reads the EXTERNAL `~/.claude/projects/<slug>/memory` path, not the in-repo `.claude/memory` (latent v3.1 gap: `init-clone.sh` before this sub-project never created the external symlink, and existing instances rode v2-era leftovers). Fixed: `init-clone.sh` now creates or repairs it. Live test 4 below records whether current CC still needs it. (2026-07-03)
- `<slug>` derivation is undocumented: absolute physical path with `/` and `.` each replaced by `-`. Live test 4 re-verifies. (2026-07-03)
- Symlink-hostile setups (e.g. Windows without developer mode): use the documented `autoMemoryDirectory` setting (absolute paths only, any settings scope) instead of the external symlink. (2026-07-03)

## Codex

- Trust is TWO-layer: per-repo trust, then per-hook-definition review via `/hooks`, re-triggered whenever the generated `.codex/hooks.json` changes. Neither is scriptable. (2026-07-03)
- The app does not load global `~/.codex/AGENTS.md` (openai/codex#27705, open); the CLI does. (2026-07-03)
- `additionalContext` ceiling: a ~2.4k-token truncation was observed 2026-07-02 on the cerebrum instance, but matches neither current docs nor current source (hook path uncapped in main; a sibling context path caps at 1k tokens). The inject script self-bounds its payload with a `[TRUNCATED ...]` trailer regardless. Live test 2 below records the current behavior. (2026-07-03)
- Hook timeouts are in seconds. (2026-07-03)

## OpenCode

- Repo moved orgs: `sst/opencode` -> `anomalyco/opencode`. (2026-07-03)
- Snapshot/undo cannot cover files behind a symlink (anomalyco/opencode#31984, open; the trigger is exactly the `.claude/x -> .agents/x` pattern). Git covers recovery. (2026-07-03)
- No local config variant (`opencode.local.json` does not exist; anomalyco/opencode#17232 open) - the per-clone fallback file is plain `opencode.json`, untracked via `.git/info/exclude`. (2026-07-03)
- Glob-through-symlink for `instructions` entries is gated on `follow: false` upstream behavior - live test 1 below decides the default wiring. (2026-07-03)

## Live-test results

Four named tests from the design spec (`docs/superpowers/specs/2026-07-03-per-vendor-adapters-template-design.md`, Verification).
Run on a throwaway scratch instance; nothing touches any real project.

| # | Question | Result | Date | Consequence |
|---|---|---|---|---|
| 1 | OpenCode glob-through-symlink on a relative global `instructions` entry | pending | - | decides default wiring (global vs `--opencode-per-clone`) |
| 2 | Codex `additionalContext` ceiling | pending | - | replaces the stale ~2.4k figure |
| 3 | Codex per-hook re-trust flow | pending | - | documents real onboarding friction |
| 4 | CC fresh-clone auto-load with ONLY the in-repo `.claude/memory` symlink (no external hop) + slug derivation | pending | - | decides whether the external hop stays load-bearing |
```

- [ ] **Step 2: Commit**

```bash
git add docs/vendor-caveats.md
git commit -m "claude-personas: per-vendor caveats doc (dated; live-test results table pending)"
```

---

### Task 11: README section

**Files:**
- Modify: `README.md` (insert a new `## Multi-vendor wiring (Claude Code, Codex, OpenCode)` section between `## What init-clone.sh does (one-time per role)` and `## Windows`)

**Interfaces:**
- Consumes: everything Tasks 1-10 built (content per the spec's "README section" design subsection).
- Produces: user-facing docs; no code dependencies.

- [ ] **Step 1: Write the section**

Insert into `README.md`:

```markdown
## Multi-vendor wiring (Claude Code, Codex, OpenCode)

`init-clone.sh` wires each role clone for all three tools at once.

What it creates per clone (all untracked via `.git/info/exclude` - your project repo never needs a commit to host a wired clone):

- `.agents/memory -> ../../<memory-repo>/<role>` - the vendor-neutral mount and the single role signal.
- `.claude/memory -> .agents/memory` - the Claude Code hop, plus an external `~/.claude/projects/<slug>/memory` symlink that Claude Code's auto-memory loader actually reads.
- `.codex/hooks.json` - a generated SessionStart hook that injects the role + shared indices via the memory repo's `scripts/inject-role-index.sh`.

One-time steps per machine that the script cannot perform (it prints them):

- Codex: open the clone, accept repo trust, then run `/hooks` and approve the generated hook (re-approve whenever the file changes).
- OpenCode: add `".agents/memory/MEMORY.md"` to the `instructions` array in `~/.config/opencode/opencode.json` - one global entry serves every wired clone. If OpenCode cannot read through the symlink on your setup, re-run `init-clone.sh` with `--opencode-per-clone` (see `docs/vendor-caveats.md`).
- Skill install (all three tools): symlink the skill once into your user-level skill dirs:

  ```bash
  ln -s "$(pwd)/skills/load-persona-memory" ~/.agents/skills/load-persona-memory   # Codex + OpenCode
  ln -s "$(pwd)/skills/load-persona-memory" ~/.claude/skills/load-persona-memory   # Claude Code
  ```

Sharp edges per vendor (trust layers, symlink bugs, context ceilings) live in [docs/vendor-caveats.md](docs/vendor-caveats.md).
Embedded-topology projects (memory inside the same repo) should start from [examples/substrate/](examples/substrate/) instead of `init-clone.sh`.
```

- [ ] **Step 2: Check rendered links**

Run: `grep -n "vendor-caveats\|examples/substrate" README.md`
Expected: both relative links resolve to files that exist (`docs/vendor-caveats.md`, `examples/substrate/`).

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "claude-personas: README multi-vendor wiring section"
```

---

### Task 12: Live tests 1-4 (by running, on a throwaway)

These are interactive verification runs, not scripted tests - they need real Claude Code, Codex, and OpenCode sessions.
Results are recorded in `docs/vendor-caveats.md` (table from Task 10) and drive two possible code flips (steps 6-7).
Setup mirrors the spec Verification section: scratch project repo + scratch memory repo with two roles; nothing touches splice.

- [ ] **Step 1: Build the throwaway instance**

```bash
SCRATCH=~/dev/scratch-adapters-livetest
mkdir -p "$SCRATCH"
git init --bare "$SCRATCH/scratch-project.git"
tmp="$(mktemp -d)" && git clone "$SCRATCH/scratch-project.git" "$tmp/seed" \
  && ( cd "$tmp/seed" && echo "# scratch" > README.md && git add . && git commit -m init && git push origin HEAD )
# Memory repo: instantiate from THIS template checkout (copy scripts/ + role dirs).
mkdir -p "$SCRATCH/claude-personas-scratch"/{developer,pm,shared} "$SCRATCH/claude-personas-scratch/scripts"
printf "# Role index\n- canary: the developer index IS loaded (line dev-canary-7f3a)\n" > "$SCRATCH/claude-personas-scratch/developer/MEMORY.md"
printf "# Role index\n- canary: pm-canary-2b9c\n" > "$SCRATCH/claude-personas-scratch/pm/MEMORY.md"
printf "# Shared index\n- canary: shared-canary-4e1d\n" > "$SCRATCH/claude-personas-scratch/shared/MEMORY.md"
( cd "$SCRATCH/claude-personas-scratch/developer" && ln -s ../shared shared )
( cd "$SCRATCH/claude-personas-scratch/pm" && ln -s ../shared shared )
TEMPLATE="$(git -C /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas rev-parse --show-toplevel)"
cp "$TEMPLATE/scripts/init-clone.sh" "$TEMPLATE/scripts/inject-role-index.sh" "$SCRATCH/claude-personas-scratch/scripts/"
( cd "$SCRATCH/claude-personas-scratch" && git init && git add -A && git commit -m init )
( cd "$SCRATCH/claude-personas-scratch" && bash scripts/init-clone.sh developer --project-url "$SCRATCH/scratch-project.git" )
```

Then run the doctor-eye check: `ls -la "$SCRATCH/scratch-project/.agents" "$SCRATCH/scratch-project/.claude"` and `cat "$SCRATCH/scratch-project/.git/info/exclude"`.

- [ ] **Step 2: Live test 4 - CC external hop still load-bearing? (+ slug derivation)**

1. Record the created external symlink: `ls -la ~/.claude/projects/ | grep scratch` - the entry name IS the observed slug; compare against `echo "$(cd $SCRATCH/scratch-project && pwd -P)" | tr '/.' '-'`. Record match/mismatch.
2. Remove the external hop: `rm ~/.claude/projects/<slug>/memory`.
3. In the clone, run: `claude -p "What is the exact canary line in your auto-loaded memory index? Answer with the line only." --add-dir "$SCRATCH/claude-personas-scratch"`.
4. If the answer contains `dev-canary-7f3a`, current CC loads the in-repo `.claude/memory` natively → external hop NOT load-bearing.
5. Recreate the hop (re-run `init-clone.sh developer --force ...`) and repeat the probe - it must load in this configuration (sanity baseline).
6. Record both results + date in the Task 10 table.

- [ ] **Step 3: Live test 1 - OpenCode glob-through-symlink**

1. Add `".agents/memory/MEMORY.md"` to `instructions` in `~/.config/opencode/opencode.json` (back up the file first; restore after the test).
2. In the clone: `opencode run "What is the exact canary line in your loaded instructions? Answer with the line only."`.
3. `dev-canary-7f3a` present → global wiring works through the symlink → default stays.
4. Absent → run `init-clone.sh developer --force --opencode-per-clone ...` and repeat; record which variant loaded.

- [ ] **Step 4: Live test 2 - Codex additionalContext ceiling**

1. Append filler lines to the scratch `developer/MEMORY.md` until it exceeds 15k characters, with a unique last line `tail-canary-9d4f`.
2. In the clone (after the one-time trust steps - record every prompt Codex shows as live test 3's result): `codex --skip-git-repo-check "What is the LAST line of the injected role memory index? Answer with the line only."`.
3. If `tail-canary-9d4f` is absent but the `[TRUNCATED ...]` trailer is present, the script's own 9000-char bound cut it (expected).
4. To measure Codex's OWN ceiling, temporarily raise `cap=9000` to `cap=60000` in the scratch copy of `inject-role-index.sh`, re-run, and probe for the tail + trailer again; record the observed ceiling (or "uncapped").
5. Record in the table; note the cerebrum AGENTS.md ~2.4k caveat needs a follow-up update in the cerebrum repo (separate PR there - do NOT edit cerebrum in this task).

- [ ] **Step 5: Live test 3 - Codex per-hook re-trust flow**

Already exercised in Step 4's setup: record the exact sequence (repo trust prompt, `/hooks` review, what re-triggers it after `--force` regeneration) in the table and, if the friction differs from the caveats doc's description, correct the doc.

- [ ] **Step 6: Flip A (only if live test 4 shows the hop is NOT load-bearing)**

In `wire_cc_external_hop`, keep repair/refusal behavior but stop creating the hop on fresh clones; instead print a note for older CC versions.
Update the Task 3 tests accordingly (creation assertions become absence assertions plus note-printed assertion), the caveats doc, and the README section.

- [ ] **Step 7: Flip B (only if live test 1 shows glob-through-symlink FAILS)**

Make `--opencode-per-clone` the default (write the per-clone file always) and add `--opencode-global` to suppress it; swap the printed note's wording; update Task 5's tests, the caveats doc, and the README section.

- [ ] **Step 8: Record, clean up, commit**

Fill all four rows of the results table in `docs/vendor-caveats.md` (result + date), restore `~/.config/opencode/opencode.json`, remove the scratch external-hop symlink, and delete `$SCRATCH`.

```bash
git add docs/vendor-caveats.md scripts/ README.md
git commit -m "claude-personas: record live-test results 1-4 (+ default flips if any)"
```

---

### Task 13: Final verification + PR

- [ ] **Step 1: Full suite + budget check**

Run: `bash scripts/tests/run_all.sh && python3 scripts/memory_cliff.py`
Expected: all tests pass; size budgets unchanged (no role index was touched).

- [ ] **Step 2: Spec coverage sweep**

Walk the spec's five Scope deliverables and each `### init-clone.sh changes` bullet; confirm a commit implements each.
Confirm both spec review-fix additions are honored: the enumeration rule (skill Discovery step 3) and the slug note (external hop comment + live test 4).

- [ ] **Step 3: Push and open the PR**

```bash
git push origin 32-adapters-implementation
```

Then open the PR with `Closes #32` in the body (the branch is dev-linked; the closing keyword makes the auto-close unambiguous), summarizing: two-hop mount, external CC hop (v3.1 gap fix), Codex generation, OpenCode default + fallback, generalized skill, examples/substrate, caveats doc with live-test results.
Request the bot review with exactly `gh pr comment <N> --body "@claude review"`, then human review; squash-merge is the merge gate.

## Self-Review Notes (run after writing, per the skill)

- Spec coverage: deliverable 1 → Tasks 2-6; deliverable 2 → Task 8; deliverable 3 → Task 9; deliverable 4 → Tasks 10-11; deliverable 5 → Task 12; init-clone bullets each have a task; list-roles two-hop awareness (not in spec's deliverable list but forced by the layout change) → Task 2, pinned by Task 7.
- Known deviation from spec letter: `examples/substrate/` documents symlinks as commands instead of committing dangling symlinks (rationale in Task 9; surface it in the PR body for review).
- Type/name consistency: `add_exclude`, `vendor_warn`, `VENDOR_WARNINGS`, `wire_cc_external_hop`, `wire_codex_adapter`, `wire_opencode_adapter`, `OPENCODE_PER_CLONE`, `CODEX_WIRED`, `OPENCODE_GLOBAL_NOTE` are defined in Task 2/3/4/5 and referenced consistently; `compute_hash` comes from `test_helpers.sh`.
- Exit-code contract: 0 clean, 1 fatal (core mount, rolls back fresh clones), 2 vendor warnings - pinned by tests in Tasks 3-5.
