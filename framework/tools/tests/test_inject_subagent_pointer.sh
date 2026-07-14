#!/usr/bin/env bash
# Test inject-subagent-role-pointer.sh (claude-personas#49 spec section 4b):
# a SubagentStart hook that injects a <2KB POINTER to the spawning role's
# memory indexes, keyed on stdin .agent_type. Never the payload (#64: CC
# silently clips additionalContext at ~2KB on this path).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
HOOK="$(cd "$SCRIPT_DIR/../.." && pwd)/hooks/inject-subagent-role-pointer.sh"

make_memrepo() {
  local base="$1"
  mkdir -p "$base/developer/shared" "$base/developer/user" "$base/pm" \
    "$base/shared" "$base/examples/developer"
  echo "# dev idx" > "$base/developer/MEMORY.md"
  echo "# shared idx" > "$base/developer/shared/MEMORY.md"
  echo "# dev@user idx" > "$base/developer/user/MEMORY.md"
  echo "# pm idx" > "$base/pm/MEMORY.md"
  echo "# top-level shared idx" > "$base/shared/MEMORY.md"
  echo "# example idx" > "$base/examples/developer/MEMORY.md"
}

echo "=== inject-subagent-role-pointer: known agent_type gets a pointer ==="
tmp="$(mktemp -d)"
make_memrepo "$tmp"
out="$(printf '{"agent_type":"developer"}' | bash "$HOOK" "$tmp")"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "Read $tmp/developer/MEMORY.md" "pointer names the role index"
assert_contains "$ctx" "Read $tmp/developer/shared/MEMORY.md" "pointer names the shared index"
assert_contains "$ctx" "Read $tmp/developer/user/MEMORY.md" "pointer names the role@user index"
assert_contains "$ctx" "do not read another role's directory" "pointer carries the isolation rule"
assert_equal "SubagentStart" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" "hookEventName is SubagentStart"
if [ "${#ctx}" -lt 2000 ]; then
  assert_equal "under2k" "under2k" "pointer stays under the 2KB clip"
else
  assert_equal "under2k" "over2k" "pointer stays under the 2KB clip"
fi
rm -rf "$tmp"

echo "=== inject-subagent-role-pointer: role without user mount omits the user pointer ==="
tmp="$(mktemp -d)"
make_memrepo "$tmp"
out="$(printf '{"agent_type":"pm"}' | bash "$HOOK" "$tmp")"
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
assert_contains "$ctx" "Read $tmp/pm/MEMORY.md" "pm pointer names the pm index"
assert_not_contains "$ctx" "/pm/shared/" "no shared pointer for a role without shared/"
case "$ctx" in
  *"/pm/user/"*) assert_equal "absent" "present" "no user pointer for unmounted role" ;;
  *) assert_equal "absent" "absent" "no user pointer for unmounted role" ;;
esac
rm -rf "$tmp"

echo "=== inject-subagent-role-pointer: unknown agent_type is silent exit 0 ==="
tmp="$(mktemp -d)"
make_memrepo "$tmp"
out="$(printf '{"agent_type":"Explore"}' | bash "$HOOK" "$tmp")"
rc=$?
assert_equal "0" "$rc" "unknown agent_type exits 0"
assert_equal "" "$out" "unknown agent_type emits nothing"
rm -rf "$tmp"

echo "=== inject-subagent-role-pointer: shared/examples agent_type is silent (not a role) ==="
tmp="$(mktemp -d)"
make_memrepo "$tmp"
out="$(printf '{"agent_type":"shared"}' | bash "$HOOK" "$tmp")"
assert_equal "" "$out" "agent_type 'shared' emits nothing despite top-level shared/MEMORY.md"
out="$(printf '{"agent_type":"examples"}' | bash "$HOOK" "$tmp")"
assert_equal "" "$out" "agent_type 'examples' emits nothing"
# Case variant: only bites on a case-insensitive filesystem (macOS APFS
# default), where Shared/MEMORY.md resolves to shared/MEMORY.md - trivially
# green on case-sensitive CI, red on a dev Mac without the tr fold.
out="$(printf '{"agent_type":"Shared"}' | bash "$HOOK" "$tmp")"
assert_equal "" "$out" "agent_type 'Shared' emits nothing (case-insensitive filesystems)"
rm -rf "$tmp"

echo "=== inject-subagent-role-pointer: traversal-shaped agent_type is silent ==="
tmp="$(mktemp -d)"
make_memrepo "$tmp"
out="$(printf '{"agent_type":"../developer"}' | bash "$HOOK" "$tmp")"
assert_equal "" "$out" "path-traversal agent_type emits nothing"
rm -rf "$tmp"

print_summary
