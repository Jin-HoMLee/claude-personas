# Memory Index — Developer

<!--
  Usage: this folder is reached via a symlink at ~/.claude/projects/<hash>/memory
  created by scripts/init-worktree.sh — no per-project config needed. Claude Code
  auto-loads files in this directory at every session start. See CONVENTIONS.md.
-->

## Always in effect (no file read required)

- **Shared memory path:** This folder is symlinked from `~/.claude/projects/<hash>/memory`
  by `scripts/init-worktree.sh` (loaded automatically at session start). Shared files
  are at `shared/<filename>` relative to this directory — use the Read tool with that path.
  <!-- src: shared/feedback_role_memory_boundary.md -->

<!-- Add more inline rules here. Use drift annotations: <!-- src: ... --> -->

## Shared (all sessions)

- [Shared memory index](shared/MEMORY.md) — All cross-role conventions

## Role: Developer

<!-- Add links to role-specific memory files. Example:
- [Test before PR](feedback_test_before_pr.md) — always run tests before opening a PR
-->
