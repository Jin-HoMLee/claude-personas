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

echo "=== test_inject_role_index no-trailing-newline last line still flags truncation ==="
# Regression: `wc -l` counts newline chars, so a file whose last line lacks a
# trailing newline is undercounted by one; if exactly that last line is cut,
# total==kept and the [TRUNCATED ...] trailer was silently skipped despite
# real content loss. Fixed by counting lines with `grep -c ''`.
tmp3="$(mktemp -d)"
mkdir -p "$tmp3/memory-repo/developer" "$tmp3/memory-repo/shared"
# Header "# Role memory index\n" is 20 chars -> awk sees cap 9000-20=8980.
# 150 lines of exactly 59 chars (60 with \n): awk keeps 149 (n=8940) and cuts
# line 150 (n=9000 > 8980). The LAST line has NO trailing newline.
pad="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # 50 chars
{
  for i in $(seq 1 149); do printf 'line %03d %s\n' "$i" "$pad"; done
  printf 'line %03d %s' 150 "$pad"
} > "$tmp3/memory-repo/developer/MEMORY.md"
printf "# Shared index\n" > "$tmp3/memory-repo/shared/MEMORY.md"
( cd "$tmp3/memory-repo/developer" && ln -s ../shared shared )

ctx3="$(bash "$INJECT" "$tmp3/memory-repo/developer" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx3" in *TRUNCATED*) echo "  PASS: trailer present when newline-less last line is cut";; *) echo "  FAIL: trailer missing (wc -l undercounts final line)"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctx3" in *"line 150"*) echo "  FAIL: cut line unexpectedly present in payload"; TESTS_FAILED=$((TESTS_FAILED+1));; *) echo "  PASS: cut line really absent from payload";; esac
rm -rf "$tmp3"

echo "=== test_inject_role_index missing jq degrades gracefully ==="
tmp4="$(mktemp -d)"
mkdir -p "$tmp4/memory-repo/developer" "$tmp4/memory-repo/shared" "$tmp4/shim"
printf "# Role index\n" > "$tmp4/memory-repo/developer/MEMORY.md"
printf "# Shared index\n" > "$tmp4/memory-repo/shared/MEMORY.md"
( cd "$tmp4/memory-repo/developer" && ln -s ../shared shared )
# Shim PATH: real wc/awk/grep/tr symlinked in, but NO jq - so only jq is
# missing, not every external the script uses.
for cmd in wc awk grep tr; do ln -s "$(command -v "$cmd")" "$tmp4/shim/$cmd"; done
rc4=0
err4="$(PATH="$tmp4/shim" "$BASH" "$INJECT" "$tmp4/memory-repo/developer" 2>&1 >/dev/null)" || rc4=$?
assert_equal "0" "$rc4" "exits 0 when jq is missing"
case "$err4" in *jq*) echo "  PASS: stderr mentions jq";; *) echo "  FAIL: stderr does not mention jq: $err4"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
rm -rf "$tmp4"

echo "=== test_inject_role_index defensive exits ==="
assert_equal "0" "$( bash "$INJECT" "/nonexistent/role/dir" >/dev/null 2>&1; echo $? )" "exits 0 on missing role dir"
assert_equal "0" "$( bash "$INJECT" >/dev/null 2>&1; echo $? )" "exits 0 with no argument"
assert_equal "" "$( bash "$INJECT" "/nonexistent/role/dir" 2>/dev/null )" "prints nothing on missing role dir"

print_summary
