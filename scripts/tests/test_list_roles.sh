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
mkdir -p "$tmp/home"
mv "$tmp/memory-repo" "$tmp/claude-personas-myapp"

# Wire 2 roles
( cd "$tmp/claude-personas-myapp" && \
  HOME="$tmp/home" bash "$INIT_CLONE" developer --project-url "$tmp/project-repo.git" )
( cd "$tmp/claude-personas-myapp" && \
  HOME="$tmp/home" bash "$INIT_CLONE" pm --project-url "$tmp/project-repo.git" )

# Break the pm memory symlink (simulate drift)
rm "$tmp/myapp-pm/.claude/memory"
ln -s /nonexistent "$tmp/myapp-pm/.claude/memory"

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

# --- list-roles reports dirty git state ---
echo "=== test_list_roles reports dirty git state ==="
tmp2="$(mktemp -d)"
make_clone_test_fixture "$tmp2"
mkdir -p "$tmp2/home"
mv "$tmp2/memory-repo" "$tmp2/claude-personas-myapp"

# Wire developer; then dirty the clone by modifying a tracked file
( cd "$tmp2/claude-personas-myapp" && \
  HOME="$tmp2/home" bash "$INIT_CLONE" developer --project-url "$tmp2/project-repo.git" )
echo "modification" >> "$tmp2/myapp/README.md"

output="$( cd "$tmp2/claude-personas-myapp" && bash "$LIST_ROLES" 2>&1 || true )"

if echo "$output" | grep -qE "developer.*dirty"; then
  echo "  PASS: developer reported dirty"
else
  echo "  FAIL: developer not reported dirty"
  echo "$output"
  exit 1
fi

cleanup_clone_test_fixture "$tmp2"

# --- list-roles errors when memory repo name lacks claude-personas- prefix ---
echo "=== test_list_roles non-claude-personas-* repo name errors ==="
tmp3="$(mktemp -d)"
make_clone_test_fixture "$tmp3"
# Leave memory-repo name as-is (does NOT start with claude-personas-)

if ( cd "$tmp3/memory-repo" && bash "$LIST_ROLES" ) 2>/dev/null; then
  echo "  FAIL: list-roles should exit non-zero for non-claude-personas-* repo name"
  exit 1
else
  echo "  PASS: list-roles errored on non-claude-personas-* repo name"
fi

cleanup_clone_test_fixture "$tmp3"

# --- v3.1 direct-symlink clone still detected (fallback branch) ---
echo "=== test_list_roles v3.1 direct-symlink clone still detected ==="
tmp4="$(mktemp -d)"
make_clone_test_fixture "$tmp4"
mv "$tmp4/memory-repo" "$tmp4/claude-personas-myapp"

# Hand-plant a v3.1-shaped clone: direct .claude/memory symlink, NO .agents/memory.
git clone --quiet "$tmp4/project-repo.git" "$tmp4/myapp"
mkdir -p "$tmp4/myapp/.claude"
ln -s "../../claude-personas-myapp/developer" "$tmp4/myapp/.claude/memory"

output="$( cd "$tmp4/claude-personas-myapp" && bash "$LIST_ROLES" 2>&1 || true )"
if echo "$output" | grep -q "developer.*OK"; then
  echo "  PASS: v3.1 developer clone reported OK via fallback"
else
  echo "  FAIL: v3.1 developer clone not detected"
  echo "$output"
  exit 1
fi

cleanup_clone_test_fixture "$tmp4"

# --- Memory Manager self-mount audited like any other role (issue #39) ---
echo "=== test_list_roles memory_manager self-mount detected ==="
tmp5="$(mktemp -d)"
make_clone_test_fixture "$tmp5"
mkdir -p "$tmp5/home"
mv "$tmp5/memory-repo" "$tmp5/claude-personas-myapp"

# Add the memory_manager role dir and wire the memory repo itself via --self.
mkdir -p "$tmp5/claude-personas-myapp/memory_manager"
printf "# Memory Index - memory_manager\n" > "$tmp5/claude-personas-myapp/memory_manager/MEMORY.md"
( cd "$tmp5/claude-personas-myapp/memory_manager" && ln -s ../shared shared )
( cd "$tmp5/claude-personas-myapp" && \
  git -c user.email=t@x -c user.name=T add -A && \
  git -c user.email=t@x -c user.name=T commit --quiet -m "add memory_manager role" )
( cd "$tmp5/claude-personas-myapp" && \
  HOME="$tmp5/home" bash "$INIT_CLONE" --self ) >/dev/null 2>&1 || [ $? -eq 2 ]

# Wire a normal role too: the self-mount candidate must not shadow clone audits.
( cd "$tmp5/claude-personas-myapp" && \
  HOME="$tmp5/home" bash "$INIT_CLONE" developer --project-url "$tmp5/project-repo.git" ) >/dev/null 2>&1 || [ $? -eq 2 ]

output="$( cd "$tmp5/claude-personas-myapp" && bash "$LIST_ROLES" 2>&1 || true )"

if echo "$output" | grep -q "memory_manager.*OK"; then
  echo "  PASS: memory_manager self-mount reported OK"
else
  echo "  FAIL: memory_manager self-mount not reported OK"
  echo "$output"
  exit 1
fi
if echo "$output" | grep -q "developer.*OK"; then
  echo "  PASS: developer clone still reported OK alongside self-mount"
else
  echo "  FAIL: developer clone not reported OK alongside self-mount"
  echo "$output"
  exit 1
fi

cleanup_clone_test_fixture "$tmp5"

print_summary
