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

assert_matches() {
  local haystack="$1"
  local regex="$2"
  local msg="${3:-assert_matches}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$haystack" | grep -qE "$regex"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo "${GREEN}  PASS${RESET}: $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$msg")
    echo "${RED}  FAIL${RESET}: $msg"
    echo "    expected to match: $regex"
    echo "    in: $haystack"
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

# --- doctor.sh user-tier fixture ---

# Create a user-tier doctor fixture: a repo dir with AGENTS.md, a flat memory
# index, and a valid user-tier manifest declaring all three adapters, plus an
# empty sibling dir for tests to point HOME at. Every $HOME-relative doctor
# check then stays inside $1/home - never touches the real home.
# Layout produced at $1:
#   $1/user-repo/AGENTS.md
#   $1/user-repo/.agents/memory/MEMORY.md
#   $1/user-repo/.agents/manifest   (manifest_version=1, topology=user-tier,
#                                    memory_layout=flat, all 3 adapters)
#   $1/home/                        (empty; the fixture $HOME)
make_user_tier_fixture() {
  local base="$1"
  mkdir -p "$base/user-repo/.agents/memory" "$base/home"
  echo "# AGENTS" > "$base/user-repo/AGENTS.md"
  echo "# Memory Index" > "$base/user-repo/.agents/memory/MEMORY.md"
  cat > "$base/user-repo/.agents/manifest" <<'EOF'
manifest_version=1
topology=user-tier
memory_layout=flat
adapter=claude-code
adapter=codex
adapter=opencode
EOF
}

# --- doctor.sh embedded fixture ---

# Create an embedded-topology doctor fixture: a single repo carrying .agents/
# alongside its own project code, pre-wired correctly on every adapter (this
# is what generalizes cerebrum's sync.sh - see doctor.sh's
# topology_embedded_checks). Only the external CC auto-memory hop is left
# unwired, since its path is derived from this fixture's own (mktemp-random)
# absolute location and can't be baked in ahead of time - callers run
# doctor.sh once in fix mode to create it before treating the fixture as the
# clean baseline.
# Layout produced at $1:
#   $1/embedded-repo/AGENTS.md
#   $1/embedded-repo/CLAUDE.md -> AGENTS.md
#   $1/embedded-repo/.agents/memory/MEMORY.md
#   $1/embedded-repo/.agents/hooks/hook-a.sh, hook-b.sh   (executable stubs)
#   $1/embedded-repo/.agents/skills/                       (empty dir)
#   $1/embedded-repo/.claude/memory -> ../.agents/memory
#   $1/embedded-repo/.claude/skills -> ../.agents/skills
#   $1/embedded-repo/.claude/settings.json    (wires hook-a via $CLAUDE_PROJECT_DIR)
#   $1/embedded-repo/.codex/hooks.json        (wires hook-a + hook-b for THIS path)
#   $1/embedded-repo/opencode.json            (instructions has the memory index)
#   $1/embedded-repo/.agents/manifest         (manifest_version=1, topology=embedded,
#                                               memory_layout=flat, all 3 adapters,
#                                               claude_hook=hook-a, codex_hook x2,
#                                               skills_mount=true)
#   $1/home/                                  (empty; the fixture $HOME)
make_embedded_fixture() {
  local base="$1"
  local repo="$base/embedded-repo"
  mkdir -p "$repo/.agents/memory" "$repo/.agents/hooks" "$repo/.agents/skills" \
    "$repo/.claude" "$repo/.codex" "$base/home"

  echo "# AGENTS" > "$repo/AGENTS.md"
  ( cd "$repo" && ln -s AGENTS.md CLAUDE.md )
  echo "# Memory Index" > "$repo/.agents/memory/MEMORY.md"

  cat > "$repo/.agents/hooks/hook-a.sh" <<'EOF'
#!/usr/bin/env bash
echo hook-a
EOF
  cat > "$repo/.agents/hooks/hook-b.sh" <<'EOF'
#!/usr/bin/env bash
echo hook-b
EOF
  chmod +x "$repo/.agents/hooks/hook-a.sh" "$repo/.agents/hooks/hook-b.sh"

  ( cd "$repo/.claude" && ln -s ../.agents/memory memory && ln -s ../.agents/skills skills )

  cat > "$repo/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR/.agents/hooks/hook-a.sh\"",
            "timeout": 10,
            "statusMessage": "Running hook-a.sh…"
          }
        ]
      }
    ]
  }
}
EOF

  local root_abs
  root_abs="$(cd "$repo" && pwd -P)"
  cat > "$repo/.codex/hooks.json" <<EOF
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "'$root_abs/.agents/hooks/hook-a.sh'",
            "timeout": 10,
            "statusMessage": "Running hook-a.sh…"
          },
          {
            "type": "command",
            "command": "'$root_abs/.agents/hooks/hook-b.sh'",
            "timeout": 10,
            "statusMessage": "Running hook-b.sh…"
          }
        ]
      }
    ]
  }
}
EOF

  cat > "$repo/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": [".agents/memory/MEMORY.md"]
}
EOF

  cat > "$repo/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
adapter=claude-code
adapter=codex
adapter=opencode
claude_hook=.agents/hooks/hook-a.sh
codex_hook=.agents/hooks/hook-a.sh
codex_hook=.agents/hooks/hook-b.sh
skills_mount=true
EOF
}

# --- framework payload staging (shared by init-clone/doctor/inject tests) ---

# Absolute path to the repo's real inject script. test_helpers.sh lives in
# framework/tools/tests/, so the hooks dir is two levels up + /hooks.
INJECT_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../hooks" && pwd)/inject-role-index.sh"

# stage_inject_script <memrepo>
# Places the inject script at the installed-payload location the wiring
# expects (<memrepo>/.agents/hooks/lib/), executable.
stage_inject_script() {
  mkdir -p "$1/.agents/hooks/lib"
  cp "$INJECT_SRC" "$1/.agents/hooks/lib/inject-role-index.sh"
  chmod +x "$1/.agents/hooks/lib/inject-role-index.sh"
}

# --- installer fixtures (test_install.sh, doctor staleness tests) ---

# make_framework_fixture <dir>
# Synthetic framework clone at <dir>/fw: 3-entry FILES (tool, hook, skill),
# one commit, annotated tag framework/v1.
make_framework_fixture() {
  local fw="$1/fw"
  mkdir -p "$fw/framework/tools" "$fw/framework/hooks" "$fw/framework/skills/demo-skill"
  printf '#!/usr/bin/env bash\necho tool-a v1\n' > "$fw/framework/tools/tool-a.sh"
  chmod +x "$fw/framework/tools/tool-a.sh"
  printf '#!/usr/bin/env bash\necho hook-x v1\n' > "$fw/framework/hooks/hook-x.sh"
  chmod +x "$fw/framework/hooks/hook-x.sh"
  printf -- '---\nname: demo-skill\n---\nv1\n' > "$fw/framework/skills/demo-skill/SKILL.md"
  cat > "$fw/framework/FILES" <<'EOF'
# fixture FILES
framework/tools/tool-a.sh -> .agents/tools/tool-a.sh
framework/hooks/hook-x.sh -> .agents/hooks/lib/hook-x.sh
framework/skills/demo-skill/SKILL.md -> .agents/skills/demo-skill/SKILL.md
EOF
  ( cd "$fw" && git init --quiet \
    && git -c user.email=t@x -c user.name=T add -A \
    && git -c user.email=t@x -c user.name=T commit --quiet -m "fw v1" \
    && git -c user.email=t@x -c user.name=T tag -a framework/v1 -m v1 )
}

# advance_framework_fixture <dir>
# v2: tool-a content changes, tool-b appears in FILES. hook-x stays.
advance_framework_fixture() {
  local fw="$1/fw"
  printf '#!/usr/bin/env bash\necho tool-a v2\n' > "$fw/framework/tools/tool-a.sh"
  printf '#!/usr/bin/env bash\necho tool-b v2\n' > "$fw/framework/tools/tool-b.sh"
  chmod +x "$fw/framework/tools/tool-b.sh"
  cat > "$fw/framework/FILES" <<'EOF'
framework/tools/tool-a.sh -> .agents/tools/tool-a.sh
framework/tools/tool-b.sh -> .agents/tools/tool-b.sh
framework/hooks/hook-x.sh -> .agents/hooks/lib/hook-x.sh
framework/skills/demo-skill/SKILL.md -> .agents/skills/demo-skill/SKILL.md
EOF
  ( cd "$fw" && git -c user.email=t@x -c user.name=T add -A \
    && git -c user.email=t@x -c user.name=T commit --quiet -m "fw v2" \
    && git -c user.email=t@x -c user.name=T tag -a framework/v2 -m v2 )
}

# drop_hook_framework_fixture <dir>
# v3: hook-x leaves FILES (and the tree) - the orphan case.
drop_hook_framework_fixture() {
  local fw="$1/fw"
  rm "$fw/framework/hooks/hook-x.sh"
  cat > "$fw/framework/FILES" <<'EOF'
framework/tools/tool-a.sh -> .agents/tools/tool-a.sh
framework/tools/tool-b.sh -> .agents/tools/tool-b.sh
framework/skills/demo-skill/SKILL.md -> .agents/skills/demo-skill/SKILL.md
EOF
  ( cd "$fw" && git -c user.email=t@x -c user.name=T add -A \
    && git -c user.email=t@x -c user.name=T commit --quiet -m "fw v3" \
    && git -c user.email=t@x -c user.name=T tag -a framework/v3 -m v3 )
}

# make_instance_fixture <dir> <name>
# Embedded-topology instance with a committed manifest and a memory canary
# that install/sync must never touch.
make_instance_fixture() {
  local inst="$1/$2"
  mkdir -p "$inst/.agents/memory"
  printf '# Memory Index\n- canary\n' > "$inst/.agents/memory/MEMORY.md"
  cat > "$inst/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
EOF
  ( cd "$inst" && git init --quiet \
    && git -c user.email=t@x -c user.name=T add -A \
    && git -c user.email=t@x -c user.name=T commit --quiet -m "instance init" )
}
