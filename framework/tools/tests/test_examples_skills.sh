#!/usr/bin/env bash
# examples/skills is copy-once starter content, not framework payload.
# This test proves the demo skill exists and keeps the FILES boundary intact.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

README="$REPO_ROOT/examples/skills/README.md"
SKILL="$REPO_ROOT/examples/skills/morning-routine/SKILL.md"
FILES="$REPO_ROOT/framework/FILES"

echo "=== test_examples_skills: example skill files exist ==="
assert_exists "$README" "examples/skills README exists"
assert_exists "$SKILL" "morning-routine skill exists"

echo "=== test_examples_skills: morning-routine skill frontmatter ==="
if [ -f "$SKILL" ]; then
  frontmatter="$(sed -n '1,8p' "$SKILL")"
  assert_contains "$frontmatter" "name: morning-routine" "skill frontmatter has expected name"
  assert_contains "$frontmatter" "description: " "skill frontmatter has description"
fi

echo "=== test_examples_skills: examples stay out of framework/FILES ==="
bad="$(awk -F' -> ' '!/^#/ && NF==2 && $1 ~ /^examples\// {print}' "$FILES" | wc -l | tr -d ' ')"
assert_equal "0" "$bad" "no examples/ entry in FILES"

print_summary
