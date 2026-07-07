# claude-personas

[![CI](https://github.com/Jin-HoMLee/claude-personas/actions/workflows/validate.yml/badge.svg)](https://github.com/Jin-HoMLee/claude-personas/actions/workflows/validate.yml)

**Lead your own AI team.** Role-aware persistent memory for solo multi-persona Claude Code workflows.

![Four VSCode windows running Developer, PM, Designer, and Scientist personas in parallel on macOS, each with its own MEMORY.md](assets/mac-vscode-personas-overview-annotated.png)

*A real setup: four roles working in parallel, each in its own VSCode window, each with its own `MEMORY.md`.*

---

## The problem

When you play multiple roles on a project (coding Monday, triaging Tuesday, reviewing Wednesday), you want Claude to behave differently in each context. Your Developer Claude shouldn't have to wade through PM rules, and your PM Claude shouldn't inherit Developer habits. One memory directory mashes them all together.

You need a roster, not a single shared brain.

## What this gives you

Each persona or role on your team gets its own `MEMORY.md` — a playbook of habits, conventions, and rules tailored to that role. `claude-personas` is a **memory-only repo** — you fork the template once per project and never use it as your project codebase. Your actual project repo stays separate.

For each role you want active, you create an independent **clone** of your project repo (sibling-dir style: `my-app/`, `my-app-pm/`, `my-app-scientist/`, ...). Each project clone has a `.claude/memory/` symlink into the matching role folder in your `claude-personas-<my-app>` repo. Claude auto-loads the right playbook based on which clone you open.

A `shared/` folder holds team-wide conventions. An `examples/` tree of patterns is included if you want to crib plays from another team.

**For:** solo developers who lead multiple personas across project clones.
**Not for:** multi-human teams, agent-to-agent coordination, or automated memory capture.

## Quick start (~10 minutes per project)

1. Click **Use this template** → create your `claude-personas-<my-app>` repo (one per project).
2. Clone the memory repo next to where you want your project clones:
   ```sh
   cd ~/dev
   git clone git@github.com:<you>/claude-personas-<my-app>.git
   ```
3. Stage the framework payload where the wiring expects it (interim step until `install.sh` ships - see issue #55):
   ```sh
   cd claude-personas-<my-app>
   mkdir -p .agents/hooks/lib
   cp framework/hooks/inject-role-index.sh .agents/hooks/lib/
   ```
4. Run `init-clone.sh` once per role you want active:
   ```sh
   ./framework/tools/init-clone.sh developer --project-url git@github.com:<you>/<my-app>.git
   ./framework/tools/init-clone.sh pm
   ./framework/tools/init-clone.sh designer
   ./framework/tools/init-clone.sh scientist
   ```
   First call persists the project URL — subsequent calls don't need `--project-url`.
5. Open any role's clone (e.g. `~/dev/my-app-pm/`) in Claude Code → role's MEMORY.md auto-loads via `.claude/memory/MEMORY.md`.
6. Browse `examples/` for patterns; copy what fits into your role's `feedback_*.md` files (then commit + push from your memory repo).

**Default no-suffix slot:** `developer` claims the `<project>/` (no-suffix) path. Override with `--main` on another role or by writing the role name into `.claude-personas/main-role.txt`.

## How it works

```text
~/dev/                                       (parent dir; both repos are siblings here)
├── my-app/                                  (Developer clone — no suffix)
│   ├── .git/                                (real, full project repo)
│   ├── .claude/memory ─symlink─► ../../claude-personas-my-app/developer/
│   └── [project files...]
│
├── my-app-pm/                               (PM clone)
│   ├── .claude/memory ─symlink─► ../../claude-personas-my-app/pm/
│   └── [project files...]
│
├── my-app-designer/                         (Designer clone — same shape)
├── my-app-scientist/                        (Scientist clone — same shape)
│
└── claude-personas-my-app/                  (memory repo, your fork of the template)
    ├── developer/
    │   ├── MEMORY.md
    │   └── shared ─symlink─► ../shared
    ├── pm/         (same shape)
    ├── designer/   (same shape)
    ├── scientist/  (same shape)
    ├── shared/                              (canonical shared layer)
    │   └── MEMORY.md
    ├── examples/   (cribbable patterns)
    └── framework/  (distributable payload: tools/, hooks/, skills/ - see framework/FILES)
```

When you open `my-app-pm/` in Claude Code, the auto-memory loader reads `my-app-pm/.claude/memory/MEMORY.md` — which resolves through the symlink to `claude-personas-my-app/pm/MEMORY.md`. References to `.claude/memory/shared/MEMORY.md` resolve through a second symlink (`pm/shared -> ../shared`) to the canonical shared layer.

Two layers of symlinks; both invisible to Claude Code.

Each `MEMORY.md` has two sections:

- **Always in effect** — rules inlined directly; Claude reads these at session start with no file reads required.
- **Reference** — links to `feedback_*.md` files Claude reads on demand.

Rules start in Reference and get promoted to Always-in-effect when they keep being missed — unless a hook or skill fits the rule better. See [`CONVENTIONS.md`](CONVENTIONS.md) for the full four-tier ladder (Always-in-effect / Reference / Skills / Hooks).

### User-memory tier

One more tier sits above role and project: **user memory** - one private repo per human (`<owner>/user-memory`), same substrate format, holding rules that apply in every project regardless of role. Precedence on conflict: role > project > user (more specific wins).

- Naming: `<scope>-memory`, e.g. `Jin-HoMLee/user-memory`.
- Mounting: the canonical `~/AGENTS.md` lives in that repo and is symlinked back; each tool's native global file symlinks onward - Claude Code `~/.claude/CLAUDE.md`, Codex `~/.codex/AGENTS.md`, OpenCode `~/.config/opencode/AGENTS.md`. `tools/sync.sh --check` in that repo doctors the wiring.
- Design spec: [`2026-07-02-knowledge-consolidation-two-module-design.md`](docs/superpowers/specs/2026-07-02-knowledge-consolidation-two-module-design.md).
- Headless caveat: non-interactive invocations may need extra flags to read memory outside the invocation cwd - Claude Code `-p` needs `--add-dir <path>` for lazy reads, OpenCode non-interactive needs `--auto` to approve the cross-directory read prompt, Codex outside a trusted git dir needs `--skip-git-repo-check`.

## What `init-clone.sh` does (one-time per role)

For each role, the script:

1. Validates the role exists in the memory repo (`<role>/MEMORY.md` present).
2. Resolves the project URL: `--project-url` flag > `.claude-personas/project.txt` > prompt.
3. Decides the target clone path:
   - If `--main` or the role matches `.claude-personas/main-role.txt` (default `developer`), claims `<parent>/<project-name>/`.
   - Otherwise, target is `<parent>/<project-name>-<role>/`.
   - Falls through to suffixed path if the no-suffix path is taken.
4. `git clone <url> <target>`.
5. Creates the two-hop memory mount in the new clone: `.agents/memory -> ../../<memory-repo>/<role>`, then `.claude/memory -> ../.agents/memory`.
6. Marks both symlinks untracked via the clone's `.git/info/exclude` (idempotent), not `.gitignore`.
   See the Multi-vendor wiring section below for the external Claude Code hop, Codex, and OpenCode wiring.
7. On first run, persists the project URL to `.claude-personas/project.txt`.

**Memory Manager (optional):** if your project has a Memory Manager, its workspace is the memory repo itself, not a project clone.
Create a real `memory_manager/` role dir (own `MEMORY.md` + `shared -> ../shared`), then run `./framework/tools/init-clone.sh --self` from inside the memory repo.
This wires the same untracked mounts self-referentially - `.agents/memory -> ../memory_manager`, the `.claude/memory` hop, the external Claude Code hop, and the Codex/OpenCode adapters - with no clone created.
The mount is untracked on purpose: role identity belongs to the workspace instance, so cloning the memory repo does not make anyone the MM.

**Audit:** run `./framework/tools/list-roles.sh` from inside your memory repo to see which clones exist, which are wired correctly, and which need fixing - the MM self-mount is audited like any other role.

## Multi-vendor wiring (Claude Code, Codex, OpenCode)

`init-clone.sh` wires each role clone for all three tools at once.

What it creates per clone (all untracked via `.git/info/exclude` - your project repo never needs a commit to host a wired clone):

- `.agents/memory -> ../../<memory-repo>/<role>` - the vendor-neutral mount and the single role signal.
- `.claude/memory -> ../.agents/memory` - the Claude Code hop, plus an external `~/.claude/projects/<slug>/memory` symlink that Claude Code's auto-memory loader actually reads.
- `.codex/hooks.json` - a generated SessionStart hook that injects the role index via the memory repo's `.agents/hooks/lib/inject-role-index.sh` (the installed framework payload; see the quick start's staging step), mirroring Claude Code's native role-file auto-load (role index only, bounded by CC's native ~200-line/~25 KB size guard; shared is loaded on demand via the `load-persona-memory` skill, with a one-line pointer in the payload).

One-time steps per machine that the script cannot perform (it prints them):

- Codex: open the clone, accept repo trust, then run `/hooks` and approve the generated hook (re-approve whenever the file changes).
- OpenCode: add `".agents/memory/MEMORY.md"` to the `instructions` array in `~/.config/opencode/opencode.json` - one global entry serves every wired clone. If OpenCode cannot read through the symlink on your setup, re-run `init-clone.sh` with `--opencode-per-clone` (see `docs/vendor-caveats.md`).
- Skill install (all three tools): symlink the skill once into your user-level skill dirs:

  ```bash
  ln -s "$(pwd)/framework/skills/load-persona-memory" ~/.agents/skills/load-persona-memory   # Codex + OpenCode
  ln -s "$(pwd)/framework/skills/load-persona-memory" ~/.claude/skills/load-persona-memory   # Claude Code
  ```

Sharp edges per vendor (trust layers, symlink bugs, context ceilings) live in [docs/vendor-caveats.md](docs/vendor-caveats.md).
Embedded-topology projects (memory inside the same repo) should start from [examples/substrate/](examples/substrate/) instead of `init-clone.sh`.

## Checking your wiring: `doctor.sh`

`init-clone.sh` wires a role clone once.
`doctor.sh` re-checks it any time - after a machine move, a version bump, or just to be sure.
It is one manifest-driven script covering three substrate topologies: `role-clones` (the constellation every fork of this template uses - run it from the memory repo), `embedded` (a single repo carries `.agents/` alongside its own project code, see [examples/substrate/](examples/substrate/)), and `user-tier` (the global user-memory tier described above).
Full design, including the check catalog per topology: [`docs/superpowers/specs/2026-07-04-toolbox-manifest-driven-doctor-design.md`](docs/superpowers/specs/2026-07-04-toolbox-manifest-driven-doctor-design.md).

### The manifest: `.agents/manifest`

Every instance declares its topology in one committed file, `.agents/manifest`, at the instance root.
`doctor.sh` never infers the topology from repo shape - an instance with no manifest gets a refusal naming the three topologies and the `--init` command, not a guess.
Syntax is flat `key=value` lines: no spaces around `=`, no quoting, no sections, no nesting.
`#` comments and blank lines are ignored; every other line is parsed strictly, and an unknown key or an unknown value is an error, not a warning - a newer manifest must fail loudly on an older doctor rather than silently skip checks (`manifest_version` is the escape hatch for future format changes).
The manifest is read with grep/cut in bash (and a small reader in `memory_cliff.py`) - it is never shell-sourced, so a manifest cannot execute code.

| Key | Values | Applies to | Meaning |
|---|---|---|---|
| `manifest_version` | `1` | all (required) | Format version; doctor refuses versions it does not know |
| `topology` | `role-clones` \| `embedded` \| `user-tier` | all (required) | Selects the check catalog; never inferred from repo shape |
| `memory_layout` | `roles` \| `flat` | all (required) | Drives payload checks and `memory_cliff.py` corpus discovery |
| `adapter` | `claude-code` \| `codex` \| `opencode` | all (repeatable) | Which vendor adapters must be wired; an undeclared adapter is not checked |
| `claude_hook` | repo-relative script path | embedded (repeatable) | Hook that `.claude/settings.json` must wire via `$CLAUDE_PROJECT_DIR` |
| `codex_hook` | repo-relative script path | embedded (repeatable) | Hook that `.codex/hooks.json` must wire with this instance's absolute path |
| `skills_mount` | `true` \| `false` (default) | embedded | Whether `.claude/skills -> ../.agents/skills` must exist |
| `opencode` | `global` (default) \| `per-clone` | role-clones | Which OpenCode wiring variant the clones use |

### Quickstart per topology

Role-clone constellation (run from the memory repo):

```sh
cd claude-personas-<my-app>
./framework/tools/doctor.sh --init role-clones
./framework/tools/doctor.sh --check
./framework/tools/doctor.sh
```

Embedded (a single repo carrying `.agents/` alongside its own project code):

```sh
cd <your-repo>
./framework/tools/doctor.sh --init embedded
./framework/tools/doctor.sh --check
./framework/tools/doctor.sh
```

User tier (a global `<owner>/user-memory` repo - see [User-memory tier](#user-memory-tier) above):

```sh
cd user-memory
./framework/tools/doctor.sh --init user-tier
./framework/tools/doctor.sh --check
./framework/tools/doctor.sh
```

`--init <topology>` writes a commented starter manifest for that topology and exits; it refuses to overwrite an existing one.
Edit the starter to match your instance - delete (or comment out) an `adapter=` line for a vendor you don't wire, and set a topology-specific optional key (`opencode=<mode>`, `claude_hook=<path>`, `codex_hook=<path>`, `skills_mount=<bool>`) by adding a bare `key=value` line.
Don't just remove the leading `#` from one of the starter's commented examples: they carry trailing inline comments, and the strict parser rejects anything after the value on a `key=value` line.
`--check` reports drift and exits nonzero without changing anything - safe to run any time, including in CI.
Plain `doctor.sh` (no flags) is fix mode: it repairs whatever it can, then reports on anything it can't the same way `--check` would.

### Fix what is derivable, report what is owned

Fix mode does not mean "fixes everything."
Symlinks and fully generated files (`.codex/hooks.json`, per-clone `opencode.json`) are fully derivable from the manifest, so fix mode writes them directly.
Dangling external-hop orphans (a `~/.claude/projects/<slug>/memory` symlink whose target no longer exists) are found by a global sweep rather than derived from the manifest, and fix mode removes them - a symlink whose target is gone serves nobody by definition.
`.claude/settings.json` hook stanzas and the global `~/.config/opencode/opencode.json` entry are user-owned config the doctor never rewrites - it reports the drift and prints the exact line or stanza to add by hand.
A real (non-symlink) file or directory sitting where a symlink is expected is never touched either - one refusal must not hide another.
More than one workspace claiming the same role is flagged as drift, report-only: retiring a stale clone is a human decision, not one the doctor makes for you.

### Exit codes

`0` - clean, or (in fix mode) everything derivable was repaired.
`1` - drift or error remains: a report-only finding in fix mode, or any finding at all in `--check` mode.
`2` - no manifest, or an invalid one (unknown key, unknown value, unsupported `manifest_version`).

### What `doctor.sh` deliberately does not check

Per-machine Codex trust grants (repo trust, plus `/hooks` review of the generated hook) are not inspectable from any script - `init-clone.sh` prints them as one-time steps at wiring time, and `doctor.sh` does not re-check them.
Skills packaging and distribution are out of scope here, tracked separately as [issue #43](https://github.com/Jin-HoMLee/claude-personas/issues/43); `doctor.sh` only checks the `.claude/skills -> ../.agents/skills` symlink itself, and only when the manifest declares `skills_mount=true`.

### `memory_cliff.py` and the manifest

`framework/tools/memory_cliff.py --layout flat` lints a flat-layout instance's single `MEMORY.md` as one always-loaded unit, since a flat instance has no shared file to add and no role/shared split to subtract.
With no `--layout` flag, it reads `memory_layout` from `.agents/manifest` when one is present, and falls back to the original role-discovery behavior when there is no manifest at all - so the template repo and any pre-manifest instance keep working unchanged.

## Windows

Symlink creation needs Developer Mode on Windows (Settings → Privacy & Security → Developer Mode). If Developer Mode isn't an option in your environment, use WSL.

## FAQ

**Q: Do I need all four roles?**
No. Skip roles you don't use. Each `init-clone.sh` call is independent. The role dirs you don't run still ship in your fork's memory repo — delete them if you want.

**Q: Can I add custom roles?**
Yes. Create a new folder in your memory repo (e.g. `mlops/`), add a `MEMORY.md` + `shared -> ../shared` symlink, then `init-clone.sh mlops`.

**Q: How is this different from auto-memory (and Dreaming)?**
Three layers that are easy to conflate:

- **Auto-memory** — Claude Code captures notes automatically as you work. Machine-local, append-mostly, and (by design) noisy.
- **Dreaming** — Anthropic's memory-*consolidation* capability (currently a research preview on the Managed Agents API): it reads a memory store and produces a cleaned one — duplicates merged, stale or contradicted entries replaced, new patterns surfaced.
- **claude-personas** — the *curated, hand-edited, version-controlled* layer. You decide which rules to keep, how to phrase them, and — the part neither of the above touches — **which visibility tier each rule belongs in**: always-loaded, reference, skill, or hook (the four primitives; see [`CONVENTIONS.md`](CONVENTIONS.md)).

These are complementary, not competing: consolidation keeps whatever's in your store clean, but it doesn't decide what belongs there in the first place — that's what choosing a tier does. Auto-memory is automatic-but-noisy; this is more work, more intentional, and shareable across the roles on your team.

**Q: Disk cost?**
Each project clone is a full `git clone` — for most projects, ~few hundred MB. Today's machines have terabytes; disk is no longer a concern for the typical solo developer.

**Q: What if I move the memory repo after init?**
The `.claude/memory/` symlinks become broken. Re-run `init-clone.sh <role> --force` for each affected clone, OR manually re-point the symlink with `ln -sf ../../<new-path>/<role> <clone>/.claude/memory`.

**Q: Multiple projects?**
Each project needs its own memory repo (`claude-personas-<app1>`, `claude-personas-<app2>`, ...). Memory content and conventions are project-specific anyway.

## Upgrading from v2

See [`MIGRATION.md`](MIGRATION.md) for a six-step walkthrough. Takes ~10 minutes per project.

**Why v3?** v2's mechanism (git worktrees + hash-derived symlinks) silently broke under Claude Code v2.1.49+ — that release collapses all worktrees into a single hash dir, so v2's per-worktree symlinks never load. v3 uses real independent clones, which each get their own native auto-memory dir.

Users on Claude Code <v2.1.49 can pin their memory repo to the `v2-final` git tag.

## License

[MIT](LICENSE)
