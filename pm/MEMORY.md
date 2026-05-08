# Memory Index — PM

<!--
  Usage: this folder is reached via a symlink at ~/.claude/projects/<hash>/memory
  created by scripts/init-worktree.sh — no per-project config needed. See CONVENTIONS.md.
-->

## Always in effect (no file read required)

- **Shared memory path:** This folder is symlinked from `~/.claude/projects/<hash>/memory`
  by `scripts/init-worktree.sh` (loaded automatically at session start). Shared files
  are at `shared/<filename>` relative to this directory — use the Read tool with that path.
  <!-- src: shared/feedback_role_memory_boundary.md -->

## Shared (all sessions)

- [Shared memory index](shared/MEMORY.md) — All cross-role conventions

## Role: PM

<!-- Add links to role-specific memory files. Example:
- [Check board first](feedback_check_board.md) — query live board at session start, not memory snapshots
-->
