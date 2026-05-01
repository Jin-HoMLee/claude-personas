# Memory Index — PM

<!--
  Usage: set autoMemoryDirectory to the absolute path of this folder in
  .claude/settings.local.json. See settings.local.json.example and CONVENTIONS.md.
-->

## Always in effect (no file read required)

- **Shared memory path:** This worktree's `CLAUDE.local.md` (loaded automatically by
  Claude Code) contains the absolute path to your role's memory directory. Use that
  prefix with the Read tool — shared files are at `<that-path>/shared/<filename>`.
  <!-- src: shared/feedback_role_memory_boundary.md -->

## Shared (all sessions)

- [Shared memory index](shared/MEMORY.md) — All cross-role conventions

## Role: PM

<!-- Add links to role-specific memory files. Example:
- [Check board first](feedback_check_board.md) — query live board at session start, not memory snapshots
-->
