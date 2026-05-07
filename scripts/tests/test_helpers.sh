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

# Compute Claude Code's project hash (path → hash transform)
# Replicates whatever transform Claude Code uses; based on observation: /Users/foo/bar → -Users-foo-bar
compute_hash() {
  echo "$1" | sed 's|/|-|g'
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
