#!/usr/bin/env bash
# Shared assertion helpers for claude-personas test scripts.
# Source this in each test_*.sh file.

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Print colored output if terminal supports it
if [ -t 1 ]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  RESET=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; RESET=''
fi

assert_equal() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-assert_equal}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$expected" = "$actual" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}  PASS${RESET}: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$msg")
    echo "${RED}  FAIL${RESET}: $msg"
    echo "    expected: $expected"
    echo "    actual:   $actual"
  fi
}

assert_symlink() {
  local path="$1"
  local expected_target="$2"
  local msg="${3:-assert_symlink $path}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -L "$path" ]; then
    local actual_target
    actual_target="$(readlink "$path")"
    if [ "$actual_target" = "$expected_target" ]; then
      TESTS_PASSED=$((TESTS_PASSED + 1))
      echo "${GREEN}  PASS${RESET}: $msg"
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
      FAILED_TESTS+=("$msg")
      echo "${RED}  FAIL${RESET}: $msg"
      echo "    expected target: $expected_target"
      echo "    actual target:   $actual_target"
    fi
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$msg")
    echo "${RED}  FAIL${RESET}: $msg"
    echo "    path is not a symlink (or doesn't exist): $path"
  fi
}

assert_exists() {
  local path="$1"
  local msg="${2:-assert_exists $path}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -e "$path" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}  PASS${RESET}: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$msg")
    echo "${RED}  FAIL${RESET}: $msg"
  fi
}

assert_not_exists() {
  local path="$1"
  local msg="${2:-assert_not_exists $path}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}  PASS${RESET}: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$msg")
    echo "${RED}  FAIL${RESET}: $msg"
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-assert_contains}"
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$haystack" in
    *"$needle"*)
      TESTS_PASSED=$((TESTS_PASSED + 1))
      echo "${GREEN}  PASS${RESET}: $msg"
      ;;
    *)
      TESTS_FAILED=$((TESTS_FAILED + 1))
      FAILED_TESTS+=("$msg")
      echo "${RED}  FAIL${RESET}: $msg"
      echo "    expected to find: $needle"
      echo "    in: $haystack"
      ;;
  esac
}

assert_exit_nonzero() {
  local msg="${1:-command should exit non-zero}"
  shift || true
  TESTS_RUN=$((TESTS_RUN + 1))
  if ! "$@" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}  PASS${RESET}: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$msg")
    echo "${RED}  FAIL${RESET}: $msg"
  fi
}

# Compute Claude Code's project hash (path → hash transform).
# Claude Code replaces both "/" and "." with "-" — verified by inspecting
# ~/.claude/projects/<hash>/<sessionid>.jsonl cwd field on macOS:
#   /private/var/folders/x.y/test → -private-var-folders-x-y-test
# Caller must pre-resolve symlinks (use `cd $path && pwd -P`).
compute_hash() {
  echo "$1" | tr '/.' '-'
}

# Print test summary; exit non-zero if any failed
print_summary() {
  echo ""
  echo "----"
  echo "Tests run:    $TESTS_RUN"
  echo "${GREEN}Passed:${RESET}       $TESTS_PASSED"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    echo "${RED}Failed:${RESET}       $TESTS_FAILED"
    echo ""
    echo "Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
      echo "  - $t"
    done
    return 1
  fi
  return 0
}

# --- v3 clone-test fixtures ---

# Create a fake memory repo + bare project repo for clone-based tests.
# Layout produced at $1:
#   $1/memory-repo/                  (working clone-personas-style repo)
#     .git/                          (real git repo with one commit)
#     developer/MEMORY.md
#     pm/MEMORY.md
#     scientist/MEMORY.md
#     shared/MEMORY.md
#     <role>/shared -> ../shared      (symlink in each role)
#   $1/project-repo.git/             (bare repo to clone from)
make_clone_test_fixture() {
  local base="$1"
  mkdir -p "$base"

  # Bare project repo to clone from
  git init --bare --quiet "$base/project-repo.git"
  # Seed the bare repo with one commit
  local seed; seed="$(mktemp -d)"
  ( cd "$seed" && git init --quiet && \
    echo "# project" > README.md && \
    git add README.md && \
    git -c user.email=test@x -c user.name=Test commit --quiet -m "init" && \
    git remote add origin "$base/project-repo.git" && \
    git push --quiet origin master 2>/dev/null || git push --quiet origin main 2>/dev/null )
  rm -rf "$seed"

  # Memory repo
  mkdir -p "$base/memory-repo"
  ( cd "$base/memory-repo" && git init --quiet )
  for role in developer pm scientist designer; do
    mkdir -p "$base/memory-repo/$role"
    printf "# Memory Index — %s\n" "$role" > "$base/memory-repo/$role/MEMORY.md"
    ( cd "$base/memory-repo/$role" && ln -s ../shared shared )
  done
  mkdir -p "$base/memory-repo/shared"
  printf "# Shared Memory Index\n" > "$base/memory-repo/shared/MEMORY.md"
  ( cd "$base/memory-repo" && \
    git -c user.email=test@x -c user.name=Test add . && \
    git -c user.email=test@x -c user.name=Test commit --quiet -m "init memory repo" )
}

# Remove the fixture directory created by make_clone_test_fixture.
cleanup_clone_test_fixture() {
  local base="$1"
  rm -rf "$base"
}
