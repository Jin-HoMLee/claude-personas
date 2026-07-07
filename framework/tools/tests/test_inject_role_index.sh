#!/usr/bin/env bash
# Test inject-role-index.sh - Codex SessionStart payload for a role dir.
#
# Scope contract (claude-personas#52): the payload carries the ROLE index only,
# mirroring Claude Code's native auto-load (CC injects the role MEMORY.md, not
# shared/). Shared is reachable on demand via a one-line pointer + the
# load-persona-memory skill, never the SessionStart payload. The truncation cap
# adopts CC's native role-index size guard (~200 lines / ~25 KB, whichever
# first) and is overridable via PERSONAS_INJECT_BYTE_CAP / PERSONAS_INJECT_LINE_CAP.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
INJECT="$(cd "$SCRIPT_DIR/../../hooks" && pwd)/inject-role-index.sh"

echo "=== test_inject_role_index happy path (role index only, shared pointer) ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/memory-repo/developer" "$tmp/memory-repo/shared"
printf "# Role index canary-role-line\n" > "$tmp/memory-repo/developer/MEMORY.md"
printf "# Shared index canary-shared-content\n" > "$tmp/memory-repo/shared/MEMORY.md"
( cd "$tmp/memory-repo/developer" && ln -s ../shared shared )

out="$(bash "$INJECT" "$tmp/memory-repo/developer")"
assert_equal "0" "$?" "exits 0 on happy path"

ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
assert_equal "SessionStart" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" "envelope is a SessionStart hook output"
case "$ctx" in *canary-role-line*) echo "  PASS: role index in payload";; *) echo "  FAIL: role index missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
# Shared CONTENT must NOT be injected (parity with CC role-only auto-load).
case "$ctx" in *canary-shared-content*) echo "  FAIL: shared index content leaked into payload"; TESTS_FAILED=$((TESTS_FAILED+1));; *) echo "  PASS: shared index content not injected";; esac
# But a one-line pointer to the on-demand shared index must be present.
case "$ctx" in *"$tmp/memory-repo/developer/shared/MEMORY.md"*) echo "  PASS: shared pointer present";; *) echo "  FAIL: shared pointer missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctx" in *"loaded on demand"*) echo "  PASS: shared pointer marks it on-demand";; *) echo "  FAIL: shared pointer does not mark it on-demand"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctx" in *TRUNCATED*) echo "  FAIL: unexpected truncation trailer"; TESTS_FAILED=$((TESTS_FAILED+1));; *) echo "  PASS: no truncation trailer on small index";; esac
rm -rf "$tmp"

echo "=== test_inject_role_index blank-line EOF must NOT false-truncate ==="
# Regression (code-review of #53): the old count-based flag compared grep -c ''
# (counts trailing blank lines) against a chunk whose trailing blanks are
# stripped by command substitution, so an index ending in a blank line fired a
# false [TRUNCATED] trailer despite injecting the full content.
tmpb="$(mktemp -d)"
mkdir -p "$tmpb/memory-repo/developer" "$tmpb/memory-repo/shared"
printf -- "- entry a\n- entry b canary-tail\n\n" > "$tmpb/memory-repo/developer/MEMORY.md"  # blank line at EOF
printf "# Shared index\n" > "$tmpb/memory-repo/shared/MEMORY.md"
( cd "$tmpb/memory-repo/developer" && ln -s ../shared shared )
ctxb="$(bash "$INJECT" "$tmpb/memory-repo/developer" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctxb" in *TRUNCATED*) echo "  FAIL: false truncation trailer on blank-line EOF"; TESTS_FAILED=$((TESTS_FAILED+1));; *) echo "  PASS: no false trailer on blank-line EOF";; esac
case "$ctxb" in *canary-tail*) echo "  PASS: full content injected";; *) echo "  FAIL: content missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
rm -rf "$tmpb"

echo "=== test_inject_role_index non-numeric cap falls back to default ==="
tmpc="$(mktemp -d)"
mkdir -p "$tmpc/memory-repo/developer"
printf "# Role index numeric-fallback-canary\n" > "$tmpc/memory-repo/developer/MEMORY.md"
ctxc="$(PERSONAS_INJECT_BYTE_CAP=25k bash "$INJECT" "$tmpc/memory-repo/developer" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctxc" in *numeric-fallback-canary*) echo "  PASS: non-numeric cap falls back, index injected";; *) echo "  FAIL: non-numeric cap suppressed the index"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
rm -rf "$tmpc"

echo "=== test_inject_role_index no shared dir -> role only, no pointer, no crash ==="
tmpn="$(mktemp -d)"
mkdir -p "$tmpn/memory-repo/developer"
printf "# Role index only-role\n" > "$tmpn/memory-repo/developer/MEMORY.md"
ctxn="$(bash "$INJECT" "$tmpn/memory-repo/developer" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctxn" in *only-role*) echo "  PASS: role index present without a shared dir";; *) echo "  FAIL: role index missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctxn" in *"loaded on demand"*) echo "  FAIL: shared pointer emitted when no shared dir exists"; TESTS_FAILED=$((TESTS_FAILED+1));; *) echo "  PASS: no shared pointer when no shared dir";; esac
rm -rf "$tmpn"

echo "=== test_inject_role_index BYTE-cap truncation trailer ==="
tmp2="$(mktemp -d)"
mkdir -p "$tmp2/memory-repo/developer" "$tmp2/memory-repo/shared"
# 100 lines x ~60 chars = ~6k chars; force a tiny 2000-byte cap so the byte
# budget (not the line cap) drives truncation.
for i in $(seq 1 100); do
  printf -- "- [entry %03d](file_%03d.md) - padding padding padding padding\n" "$i" "$i"
done > "$tmp2/memory-repo/developer/MEMORY.md"
printf "# Shared index\n" > "$tmp2/memory-repo/shared/MEMORY.md"
( cd "$tmp2/memory-repo/developer" && ln -s ../shared shared )

ctx2="$(PERSONAS_INJECT_BYTE_CAP=2000 PERSONAS_INJECT_LINE_CAP=9999 bash "$INJECT" "$tmp2/memory-repo/developer" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx2" in *TRUNCATED*) echo "  PASS: truncation trailer present (byte cap)";; *) echo "  FAIL: truncation trailer missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctx2" in *"entry 001"*) echo "  PASS: top of index survives the cut";; *) echo "  FAIL: top of index missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
# Trailer + shared pointer add a little; role-index bytes stay near the 2000 cap.
if [ "${#ctx2}" -le 2600 ]; then
  echo "  PASS: payload bounded near the byte cap"
else
  echo "  FAIL: payload not bounded (${#ctx2} chars)"; TESTS_FAILED=$((TESTS_FAILED+1))
fi
rm -rf "$tmp2"

echo "=== test_inject_role_index LINE-cap truncation trailer ==="
tmp6="$(mktemp -d)"
mkdir -p "$tmp6/memory-repo/developer" "$tmp6/memory-repo/shared"
# 50 short lines; force a 10-line cap with a generous byte cap so the LINE cap
# drives truncation.
for i in $(seq 1 50); do printf -- "- line %03d\n" "$i"; done > "$tmp6/memory-repo/developer/MEMORY.md"
printf "# Shared index\n" > "$tmp6/memory-repo/shared/MEMORY.md"
( cd "$tmp6/memory-repo/developer" && ln -s ../shared shared )

ctx6="$(PERSONAS_INJECT_BYTE_CAP=999999 PERSONAS_INJECT_LINE_CAP=10 bash "$INJECT" "$tmp6/memory-repo/developer" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx6" in *TRUNCATED*) echo "  PASS: truncation trailer present (line cap)";; *) echo "  FAIL: truncation trailer missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctx6" in *"line 001"*) echo "  PASS: top of index survives the cut";; *) echo "  FAIL: top of index missing"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctx6" in *"line 011"*) echo "  FAIL: line past the 10-line cap leaked in"; TESTS_FAILED=$((TESTS_FAILED+1));; *) echo "  PASS: lines past the cap dropped";; esac
rm -rf "$tmp6"

echo "=== test_inject_role_index no-trailing-newline last line still flags truncation ==="
# Regression: grep -c '' counts lines (not newlines), so a file whose last line
# lacks a trailing newline is not undercounted; if exactly that last line is
# cut, the [TRUNCATED ...] trailer must still fire.
tmp3="$(mktemp -d)"
mkdir -p "$tmp3/memory-repo/developer" "$tmp3/memory-repo/shared"
pad="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # 50 chars
{
  for i in $(seq 1 149); do printf 'line %03d %s\n' "$i" "$pad"; done
  printf 'line %03d %s' 150 "$pad"   # last line: NO trailing newline
} > "$tmp3/memory-repo/developer/MEMORY.md"
printf "# Shared index\n" > "$tmp3/memory-repo/shared/MEMORY.md"
( cd "$tmp3/memory-repo/developer" && ln -s ../shared shared )

# Header "# Role memory index\n" is 20 chars -> byte budget 9000-20=8980.
# 150 lines of 59 chars (60 with \n): keeps 149 (n=8940), cuts line 150 (n=9000).
ctx3="$(PERSONAS_INJECT_BYTE_CAP=9000 PERSONAS_INJECT_LINE_CAP=9999 bash "$INJECT" "$tmp3/memory-repo/developer" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx3" in *TRUNCATED*) echo "  PASS: trailer present when newline-less last line is cut";; *) echo "  FAIL: trailer missing (line undercount)"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctx3" in *"line 150"*) echo "  FAIL: cut line unexpectedly present in payload"; TESTS_FAILED=$((TESTS_FAILED+1));; *) echo "  PASS: cut line really absent from payload";; esac
rm -rf "$tmp3"

echo "=== test_inject_role_index single line longer than the cap still flags truncation ==="
# Regression: when the entire MEMORY.md is one line longer than the byte budget,
# awk's exit fires before printing it, so chunk="" - but printf '%s\n' "" | wc -l
# reports 1, so kept must be forced to 0 or the trailer silently skips.
tmp5="$(mktemp -d)"
mkdir -p "$tmp5/memory-repo/developer" "$tmp5/memory-repo/shared"
long_line="$(printf 'x%.0s' $(seq 1 5900))MIDDLE_MARKER_CANARY$(printf 'x%.0s' $(seq 1 5900))"
printf '%s' "$long_line" > "$tmp5/memory-repo/developer/MEMORY.md"
printf "# Shared index\n" > "$tmp5/memory-repo/shared/MEMORY.md"
( cd "$tmp5/memory-repo/developer" && ln -s ../shared shared )

ctx5="$(PERSONAS_INJECT_BYTE_CAP=9000 PERSONAS_INJECT_LINE_CAP=9999 bash "$INJECT" "$tmp5/memory-repo/developer" | jq -r '.hookSpecificOutput.additionalContext')"
case "$ctx5" in *TRUNCATED*) echo "  PASS: trailer present when the single over-cap line is dropped";; *) echo "  FAIL: trailer missing (single-line cut not detected)"; TESTS_FAILED=$((TESTS_FAILED+1));; esac
case "$ctx5" in *MIDDLE_MARKER_CANARY*) echo "  FAIL: dropped line's content leaked into payload"; TESTS_FAILED=$((TESTS_FAILED+1));; *) echo "  PASS: dropped line's content really absent from payload";; esac
rm -rf "$tmp5"

echo "=== test_inject_role_index missing jq degrades gracefully ==="
tmp4="$(mktemp -d)"
mkdir -p "$tmp4/memory-repo/developer" "$tmp4/memory-repo/shared" "$tmp4/shim"
printf "# Role index\n" > "$tmp4/memory-repo/developer/MEMORY.md"
printf "# Shared index\n" > "$tmp4/memory-repo/shared/MEMORY.md"
( cd "$tmp4/memory-repo/developer" && ln -s ../shared shared )
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
