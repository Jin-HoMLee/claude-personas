# Migrating from claude-personas v2 to v3

v3 replaces v2's git worktrees + hash-symlinks mechanism with independent project-repo clones + a single `memory/` symlink per clone.

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

### 4. Run `init-clone.sh` for each role

```bash
cd ~/path/to/claude-personas-<app>
./scripts/init-clone.sh developer --project-url <project-repo-url>
./scripts/init-clone.sh pm
./scripts/init-clone.sh designer
./scripts/init-clone.sh scientist     # if you ship the scientist role
```

The first run persists the project URL to `.claude-personas/project.txt` — subsequent runs read it automatically.

**Note:** `init-clone.sh` adds `memory/` to each clone's `.gitignore`. After the first role's init, commit and push that `.gitignore` change from the first clone before running init for the other roles, so each subsequent role clone inherits the entry from the remote (instead of each clone re-adding it locally and diverging until pushed):

```bash
cd <project>                       # first clone — wherever init-clone.sh landed it
git add .gitignore && git commit -m "chore: gitignore role-memory symlink" && git push
```

Result:

- `<project>/` — Developer clone (no suffix, primary)
- `<project>-pm/`, `<project>-designer/`, `<project>-scientist/` — other role clones
- Each with a `memory/` symlink into the memory repo

### 5. Verify

```bash
./scripts/list-roles.sh
```

Expected: all roles reported `OK`. Open each clone in Claude Code, confirm:

- Role's `MEMORY.md` auto-loads (look for the "always in effect" rules in the first response).
- `memory/shared/MEMORY.md` resolves (try a Read on it).

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
