# Changelog

## [frozen] - 2026-07-07

This file versioned the template era and ends here.
The repo is now an installable framework: payload changes are tracked in [framework/CHANGELOG.md](framework/CHANGELOG.md) against `framework/v*` tags (a disjoint namespace from the template-era `v1.0`-`v3.1.0` tags, which remain).
Post-switch changes outside the payload (examples, docs) are not changelogged; git history suffices.

## [3.1.0] — 2026-05-18

### Breaking changes

- **Role-memory symlink moves from `<clone>/memory` to `<clone>/.claude/memory`** for consistency with Claude Code's own `.claude/` namespace.
- `.gitignore` entry written by `init-clone.sh` is now `/.claude/memory/` instead of `/memory/`.

### Migration

- For each existing v3.0 role clone, run `scripts/init-clone.sh --force <role>` from inside the sister `claude-personas-<app>/` memory repo. The script detects the legacy layout, backs up the old root symlink to `<clone>/.claude/memory.legacy-backup-<timestamp>`, removes the stale `/memory/` line from `.gitignore`, and writes the new layout. See [MIGRATION.md](MIGRATION.md) for details.

## [3.0.0] — 2026-05-15

### Breaking changes

v3 replaces v2's git-worktree + hash-derived-symlink mechanism with
**independent project-repo clones** per role, wired by a single `memory/`
symlink in each clone pointing into a sibling memory repo.

**Why**: Claude Code v2.1.49+ (Feb 2026) intentionally collapses all
worktrees of one repo into the main repo's auto-memory hash dir. v2's
per-worktree symlinks silently never load on current Claude Code.

**Architecture**: each role gets a real `git clone` at a sibling path
(e.g. `my-app/`, `my-app-pm/`, `my-app-scientist/`). The Developer role
claims the no-suffix path by default; other roles get `-<role>` suffixes.
Override the claimer with `--main` or `.claude-personas/main-role.txt`.

Pinned `v2-final` git tag preserves v2 for users on older Claude Code.

### Added

- `scripts/init-clone.sh` replaces v2's `scripts/init-worktree.sh`.
- `scientist/` role skeleton + `examples/scientist/` ported patterns.
- `MIGRATION.md` with six-step v2-to-v3 walkthrough.
- `.claude-personas/project.txt` (gitignored) persists project URL after first init.
- `.claude-personas/main-role.txt` (tracked, optional) overrides default no-suffix claimer.

### Changed

- `scripts/list-roles.sh` rewritten to walk sibling clone dirs instead of
  `~/.claude/projects/<hash>/memory` paths.
- `README.md` and `CONVENTIONS.md` rewritten for the clones model.
- Role MEMORY.md boilerplate updated to drop v2-specific commentary.

### Removed

- `scripts/init-worktree.sh` (preserved in the `v2-final` tag).
- `scripts/tests/test_init_worktree.sh` (preserved in the `v2-final` tag).
- v2 `autoMemoryDirectory` references in docs.

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
