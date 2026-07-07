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
