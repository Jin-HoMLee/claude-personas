# claude-personas v3 — Clones Pivot Design Spec

**Date:** 2026-05-15
**Status:** Approved, ready for implementation plan
**Supersedes:** v2 (autoMemoryDirectory hash-symlinks at `~/.claude/projects/<hash>/memory/`)

## Goal

Replace v2's worktree-plus-hash-symlink mechanism with an **independent-clone-per-role** mechanism, wired by a single `memory/` symlink in each project clone pointing to a sibling memory repo. v3 is a hard release with a migration walkthrough — no parallel v2 docs.

## Why v3 is needed

Claude Code v2.1.49 (Feb 2026) intentionally collapses all worktrees of a single repo into the main repo's auto-memory hash dir. v2's design relied on **distinct** hash dirs per worktree path, so its memory symlinks silently never load on current Claude Code. Discovered + diagnosed during splice maintenance on 2026-05-14; splice migrated off worktrees to independent clones the same day and has run cleanly for ~24h.

v3 promotes that proven splice pattern into the framework default.

## Non-goals

- **No support for both mechanisms in parallel.** v2 is retired (git-tagged `v2.0.1`, archived). Users on Claude Code <v2.1.49 who want v2 can pin to that tag.
- **No automated v2→v3 migration script.** User base is small; a written walkthrough is sufficient.
- **No rename of the framework.** Despite 3 namespace collisions per the 2026-05-14 landscape survey, `claude-personas` stays. Differentiate via README, not rename.

## Architecture

### On-disk layout after setup (project `my-app`)

```text
~/dev/.../
  my-app/                              ← Developer clone (no suffix, primary)
    memory -> ../claude-personas-my-app/developer/
    .git/                              (real, full project clone)
    [project files...]

  my-app-pm/                           ← PM clone
    memory -> ../claude-personas-my-app/pm/
    .git/
    [project files...]

  my-app-designer/                     ← Designer clone
    memory -> ../claude-personas-my-app/designer/

  my-app-scientist/                    ← Scientist clone
    memory -> ../claude-personas-my-app/scientist/

  claude-personas-my-app/              ← memory repo (template fork)
    .claude-personas/
      project.txt                      (project repo URL, 1 line)
      main-role.txt                    (role that claims no-suffix path; optional, default "developer")
    developer/
      MEMORY.md
      shared -> ../shared
      [feedback_*.md, project_*.md, ...]
    pm/         (same shape)
    designer/   (same shape)
    scientist/  (same shape)
    shared/                            ← canonical shared layer (real dir)
      MEMORY.md
      [feedback_*.md, ...]
    examples/
      developer/  pm/  designer/  scientist/  shared/
      README.md
    scripts/
      init-clone.sh
      list-roles.sh
      tests/
    docs/
      superpowers/
        specs/   plans/
      CONVENTIONS.md
    README.md
    CHANGELOG.md
    MIGRATION.md
    LICENSE
```

### Why each layer

| Layer | Role |
|-------|------|
| Project clone's `memory/` symlink | Surfaces role-specific `MEMORY.md` into Claude Code's cwd. Native auto-memory dir loads it. |
| Memory repo's `<role>/shared -> ../shared` symlink | Lets every role transparently see the canonical shared layer at `memory/shared/MEMORY.md`. |
| Memory repo's `shared/` real dir | Single source of truth for cross-role conventions. Edits propagate to all roles automatically. |
| `.claude-personas/project.txt` | Lets `init-clone.sh` know which project URL to clone. Set once on first init. |
| `.claude-personas/main-role.txt` | Lets users override the default no-suffix-claimer. Default "developer". |

## Components

### 1. Repo skeleton (what `Use this template` produces)

Same as the on-disk layout above, except no `.claude-personas/project.txt` (it's per-user, gitignored) and the role dirs contain only boilerplate `MEMORY.md` files + the `shared` symlink. No project clones exist yet — the user creates those via `init-clone.sh`.

Default roles shipped in skeleton: **developer, pm, designer, scientist**, plus **shared**.

### 2. `init-clone.sh <role> [--project-url <url>] [--target <path>] [--main] [--force]`

**Where it runs.** Inside the memory repo (`claude-personas-<app>/`). The script auto-discovers its repo root via `$BASH_SOURCE`.

**Behavior:**

1. **Validate role.** Role dir must exist in memory repo (`./<role>/`); else hard fail with list of available roles.
2. **Resolve project URL.** Precedence: `--project-url` flag > `.claude-personas/project.txt` > prompt user. On first successful clone, write the URL to `project.txt` (gitignored).
3. **Resolve target path.** Precedence: `--target` flag > suffix rules. Suffix rules:
   - If `--main` flag passed, OR `<role>` matches `.claude-personas/main-role.txt`, OR no `main-role.txt` exists AND `<role>` is "developer" → target is `<parent-of-memory-repo>/<project-name>/` (no suffix).
   - Else target is `<parent-of-memory-repo>/<project-name>-<role>/`.
   - If the no-suffix path is already taken by a non-empty dir, fall through to suffixed.
4. **Validate target.** Must not already exist. `--force` override: existing dir must be a clean git checkout of the same `project-url`; if so, only re-wire the `memory/` symlink (do not re-clone).
5. **Clone.** `git clone <project-url> <target>`.
6. **Wire memory symlink.** `ln -s ../claude-personas-<app>/<role> <target>/memory` (relative path — survives sibling-dir moves).
7. **Add `memory/` to `<target>/.gitignore`** if not already there. Idempotent (grep before append). Tracked — visible to anyone reading the repo, single source of truth across role clones (matches splice's PR #371 pattern).
8. **Print next-step hint.** `"Open <target> in Claude Code → role MEMORY.md auto-loads via memory/MEMORY.md."`

**Edge-case handling preserved from v2:**

- `--force` on a broken symlink: back up to `memory.backup-<YYYY-MM-DD>/` then re-link.
- Stale `~/.claude/projects/<hash>/` from prior sessions: detect + warn but don't auto-delete (user data).

### 3. `list-roles.sh` (rewritten for v3)

**Where it runs.** Inside the memory repo.

**Output.** One row per `<parent>/<project-name>*` sibling directory found:

```text
Role        Clone path                          Memory symlink           Git status
----------  ----------------------------------  -----------------------  -----------
developer   my-app/                             OK → developer/          clean
pm          my-app-pm/                          OK → pm/                 dirty (3)
designer    my-app-designer/                    BROKEN                   clean
scientist   <missing>                           —                        —
```

Used for drift detection: "did one of my role symlinks rot? are any role clones missing?"

### 4. MIGRATION.md (new)

Step-by-step walkthrough from v2 to v3. Six steps, ~10 min per project:

1. Push v2 memory repo to GitHub (verify all role content is committed).
2. Tear down v2 worktrees (`git worktree remove`) and delete the hash-symlinks at `~/.claude/projects/<hash>/memory/`.
3. (Optional) Archive `~/.claude/projects/<old-hashes>/`.
4. Add `memory/` to the project repo's tracked `.gitignore` (one line). Commit + push so all role clones inherit it. (Skip if `init-clone.sh` has already done this on first run — the script is idempotent.)
5. Run `init-clone.sh <role>` once per role. Memory content carries over unchanged. (Script verifies `memory/` is in `.gitignore` and adds it if not.)
6. Verify: open each clone in Claude Code, confirm role MEMORY.md auto-loads, confirm `memory/shared/MEMORY.md` resolves.
7. Tidy: optionally `git tag v2-final` in the memory repo before pushing v3 layout, for traceability.

### 5. Retired v2 surface

Deleted from main (preserved in git tag `v2.0.1`):

- `scripts/init-worktree.sh`
- v2 versions of `scripts/list-roles.sh` (replaced with v3 version, same filename)
- v2 versions of `scripts/tests/` (replaced with v3 tests)
- All `autoMemoryDirectory` references in `CONVENTIONS.md` and `README.md`
- v2 hero diagram in `assets/` (worktree-centric — re-annotated for clones)
- `--force` and hash-backup edge-case helpers stay in code but retargeted at the new `memory/` symlink path

### 6. Added in v3

- `MIGRATION.md` at repo root
- `scientist/` role skeleton (`MEMORY.md` + `shared` symlink)
- `examples/scientist/` (port a handful of patterns from splice's scientist memory)
- `.claude-personas/project.txt` (per-user, gitignored)
- `.claude-personas/main-role.txt` (optional, tracked if set; default behavior assumes "developer")
- Updated `assets/` hero diagram showing clones-not-worktrees

## Data flow

**MEMORY.md resolution chain for a PM session opened in `my-app-pm/`:**

1. Claude Code starts in cwd `my-app-pm/`.
2. Claude Code's auto-memory loader looks for `<cwd>/memory/MEMORY.md` — finds the symlink.
3. Resolves through `my-app-pm/memory -> ../claude-personas-my-app/pm/` → reads `pm/MEMORY.md`.
4. `pm/MEMORY.md` references `memory/shared/MEMORY.md`. Claude resolves relative to cwd:
   - `my-app-pm/memory/shared/MEMORY.md`
   - → through `memory -> ../claude-personas-my-app/pm/` → `claude-personas-my-app/pm/shared/MEMORY.md`
   - → through `pm/shared -> ../shared` → `claude-personas-my-app/shared/MEMORY.md` ✓

Two layers of symlinks; both invisible to Claude Code (it sees normal file paths).

## Error handling

| Failure mode | init-clone.sh response |
|--------------|------------------------|
| Role dir missing in memory repo | Hard fail; list available roles. |
| `project.txt` missing AND no `--project-url` flag | Prompt user; persist their answer. |
| Target dir exists, not a git checkout | Hard fail; suggest `--target` to override. |
| Target dir exists, git checkout of WRONG project | Hard fail; suggest `--target`. |
| Target dir exists, clean checkout of SAME project, no `--force` | Hard fail; suggest `--force` to just wire the symlink. |
| Target dir exists, clean checkout of SAME project, `--force` | Skip clone; back up existing symlink if present; create new symlink. |
| `git clone` fails (auth, network, ...) | Surface git error verbatim; exit non-zero; do not partially commit setup. |
| `ln -s` fails (already exists despite earlier check) | Surface OS error; rollback by removing the target clone if we created it this run. |

## Testing

Migrate the v2 test suite shape (`scripts/tests/`) to cover v3:

- `init-clone.sh` happy path (each of the 4 default roles).
- No-suffix slot logic (developer claims it; configurable via `main-role.txt`; fallthrough if path taken).
- `--force` on broken symlink; `--force` on existing-clean-same-project clone; `--force` on existing-WRONG-project clone (must fail).
- `project.txt` precedence (flag > file > prompt).
- `memory/` added to `.gitignore` exactly once even on repeated `--force` runs.
- `list-roles.sh` reports broken symlinks, missing clones, dirty git state correctly.

Tests must run in an isolated `$HOME` per fixture (lesson from v2.0.1 — see CHANGELOG); helpers `make_test_fixture` / `cleanup_test_fixture` carried over with no behavior change.

## Resolutions captured post-brainstorm

- **Where does `memory/` get gitignored?** In the project repo's tracked `.gitignore` (matches splice's PR #371 pattern). Single line, single source of truth, visible to anyone reading the repo. `init-clone.sh` adds it idempotently on first run; subsequent clones inherit via the tracked file.
- **Should `list-roles.sh` accept `--json` for scripting?** YAGNI for v3; revisit if a user asks.
- **Should we ship a `pre-commit` hook in role MEMORY.md skeletons that blocks committing role-specific paths into the project repo?** Out of scope for v3.

## Success criteria

- Splice's already-running setup matches v3 exactly with zero changes (proof the design is right).
- A new user can go from "Use template" → working 4-role setup in <10 minutes.
- v2 user can complete MIGRATION.md walkthrough in <10 minutes per project.
- `list-roles.sh` catches at least 3 drift scenarios: broken symlink, missing clone, wrong-project clone.

## Related memory

- [[claude-personas-v3-clones-pivot]] — the queued plan that anchored this design
- [[splice-worktree-to-clones-2026-05-14]] — the migration that revealed the v2 bug
- [[project-claude-personas-v2-status]] — current v2 state being superseded
- [[landscape-survey-2026-05-14]] — name-collision context for the "keep claude-personas" decision
- [[multi-role-value-audit-2026-05-14]] — load-bearing evidence for multi-role per project
