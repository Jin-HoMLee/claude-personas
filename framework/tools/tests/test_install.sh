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

print_summary
