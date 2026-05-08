#!/usr/bin/env bash
# Tests for scripts/list-roles.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERSONAS_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIST_SCRIPT="$PERSONAS_ROOT/scripts/list-roles.sh"

source "$SCRIPT_DIR/test_helpers.sh"

ORIGINAL_HOME="$HOME"

# ---- Test 1: list-roles outputs nothing when no symlinks present ----
echo "Test 1: empty output when no role symlinks"

tmp="$(mktemp -d -t list-roles-empty-XXXX)"
export HOME="$tmp"
mkdir -p "$HOME/.claude/projects"

output="$(bash "$LIST_SCRIPT" 2>&1 || true)"
echo "$output" | grep -qi "no" || echo "$output" | grep -qE "0 |empty|none"
status=$?
assert_equal "0" "$status" "list-roles handles empty state without crashing"

rm -rf "$tmp"
export HOME="$ORIGINAL_HOME"

# ---- Test 2: list-roles reports a healthy symlink ----
echo ""
echo "Test 2: reports healthy symlink with role"

# The unhash in list-roles.sh is intentionally lossy on dashes AND dots
# (compute_hash replaces both / and . with -, so the reverse can't recover
# which char each "-" was). The display is for human auditing — we test
# that the role name appears, not exact path round-trip.
tmp="$(mktemp -d)"
tmp="$(cd "$tmp" && pwd -P)"
export HOME="$tmp"
mkdir -p "$HOME/.claude/projects"

# Fake clone + role
mkdir -p "$tmp/clone/pm"
echo "# pm" > "$tmp/clone/pm/MEMORY.md"

# Hash a worktree path (path doesn't need to exist — list-roles only reads
# the hash dir name and the symlink target).
hash="$(compute_hash "$tmp/projectpm")"
mkdir -p "$HOME/.claude/projects/$hash"
ln -s "$tmp/clone/pm/" "$HOME/.claude/projects/$hash/memory"

output="$(bash "$LIST_SCRIPT" 2>&1 || true)"
echo "$output" | grep -q "pm"
status=$?
assert_equal "0" "$status" "list-roles output mentions role 'pm'"

rm -rf "$tmp"
export HOME="$ORIGINAL_HOME"

# ---- Test 3: list-roles flags broken symlinks ----
echo ""
echo "Test 3: broken symlinks flagged as broken/dead"

tmp="$(mktemp -d -t list-roles-broken-XXXX)"
export HOME="$tmp"
mkdir -p "$HOME/.claude/projects"

worktree_abs="$tmp/project-pm"
hash="$(compute_hash "$worktree_abs")"
mkdir -p "$HOME/.claude/projects/$hash"
# Create a symlink to a non-existent target
ln -s "$tmp/nonexistent/pm/" "$HOME/.claude/projects/$hash/memory"

output="$(bash "$LIST_SCRIPT" 2>&1 || true)"
echo "$output" | grep -qiE "broken|dead|missing|invalid"
status=$?
assert_equal "0" "$status" "broken symlink flagged in output"

rm -rf "$tmp"
export HOME="$ORIGINAL_HOME"

print_summary
exit $?
