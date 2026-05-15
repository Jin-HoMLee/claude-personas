#!/usr/bin/env bash
# Test list-roles.sh against a v3 clones-pivot layout.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
LIST_ROLES="$(cd "$SCRIPT_DIR/.." && pwd)/list-roles.sh"
INIT_CLONE="$(cd "$SCRIPT_DIR/.." && pwd)/init-clone.sh"

echo "=== test_list_roles v3 layout ==="

tmp="$(mktemp -d)"
make_clone_test_fixture "$tmp"
mv "$tmp/memory-repo" "$tmp/claude-personas-myapp"

# Wire 2 roles
( cd "$tmp/claude-personas-myapp" && \
  bash "$INIT_CLONE" developer --project-url "$tmp/project-repo.git" )
( cd "$tmp/claude-personas-myapp" && \
  bash "$INIT_CLONE" pm --project-url "$tmp/project-repo.git" )

# Break the pm memory symlink (simulate drift)
rm "$tmp/myapp-pm/memory"
ln -s /nonexistent "$tmp/myapp-pm/memory"

# Run list-roles.sh
output="$( cd "$tmp/claude-personas-myapp" && bash "$LIST_ROLES" 2>&1 || true )"

# Should mention developer clone as healthy
if echo "$output" | grep -q "developer.*OK"; then
  echo "  PASS: developer reported OK"
else
  echo "  FAIL: developer not reported OK"
  echo "$output"
  exit 1
fi

# Should mention pm as broken
if echo "$output" | grep -qiE "pm.*broken|broken.*pm"; then
  echo "  PASS: pm reported BROKEN"
else
  echo "  FAIL: pm not reported broken"
  echo "$output"
  exit 1
fi

# Should mention scientist as missing
if echo "$output" | grep -qiE "scientist.*missing|missing.*scientist|no clone"; then
  echo "  PASS: scientist reported missing"
else
  echo "  FAIL: scientist not reported missing"
  echo "$output"
  exit 1
fi

cleanup_clone_test_fixture "$tmp"
print_summary
