# Memory-Under-Dotclaude Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Relocate the role-memory symlink from `<clone>/memory` to `<clone>/.claude/memory` in claude-personas v3.1.0, with `init-clone.sh --force` handling fresh installs *and* v3.0 → v3.1 in-place migration. Then retrofit the 3 splice role clones.

**Architecture:** Single-script change (`init-clone.sh`) plus docs/template path updates. The `--force` path on the script is extended to detect a legacy `memory/` symlink at the project-clone root, back it up, remove the stale `/memory/` line from `.gitignore`, and re-wire the new `.claude/memory/` layout. Memory is loaded by Claude Code via CLAUDE.md import (no hardcoded path in the harness), so the change is purely organizational.

**Tech Stack:** Bash (the script + its test harness), Markdown (docs), no application runtime.

**Spec:** [2026-05-17-memory-under-dotclaude-design.md](../specs/2026-05-17-memory-under-dotclaude-design.md)

**Branch:** `v3.1-dev` (already created from `main` at `3c1e37d`; spec committed at `a8e94f6`)

---

## File Structure

**claude-personas repo (Phase A — v3.1.0 PR):**

| File | Responsibility | Action |
| --- | --- | --- |
| `scripts/init-clone.sh` | Creates the role clone + memory symlink + .gitignore entry. The single source of truth for the new layout. | Modify |
| `scripts/tests/test_init_clone.sh` | Asserts script behavior. All existing memory-path assertions need updating; one new test case added for the v3.0 → v3.1 migration via `--force`. | Modify |
| `developer/MEMORY.md`, `pm/MEMORY.md`, `scientist/MEMORY.md`, `designer/MEMORY.md` | Role boilerplate. Line 4 in each references the symlink. | Modify |
| `README.md` | Public-facing layout + walkthrough. Multiple path references. | Modify |
| `CONVENTIONS.md` | Architectural doc. Three path references. | Modify |
| `MIGRATION.md` | Update v2→v3 path references AND append new "v3.0 → v3.1" section. | Modify |
| `CHANGELOG.md` | Append v3.1.0 entry at top; leave v3.0.0 entry intact (historical). | Modify |

**claude-personas-splice-neoepitope-pipeline repo + splice role clones (Phase B — post-merge):**

| File | Responsibility | Action |
| --- | --- | --- |
| `claude-personas-splice-neoepitope-pipeline/scripts/init-clone.sh` | Splice memory repo's copy of the script. Sync from claude-personas v3.1.0. | Sync (copy) |
| splice role clones × 3 (`splice-neoepitope-pipeline`, `splice-neoepitope-pipeline-pm`, `splice-neoepitope-pipeline-scientist`) | Each gets its symlink re-wired and `.gitignore` updated via `init-clone.sh --force`. | Migrate via script |

---

## Phase A: claude-personas v3.1.0

### Task 1: Update existing test assertions for new path

**Files:**
- Modify: `scripts/tests/test_init_clone.sh` (all `memory/` references — see lines 22, 23, 25-30, 108, 125, 147-148, 154-156, 215-223, 264, 291)

- [ ] **Step 1: Make all symlink-path assertions expect `.claude/memory`**

In `scripts/tests/test_init_clone.sh`, do a `replace_all` of each pattern:

For symlink path assertions, replace every occurrence of `$tmp/myapp/memory` with `$tmp/myapp/.claude/memory`, and the equivalent for `$tmp5`, `$tmp6`, `$tmp7`, `$tmp10`, `$tmp12`, `$tmp13`, plus the custom-target case (`$custom/memory` → `$custom/.claude/memory`).

For symlink target strings, replace every `"../claude-personas-myapp/<role>"` with `"../../claude-personas-myapp/<role>"` (the extra `../` because `.claude/memory` is one level deeper).

For the `.gitignore` regex on lines 26, 215, 221, replace:
```
^memory/$\|^memory$\|^/memory$\|^/memory/$
```
with:
```
^\.claude/memory/$\|^/\.claude/memory/$
```

For the backup-detection on line 155, replace `-name "memory.backup-*"` with `-name "memory.backup-*"` *kept at the clone root* — the backup convention is unchanged (the script backs up to `$TARGET/memory.backup-*` for the legacy case, or `$TARGET/.claude/memory.backup-*` for the new case; pick `$TARGET/.claude/memory.backup-*` since Task 3 will produce that). Update line 155 to:
```bash
backup_count="$(find "$tmp7/myapp/.claude" -maxdepth 1 -name "memory.backup-*" | wc -l | tr -d ' ')"
```

For the negative assertion on line 291 (`memory/ NOT created in refused dir`), replace with:
```bash
assert_not_exists "$tmp13/myapp/.claude/memory" ".claude/memory NOT created in refused dir"
```

For the "memory broken before re-force" setup on lines 147-148, update to the new location:
```bash
rm "$tmp7/myapp/.claude/memory"
ln -s /nonexistent "$tmp7/myapp/.claude/memory"
```

- [ ] **Step 2: Run tests to verify they fail against current script**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas
bash scripts/tests/run_all.sh
```

Expected: multiple `FAIL` lines from `test_init_clone.sh` (assertions expect `.claude/memory` but script still writes `memory`). `test_list_roles.sh` should still pass — it doesn't touch memory paths.

- [ ] **Step 3: Commit the failing tests**

```bash
git add scripts/tests/test_init_clone.sh
git commit -m "$(cat <<'EOF'
test: assert .claude/memory layout (red)

Update test_init_clone.sh assertions to expect the v3.1 layout
(<clone>/.claude/memory). All migrated assertions now fail against
the current init-clone.sh; the script will be updated in a follow-up
commit to make them pass.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Add v3.0 → v3.1 migration test case

**Files:**
- Modify: `scripts/tests/test_init_clone.sh` (append new test case before the `print_summary` call at line 295)

- [ ] **Step 1: Add the migration test case**

Insert this block in `scripts/tests/test_init_clone.sh` immediately before the `print_summary` line at the end of the file:

```bash
# --- v3.0 -> v3.1 migration via --force ---
echo "=== test_init_clone v3.0 -> v3.1 migration ==="
tmp14="$(mktemp -d)"
make_clone_test_fixture "$tmp14"
mv "$tmp14/memory-repo" "$tmp14/claude-personas-myapp"

# Arrange: clone the project, then plant a LEGACY v3.0 layout by hand
# (root-level memory/ symlink + /memory/ gitignore line)
git clone --quiet "$tmp14/project-repo.git" "$tmp14/myapp"
ln -s "../claude-personas-myapp/developer" "$tmp14/myapp/memory"
printf "\n# legacy v3.0 marker\n/memory/\n" >> "$tmp14/myapp/.gitignore"

# Act: run --force, which should detect the legacy layout and migrate
( cd "$tmp14/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --force --project-url "$tmp14/project-repo.git" )

# Assert: new layout exists
assert_symlink "$tmp14/myapp/.claude/memory" "../../claude-personas-myapp/developer" "new .claude/memory symlink created"
assert_exists "$tmp14/myapp/.claude/memory/MEMORY.md" "MEMORY.md resolves through new symlink"

# Assert: legacy root symlink removed
assert_not_exists "$tmp14/myapp/memory" "legacy root memory/ symlink removed"

# Assert: legacy /memory/ line removed from .gitignore, new /.claude/memory/ line present
if grep -qE '^/?memory/?$' "$tmp14/myapp/.gitignore"; then
  echo "  FAIL: legacy /memory/ line still in .gitignore"
  exit 1
else
  echo "  PASS: legacy /memory/ line removed from .gitignore"
fi
if grep -qE '^/?\.claude/memory/?$' "$tmp14/myapp/.gitignore"; then
  echo "  PASS: /.claude/memory/ line present in .gitignore"
else
  echo "  FAIL: /.claude/memory/ line not in .gitignore"
  exit 1
fi

cleanup_clone_test_fixture "$tmp14"
```

- [ ] **Step 2: Run tests to verify the new test also fails**

```bash
bash scripts/tests/run_all.sh
```

Expected: the new "v3.0 -> v3.1 migration" test fails (script doesn't yet know about the legacy layout). Existing red tests from Task 1 still fail.

- [ ] **Step 3: Commit the new test**

```bash
git add scripts/tests/test_init_clone.sh
git commit -m "$(cat <<'EOF'
test: add v3.0 -> v3.1 migration case (red)

Plants a legacy v3.0 layout (root memory/ symlink + /memory/
gitignore) in a fresh clone, runs init-clone.sh --force, asserts
the new .claude/memory layout is in place and the legacy artifacts
are gone. Test fails until init-clone.sh learns the migration path.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Update `init-clone.sh` to write the new layout + migrate

**Files:**
- Modify: `scripts/init-clone.sh` (lines 2-3 header comment, 138-160 symlink+gitignore block, 170 final message)

- [ ] **Step 1: Update header comment (lines 2-3)**

Replace:
```bash
# init-clone.sh — create an independent project-repo clone for a role and wire
# the memory/ symlink to the sibling claude-personas memory repo.
```
with:
```bash
# init-clone.sh — create an independent project-repo clone for a role and wire
# the .claude/memory/ symlink to the sibling claude-personas memory repo.
```

- [ ] **Step 2: Update symlink wiring block (lines 138-160)**

Replace the existing block (from `# Wire memory symlink (back up existing first if --force and broken)` through the `printf ... >> "$GITIGNORE"` block) with:

```bash
# Wire memory symlink under .claude/. On --force, also clean up any legacy
# root-level memory/ symlink and stale /memory/ .gitignore line from v3.0.
mkdir -p "$TARGET/.claude"
MEMORY_LINK="$TARGET/.claude/memory"

# Migrate v3.0 layout: legacy root symlink → back up under .claude/
LEGACY_LINK="$TARGET/memory"
if [[ "$FORCE" -eq 1 && ( -L "$LEGACY_LINK" || -e "$LEGACY_LINK" ) ]]; then
  LEGACY_BACKUP="$TARGET/.claude/memory.legacy-backup-$(date +%Y%m%d-%H%M%S)"
  mv "$LEGACY_LINK" "$LEGACY_BACKUP"
  echo "✓ Migrated legacy root memory/ → $LEGACY_BACKUP"
fi

if [[ -e "$MEMORY_LINK" || -L "$MEMORY_LINK" ]]; then
  if [[ "$FORCE" -eq 1 ]]; then
    BACKUP="$TARGET/.claude/memory.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$MEMORY_LINK" "$BACKUP"
    echo "✓ Backed up existing .claude/memory → $BACKUP"
  else
    echo "Error: $MEMORY_LINK already exists. Use --force to back up." >&2
    exit 1
  fi
fi

ln -s "../../$MEMORY_REPO_NAME/$ROLE" "$MEMORY_LINK"
echo "✓ Symlinked $MEMORY_LINK → ../../$MEMORY_REPO_NAME/$ROLE"

# Update .gitignore: add /.claude/memory/, remove legacy /memory/ if present
GITIGNORE="$TARGET/.gitignore"
touch "$GITIGNORE"

# Remove legacy /memory/ line on --force (v3.0 → v3.1 migration)
if [[ "$FORCE" -eq 1 ]] && grep -qE '^/?memory/?$' "$GITIGNORE"; then
  # Portable in-place edit: write to temp, swap
  grep -vE '^/?memory/?$' "$GITIGNORE" > "$GITIGNORE.tmp" && mv "$GITIGNORE.tmp" "$GITIGNORE"
  echo "✓ Removed legacy /memory/ from $GITIGNORE"
fi

if ! grep -qE '^/?\.claude/memory/?$' "$GITIGNORE"; then
  printf "\n# claude-personas role-memory symlink\n/.claude/memory/\n" >> "$GITIGNORE"
  echo "✓ Added /.claude/memory/ to $GITIGNORE"
fi
```

- [ ] **Step 3: Update final message (line 170)**

Replace:
```bash
echo "Done. Open $TARGET in Claude Code → memory/MEMORY.md auto-loads."
```
with:
```bash
echo "Done. Open $TARGET in Claude Code → .claude/memory/MEMORY.md auto-loads."
```

- [ ] **Step 4: Run tests to verify all green**

```bash
bash scripts/tests/run_all.sh
```

Expected: all tests pass, including the new "v3.0 -> v3.1 migration" case from Task 2 and all the updated assertions from Task 1.

- [ ] **Step 5: Commit**

```bash
git add scripts/init-clone.sh
git commit -m "$(cat <<'EOF'
feat: write memory symlink to .claude/memory; --force migrates v3.0 layout

init-clone.sh now wires the role-memory symlink at
<clone>/.claude/memory (one level deeper than v3.0's root <clone>/memory).
On --force, it also detects a legacy root memory/ symlink and a stale
/memory/ line in .gitignore, backs them up, and writes the new layout —
so the same command serves fresh v3.1 installs and v3.0 → v3.1 migrations.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Update role MEMORY.md boilerplate

**Files:**
- Modify: `developer/MEMORY.md`, `pm/MEMORY.md`, `scientist/MEMORY.md`, `designer/MEMORY.md` — line 4 in each

- [ ] **Step 1: Update line 4 in each role's MEMORY.md**

The current line in each role MEMORY.md is:
```
  Usage: this folder is loaded by Claude Code via the `memory/` symlink in your
```

Replace it in each file with:
```
  Usage: this folder is loaded by Claude Code via the `.claude/memory/` symlink in your
```

Use the Edit tool with `replace_all: false` against each file individually (the line is unique in each file).

- [ ] **Step 2: Verify with grep**

```bash
grep -n 'memory/' developer/MEMORY.md pm/MEMORY.md scientist/MEMORY.md designer/MEMORY.md
```

Expected: every remaining match shows `.claude/memory/` (or `memory/MEMORY.md` *inside* the new boilerplate, which is fine). No bare `` `memory/` `` references should remain on line 4.

- [ ] **Step 3: Commit**

```bash
git add developer/MEMORY.md pm/MEMORY.md scientist/MEMORY.md designer/MEMORY.md
git commit -m "$(cat <<'EOF'
docs: role MEMORY.md boilerplate reflects .claude/memory layout

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Update README.md path references

**Files:**
- Modify: `README.md` (lines 23, 47, 81, 103, 104, 128 — anywhere `memory/` is referenced as a path in the user-facing walkthrough)

- [ ] **Step 1: Update each reference**

Use `Edit` (with unique surrounding context per call, since several occurrences exist) to update:

- Line 23 (`Each project clone has a \`memory/\` symlink...`): change to `Each project clone has a \`.claude/memory/\` symlink...`
- Line 47 (`role's MEMORY.md auto-loads via \`memory/MEMORY.md\``): change to `role's MEMORY.md auto-loads via \`.claude/memory/MEMORY.md\``
- Line 81 (the long sentence with `my-app-pm/memory/MEMORY.md` and `memory/shared/MEMORY.md`): change both occurrences to `my-app-pm/.claude/memory/MEMORY.md` and `.claude/memory/shared/MEMORY.md`
- Line 103 (`Creates the \`memory/\` symlink...`): change to `Creates the \`.claude/memory/\` symlink...`
- Line 104 (`Adds \`memory/\` to the clone's \`.gitignore\``): change to `Adds \`.claude/memory/\` to the clone's \`.gitignore\``
- Line 128 (`The \`memory/\` symlinks become broken... \`ln -sf ../<new-path>/<role> <clone>/memory\``): change the prose path to `.claude/memory/` and the example `ln -sf` command to `ln -sf ../../<new-path>/<role> <clone>/.claude/memory` (note the extra `../`)

- [ ] **Step 2: Verify**

```bash
grep -nE '(^|[^a-zA-Z.])memory/' README.md
```

Expected: no remaining bare-`memory/` references. Any matches should be `.claude/memory/`, `memory/MEMORY.md` (with `.claude/` prefix), `<memory-repo>/`, or similar non-symlink references that are correct as-is.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
docs: README walkthrough and layout reflect .claude/memory

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Update CONVENTIONS.md path references

**Files:**
- Modify: `CONVENTIONS.md` (lines 9, 28, 82)

- [ ] **Step 1: Update each reference**

- Line 9: `single \`memory/\` symlink pointing into` → `single \`.claude/memory/\` symlink pointing into`
- Line 28: `The \`memory/\` symlink in that clone resolves` → `The \`.claude/memory/\` symlink in that clone resolves`
- Line 82: `The \`memory/\` symlink in each project clone (\`<project-clone>/memory -> ../claude-personas-<app>/<role>\`)` → `The \`.claude/memory/\` symlink in each project clone (\`<project-clone>/.claude/memory -> ../../claude-personas-<app>/<role>\`)`

- [ ] **Step 2: Verify**

```bash
grep -nE '(^|[^a-zA-Z.])memory/' CONVENTIONS.md
```

Expected: no remaining bare-`memory/` references in path positions.

- [ ] **Step 3: Commit**

```bash
git add CONVENTIONS.md
git commit -m "$(cat <<'EOF'
docs: CONVENTIONS reflects .claude/memory layout

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Update MIGRATION.md + append v3.0 → v3.1 section

**Files:**
- Modify: `MIGRATION.md` (lines 3, 69, 80, 91; append new section at end)

- [ ] **Step 1: Update existing v2→v3 references**

- Line 3: `independent project-repo clones + a single \`memory/\` symlink per clone` → `independent project-repo clones + a single \`.claude/memory/\` symlink per clone`
- Line 69: `\`init-clone.sh\` adds \`memory/\` to each clone's \`.gitignore\`` → `\`init-clone.sh\` adds \`.claude/memory/\` to each clone's \`.gitignore\``
- Line 80: `Each with a \`memory/\` symlink into the memory repo` → `Each with a \`.claude/memory/\` symlink into the memory repo`
- Line 91: `\`memory/shared/MEMORY.md\` resolves` → `\`.claude/memory/shared/MEMORY.md\` resolves`

- [ ] **Step 2: Append new v3.0 → v3.1 section**

Append to the bottom of `MIGRATION.md`:

```markdown

## v3.0 → v3.1

v3.1 moves the role-memory symlink from `<clone>/memory` to `<clone>/.claude/memory` for consistency with Claude Code's own `.claude/` namespace. The memory content itself (in your sister `claude-personas-<app>/` repo) is unchanged.

For each role clone (run from inside your `claude-personas-<app>/` memory repo):

```bash
scripts/init-clone.sh --force <role>
```

`--force` detects the legacy v3.0 layout, backs up the old root-level `memory/` symlink to `<clone>/.claude/memory.legacy-backup-<timestamp>`, removes the stale `/memory/` line from the clone's `.gitignore`, and writes the new `.claude/memory/` symlink + `/.claude/memory/` gitignore entry.

Verification:

- `ls -l <clone>/.claude/memory` shows a symlink pointing to `../../claude-personas-<app>/<role>`.
- `cat <clone>/.gitignore | grep memory` shows only `/.claude/memory/` (no bare `/memory/`).
- Restart Claude Code in the clone; the next session-start memory load should resolve `.claude/memory/MEMORY.md`.

After all clones are migrated, you can delete the `.claude/memory.legacy-backup-*` directories.
```

- [ ] **Step 3: Verify**

```bash
grep -nE '(^|[^a-zA-Z.])memory/' MIGRATION.md
```

Expected: remaining matches are either inside the new v3.0→v3.1 section (intentional `<clone>/memory` reference to describe the legacy layout) or within the v1/v2 historical context. No bare `memory/` symlink references should remain as the *current* recommended layout.

- [ ] **Step 4: Commit**

```bash
git add MIGRATION.md
git commit -m "$(cat <<'EOF'
docs: MIGRATION covers v3.0 -> v3.1 path move + --force migration

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Add CHANGELOG v3.1.0 entry

**Files:**
- Modify: `CHANGELOG.md` (insert new entry at top; leave v3.0.0 entry intact)

- [ ] **Step 1: Read current CHANGELOG to find the v3.0.0 header**

```bash
head -20 CHANGELOG.md
```

This reveals the heading format used for v3.0.0 (e.g. `## v3.0.0` or `## [3.0.0]`). Match that format for the v3.1.0 entry.

- [ ] **Step 2: Insert v3.1.0 entry immediately above the v3.0.0 entry**

Using `Edit` against the v3.0.0 heading as the unique anchor, prepend a new v3.1.0 section. Sample content (adjust heading format to match existing style):

```markdown
## v3.1.0

### Changed (breaking)

- **Role-memory symlink moves from `<clone>/memory` to `<clone>/.claude/memory`** for consistency with Claude Code's own `.claude/` namespace.
- `.gitignore` entry written by `init-clone.sh` is now `/.claude/memory/` instead of `/memory/`.

### Migration

- For each existing v3.0 role clone, run `scripts/init-clone.sh --force <role>` from inside the sister `claude-personas-<app>/` memory repo. The script detects the legacy layout, backs up the old root symlink to `<clone>/.claude/memory.legacy-backup-<timestamp>`, removes the stale `/memory/` line from `.gitignore`, and writes the new layout. See [MIGRATION.md](MIGRATION.md#v30--v31) for details.

```

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs: CHANGELOG entry for v3.1.0 path move

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Full verification

- [ ] **Step 1: Run the full test suite**

```bash
bash scripts/tests/run_all.sh
```

Expected: all tests pass, no failures.

- [ ] **Step 2: Sanity-check the script's help output**

```bash
bash scripts/init-clone.sh --help
```

Expected: usage prints cleanly; no syntax errors; no references to legacy `memory/` in the output.

- [ ] **Step 3: Grep for any stragglers**

```bash
grep -RnE '(^|[^a-zA-Z.])memory/' --include='*.md' --include='*.sh' \
  --exclude-dir=.git --exclude-dir=docs/superpowers .
```

Expected: any remaining matches are inside legitimate contexts (legacy-mention in CHANGELOG/MIGRATION, or `<memory-repo>/...` paths inside the sister repo description). No bare `memory/` references as the recommended current layout. If anything looks suspect, fix it inline and commit before pushing.

---

### Task 10: Push branch + open PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin v3.1-dev
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create --base main --head v3.1-dev --title "v3.1.0: move role-memory symlink under .claude/" --body "$(cat <<'EOF'
## Summary

- Relocates the role-memory symlink from `<clone>/memory` to `<clone>/.claude/memory` for consistency with Claude Code's own `.claude/` namespace
- `init-clone.sh --force` detects v3.0 layout and migrates in place (backs up legacy symlink, swaps `.gitignore` entry)
- Docs and role boilerplate updated; new test case covers the migration path

Spec: `docs/superpowers/specs/2026-05-17-memory-under-dotclaude-design.md`
Plan: `docs/superpowers/plans/2026-05-17-memory-under-dotclaude.md`

## Test plan

- [x] `bash scripts/tests/run_all.sh` — all green, including new v3.0 → v3.1 migration case
- [ ] Manual verification on a fresh `init-clone.sh <role>` invocation
- [ ] Manual verification on `init-clone.sh --force <role>` against a planted v3.0-layout clone

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Report the PR URL once created.

---

## Phase B: Splice retrofit (after v3.1.0 PR merges)

> Run only after Phase A's PR is merged to `main` and v3.1.0 is tagged.

### Task 11: Sync updated `init-clone.sh` into the splice memory repo

**Files:**
- Copy: `claude-personas/scripts/init-clone.sh` → `claude-personas-splice-neoepitope-pipeline/scripts/init-clone.sh`

- [ ] **Step 1: Copy the updated script**

```bash
cp /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas/scripts/init-clone.sh \
   /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline/scripts/init-clone.sh
```

- [ ] **Step 2: Verify the copy**

```bash
diff /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas/scripts/init-clone.sh \
     /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline/scripts/init-clone.sh
```

Expected: no diff output.

- [ ] **Step 3: Commit + push in the splice memory repo**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline
git add scripts/init-clone.sh
git commit -m "$(cat <<'EOF'
chore: sync init-clone.sh from claude-personas v3.1.0

Brings the .claude/memory layout + --force migration logic into the
splice memory repo so the splice role clones can be retrofitted.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push
```

---

### Task 12: Migrate each splice role clone via `--force`

**Files:**
- Modify (via script): `splice-neoepitope-pipeline/.claude/memory` (developer role, no-suffix slot), `splice-neoepitope-pipeline-pm/.claude/memory`, `splice-neoepitope-pipeline-scientist/.claude/memory`, plus each clone's `.gitignore`

- [ ] **Step 1: Confirm pre-state**

```bash
for clone in \
  /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline \
  /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline-pm \
  /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline-scientist; do
  echo "== $clone =="
  ls -l "$clone/memory" 2>/dev/null || echo "  (no root memory/)"
  grep -nE '^/?memory/?$' "$clone/.gitignore" 2>/dev/null || echo "  (no /memory/ in .gitignore)"
done
```

Expected: each clone has a root `memory/` symlink and a `/memory/` line in `.gitignore` (the v3.0 layout). If any clone is already on `.claude/memory/`, skip it in the next step.

- [ ] **Step 2: Run `--force` for each role from the splice memory repo**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/claude-personas-splice-neoepitope-pipeline
scripts/init-clone.sh --force developer
scripts/init-clone.sh --force pm
scripts/init-clone.sh --force scientist
```

Expected: each invocation prints `✓ Migrated legacy root memory/ → ...`, `✓ Symlinked .../.claude/memory → ../../claude-personas-splice-neoepitope-pipeline/<role>`, `✓ Removed legacy /memory/ from .gitignore`, `✓ Added /.claude/memory/ to .gitignore`.

- [ ] **Step 3: Verify post-state**

```bash
for clone in \
  /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline \
  /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline-pm \
  /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline-scientist; do
  echo "== $clone =="
  ls -l "$clone/.claude/memory"
  ls "$clone/.claude/memory/MEMORY.md" >/dev/null && echo "  MEMORY.md resolves"
  grep -nE '^/?(\.claude/)?memory/?$' "$clone/.gitignore"
done
```

Expected: each clone shows `.claude/memory → ../../claude-personas-splice-neoepitope-pipeline/<role>`, `MEMORY.md resolves` for each, and `.gitignore` contains only `/.claude/memory/` (no bare `/memory/`).

- [ ] **Step 4: Restart Claude Code in each role clone**

Manual step (user action): close and reopen each clone in Claude Code; confirm session-start memory load succeeds against `.claude/memory/MEMORY.md`.

---

### Task 13: Commit + push the `.gitignore` change in one clone; pull in the others

> Per [feedback_one_commit_per_clone_group](../../../../cerebrum/memory/feedback_one_commit_per_clone_group.md): the 3 splice role clones share the same remote, so the identical `.gitignore` diff is committed once and pulled into the others.

**Files:**
- Modify: `<chosen-clone>/.gitignore` (commit + push)
- Sync: the other two clones via `git pull`

- [ ] **Step 1: Pick a clone, commit + push**

```bash
cd /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline
git add .gitignore
git commit -m "$(cat <<'EOF'
chore: move role-memory gitignore entry to /.claude/memory/

Reflects claude-personas v3.1.0 layout. Symlink itself is unchanged
in tracked content (the symlink is .gitignored) — this is just the
gitignore entry update.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
git push
```

- [ ] **Step 2: Pull into the other two clones**

```bash
for clone in \
  /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline-pm \
  /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline-scientist; do
  echo "== $clone =="
  ( cd "$clone" && git pull --ff-only )
done
```

Expected: each pull either fast-forwards (if the branch tracks `main`) or reports `Already up to date.` for clones on a feature branch — those clones can rebase/merge `main` at their own cadence; the local `.gitignore` is already correct on disk because Task 12 wrote it directly.

> If a clone is on a feature branch and `git pull --ff-only` errors, that's fine — leave it. The on-disk `.gitignore` was already updated correctly by `init-clone.sh --force` in Task 12. The branch will pick up the committed version when it next merges/rebases `main`.

- [ ] **Step 3: Final sanity check**

```bash
for clone in \
  /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline \
  /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline-pm \
  /Users/jin-holee/dev/GitHub/Jin-HoMLee/splice-neoepitope-pipeline-scientist; do
  echo "== $clone =="
  git -C "$clone" status -s -b
done
```

Expected: clean or only role-clone-specific working changes, no `.gitignore` shown as unstaged.

---

## Self-review notes

- **Spec coverage:** Every spec section maps to at least one task (path change → 3, script changes → 3, docs → 4-8, splice retrofit → 11-13, versioning → 8, migration mechanic → 2/3/7, tests → 1/2/9).
- **Placeholder scan:** No "TBD"/"add appropriate"/"similar to Task N" anywhere. Every code block contains the actual content.
- **Type consistency:** `MEMORY_LINK`, `LEGACY_LINK`, `LEGACY_BACKUP`, `BACKUP` variable names match across the Task 3 script block and the Task 2 test assertions. The `.claude/memory.legacy-backup-<timestamp>` filename used in the MIGRATION.md addition (Task 7) matches the actual filename written by the script in Task 3.
- **Out-of-band risks called out:** Task 13 Step 2 explicitly handles the case where a splice clone sits on a feature branch and can't fast-forward `main`.
