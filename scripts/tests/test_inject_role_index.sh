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
