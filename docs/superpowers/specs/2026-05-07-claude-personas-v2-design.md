# claude-personas v2 — Design

**Date**: 2026-05-07
**Status**: Approved (ready for implementation planning)
**Author**: Jin-Ho Lee (with Claude Code)

## Background

`claude-personas` v1 ships per-role memory directories (`developer/`, `pm/`, `designer/`, `shared/`) and wires each project worktree to the matching role via Claude Code's `autoMemoryDirectory` setting in project-level `.claude/settings.local.json`.

That setting has been silently ignored at project level since at least 2026-03-20 (see [issue #55801](https://github.com/anthropics/claude-code/issues/55801) and related #36636, #39204, #46701, #49995). Empirically:

- Project-level `autoMemoryDirectory` in `.claude/settings.local.json` is silently dropped — system prompt reports the default `~/.claude/projects/<hash>/memory/` path
- User-level `autoMemoryDirectory` in `~/.claude/settings.json` IS honored, but as a *literal* path with no per-project sub-structure — all projects collide in one flat directory

In short: there is no working configuration that lets multiple projects each have their own memory directory via `autoMemoryDirectory`. v1's documented pattern is non-functional. v1 only continues to work in practice because of a custom `CLAUDE.local.md` + skill-based workaround that bypasses the setting entirely.

This spec defines v2: replace `autoMemoryDirectory` with native filesystem symlinks at Claude Code's existing per-project hash-derived memory paths. No reliance on Claude Code settings beyond defaults.

## Decisions made during brainstorming

1. **Scope**: mechanism swap + cleanup. Not a full structural rethink.
2. **Memory location**: each role's memory dir at Claude Code's native `~/.claude/projects/<hash>/memory/` is symlinked into a `claude-personas` clone.
3. **Release strategy**: replace v1 — tag old as `v1.0`, merge v2 as new `main`.
4. **Repo strategy**: claude-personas is cloned **once per project** (not once globally as in v1).
5. **Shared layer**: per-project shared via project's main-repo hash dir, surfaced through a triple-symlink chain.
6. **Migration**: no dedicated migration script (no real v1 user base to support); short manual recipe in CHANGELOG.

## Architecture

### Topology

Per-project setup. The "main repo" is unused by any role — every role gets its own worktree.

```
~/projects/my-app/                       (main repo, no role uses this)
~/projects/my-app-dev/                   (developer worktree)
~/projects/my-app-pm/                    (PM worktree)
~/projects/my-app-scientist/             (scientist worktree)

~/projects/claude-personas-my-app/       (per-project clone of claude-personas)
├── developer/, pm/, scientist/          (role memories)
└── shared  →  ~/.claude/projects/<main-hash>/memory/   (symlink #3)

~/.claude/projects/<dev-hash>/memory   →   claude-personas-my-app/developer/   (symlink #1, set up by init)
~/.claude/projects/<pm-hash>/memory    →   claude-personas-my-app/pm/
~/.claude/projects/<sci-hash>/memory   →   claude-personas-my-app/scientist/

~/.claude/projects/<main-hash>/memory/   (real dir — actual shared content)
├── MEMORY.md
└── feedback_*.md
```

Inside each role folder: `<role>/shared  →  ../shared` (unchanged from v1; this is symlink #2 internal to the clone).

When Claude reads `<role>/shared/feedback_X.md` in a session running in any role's worktree, the path resolves through 3 hops to the real file at `~/.claude/projects/<main-hash>/memory/feedback_X.md`.

### Hash computation

Claude Code hashes each project by transforming the worktree's absolute path: replace each `/` with `-`. This is deterministic and used by Claude Code for default memory location.

The init script computes hashes the same way:
- `role-hash` = `<absolute-worktree-path>` with `/` → `-`
- `main-hash` = `<absolute-main-repo-path>` with `/` → `-`

Init script must use `pwd -P` to resolve symlinks and produce canonical paths.

### What's no longer needed in project worktrees

v1 placed two files per worktree, gitignored: `.claude/settings.local.json` (autoMemoryDirectory) and `CLAUDE.local.md` (path conveyance). v2 needs neither — the symlink at `<role-hash>/memory` is sufficient for Claude Code to load memory natively. Project worktrees stay completely clean.

## Implementation

### Init script (`scripts/init-worktree.sh`) — full rewrite

**Inputs** (unchanged from v1):
```sh
~/path/to/claude-personas-clone/scripts/init-worktree.sh <role> <worktree-path> [branch-name]
```

**Behavior**:
1. Validate: role exists in clone, target path free, current dir is a git repo, no existing same-named branch
2. `git worktree add <worktree-path> -b <branch-name>`
3. Compute `role-hash` from the new worktree's absolute path
4. Compute `main-hash` from the project repo's main path (the dir the script was run from)
5. `mkdir -p ~/.claude/projects/<role-hash>` (parent dir if needed)
6. Pre-existing-content check at `~/.claude/projects/<role-hash>/memory`:
   - Doesn't exist → proceed
   - Symlink to same target → no-op (idempotent)
   - Symlink to different target → error
   - Real dir with content → error, suggest `--force`
7. Create symlink: `ln -s <claude-personas-clone>/<role>/ ~/.claude/projects/<role-hash>/memory`
8. **First-time-only shared setup** (detected by `<claude-personas-clone>/shared` being a real folder, not a symlink):
   - `mkdir -p ~/.claude/projects/<main-hash>/memory/`
   - Move contents of `<claude-personas-clone>/shared/` into `~/.claude/projects/<main-hash>/memory/`
   - Remove the now-empty `<claude-personas-clone>/shared/` folder
   - Create symlink: `ln -s ~/.claude/projects/<main-hash>/memory/ <claude-personas-clone>/shared`
9. **Subsequent runs in the same clone**: verify `<claude-personas-clone>/shared` already symlinks to this project's `<main-hash>/memory/`. If it points elsewhere → error (clone is wired to a different project; user must use a fresh clone).

**`--force` flag**: backs up `~/.claude/projects/<role-hash>/memory/` to `<role-hash>/memory.backup-YYYYMMDD/` before creating symlink.

**No longer creates**: `.claude/settings.local.json`, `CLAUDE.local.md`, `.gitignore` additions in the project worktree.

### Companion script: `scripts/list-roles.sh`

Audit utility for discoverability (loss of in-project marker files makes manual audit harder).

- Scan `~/.claude/projects/*/memory` for symlinks
- For each symlink: report worktree path (reverse the hash transform), target role dir, healthy/broken status
- ~40 lines of bash

### Files removed from claude-personas repo

- `settings.local.json.example`
- `CLAUDE.local.md.example`

### Files heavily rewritten

- `README.md`:
  - New mental model: "clone per project, every role gets a worktree, main repo hosts shared"
  - Updated "How it works" diagram with triple-symlink topology
  - Quick start: clone → init first role → done
  - Worktree-per-role becomes documented standard (not optional)
  - One-line forward-pointer: "v3 may support a single clone across multiple projects via a project-tier structure"
  - Windows section: requires Developer Mode for symlinks; fallback is WSL (drop v1's "copy files" fallback)
  - FAQ updates: drop autoMemoryDirectory questions, add symlink troubleshooting
  - Brief upgrade-from-v1 paragraph
- `CONVENTIONS.md`:
  - Drop the `CLAUDE.local.md` row from "Three-system split" table → table becomes two-system
  - Rewrite "Why role-specific memory directories?" to describe the symlink mechanism instead of `autoMemoryDirectory`
- `scripts/init-worktree.sh`: full rewrite per spec above

### Files lightly modified

- Each role's `MEMORY.md` (`developer/`, `pm/`, `designer/`) — replace boilerplate references to `autoMemoryDirectory` and `settings.local.json` with v2 wording. Actual rules and structure unchanged.
- `shared/MEMORY.md` — same boilerplate cleanup (note: this file moves out of the clone on first init and lives at `<main-hash>/memory/MEMORY.md` thereafter)
- `.github/workflows/validate.yml` — drop checks for removed `.example` files; keep all other validation

### Files added

- `CHANGELOG.md` — v2.0.0 entry covering breaking changes + brief upgrade recipe
- `scripts/list-roles.sh` — companion audit script

### Files unchanged

- All `examples/` content (sample memory entries, mechanism-agnostic)
- `shared/feedback_*.md` files (content rules, just relocated on first init)
- `LICENSE`
- claude-personas's own `.gitignore`
- `assets/` (review screenshots; update if they show v1 setup files in project worktrees)

## Edge cases

### Symlink chain edge cases

- Multi-hop resolution: macOS, Linux, modern Windows (Developer Mode) all handle 3-hop symlinks. Hard limit ~32+ hops.
- Broken symlinks: if any link breaks (e.g., user moves the clone), `<role-hash>/memory/` becomes a dead path. `list-roles.sh` detects and reports.

### Pre-existing memory at hash paths

| State | Action |
|---|---|
| `<role-hash>/memory/` doesn't exist | Proceed normally |
| Symlink pointing to same target | No-op, idempotent |
| Symlink pointing elsewhere | Error, manual review required |
| Real dir with content | Error; suggest `--force` (backs up to `memory.backup-YYYYMMDD/`) |
| `<main-hash>/memory/` real dir with content | Keep — it becomes the shared content source |
| Clone's `shared/` already symlinked to wrong main-hash | Error; clone is "claimed" by another project, suggest fresh clone |

### Hash collisions

Two different worktrees can't have the same absolute path → no hash collisions possible.

### Multi-machine portability

- Hash is path-derived: on a new machine, the worktree must be at the same absolute path for symlinks to resolve correctly
- Otherwise: re-run `init-worktree.sh` per role per machine — it computes the right hash for whatever path the worktree ends up at
- Documented as "per-machine setup is run once per role per machine"

### Windows compatibility

- Symlinks require Developer Mode (Settings → Privacy & Security → Developer Mode) or admin privileges
- v1 had a "copy files instead of symlinks" fallback — dropped in v2 because the `<role-hash>/memory/` itself MUST be a symlink (the architecture has no path that works with copies)
- Windows users without Developer Mode → use WSL instead

## Release plan

1. **Tag v1.0** at current `main` HEAD before any v2 work begins (archival)
2. **Develop on `v2-dev` branch**: scripts → tests → docs
3. **Smoke-test**: run `init-worktree.sh` against a temp git repo (in CI), verify all 3 symlinks resolve to expected paths
4. **Merge to `main`** when v2-dev passes CI + manual end-to-end test
5. **Tag `v2.0.0`** at the merge commit
6. **GitHub release notes** mirror CHANGELOG.md content

### CI updates (`.github/workflows/validate.yml`)

- Remove: existence/format checks for `settings.local.json.example` and `CLAUDE.local.md.example`
- Add: lint check that init script is executable, role folders contain `MEMORY.md`, claude-personas-internal symlinks resolve (`<role>/shared → ../shared`)
- Add: smoke test running `init-worktree.sh` against a temp git repo, verifying symlinks land at expected paths and resolve correctly

## Out of scope (deferred)

- Migration script for v1 adopters (no real user base; manual recipe sufficient)
- Multi-project support via project-tier structure within one clone (v3 candidate; one-line forward-pointer in README)
- `scripts/unwire.sh` companion (low priority; manual `rm <symlink>` works)
- Cross-project shared layer (handled via system-level settings if needed, or v3+)
- Pattern 1 (single clone across projects) — v2 only supports Pattern 2 (clone per project)

## References

- [Issue #55801: autoMemoryDirectory silently ignored](https://github.com/anthropics/claude-code/issues/55801)
- Related: #36636, #39204, #46701, #49995
- Auto-memory architecture: `~/.claude/projects/<hash>/memory/MEMORY.md` is loaded by Claude Code automatically at session start
