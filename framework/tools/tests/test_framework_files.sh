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

files_manifest_malformed_count() {
  local manifest="$1"
  awk '
    /^[[:space:]]*$/ { next }
    /^#/ { next }
    index($0, " -> ") == 0 { bad += 1 }
    END { print bad + 0 }
  ' "$manifest"
}

files_manifest_inject_count() {
  local manifest="$1"
  awk -F' -> ' '!/^#/ && NF == 2 && $1 ~ /inject-role-index[.]sh$/ { count += 1 } END { print count + 0 }' "$manifest"
}

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
assert_equal "0" "$(files_manifest_malformed_count "$FILES")" "real FILES has no malformed non-comment lines"

echo "=== test_framework_files: inject-hook landing matches the doctor/init-clone literals ==="
declared="$(awk -F' -> ' '/inject-role-index.sh/ && !/^#/ {print $2}' "$FILES")"
assert_equal "1" "$(files_manifest_inject_count "$FILES")" "FILES declares exactly one inject-role-index.sh entry"
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

echo "=== test_framework_files: helper coverage for malformed lines and zero inject entries ==="
tmp="$(mktemp -d)"
cat > "$tmp/malformed-FILES" <<'EOF'
# fixture FILES
framework/tools/tool-a.sh .agents/tools/tool-a.sh
framework/tools/tool-b.sh -> .agents/tools/tool-b.sh
EOF
assert_equal "1" "$(files_manifest_malformed_count "$tmp/malformed-FILES")" "malformed FILES helper flags the missing arrow branch"
cat > "$tmp/no-inject-FILES" <<'EOF'
framework/tools/tool-a.sh -> .agents/tools/tool-a.sh
framework/skills/demo-skill/SKILL.md -> .agents/skills/demo-skill/SKILL.md
EOF
assert_equal "0" "$(files_manifest_inject_count "$tmp/no-inject-FILES")" "inject-count helper handles zero inject entries"
rm -rf "$tmp"

echo "=== test_framework_files: reserved-name set identical in every component that inlines it (#76) ==="
# The shared/examples non-role exclusion is deliberately inlined in four
# standalone payload files (the inject hook is distributed as a byte-exact
# copy and may not source a lib at runtime). Each copy must express it as a
# case-folded case arm; this extracts the ACTUAL arm from each file and
# asserts every one matches the canonical set, so adding a reserved name in
# one place fails loudly here instead of silently desyncing role discovery.
reserved_arm_of() {
  # All case arms that name 'shared', normalized: names sorted, one line.
  grep -hE '^[[:space:]]*[a-z0-9_|-]*shared[a-z0-9_|-]*\)' "$1" \
    | sed -E 's/^[[:space:]]*//; s/\).*$//' \
    | tr '|' '\n' | sort -u | paste -sd'|' -
}
reserved_canonical="examples|shared"
for f in \
  framework/tools/doctor.sh \
  framework/tools/list-roles.sh \
  framework/tools/init-clone.sh \
  framework/hooks/inject-subagent-role-pointer.sh; do
  assert_equal "$reserved_canonical" "$(reserved_arm_of "$REPO_ROOT/$f")" \
    "reserved-name case arm in $f matches the canonical set"
done

print_summary
