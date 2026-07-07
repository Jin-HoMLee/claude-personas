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
skill_mode="$(ls -l "$tmp/inst/.agents/skills/demo-skill/SKILL.md" | awk '{print $1}' | cut -c1-10)"
assert_equal "-rw-r--r--" "$skill_mode" "non-executable payload lands mode 0644, not mktemp's 0600"
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

echo "=== test_install: '..' component in a landing path is rejected (escapes .agents/) ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst_evil
cat > "$tmp/fw/framework/FILES" <<'EOF'
# fixture FILES
framework/tools/tool-a.sh -> .agents/tools/tool-a.sh
framework/hooks/hook-x.sh -> .agents/hooks/lib/hook-x.sh
framework/skills/demo-skill/SKILL.md -> .agents/skills/demo-skill/SKILL.md
framework/tools/tool-a.sh -> .agents/../escaped.txt
EOF
( cd "$tmp/fw" && git -c user.email=t@x -c user.name=T add -A \
  && git -c user.email=t@x -c user.name=T commit --quiet -m "fw evil: traversal entry" )
evil_ref="$(cd "$tmp/fw" && git rev-parse HEAD)"
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst_evil" --ref "$evil_ref" 2>&1)"
status=$?
assert_equal "2" "$status" "'..' landing component: exit 2"
assert_contains "$out" "'..' component" "error names the '..' component"
assert_not_exists "$tmp/inst_evil/escaped.txt" "escaped file did not land outside .agents/"
rm -rf "$tmp"

echo "=== test_install: orphan sweep skips a tainted pinned landing ('..' + outside .agents/) ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst_taint
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst_taint" 2>&1)"
assert_equal "0" "$?" "clean install for taint fixture exits 0"

# v2: a bad historical FILES declares a traversal entry alongside the normal
# 3. bait-src.txt's content is literally "bait" so we can later plant an
# identical instance-side file and see whether --prune would delete it.
printf 'bait' > "$tmp/fw/framework/tools/bait-src.txt"
cat > "$tmp/fw/framework/FILES" <<'EOF'
framework/tools/tool-a.sh -> .agents/tools/tool-a.sh
framework/hooks/hook-x.sh -> .agents/hooks/lib/hook-x.sh
framework/skills/demo-skill/SKILL.md -> .agents/skills/demo-skill/SKILL.md
framework/tools/bait-src.txt -> .agents/../escaped.txt
EOF
( cd "$tmp/fw" && git -c user.email=t@x -c user.name=T add -A \
  && git -c user.email=t@x -c user.name=T commit --quiet -m "fw v2: tainted entry" \
  && git -c user.email=t@x -c user.name=T tag -a framework/v2 -m v2 )

# Simulate a legacy instance whose pin already points at the tainted ref (the
# guarded CURRENT-ref walk would fatal on this entry if it were live today -
# the point is a bad entry sitting in HISTORY, behind the pin, must not be
# trusted either). Stamp the manifest directly, the same awk-to-tmp+mv
# rewrite install.sh itself uses for its pin stamp - no sed -i.
manifest_tmp="$(mktemp)"
awk -F= '$1 == "framework_ref" { print "framework_ref=framework/v2"; next } { print }' \
  "$tmp/inst_taint/.agents/manifest" > "$manifest_tmp"
mv "$manifest_tmp" "$tmp/inst_taint/.agents/manifest"

# Plant the instance-side landing, content-identical to the tainted pinned
# blob - exactly what --prune would delete if the guard were absent.
printf 'bait' > "$tmp/inst_taint/escaped.txt"

# v3: FILES is clean again (tainted entry gone) - the tainted landing is now
# an orphan relative to the (tainted) pin.
cat > "$tmp/fw/framework/FILES" <<'EOF'
framework/tools/tool-a.sh -> .agents/tools/tool-a.sh
framework/hooks/hook-x.sh -> .agents/hooks/lib/hook-x.sh
framework/skills/demo-skill/SKILL.md -> .agents/skills/demo-skill/SKILL.md
EOF
( cd "$tmp/fw" && git -c user.email=t@x -c user.name=T add -A \
  && git -c user.email=t@x -c user.name=T commit --quiet -m "fw v3: tainted entry dropped" \
  && git -c user.email=t@x -c user.name=T tag -a framework/v3 -m v3 )

out="$(cd "$tmp/inst_taint" && bash "$INSTALL" --sync --ref framework/v3 --prune 2>&1)"
status=$?
assert_equal "1" "$status" "tainted orphan: sync --prune reports pending, exit 1"
assert_contains "$out" "TAINTED ORPHAN" "tainted orphan is named and skipped"
assert_equal "bait" "$(cat "$tmp/inst_taint/escaped.txt" 2>/dev/null)" "escaped file outside .agents/ was never touched"
assert_contains "$(cat "$tmp/inst_taint/.agents/manifest")" "framework_ref=framework/v3" "pin still advances to the clean ref despite the tainted orphan"
rm -rf "$tmp"

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
assert_contains "$(cat "$tmp/inst/.agents/manifest")" "framework_ref=framework/v3" "pin advances past the pending ORPHANED landing (receipt keeps it discoverable, not the pin)"
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
assert_contains "$(cat "$tmp/inst/.agents/manifest")" "framework_ref=framework/v3" "pin advances past the MODIFIED ORPHAN too (receipt keeps it discoverable, not the pin)"
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

echo "=== test_install: regression - sync spanning a change + a drop in one jump does not misflag the changed file MODIFIED ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
advance_framework_fixture "$tmp"       # v2: tool-a changes, tool-b appears
drop_hook_framework_fixture "$tmp"     # v3 (built on v2): hook-x drops
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync 2>&1)"
status=$?
assert_equal "1" "$status" "sync straight from v1 to v3 (spans a change + a drop): orphan pending, exit 1"
assert_contains "$out" "ORPHANED: .agents/hooks/lib/hook-x.sh" "hook-x reported orphaned"
assert_contains "$out" "SYNCED: .agents/tools/tool-a.sh" "tool-a synced to the new content in the same run"
case "$out" in
  *"MODIFIED: .agents/tools/tool-a.sh"*) echo "  FAIL: tool-a wrongly flagged MODIFIED"; TESTS_FAILED=$((TESTS_FAILED+1)) ;;
  *) echo "  PASS: tool-a not flagged MODIFIED" ;;
esac
assert_contains "$(cat "$tmp/inst/.agents/tools/tool-a.sh")" "tool-a v2" "tool-a content is the new upstream content"
assert_contains "$(cat "$tmp/inst/.agents/manifest")" "framework_ref=framework/v3" "pin advances to v3 despite the pending orphan"
assert_exists "$tmp/inst/.agents/hooks/lib/hook-x.sh" "hook-x still on disk (orphan kept, not deleted)"

out="$(cd "$tmp/inst" && bash "$INSTALL" --sync --prune 2>&1)"
assert_equal "0" "$?" "--sync --prune resolves the orphan (found via the receipt): exit 0"
assert_contains "$out" "PRUNED: .agents/hooks/lib/hook-x.sh" "hook-x pruned even though the pin already moved past its FILES entry"
assert_not_exists "$tmp/inst/.agents/hooks/lib/hook-x.sh" "hook-x removed"

out="$(cd "$tmp/inst" && bash "$INSTALL" --sync 2>&1)"
assert_equal "0" "$?" "final plain sync on the settled instance: exit 0"
assert_contains "$(cat "$tmp/inst/.agents/tools/tool-a.sh")" "tool-a v2" "tool-a still current"
case "$out" in
  *"MODIFIED"*) echo "  FAIL: something got flagged MODIFIED on the settled instance"; TESTS_FAILED=$((TESTS_FAILED+1)) ;;
  *) echo "  PASS: nothing flagged on the settled instance" ;;
esac
rm -rf "$tmp"

echo "=== test_install: framework-receipt is created on --into (one sorted line per landing + oid); --check never touches it ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" --check ) >/dev/null
assert_not_exists "$tmp/inst/.agents/framework-receipt" "--check never creates the receipt"
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
assert_exists "$tmp/inst/.agents/framework-receipt" "receipt created by --into"
receipt="$(cat "$tmp/inst/.agents/framework-receipt")"
assert_contains "$receipt" "written by install.sh" "receipt carries the do-not-edit header comment"
landing_count="$(grep -vc '^#' "$tmp/inst/.agents/framework-receipt")"
assert_equal "3" "$landing_count" "one receipt line per installed landing"
for landing in .agents/tools/tool-a.sh .agents/hooks/lib/hook-x.sh .agents/skills/demo-skill/SKILL.md; do
  case "$receipt" in
    *"$landing"$'\t'*) : ;;
    *) echo "  FAIL: receipt missing an oid line for $landing"; TESTS_FAILED=$((TESTS_FAILED+1)) ;;
  esac
done
sorted_landings="$(grep -v '^#' "$tmp/inst/.agents/framework-receipt" | cut -f1)"
assert_equal "$(printf '%s\n' "$sorted_landings" | sort)" "$sorted_landings" "receipt lines are sorted by landing path"
receipt_before="$receipt"
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync --check 2>&1)"
assert_equal "$receipt_before" "$(cat "$tmp/inst/.agents/framework-receipt")" "--check on sync never modifies the receipt"
rm -rf "$tmp"

echo "=== test_install: receipt entry removed on PRUNED, kept unchanged on a MODIFIED refusal ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
advance_framework_fixture "$tmp"
( cd "$tmp/inst" && bash "$INSTALL" --sync ) >/dev/null
drop_hook_framework_fixture "$tmp"
( cd "$tmp/inst" && bash "$INSTALL" --sync --prune ) >/dev/null
case "$(cat "$tmp/inst/.agents/framework-receipt")" in
  *".agents/hooks/lib/hook-x.sh"*) echo "  FAIL: receipt still tracks the pruned landing"; TESTS_FAILED=$((TESTS_FAILED+1)) ;;
  *) echo "  PASS: receipt entry removed on PRUNED" ;;
esac

printf '#!/usr/bin/env bash\necho locally hacked\n' > "$tmp/inst/.agents/tools/tool-a.sh"
receipt_line_before="$(awk -F'\t' '$1==".agents/tools/tool-a.sh"{print}' "$tmp/inst/.agents/framework-receipt")"
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync 2>&1)"
assert_contains "$out" "MODIFIED: .agents/tools/tool-a.sh" "tool-a.sh flagged MODIFIED"
assert_contains "$(cat "$tmp/inst/.agents/framework-receipt")" "$receipt_line_before" "receipt entry for the MODIFIED file is kept unchanged"
rm -rf "$tmp"

echo "=== test_install: bootstrap - missing receipt falls back to the pin baseline and regenerates ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
rm "$tmp/inst/.agents/framework-receipt"
advance_framework_fixture "$tmp"
out="$(cd "$tmp/inst" && bash "$INSTALL" --sync 2>&1)"
status=$?
assert_equal "0" "$status" "sync with no receipt falls back to the pin baseline: exits 0"
assert_contains "$out" "SYNCED: .agents/tools/tool-a.sh" "pristine file synced via pin fallback, not flagged MODIFIED"
assert_contains "$(cat "$tmp/inst/.agents/tools/tool-a.sh")" "tool-a v2" "tool-a now at v2 content"
assert_exists "$tmp/inst/.agents/framework-receipt" "receipt regenerated by the sync"
landing_count="$(grep -vc '^#' "$tmp/inst/.agents/framework-receipt")"
assert_equal "4" "$landing_count" "regenerated receipt tracks all 4 currently-installed landings (tool-a, tool-b, hook-x, skill)"
rm -rf "$tmp"

echo "=== test_install: --ref HEAD resolves to the full commit SHA, not the literal string 'HEAD' ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
head_sha="$(git -C "$tmp/fw" rev-parse HEAD)"
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" --ref HEAD 2>&1)"
assert_equal "0" "$?" "--ref HEAD install exits 0"
pinned="$(awk -F= '$1=="framework_ref"{print $2}' "$tmp/inst/.agents/manifest")"
assert_matches "$pinned" "^[0-9a-f]{40}$" "HEAD resolves to a 40-char commit SHA in the manifest"
assert_equal "$head_sha" "$pinned" "resolved SHA matches the source clone's HEAD"
rm -rf "$tmp"

echo "=== test_install: --ref framework/v1 stays pinned verbatim as the tag name, not a SHA ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
out="$(cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" --ref framework/v1 2>&1)"
assert_equal "0" "$?" "--ref framework/v1 install exits 0"
assert_contains "$(cat "$tmp/inst/.agents/manifest")" "framework_ref=framework/v1" "tag ref pinned verbatim, not resolved to a SHA"
rm -rf "$tmp"

echo "=== test_install: install's own state files (manifest, receipt) land mode 0644, not mktemp's 0600 ==="
tmp="$(mktemp -d)"
make_framework_fixture "$tmp"
make_instance_fixture "$tmp" inst
( cd "$tmp/fw" && bash "$INSTALL" --into "$tmp/inst" ) >/dev/null
manifest_mode="$(ls -l "$tmp/inst/.agents/manifest" | awk '{print $1}' | cut -c1-10)"
receipt_mode="$(ls -l "$tmp/inst/.agents/framework-receipt" | awk '{print $1}' | cut -c1-10)"
assert_equal "-rw-r--r--" "$manifest_mode" "manifest lands mode 0644, not mktemp's 0600"
assert_equal "-rw-r--r--" "$receipt_mode" "receipt lands mode 0644, not mktemp's 0600"
rm -rf "$tmp"

print_summary
