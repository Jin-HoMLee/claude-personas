# Move role-memory symlink under `.claude/`

**Status:** Approved 2026-05-17
**Target version:** claude-personas v3.1.0
**Supersedes:** path conventions in [2026-05-15-v3-clones-pivot-design.md](2026-05-15-v3-clones-pivot-design.md)

## Why

Role clones currently expose memory via a top-level symlink:

```text
<project-clone>/memory  →  ../claude-personas-<app>/<role>
```

Claude Code's own state already nests under a `.claude/` namespace at the user level (`~/.claude/projects/<hash>/memory/`). Putting the role-memory symlink at the project root is inconsistent with that convention and adds a non-config artifact to the project's top-level listing. Moving it to `<project-clone>/.claude/memory/` mirrors Claude Code's own layout and consolidates all Claude-related artifacts (settings, hooks, commands, memory) under one directory.

The change is purely organizational — no behavior change for Claude Code itself, since memory is loaded via CLAUDE.md import, not via a hardcoded path inside the harness.

## Scope

In scope:

- `scripts/init-clone.sh` — symlink location, `.gitignore` rule, `--force` migration
- Role CLAUDE.md / MEMORY.md boilerplate that names the path
- Repo-level docs (`README.md`, `CHANGELOG.md`, `CONVENTIONS.md`, `MIGRATION.md`)
- `scripts/tests/` assertions
- Retrofit of the 3 splice role clones (`developer`, `pm`, `scientist`)

Out of scope:

- Two-layout support / backwards-compat flag. New layout only.
- Any other path indirection (env var, config). Hardcode `.claude/memory/`.
- Changes to the sister memory repo (`claude-personas-<app>/`) — its layout is unchanged.
- Cerebrum's own memory location — cerebrum is not a claude-personas clone; it uses Claude Code's native auto-memory directory.

## Design

### Path change

| Surface | Before | After |
| --- | --- | --- |
| Symlink path | `<clone>/memory` | `<clone>/.claude/memory` |
| Symlink target | `../claude-personas-<app>/<role>` | `../../claude-personas-<app>/<role>` |
| `.gitignore` rule | `/memory/` | `/.claude/memory/` |
| Memory file reference in CLAUDE.md / docs | `memory/MEMORY.md` | `.claude/memory/MEMORY.md` |

The extra `../` in the symlink target is the one mechanical subtlety: `.claude/memory` is one directory deeper than `memory`, so the relative path back to the sibling must climb one more level.

### `scripts/init-clone.sh`

Three edits:

1. **Symlink location and target** — replace the `MEMORY_LINK` assignment and `ln -s` call with:

    ```bash
    MEMORY_LINK="$TARGET/.claude/memory"
    mkdir -p "$TARGET/.claude"
    ln -s "../../$MEMORY_REPO_NAME/$ROLE" "$MEMORY_LINK"
    ```

2. **`.gitignore` rule** — replace `/memory/` with `/.claude/memory/`. Keep the idempotency check.
3. **`--force` migration** — when `--force` is set, *also* detect a legacy `$TARGET/memory` symlink (root-level) and a legacy `/memory/` line in `.gitignore`. Back up the old symlink, remove the old gitignore line, write the new layout. Result: `init-clone.sh --force <role>` is the single command for both fresh installs on v3.1 and v3.0 → v3.1 migration.

The usage/help text and final "Done" line update to reference `.claude/memory/MEMORY.md`.

### Docs and templates

- `CHANGELOG.md`: v3.1.0 entry — breaking change (path moved), migration via `init-clone.sh --force`.
- `MIGRATION.md`: append "v3.0 → v3.1" section. One-command migration. Note that role memory content itself doesn't move — only the symlink in the project clone.
- `README.md`: update wherever the layout diagram or the install walkthrough mentions `memory/`.
- `CONVENTIONS.md`: update path references.
- Each role boilerplate (`developer/MEMORY.md`, `pm/MEMORY.md`, `scientist/MEMORY.md`, `designer/MEMORY.md` if present): update any `memory/...` path references to `.claude/memory/...`.

### Tests

`scripts/tests/` likely asserts on the symlink path and `.gitignore` content. Audit each test, update assertions to the new path. Add at least one test that verifies the `--force` migration path: arrange a legacy layout (root `memory/` symlink + `/memory/` gitignore line), run `--force`, assert the new layout exists and the old symlink is backed up.

### Splice retrofit

After the claude-personas PR merges and v3.1.0 is tagged, retrofit the three splice role clones:

1. Pull latest claude-personas template into `claude-personas-splice-neoepitope-pipeline` (the sister memory repo — it already has `scripts/` available via the template install).
2. For each role, from inside the sister repo, run:

    ```bash
    scripts/init-clone.sh --force developer
    scripts/init-clone.sh --force pm
    scripts/init-clone.sh --force scientist
    ```

3. Restart Claude Code in each role clone; confirm a session-start memory load resolves `.claude/memory/MEMORY.md` correctly.
4. Commit the resulting `.gitignore` change in each role clone (the only tracked change per clone).

Order doesn't matter — the three clones are independent.

## Versioning

v3.1.0 minor bump. Path move is a breaking change for anyone who installed v3.0.0, but small enough that a minor + clear MIGRATION note is appropriate (SemVer is loose here because `--force` migrates the legacy layout to the new one in a single command, so users aren't stuck choosing between layouts).

## Risks and mitigations

- **Existing v3.0 users on external installs**: addressed by `--force` auto-migration and MIGRATION.md.
- **`.claude/` discoverability**: hidden by default in some file managers. Mitigated by docs naming the path explicitly and by Claude Code editors (which show dotfiles by default).
- **Test surface gaps**: explicit test for the migration path catches the most likely regression.

## Non-goals

- Renaming the symlink (e.g., to `role-memory/`). Keep the `memory` name to minimize churn in muscle memory and docs.
- Restructuring the sister memory repo. Its layout (`<role>/MEMORY.md`) is unchanged.
- Adding a separate migration script. The `--force` path on `init-clone.sh` is the migration mechanism.
