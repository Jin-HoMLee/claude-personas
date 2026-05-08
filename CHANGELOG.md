# Changelog

## [2.0.0] — 2026-05-08

### Breaking changes

v2 replaces v1's `autoMemoryDirectory` mechanism with native filesystem symlinks
at Claude Code's per-project hash-derived memory paths.

**Why**: project-level `autoMemoryDirectory` in `.claude/settings.local.json` is
silently ignored by Claude Code (see [issue #55801](https://github.com/anthropics/claude-code/issues/55801)).
v1 was non-functional as documented.

**Architecture**: per-project clones of claude-personas. Each role's worktree has
its memory dir at `~/.claude/projects/<role-hash>/memory/` symlinked to the clone's
role folder. The clone's `shared/` is a symlink to the project's main-repo hash dir.

### Removed

- `settings.local.json.example`
- `CLAUDE.local.md.example`
- "Single clone serves many projects" pattern (v3 candidate)

### Added

- `CHANGELOG.md` (this file)
- `scripts/list-roles.sh` — audit which worktrees are wired to which roles
- `scripts/tests/` — test scripts and runner for init script + list-roles
- v2 init script: full rewrite using symlink mechanism

### Manual upgrade from v1

1. In each role's project worktree, delete `.claude/settings.local.json` and
   `CLAUDE.local.md`, and remove their entries from `.gitignore`.
2. Re-run `scripts/init-worktree.sh <role> <worktree-path>` from your project repo.

No memory data is lost; only the wiring mechanism changes.

## [1.0] — 2026-04-30

Initial public release of claude-personas. v1 architecture used `autoMemoryDirectory`
in `.claude/settings.local.json` (subsequently discovered to be silently ignored).
Tagged before v2 development as `v1.0` for archival.
