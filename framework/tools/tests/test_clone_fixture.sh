#!/usr/bin/env bash
# Test that make_clone_test_fixture creates a valid memory repo + bare project repo.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"

echo "=== test_clone_fixture ==="

tmp="$(mktemp -d)"
make_clone_test_fixture "$tmp"

assert_exists "$tmp/memory-repo" "memory repo created"
assert_exists "$tmp/memory-repo/developer/MEMORY.md" "developer role exists"
assert_exists "$tmp/memory-repo/pm/MEMORY.md" "pm role exists"
assert_exists "$tmp/memory-repo/scientist/MEMORY.md" "scientist role exists"
assert_exists "$tmp/memory-repo/shared/MEMORY.md" "shared/MEMORY.md exists"
assert_symlink "$tmp/memory-repo/pm/shared" "../shared" "pm/shared symlink"
assert_exists "$tmp/project-repo.git/HEAD" "bare project repo exists"

cleanup_clone_test_fixture "$tmp"
assert_not_exists "$tmp" "fixture removed after cleanup"

print_summary
