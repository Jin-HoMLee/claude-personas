# claude-personas

[![CI](https://github.com/Jin-HoMLee/claude-personas/actions/workflows/validate.yml/badge.svg)](https://github.com/Jin-HoMLee/claude-personas/actions/workflows/validate.yml)

**Lead your own AI team.** Role-aware persistent memory for solo multi-persona Claude Code workflows.

![Four VSCode windows running cerebrum, Scientist, Developer, and PM personas in parallel on macOS, annotated to show cerebrum as the shared-memory hub](assets/mac-vscode-personas-overview-annotated.png)

*A real setup: four roles working in parallel — `cerebrum` (shared memory), Scientist, Developer, and PM — each in its own VSCode window, each with its own `MEMORY.md`.*

---

## The problem

When you play multiple roles on a project (coding Monday, triaging Tuesday,
reviewing Wednesday), you want Claude to behave differently in each context.
Your Developer Claude shouldn't have to wade through PM rules, and your PM
Claude shouldn't inherit Developer habits. One memory directory mashes them
all together.

You need a roster, not a single shared brain.

## What this gives you

Each persona or role on your team gets its own `MEMORY.md` — a playbook of habits, conventions, and rules tailored to that role. `claude-personas` is a **memory-only repo** — you clone one copy per project and never use it as your project codebase. Your actual project repo stays separate. For each role you want active, you create a project worktree; Claude auto-loads the right playbook based on which worktree you opened via native symlinks.

A `shared/` folder holds team-wide conventions — things every role on your team should know. An `examples/` tree of ~28 real-world patterns is included if you want to crib plays from another team.

**For:** solo developers who lead multiple personas across git worktrees.
**Not for:** multi-human teams, agent-to-agent coordination, or automated memory capture.

## Quick start (~5 minutes per project)

1. Click **Use this template** → create your `claude-personas-<my-app>` repo (one per project)
2. Clone it next to your project repo:
   `git clone git@github.com:<you>/claude-personas-<my-app>.git ~/projects/claude-personas-<my-app>`
3. From inside your **project repo** (not claude-personas), create a worktree per role:

   ```sh
   ~/projects/claude-personas-<my-app>/scripts/init-worktree.sh developer ../my-app-dev
   ~/projects/claude-personas-<my-app>/scripts/init-worktree.sh pm ../my-app-pm
   ~/projects/claude-personas-<my-app>/scripts/init-worktree.sh designer ../my-app-designer
   ```

   Each call creates a worktree on a `<role>/workspace` branch and sets up the symlinks
   so Claude Code auto-loads the right MEMORY.md when you open the worktree.

4. Open Claude Code in any role's worktree → it auto-loads that role's MEMORY.md.

5. Browse `examples/` for patterns; copy what fits into your role's `feedback_*.md`
   files (then commit + push from your claude-personas clone).

**Note**: every role gets its own worktree. The main project repo path stays
"unused by any role" — its hash dir hosts the shared layer.

## How it works

```text
~/projects/my-app/                       (main repo — no role uses it; hosts shared)
~/projects/my-app-dev/                   (developer worktree)
~/projects/my-app-pm/                    (PM worktree)
~/projects/my-app-designer/              (designer worktree)

~/projects/claude-personas-my-app/       (per-project clone of this repo)
├── developer/MEMORY.md
├── pm/MEMORY.md
├── designer/MEMORY.md
└── shared  ─symlink─►  ~/.claude/projects/<main-hash>/memory/

Claude Code's native paths:
~/.claude/projects/<dev-hash>/memory   ─symlink─►  claude-personas-my-app/developer/
~/.claude/projects/<pm-hash>/memory    ─symlink─►  claude-personas-my-app/pm/
~/.claude/projects/<des-hash>/memory   ─symlink─►  claude-personas-my-app/designer/
~/.claude/projects/<main-hash>/memory/  (real dir — actual shared content)
```

Open Claude Code in any role's worktree and it auto-loads the matching MEMORY.md
through the symlink chain. No `autoMemoryDirectory`, no per-worktree config files.

> ⓘ **Coming in v3**: a single claude-personas clone serving multiple projects
> via a project-tier structure. v2 is one clone per project.

Each `MEMORY.md` has two sections:

- **Always in effect** — rules inlined directly; Claude reads these at session start with
  no file reads required
- **Reference** — links to `feedback_*.md` files Claude reads on demand

Rules start in Reference, get promoted to Always-in-effect when they keep being missed.
See `CONVENTIONS.md` for the full pattern.

## What init-worktree.sh does (one-time per role)

`scripts/init-worktree.sh` automates this section. Read on if you want to know what
it does, or do it by hand.

For each role, the script:

1. Creates a git worktree on a new `<role>/workspace` branch
2. Computes Claude Code's hash from the worktree's absolute path
3. Symlinks `~/.claude/projects/<role-hash>/memory` to the role folder in your clone
4. (First role only) migrates your clone's `shared/` content into
   `~/.claude/projects/<main-hash>/memory/` and replaces `shared/` with a symlink
   pointing there

After init, the project worktree contains nothing claude-personas-related — no
`.claude/settings.local.json`, no `CLAUDE.local.md`. Your project's `.gitignore`
stays clean.

**Audit:** run `~/projects/claude-personas-<my-app>/scripts/list-roles.sh` to see
which worktrees are currently wired to which roles.

## Windows

v2 requires symlinks at multiple paths. Enable Developer Mode (Settings → Privacy
& Security → Developer Mode) so non-admin users can create symlinks. If Developer
Mode isn't an option in your environment, use WSL — claude-personas v2 has no
non-symlink fallback.

## FAQ

**Q: Do I need all three roles?**
Delete any role you don't use. The remaining roles still work — the symlinks are independent.

**Q: Can I add more roles?**
Yes. Create a new folder, add a `MEMORY.md` stub, then run
`scripts/init-worktree.sh <new-role> <worktree-path>` to wire it up.

**Q: How is this different from auto-memory?**
Auto-memory captures everything automatically. This is curated and hand-edited — you
decide what rules to keep and how to phrase them. Different tradeoff: more work, more
intentional.

**Q: What if I only want to start with one role for now?**
Run `scripts/init-worktree.sh` for just that one role. You can add more roles
(and the worktrees they need) later without restructuring. The shared layer is
initialized on first-role init, so adding roles later just needs the same script call.

**Q: Does claude-personas need to be in the same parent directory as my project?**
No, but it must be reachable via an absolute path that won't move (the role
symlinks store the path verbatim). One natural place: `~/projects/claude-personas-<my-app>/`
next to your project repo.

**Q: What if I move or rename the claude-personas clone after init?**
The role symlinks become broken. Run `scripts/list-roles.sh` to detect, then
re-run `scripts/init-worktree.sh <role> <worktree>` (with `--force`) for each
role to re-create the symlinks at the new path.

**Q: Can I have multiple projects share one claude-personas clone?**
Not in v2. Each clone is wired to one project on first init (the `shared` symlink
hardcodes that project's main-hash). Use a separate clone per project. v3 may
support multi-project via a project-tier directory structure.

## Upgrading from v1

v2 is a breaking change from v1. v1 used `autoMemoryDirectory` in a project-level
settings file, which is silently ignored by Claude Code (see issue #55801). v2
replaces this with native filesystem symlinks.

**Manual upgrade per project**:

1. In each role's project worktree, delete `.claude/settings.local.json` and
   `CLAUDE.local.md`, and remove their entries from `.gitignore`.
2. Re-run `scripts/init-worktree.sh <role> <worktree-path>` from your project
   repo — the v2 script produces symlink-based wiring instead of v1's config files.

Your `claude-personas/<role>/` memory files are unchanged; only the wiring mechanism
between project worktree and role memory has changed.

## License

[MIT](LICENSE)
