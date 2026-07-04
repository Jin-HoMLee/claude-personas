# Per-vendor adapters, generalized for the template (design)

Date: 2026-07-03
Status: approved (brainstormed with Jin-Ho; approach A selected from three candidates)
Tracking: issue #32 (sub-issue of epic #27, roadmap item 2)
Prior art: cerebrum substrate spec (`cerebrum/docs/superpowers/specs/2026-07-02-vendor-agnostic-memory-substrate-design.md`), knowledge-consolidation two-module spec (`2026-07-02-knowledge-consolidation-two-module-design.md`), splice PR `claude-personas-splice-neoepitope-pipeline#93`.

## Context

The template today wires exactly one tool.
`init-clone.sh` creates a role clone with a `.claude/memory -> ../../<memory-repo>/<role>` symlink, which only Claude Code reads.
Cerebrum proved the three-vendor adapter pattern (Claude Code, Codex, OpenCode), but only for the embedded topology, where memory lives inside the same repo under `.agents/memory/`.
Role clones are the harder case: they are clones of the project repo, so adapter files cannot be committed without leaking tool config onto every collaborator.

The two-module spec explicitly deferred one decision to this spec: whether `.agents/` supersedes the 2026-05-17 memory-under-`.claude` convention for the template's own role clones.
This spec decides it: yes, via a two-hop layout (decision log, row 1).

All vendor-capability claims below were re-verified against live docs and source on 2026-07-03 (three parallel research passes: Codex, OpenCode, cross-tool standards).

## Scope

Five deliverables, all landing in this repo:

1. Three-vendor role-clone wiring in `init-clone.sh`.
2. A generalized, vendor-neutral `load-persona-memory` skill (absorbs the role-resolution algorithm of splice PR 93; the splice instance stays untouched).
3. `examples/substrate/` with the embedded-topology adapter set as copy-and-adapt templates.
4. README section plus a per-vendor caveats doc.
5. Live-test results for the four open behavior questions (listed under Verification).

## Non-goals

- No memory-repo layout restructure: role dirs stay at the memory repo root.
- No generalized `sync`/`doctor` (epic sub-project 3; cerebrum's `sync.sh` says so in its own header).
- No rename (epic sub-project 4): this spec deliberately keeps the current `claude-personas-<app>` memory-repo naming throughout; the two-module spec's target `<endeavor>-memory` naming lands with that sub-project.
- No changes to the splice instance: MM is sole committer there; adoption happens via a handoff issue if MM wants it.

## Design

### The mount (role clones)

`init-clone.sh` creates one untracked symlink per clone:

```
<clone>/.agents/memory -> ../../<memory-repo>/<role>
```

This symlink is the single role-defining artifact.
The clone describes itself on disk: symlink target dir name = role, target path = memory repo.
All three vendor adapters point at it, so no vendor's dotdir is the mount another vendor depends on.

Untracked-ness moves from `.gitignore` appends to `.git/info/exclude` (per-clone, never dirties the project repo).
Existing committed `.gitignore` lines from v3.1 instances keep working; the script just stops adding new ones.

### Claude Code adapter

Two pieces, not one.

In-repo: a hop symlink `.claude/memory -> ../.agents/memory`.
This is what the model's file-relative reads resolve through, and it keeps the clone self-describing.

External: Claude Code's auto-memory loader reads `~/.claude/projects/<slug>/memory`, not the in-repo path.
Self-review of this spec against the live splice clones found that they load role memory through external symlinks created in the v2 era, which `init-clone.sh` never creates; a fresh v3.1 install has no such symlink and likely gets an empty real directory there instead (silent divergence, the exact failure cerebrum's `sync.sh` guards against).
So the template's CC wiring must own the external hop too: `init-clone.sh` creates `~/.claude/projects/<slug>/memory -> <clone>/.claude/memory` (or repairs a wrong one), same as cerebrum's `sync.sh` does for the embedded case.
`<slug>` is Claude Code's own derivation of the clone's absolute path, which is undocumented; the observed rule is path separators replaced by `-`, leading separator included (`/Users/x/proj` becomes `-Users-x-proj`), but the script's reproduction of it is only correct if verified against a live loader, so live test 4 also records the derivation.
Live test 4 (below) decides whether current Claude Code has since gained native in-repo `.claude/memory` loading; if it has, the external hop is dropped and only doctored for older versions.
Documented alternative for symlink-hostile setups (e.g. Windows without developer mode): `autoMemoryDirectory` in `.claude/settings.local.json`, now an officially documented setting (absolute paths only, any settings scope).

v3.1 clones migrate by re-running `init-clone.sh --force`, which rewires the direct symlink into the two-hop form using the script's existing backup semantics, and creates or repairs the external hop.

### Codex adapter

`init-clone.sh` generates a per-clone `.codex/hooks.json` (absolute paths, matching cerebrum's pattern) with a SessionStart hook that injects the role index and shared index via `additionalContext`.
The inject script itself lives in the memory repo (committed, shared across that project's clones); the generated hook calls it with the role dir as argument.
The script self-bounds its payload and appends a `[TRUNCATED ...]` trailer when it cuts, so a hard vendor-side cap never silently eats the index tail.
Known friction, documented rather than worked around: Codex trust is two-layer (per-repo trust, then per-hook-definition review via `/hooks`, re-triggered whenever the generated file changes), and hook timeouts are seconds.

### OpenCode adapter

Preferred wiring: one global `~/.config/opencode/opencode.json` `instructions` entry with the relative pattern `.agents/memory/MEMORY.md`.
OpenCode resolves relative instruction entries against the session's project directory (globbing upward to the worktree root), so a single one-time global entry serves every wired clone with zero per-clone files.
Gate: OpenCode's glob layer does not follow symlinked directories (`follow: false`; multiple open upstream bugs), and in a role clone `.agents/memory` is a symlink.
A live test decides the default; if glob-through-symlink fails, the fallback is `init-clone.sh` writing a per-clone `opencode.json` with the absolute resolved path, excluded via `.git/info/exclude`.
Both variants ship documented either way.

### init-clone.sh changes

- Creates the `.agents/memory` mount plus the `.claude/memory` hop (was: single direct symlink).
- Creates or repairs the external `~/.claude/projects/<slug>/memory` symlink (subject to live test 4; refuses to touch a real directory with content, reporting it for hand-reconciliation instead).
- Generates `.codex/hooks.json`; prints the one-time trust steps (repo trust plus `/hooks` review) instead of pretending they are scriptable.
- Prints the one-time OpenCode step: the global `instructions` entry to add (or writes the per-clone fallback file, if the live test selected that default).
- Writes `.git/info/exclude` entries for everything it creates.
- `--force` migrates v3.1-shaped clones (existing backup and rollback contract unchanged).
- Failure handling keeps the fresh-clone rollback contract, and per-vendor wiring failures are independent: a refused symlink or missing `jq` reports and continues, so one vendor's problem does not kill the other two (cerebrum `sync.sh`'s report-and-continue behavior).

### The generalized load-persona-memory skill

One vendor-neutral skill directory in the template: `skills/load-persona-memory/SKILL.md`.
Frontmatter is strictly the agentskills.io standard fields (`name`, `description`); Claude-specific extension fields are omitted so all three tools consume the same file.

Install model: user-level, once per machine.
Symlink or copy the skill dir into `~/.agents/skills/` (natively scanned by Codex and OpenCode) and `~/.claude/skills/` (Claude Code; per-skill-dir symlinks are docs-supported).
Any clone on the machine then finds it; no per-instance copies.

Role resolution drops splice's hardcoded mappings and becomes pure convention-walking, in order:

1. Read the workspace's `.agents/memory` symlink target (new canonical); target dir name = role, target path = memory repo.
2. Else read `.claude/memory` the same way (v3.1 legacy).
3. Else enumerate candidates: every sibling directory of the workspace (same parent dir) containing a `.claude-personas/project.txt` marker.
   Verify each by comparing the workspace's `origin` remote against that `project.txt`, keeping PR 93's URL normalization (scp-like SSH, scheme SSH, and HTTPS forms compare equal); exactly one match wins, zero or multiple matches fail with a report, never a guess.
4. If the workspace is itself the memory repo, role = `memory_manager`.
5. Last resort: clone-naming conventions as implemented by `init-clone.sh` (`main-role.txt` else `developer` for the no-suffix clone; `<project>-<role>` for suffix clones).

Read order (role index, then shared index, as routing tables), file-relative path rules, and the governance section (read freely; MM is sole committer of a memory repo; do not touch another role's dir) carry over from PR 93 intact.

Per-tool role of the skill: for Codex and OpenCode it is the lazy-read complement to the always-loaded index and the fallback when hooks are not yet trusted; for Claude Code it is the mid-session refresh (the `cerebrum-memory-check` pattern) and the escape hatch from unwired directories.

### Embedded-topology examples

`examples/substrate/` carries the cerebrum-proven adapter set as copy-and-adapt templates:

- `.claude/`: the `memory` and `skills` symlinks plus the `settings.json` permissions and hook stanza.
- `.codex/hooks.json` with an `<ABSOLUTE-REPO-PATH>` placeholder and a note that regeneration tooling is sub-project 3.
- Root `opencode.json` with the `instructions` entry.
- `CLAUDE.md -> AGENTS.md` symlink (Claude Code does not read `AGENTS.md` natively; the symlink stays load-bearing).
- A README explaining the topology choice (embedded vs role-clones) via the boundary test from the two-module spec: does a decision in repo A change what an agent does in repo B?

### README section

The README gains one section covering: the three-vendor wiring at a glance (what `init-clone.sh` creates per clone, and that `.agents/memory` is the vendor-neutral mount), the one-time per-machine steps the script cannot perform (Codex repo trust plus `/hooks` review, the OpenCode global `instructions` entry, the user-level skill install), and a pointer to the caveats doc for the sharp edges.

### Caveats doc

One per-vendor caveats section collecting, with dates:

- Codex two-layer trust and per-hook re-trust on hook-file change.
- Codex app does not load global `~/.codex/AGENTS.md` (openai/codex#27705, open); CLI does.
- Codex `additionalContext` ceiling: the previously observed ~2.4k-token truncation matches neither current docs nor current source (hook path uncapped in main; a sibling context path caps at 1k tokens); live re-test result recorded here.
- OpenCode snapshot/undo cannot cover files behind a symlink (anomalyco/opencode#31984, open; trigger is exactly the `.claude/x -> .agents/x` pattern); git covers recovery.
- OpenCode repo moved orgs: `sst/opencode` -> `anomalyco/opencode`.
- OpenCode glob-through-symlink behavior for `instructions` (live-test result recorded here).
- Latent v3.1 gap (found during spec self-review): `init-clone.sh` never created the external `~/.claude/projects/<slug>/memory` symlink the CC auto-memory loader reads, and `list-roles.sh` does not audit it; existing instances work on v2-era leftovers or manual wiring. Fixed by this sub-project; live test 4 records whether current CC still needs it.

## Verification (three-tool, by running, on a throwaway)

Scratch project repo plus scratch memory repo with two roles; nothing touches splice.
Per tool:

- Fresh `init-clone.sh` wiring succeeds and the doctor-eye check of created artifacts passes.
- The always-loaded index is actually present in a live session.
- Lazy per-file read follows the index to a specific memory file.
- The skill resolves memory repo and role correctly from a role clone, from the memory repo itself, and from an unwired directory.

Plus one migration test: `--force` on a v3.1-shaped clone lands the two-hop layout.

Named live tests whose results feed back into this design:

1. OpenCode glob-through-symlink on a relative global `instructions` entry (decides the OpenCode default wiring).
2. Codex `additionalContext` ceiling (replaces the stale ~2.4k figure in cerebrum's docs and memory).
3. Codex per-hook re-trust flow (documents the real onboarding friction).
4. Claude Code fresh-clone auto-load with ONLY the in-repo `.claude/memory` symlink, no external hop (decides whether the external symlink is still load-bearing; found during spec self-review - the v3.1 template never creates it, and live splice clones ride v2-era leftovers).
   Same test also records the `<slug>` derivation the loader actually uses, since the external hop is only correct if `init-clone.sh` reproduces it exactly.

## Decision log

| Decision | Alternative rejected | Rationale |
|---|---|---|
| Two-hop mount: `.agents/memory` canonical, `.claude/memory` a hop onto it | Keep `.claude/memory` as canonical (approach B) | No vendor's dotdir should be the mount other vendors depend on; settles the question the two-module spec deferred here |
| Symlink mount stays the role signal | Config-first, no symlinks, marker file for role (approach C) | Clone stays self-describing on disk; PR 93 resolution keeps its primary signal; per-machine config scatter is harder to doctor. `autoMemoryDirectory` kept as documented CC fallback |
| `.git/info/exclude` for per-clone artifacts | Append to project `.gitignore` | A project repo you may not own should not need a commit to host a wired clone |
| OpenCode wired globally (one entry, all clones) | Per-clone `opencode.json` | No local config variant exists upstream (anomalyco/opencode#17232 open); global relative entries resolve per-project; fewer per-clone artifacts. Falls back per-clone if the symlink-glob test fails |
| Skill installed at user level | Per-instance skill copies | `~/.agents/skills` is natively scanned by Codex and OpenCode, `~/.claude/skills` by CC; one install serves all clones |
| Skill frontmatter restricted to standard fields | Claude-extended frontmatter | agentskills.io standard (`name` + `description`) is confirmed cross-vendor; extensions are ignored at best |
| Embedded topology ships as examples plus docs | Scripted embedded bootstrap | Regeneration/doctor tooling is sub-project 3; examples generalize what cerebrum already runs without new mechanism |
| `init-clone.sh` changes in scope, `sync.sh` out | Both in, or both out | init-clone is roles-module wiring (this sub-project); sync/doctor is toolbox (sub-project 3, per cerebrum sync.sh's own header) |

## Web-verified capability basis (2026-07-03)

- Codex: project `.codex/hooks.json` confirmed (SessionStart, Claude-style schema, timeouts in seconds); two-layer trust confirmed; skills scan `.agents/skills` (repo) and `~/.agents/skills` (user); global AGENTS.md at `~/.codex/AGENTS.md` (CLI yes, app gap #27705); the vendor-neutral `~/.agents/` instructions home was declined-as-covered (openai/codex#24524).
- OpenCode: project `opencode.json` `instructions` confirmed; no local variant (#17232); global relative entries resolve against the session's project dir; skills scan `.agents/skills`, `.claude/skills`, `.opencode/skills` at project and global level; AGENTS.md native with CLAUDE.md fallback; snapshot-symlink bug #31984 open.
- Claude Code: does NOT read `AGENTS.md` natively (docs explicit; symlink or `@` import required); scans only `.claude/skills` (not `.agents/skills`); auto-memory current, redirectable via documented `autoMemoryDirectory`.
- Cross-tool: AGENTS.md standard stewarded by AAIF (20+ tools, CC the notable holdout); SKILL.md (agentskills.io) confirmed cross-vendor with `name` + `description` required; `.agents/skills/` is a widely-adopted convention, deliberately not a location mandate; no formal `.agents/` directory spec exists.
