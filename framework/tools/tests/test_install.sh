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
