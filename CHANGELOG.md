# Changelog

## [2.0.1] — 2026-05-09

### Fixed

- Test scaffolding silently polluted the developer's real `~/.claude/projects/`
  directory. `make_test_env` ran inside `$()` command substitution which forks
  a subshell, so its `export HOME="$tmp/home"` evaporated when the subshell
  exited and `init-worktree.sh` then ran with the real `$HOME`. Each
  `run_all.sh` left ~18 orphan hash dirs in the developer's home. Tests still
  passed (the bug doesn't break correctness, only isolation), but it could
  collide with real session data over time.

  Fix: split responsibility cleanly. The renamed `make_test_fixture` /
  `cleanup_test_fixture` helpers do filesystem setup/teardown only; callers
  export and restore `HOME` in their own (parent) scope around each test.
  `run_all.sh` now adds zero entries to the developer's real home.

### Added

- 5 deferred coverage tests for `init-worktree.sh` edge cases identified in
  the v2.0.0 PR review: `--force` on a mispointing symlink, custom branch
  name (3rd argument), worktree path already exists, `--force` with an empty
  memory dir, and re-init while worktree is still mounted.

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
2. Re-run `scripts/init-worktree.sh --force <role> <worktree-path>` from your
   project repo. The `--force` flag is needed because v1 users who ran Claude
   sessions in the worktree will have content at `~/.claude/projects/<hash>/memory/`
   (Claude Code wrote there because v1's `autoMemoryDirectory` was silently
   ignored). `--force` backs up that directory to `memory.backup-<date>/` next
   to it before installing the symlink — no memory data is lost; only the
   wiring mechanism changes.

## [1.0] — 2026-04-30

Initial public release of claude-personas. v1 architecture used `autoMemoryDirectory`
in `.claude/settings.local.json` (subsequently discovered to be silently ignored).
Tagged before v2 development as `v1.0` for archival.
