# Migrating from claude-personas v2 to v3

v3 replaces v2's git worktrees + hash-symlinks mechanism with independent project-repo clones + a single `.claude/memory/` symlink per clone.

**Why migrate?** v2 silently broke under Claude Code v2.1.49+ (Feb 2026), which collapses all worktrees of one repo into a single auto-memory hash dir. v2 symlinks at per-worktree hash paths never load.

**Estimated time:** ~10 minutes per project.

## Prerequisites

- Your memory repo (`claude-personas-<app>`) is pushed and clean.
- You're on Claude Code v2.1.49 or newer (older users can pin to the `v2-final` git tag).

## Steps

### 1. Push and verify memory repo

```bash
cd ~/path/to/claude-personas-<app>
git status                          # should be clean
git push origin main                # ensure remote is up-to-date
```

### 2. Tear down v2 worktrees

For each v2 worktree (one per role), find it via:

```bash
cd ~/path/to/<project>              # your main project repo
git worktree list
```

Remove each:

```bash
git worktree remove ../<project>-pm
git worktree remove ../<project>-designer
# ...etc per role
```

### 3. Delete v2 hash-symlinks

v2 created symlinks at `~/.claude/projects/<hash>/memory/`. Find and remove the ones from your worktree paths:

```bash
ls -la ~/.claude/projects/ | grep memory
```

For each broken or worktree-specific entry, delete the `memory` symlink:

```bash
rm ~/.claude/projects/<some-hash>/memory
```

**Caution:** don't delete the hash dir itself (`<some-hash>/`) — Claude Code may have session JSONLs there. Only delete the `memory` symlink inside.

### 4. Install the framework payload, then run `init-clone.sh` for each role

The Codex adapter needs the inject hook at the installed-payload location; install and commit it once per memory repo:

```bash
cd ~/path/to/claude-personas-<app>
./framework/tools/doctor.sh --init role-clones   # skip if .agents/manifest already exists
./framework/tools/install.sh --into .
git add .agents && git commit -m "install framework payload"
```

This commits the payload, the manifest pin, and the installer's `.agents/framework-receipt`.

Then run `init-clone.sh` once per role:

```bash
./framework/tools/init-clone.sh developer --project-url <project-repo-url>
./framework/tools/init-clone.sh pm
./framework/tools/init-clone.sh designer
./framework/tools/init-clone.sh scientist     # if you ship the scientist role
```

The first run persists the project URL to `.claude-personas/project.txt` — subsequent runs read it automatically.

**Note:** `init-clone.sh` adds `.claude/memory/` to each clone's `.gitignore`. After the first role's init, commit and push that `.gitignore` change from the first clone before running init for the other roles, so each subsequent role clone inherits the entry from the remote (instead of each clone re-adding it locally and diverging until pushed):

```bash
cd <project>                       # first clone — wherever init-clone.sh landed it
git add .gitignore && git commit -m "chore: gitignore role-memory symlink" && git push
```

Result:

- `<project>/` — Developer clone (no suffix, primary)
- `<project>-pm/`, `<project>-designer/`, `<project>-scientist/` — other role clones
- Each with a `.claude/memory/` symlink into the memory repo

### 5. Verify

```bash
./framework/tools/list-roles.sh
```

Expected: all roles reported `OK`. Open each clone in Claude Code, confirm:

- Role's `MEMORY.md` auto-loads (look for the "always in effect" rules in the first response).
- `.claude/memory/shared/MEMORY.md` resolves (try a Read on it).

### 6. Optional: tidy old hash dirs

If you don't need the v2 session JSONLs, archive or delete the orphaned hash dirs:

```bash
mv ~/.claude/projects/<old-hash> ~/.claude/projects-archive/  # or rm -rf
```

## Rollback

If anything goes wrong:

```bash
cd ~/path/to/claude-personas-<app>
git checkout -b v2-restore v2-final   # branch off the archival tag (avoids detached HEAD)
```

Re-run the v2 `init-worktree.sh` from that checkout — your role memory content is unchanged.

## FAQ

**Q: Do I lose any memory content?**
No. The role directories (`developer/`, `pm/`, etc.) are untouched. Only the wiring changes.

**Q: Can I keep using v2 on older Claude Code?**
Yes — pin your memory repo to the `v2-final` tag and use the v2 scripts. v3 only matters on Claude Code v2.1.49+.

**Q: My init-clone.sh asks for a project URL each time.**
Likely cause: `.claude-personas/project.txt` was wiped or never created. Re-run with `--project-url` once; the file will be re-created.

**Q: My saved project URL is wrong — passing `--project-url` doesn't update it.**
`init-clone.sh` only writes `project.txt` if it doesn't already exist; `--project-url` overrides the saved value for the current invocation but does not rewrite the file. To fix a wrong saved URL, delete `.claude-personas/project.txt` and re-run with `--project-url <correct-url>` — the file will be re-created with the new value.

## v3.0 → v3.1

v3.1 moves the role-memory symlink from `<clone>/memory` to `<clone>/.claude/memory` for consistency with Claude Code's own `.claude/` namespace. The memory content itself (in your sister `claude-personas-<app>/` repo) is unchanged.

For each role clone (run from inside your `claude-personas-<app>/` memory repo):

```bash
framework/tools/init-clone.sh --force <role>
```

`--force` detects the legacy v3.0 layout, backs up the old root-level `memory/` symlink to `<clone>/.claude/memory.legacy-backup-<timestamp>`, removes the stale `/memory/` line from the clone's `.gitignore`, and writes the new `.claude/memory/` symlink + `/.claude/memory/` gitignore entry.

Verification:

- `ls -l <clone>/.claude/memory` shows a symlink pointing to `../../claude-personas-<app>/<role>`.
- `cat <clone>/.gitignore | grep memory` shows only `/.claude/memory/` (no bare `/memory/`).
- Restart Claude Code in the clone; the next session-start memory load should resolve `.claude/memory/MEMORY.md`.

After all clones are migrated, you can delete the `.claude/memory.legacy-backup-*` directories.

## scripts/ → framework/ layout (2026-07)

The template's payload moved from `scripts/` (and root `skills/`) to `framework/{tools,hooks,skills}/`, and the wiring now expects the inject hook at the memory repo's `.agents/hooks/lib/inject-role-index.sh` instead of `scripts/inject-role-index.sh`.
For an existing memory repo that pulled this change:

```bash
cd ~/path/to/claude-personas-<app>
./framework/tools/doctor.sh --init role-clones   # skip if .agents/manifest already exists
./framework/tools/install.sh --into .
git add .agents && git commit -m "install framework payload"
```

This commits the payload, the manifest pin, and the installer's `.agents/framework-receipt`.

Then regenerate each clone's `.codex/hooks.json` (it still points at the removed `scripts/` path) with `./framework/tools/doctor.sh`, or `./framework/tools/init-clone.sh --force <role>` per clone.
Codex will ask you to re-approve the changed hook via `/hooks` in each clone.
Symptoms of a half-done migration: `init-clone.sh` warns `inject-role-index.sh missing or not executable`, or `doctor.sh` reports the hooks.json DRIFT naming the old path.
