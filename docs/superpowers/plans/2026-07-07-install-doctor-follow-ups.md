# Install/Doctor Follow-Ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the PR #59 installer/doctor follow-ups tracked in issue #60.

**Architecture:** Keep `framework/tools/install.sh` as the only payload install/sync engine and `framework/tools/doctor.sh` as the wiring integrity checker.
Strengthen the shell scripts in place and pin each behavior with the existing Bash harness.
Do not introduce a new parser or dependency.

**Tech Stack:** Bash 3.2-compatible shell scripts, git CLI, gh CLI for workflow, jq only where existing tests already require it.

## Global Constraints

- Preserve Bash 3.2 compatibility: no associative arrays and no modern Bash-only conveniences.
- Follow the existing harness style in `framework/tools/tests/test_helpers.sh`.
- Write failing regression tests first and watch them fail before production edits.
- Do not manually edit `CHANGELOG.md`.
- Do not use em dash in new prose.
- Keep framework sync/install ownership limited to `framework/FILES`, `.agents/framework-receipt`, and manifest framework keys.

---

### Task 1: Installer Argument Validation And `--into` Missing Source

**Files:**
- Modify: `framework/tools/tests/test_install.sh`
- Modify: `framework/tools/install.sh`

**Interfaces:**
- Consumes: existing `install.sh --into <target>` and `install.sh --sync` CLI.
- Produces: fatal exit 2 for invalid flag combinations and missing FILES source entries.

- [ ] **Step 1: Write failing tests**

Add cases to `test_install.sh`:

```bash
echo "=== test_install: --into rejects sync-only flags ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" --prune 2>&1)"
assert_equal "2" "$?" "--into --prune exits 2"
assert_contains "$out" "--prune is only valid with --sync" "--into --prune explains the invalid combination"
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" --force-file .agents/tools/tool-a.sh 2>&1)"
assert_equal "2" "$?" "--into --force-file exits 2"
assert_contains "$out" "--force-file is only valid with --sync" "--into --force-file explains the invalid combination"
rm -rf "$tmp"

echo "=== test_install: --into fatal when FILES source is absent even if landing exists ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst_missing_src
mkdir -p "$tmp/inst_missing_src/.agents/tools"
printf 'instance-owned fallback\n' > "$tmp/inst_missing_src/.agents/tools/missing.sh"
cat > "$tmp/fw/framework/FILES" <<'EOF'
framework/tools/missing.sh -> .agents/tools/missing.sh
EOF
( cd "$tmp/fw" && git -c user.email=t@x -c user.name=T add -A \
  && git -c user.email=t@x -c user.name=T commit --quiet -m "fw missing source in FILES" )
missing_ref="$(cd "$tmp/fw" && git rev-parse HEAD)"
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst_missing_src" --ref "$missing_ref" 2>&1)"
assert_equal "2" "$?" "missing source under --into exits 2"
assert_contains "$out" "cannot read 'framework/tools/missing.sh'" "missing source is fatal, not SHADOWED"
assert_equal "instance-owned fallback" "$(cat "$tmp/inst_missing_src/.agents/tools/missing.sh")" "existing landing kept"
rm -rf "$tmp"
```

- [ ] **Step 2: Verify red**

Run: `bash framework/tools/tests/test_install.sh`
Expected: FAIL because `--into` silently accepts sync-only flags and mislabels the missing source as `SHADOWED`.

- [ ] **Step 3: Implement minimal fix**

In `install.sh`, after mode parsing, add validation:

```bash
if [ "$MODE" = into ]; then
  [ "$PRUNE" = 0 ] || fatal "--prune is only valid with --sync"
  [ "${#FORCE_FILES[@]}" -eq 0 ] || fatal "--force-file is only valid with --sync"
fi
```

In `process_into`, calculate `new_oid` before checking the destination, so a bad `FILES` source fatals first:

```bash
new_oid="$(source_oid "$REF" "$src_path")"
[ -n "$new_oid" ] || fatal "cannot read '$src_path' at '$REF' from $SRC (is it in framework/FILES but not committed?)"
```

- [ ] **Step 4: Verify green**

Run: `bash framework/tools/tests/test_install.sh`
Expected: PASS.

### Task 2: Installer Atomic Writes And Receipt No-Op Preservation

**Files:**
- Modify: `framework/tools/tests/test_install.sh`
- Modify: `framework/tools/install.sh`

**Interfaces:**
- Consumes: existing `write_from_ref`, `write_receipt`, and manifest rewrite behavior.
- Produces: temp files created next to destinations and unchanged receipt files left byte-identical and inode-stable on no-op sync.

- [ ] **Step 1: Write failing tests**

Add cases to `test_install.sh`:

```bash
echo "=== test_install: no-op sync preserves framework-receipt inode and mtime ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
receipt_before="$(ls -li "$tmp/inst/.agents/framework-receipt")"
sleep 1
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync 2>&1)"
assert_equal "0" "$?" "no-op sync exits 0"
assert_equal "$receipt_before" "$(ls -li "$tmp/inst/.agents/framework-receipt")" "no-op sync preserves receipt inode and timestamp"
rm -rf "$tmp"
```

- [ ] **Step 2: Verify red**

Run: `bash framework/tools/tests/test_install.sh`
Expected: FAIL because `write_receipt` rewrites the receipt even when content is unchanged.

- [ ] **Step 3: Implement minimal fix**

Change temp file creation to use destination directories:

```bash
tmp="$(mktemp "$(dirname "$dest")/.install.$(basename "$dest").XXXXXX" 2>/dev/null)" || fatal "mktemp failed"
```

For receipt and manifest rewrites, create temp files in `$(dirname "$RECEIPT_FILE")` or `$(dirname "$MANIFEST")`.

Teach `write_receipt` to compare the rendered content before `mv`:

```bash
if [ -f "$RECEIPT_FILE" ] && cmp -s "$tmp" "$RECEIPT_FILE"; then
  rm -f "$tmp"
  return 0
fi
```

- [ ] **Step 4: Verify green**

Run: `bash framework/tools/tests/test_install.sh`
Expected: PASS.

### Task 3: Installer Labels And Topology Fixtures

**Files:**
- Modify: `framework/tools/tests/test_install.sh`
- Modify: `framework/tools/install.sh`
- Modify: `framework/tools/tests/test_helpers.sh` only if a fixture helper reduces real duplication.

**Interfaces:**
- Consumes: `make_user_tier_fixture`, role-clone fixture conventions, and existing installer CLI.
- Produces: test coverage for user-tier and role-clone install targets, `--into` pin stamping with SHADOWED refusals, and clearer orphan labels when `--check --prune` is passed.

- [ ] **Step 1: Write failing tests**

Add cases to `test_install.sh`:

```bash
echo "=== test_install: --into stamps pin even when SHADOWED refusals exit 1 ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
mkdir -p "$tmp/inst/.agents/tools"
printf 'instance-owned tool-a\n' > "$tmp/inst/.agents/tools/tool-a.sh"
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" 2>&1)"
assert_equal "1" "$?" "shadowed install exits 1"
assert_contains "$(cat "$tmp/inst/.agents/manifest")" "framework_ref=framework/v1" "pin still stamped despite SHADOWED"
assert_contains "$(cat "$tmp/inst/.agents/manifest")" "framework_source=../fw" "source still stamped despite SHADOWED"
rm -rf "$tmp"

echo "=== test_install: --check --prune reports would-prune for unmodified orphans ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
advance_framework_fixture "$tmp"
( cd "$tmp/inst" && bash "$INSTALL" --sync ) >/dev/null
drop_hook_framework_fixture "$tmp"
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync --check --prune 2>&1)"
assert_equal "1" "$?" "--check --prune with orphan exits 1"
assert_contains "$out" "WOULD-PRUNE: .agents/hooks/lib/hook-x.sh" "--check --prune says WOULD-PRUNE, not remove with --prune"
assert_not_contains "$out" "remove with --prune" "--check --prune does not suggest the flag already passed"
rm -rf "$tmp"
```

Add install fixture checks for `user-tier` and `role-clones` manifests by reusing existing memory payload fixtures and asserting payload files land while memory files remain unchanged.

- [ ] **Step 2: Verify red**

Run: `bash framework/tools/tests/test_install.sh`
Expected: FAIL for missing label behavior or missing topology coverage.

- [ ] **Step 3: Implement minimal fix**

In `process_orphans`, split label behavior:

```bash
elif [ "$PRUNE" = 1 ] && [ "$CHECK" = 1 ]; then
  report_pending "WOULD-PRUNE: $landing no longer in framework/FILES"
else
  report_pending "ORPHANED: $landing no longer in framework/FILES - kept (remove with --prune)"
fi
```

Keep existing pin stamping at the end of non-check `--into` runs.

- [ ] **Step 4: Verify green**

Run: `bash framework/tools/tests/test_install.sh`
Expected: PASS.

### Task 4: Doctor Staleness Regression Coverage

**Files:**
- Modify: `framework/tools/tests/test_doctor_manifest.sh`
- Modify: `framework/tools/doctor.sh` only if a red test exposes a behavior mismatch.

**Interfaces:**
- Consumes: `check_framework_staleness`.
- Produces: coverage for no source/default clone and unreachable explicit source.

- [ ] **Step 1: Write failing tests**

Add cases after the existing staleness tests:

```bash
echo "=== test_doctor_manifest: DRIFT when pinned with no framework_source and no sibling clone ==="
base="$(mktemp -d)"
tmp="$base/embedded-repo"
mkdir -p "$tmp/.agents/memory" "$tmp/.claude"
echo "# index" > "$tmp/.agents/memory/MEMORY.md"
echo "# AGENTS" > "$tmp/AGENTS.md"
( cd "$tmp" && ln -s AGENTS.md CLAUDE.md )
( cd "$tmp/.claude" && ln -s ../.agents/memory memory )
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
framework_ref=framework/v1
EOF
run_doctor --check --root "$tmp"
assert_equal "1" "$DOCTOR_EXIT" "pinned with no source exits 1"
assert_contains "$DOCTOR_STDOUT" "no framework_source is set and no sibling framework clone exists" "missing default source named"
rm -rf "$base"

echo "=== test_doctor_manifest: DRIFT when explicit framework_source is unreachable ==="
base="$(mktemp -d)"
tmp="$base/embedded-repo"
mkdir -p "$tmp/.agents/memory" "$tmp/.claude"
echo "# index" > "$tmp/.agents/memory/MEMORY.md"
echo "# AGENTS" > "$tmp/AGENTS.md"
( cd "$tmp" && ln -s AGENTS.md CLAUDE.md )
( cd "$tmp/.claude" && ln -s ../.agents/memory memory )
cat > "$tmp/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
framework_source=../missing-fw
framework_ref=framework/v1
EOF
run_doctor --check --root "$tmp"
assert_equal "1" "$DOCTOR_EXIT" "unreachable source exits 1"
assert_contains "$DOCTOR_STDOUT" "framework_source '$base/embedded-repo/../missing-fw' unreachable" "unreachable explicit source named"
rm -rf "$base"
```

- [ ] **Step 2: Verify red or coverage green**

Run: `bash framework/tools/tests/test_doctor_manifest.sh`
Expected: PASS if the behavior already exists, otherwise FAIL with the missing branch.

- [ ] **Step 3: Implement only if needed**

If tests fail, adjust `check_framework_staleness` messages without changing its INFO-vs-DRIFT contract.

- [ ] **Step 4: Verify green**

Run: `bash framework/tools/tests/test_doctor_manifest.sh`
Expected: PASS.

### Task 5: Framework FILES Contract Tests

**Files:**
- Modify: `framework/tools/tests/test_framework_files.sh`

**Interfaces:**
- Consumes: committed `framework/FILES`.
- Produces: explicit regression coverage for malformed lines and zero inject entries.

- [ ] **Step 1: Write tests**

Add a helper that checks a supplied FILES fixture and fails on malformed lines.
Add fixture cases for:

```text
framework/tools/tool-a.sh .agents/tools/tool-a.sh
```

and for a FILES body with zero `inject-role-index.sh` entries.

- [ ] **Step 2: Verify behavior**

Run: `bash framework/tools/tests/test_framework_files.sh`
Expected: PASS on the real manifest and PASS for the synthetic negative cases that assert failure counters increment.

### Task 6: Docs And Spec Corrections

**Files:**
- Modify: `docs/superpowers/specs/2026-07-06-framework-distribution-design.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: issue #60 doc notes.
- Produces: docs that name `.agents/framework-receipt` as install-owned state and replace stale `tools/sync.sh --check`.

- [ ] **Step 1: Update spec**

Change the section 3 "What sync never does" sentence to:

```markdown
What sync never does: touch `.agents/memory/`, manifest values other than `framework_ref`, instance skills, or anything not in `FILES`, except for install-owned `.agents/framework-receipt`.
```

- [ ] **Step 2: Update README**

Replace:

```markdown
`tools/sync.sh --check` in that repo doctors the wiring.
```

with:

```markdown
`.agents/tools/doctor.sh --check` in that repo doctors the wiring.
```

- [ ] **Step 3: Verify docs**

Run: `rg -n "tools/sync.sh --check|framework-receipt|What sync never does" README.md docs/superpowers/specs/2026-07-06-framework-distribution-design.md`
Expected: README no longer contains the stale command, and the spec names the receipt exception.

### Task 7: Full Verification And PR

**Files:**
- No direct edits.

**Interfaces:**
- Consumes: all prior tasks.
- Produces: pushed branch and PR against issue #60.

- [ ] **Step 1: Run focused tests**

Run:

```bash
bash framework/tools/tests/test_install.sh
bash framework/tools/tests/test_doctor_manifest.sh
bash framework/tools/tests/test_framework_files.sh
```

Expected: all PASS.

- [ ] **Step 2: Run full harness**

Run: `bash framework/tools/tests/run_all.sh`
Expected: all PASS.

- [ ] **Step 3: Commit implementation**

Run:

```bash
git add framework/tools/install.sh framework/tools/doctor.sh framework/tools/tests/test_install.sh framework/tools/tests/test_doctor_manifest.sh framework/tools/tests/test_framework_files.sh framework/tools/tests/test_helpers.sh docs/superpowers/specs/2026-07-06-framework-distribution-design.md README.md docs/superpowers/plans/2026-07-07-install-doctor-follow-ups.md
git commit -m "claude-personas: tighten framework install and doctor follow-ups"
```

- [ ] **Step 4: Push and open PR**

Use `--body-file` for PR text.
Do not pass quoted literal `\n` bodies to `gh`.
