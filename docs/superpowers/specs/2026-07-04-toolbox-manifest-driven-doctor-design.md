# Toolbox: generalized manifest-driven doctor (design)

Date: 2026-07-04
Status: draft (pending Jin-Ho review)
Tracking: issue #42 (sub-issue of epic #27, roadmap item 3; scoping approved 2026-07-04)
Prior art: cerebrum `.agents/tools/sync.sh` (embedded topology), user-memory `tools/sync.sh` (user tier), this repo's `init-clone.sh` / `list-roles.sh` (role-clone constellation), per-vendor adapters spec (`2026-07-03-per-vendor-adapters-template-design.md`).

## Context

The epic promises a future-proof seam: a vendor changes format, you edit one adapter spec and rerun.
Today that seam is three divergent hand-rolled scripts, one per instance topology, and the template itself has none.
Every new instance re-derives the wiring knowledge and drifts, and the doctor backlog (external-hop orphans, multi-candidate role workspaces) has no owner surface.

The two hand-rolled scripts already agree on the core idioms, proven in daily use:

- Fix mode by default, `--check` for report-only with a nonzero exit on drift.
- Never touch a real (non-symlink) file: report DRIFT and continue, so one refusal does not hide others.
- Validate generated files (`.codex/hooks.json`) by exact absolute-path match against THIS instance's root, never by substring, and regenerate them wholesale in fix mode because they are fully derivable.

What they do not share is any way to know *what to check*.
Each hardcodes its own topology.
This spec generalizes the seam by making the instance declare its topology instead of the script inferring it.

## Scope

Four deliverables, all landing in this repo:

1. `scripts/doctor.sh`: one manifest-driven doctor covering the three substrate topologies (role-clone constellation, embedded, user tier), including the two backlog checks (external-hop orphan sweep, multi-candidate role workspace flag).
2. The manifest convention: `.agents/manifest`, flat `key=value`, documented in the README and written by `doctor.sh --init <topology>`.
3. `memory_cliff.py` flat-layout support, manifest-aware.
4. Fixture-based tests per topology in `scripts/tests/`, keeping `run_all.sh` green.

## Non-goals

- Skills packaging and distribution (#43, absorbs #21 + #17); the doctor may later verify whatever skills wiring #43 settles on.
- #14 (v3.1 migrate + validate scripts) and #25 (docstring-overlap checker) stay standalone.
- Adoption swaps are follow-ups, not gates: cerebrum and user-memory later replace their hand-rolled scripts with the template doctor (adaptation plus run against live data, per porting convention); the splice memory repo swap is the MM's call.
- The on-demand consolidation skill and extraction-as-proposal pass (epic backlog notes, 2026-07-03) stay parked on the epic; they are toolbox-adjacent but not integrity tooling.
- No rename work (sub-project 4); the manifest deliberately lives under `.agents/`, so it is already rename-proof.

## Design

### The manifest: `.agents/manifest`

One committed file at the instance root, in the vendor-neutral payload dir, for all three topologies.

The memory repo of a constellation has no `.agents/` dir natively, but the #39 MM self-mount already places an untracked `.agents/memory` symlink there; the manifest is the first *committed* file in that dir, and the existing `/.agents/memory` exclude line keeps the two regimes separate.

Syntax: flat `key=value` lines, `#` comments and blank lines ignored, repeatable keys where noted.
No quoting, no sections, no nesting.
It is parsed with grep/cut in bash and a ten-line reader in Python; it is never shell-sourced, so a manifest cannot execute code.
An unknown key or unknown value is an error, not a warning: a newer manifest must fail loudly on an older doctor rather than silently skip checks (`manifest_version` is the escape hatch for future format changes).

Key vocabulary, v1:

| Key | Values | Applies to | Meaning |
|---|---|---|---|
| `manifest_version` | `1` | all (required) | Format version; doctor refuses versions it does not know |
| `topology` | `role-clones` \| `embedded` \| `user-tier` | all (required) | Selects the check catalog; never inferred from repo shape |
| `memory_layout` | `roles` \| `flat` | all (required) | Drives payload checks and `memory_cliff.py` corpus discovery |
| `adapter` | `claude-code` \| `codex` \| `opencode` | all (repeatable) | Which vendor adapters must be wired; an undeclared adapter is not checked |
| `claude_hook` | repo-relative script path | embedded (repeatable) | Hook that `.claude/settings.json` must wire via `$CLAUDE_PROJECT_DIR` |
| `codex_hook` | repo-relative script path | embedded (repeatable) | Hook that `.codex/hooks.json` must wire with this clone's absolute path |
| `skills_mount` | `true` \| `false` (default) | embedded | Whether `.claude/skills -> ../.agents/skills` must exist |
| `opencode` | `global` (default) \| `per-clone` | role-clones | Which OpenCode wiring variant the clones use |

Constellation-specific facts that already have a committed home keep it: `.claude-personas/project.txt` and `main-role.txt` are not duplicated into the manifest (they move under the rename in sub-project 4, not here).
Role discovery inside a declared `role-clones` topology is not shape inference: role dirs with `MEMORY.md` at the memory-repo root *are* the declaration, and the suffix rules are `init-clone.sh`'s documented contract.

### `doctor.sh`: CLI contract

Ships in template `scripts/`, next to `init-clone.sh`; instances consume it from there (memory repos carry it by being template instances; embedded and user-tier instances copy it at adoption time, manifest alongside).

```
doctor.sh [--check] [--root PATH]
doctor.sh --init <topology>
```

- Default mode fixes; `--check` reports only and changes nothing (same contract as both existing sync.sh scripts).
- `--root` doctors another instance (defaults to the repo containing the script's cwd); everything anchors on `$root/.agents/manifest`.
- No manifest: the doctor refuses with a static explanation of the three topologies and the `--init` command, and exits 2. It never guesses the topology from repo shape - this extends the declaration-over-inference principle that settled role identity in #37/#38/#39; the manifest is to the toolbox what the `.agents/memory` symlink is to roles.
- `--init <topology>` writes a commented starter manifest for that topology and exits; it refuses to overwrite an existing one.
- Exit codes: 0 clean, 1 drift or error, 2 no/invalid manifest.

Fix-vs-report principle, applied uniformly: **fix what is derivable, report what is owned.**

- Fixable: symlinks (create missing, repoint wrong ones), fully generated files (`.codex/hooks.json`, per-clone `opencode.json`), dangling external-hop orphans.
- Report-only with guidance: real files or directories at a link path (never touched, same as today), `.claude/settings.json` hook stanzas (the file holds user-owned permissions config), the global `~/.config/opencode/opencode.json` entry (user-owned global config; the doctor prints the exact entry to add), reconciliation of a real external-hop directory that may contain silently-diverged memories.
- Not checkable, printed as a reminder: the per-machine Codex trust grants (repo trust plus `/hooks` review).

Output vocabulary stays `DRIFT:` / `FIXED:` / `ERROR:` plus a final `OK:` line, so existing eyes and greps keep working.

### Check catalog per topology

All topologies share: manifest is valid; the payload index exists (`.agents/memory/MEMORY.md` for `flat`, per-role `MEMORY.md` plus `shared/MEMORY.md` for `roles`); every declared hook script exists and is executable; `jq` present when a declared check needs it (drift if absent, and the jq-dependent checks are skipped loudly, not silently).

**Embedded** (generalizes cerebrum's `sync.sh`):

- In-repo links: `.claude/memory -> ../.agents/memory`, `CLAUDE.md -> AGENTS.md`, and `.claude/skills -> ../.agents/skills` when `skills_mount=true`.
- `claude-code` adapter: every `claude_hook` wired in `.claude/settings.json` via `$CLAUDE_PROJECT_DIR` (report-only); external CC hop `~/.claude/projects/<slug>/memory` present and resolving to `$root/.agents/memory` (fixable).
- `codex` adapter: `.codex/hooks.json` wires every `codex_hook` with THIS root's absolute path, exact-match; regenerated wholesale in fix mode.
- `opencode` adapter: root `opencode.json` `instructions` contains `.agents/memory/MEMORY.md` (report-only).

**Role-clone constellation** (run from the memory repo; generalizes the wiring contract of `init-clone.sh` and the audit walk of `list-roles.sh`):

Per role dir, walk the same candidates as `list-roles.sh` (memory-repo self-mount, no-suffix clone, suffixed clone) and check the one(s) that claim the role:

- Two-hop mount: `.agents/memory -> ../../<memory-repo>/<role>` (or `../<role>` for the self-mount) and `.claude/memory -> ../.agents/memory`.
- `.git/info/exclude` carries the entries `init-clone.sh` owns (fixable: append missing lines).
- External CC hop for that clone's slug, present and resolving through the clone's `.claude/memory` (fixable).
- `.codex/hooks.json` calls THIS memory repo's `inject-role-index.sh` with THIS role dir, exact-match (regenerable).
- OpenCode wiring per the declared `opencode` mode: `per-clone` checks the generated `opencode.json` (regenerable); `global` checks `~/.config/opencode/opencode.json` for the relative entry (report-only with the exact line to add).
- **Multi-candidate flag** (from PR #40 review): more than one candidate workspace claims the same role (e.g. a stale pre-#40 suffixed `memory_manager` clone alongside the self-mount) is DRIFT, report-only; the doctor never auto-picks a winner because retiring a workspace is a human decision.
- **External-hop orphan sweep** (from #34's hand-off): scan `~/.claude/projects/*/memory` for *dangling* symlinks (target no longer exists, the signature of a moved or deleted clone); report them all, and fix mode removes them. Live symlinks pointing at other instances are never touched, and a real directory there is never swept (it may hold silently-diverged memories; report for hand-reconciliation).

The orphan sweep necessarily looks at hops belonging to other instances (the projects dir is global); it is still safe because the *only* fix action is removing a symlink whose target does not exist, which by definition serves nobody.

**User tier** (generalizes user-memory's `sync.sh`):

- Canonical home hop `~/AGENTS.md -> $root/AGENTS.md`.
- Per-tool global adapters onto it: `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.config/opencode/AGENTS.md` (each gated on its `adapter` declaration).
- Payload sanity: `AGENTS.md` and the flat index exist.

### `memory_cliff.py` flat layout

Corpus discovery today is pure shape inference (a role dir is `MEMORY.md` plus a `shared` symlink); a flat instance finds zero roles and reports nothing, silently.

Change: read `$root/.agents/manifest` when present and take `memory_layout` from it; a new `--layout roles|flat` flag overrides; with neither, current role discovery remains the default (the template repo and the splice instance predate manifests and must keep working unchanged).

`flat` layout lints `$root/.agents/memory/MEMORY.md` as a single always-loaded unit: the whole file counts as tier 1, because flat-topology adapters inject the entire index at session start (there is no lazy role/shared split to subtract).
The three cliffs (14 rules / 200 lines / ~4000 tokens) and the baseline/ratchet flags apply unchanged.

### `list-roles.sh` stays

`list-roles.sh` remains the quick human-facing table (role, path, symlink health, git dirtiness); the doctor is the integrity surface with exit codes and a fix mode.
The overlap (broken-symlink detection) is cheap, and folding the table into a `doctor --list` view would couple a read-only glance to the manifest requirement.
Revisit at the rename (sub-project 4), when the script inventory gets touched anyway.

### Implementation notes

- Bash, `set -u`, one script with a function per topology plus the shared `need_link` idiom lifted from the two sync.sh scripts; matches the existing scripts/ toolchain and reuses check idioms proven in daily use (a Python rewrite adds a parse layer without removing any complexity, since the checks are symlink/exec/jq plumbing either way).
- `need_link` gains the `mkdir -p` parent-creation from the user-memory variant (superset of cerebrum's).
- All `$HOME`-relative checks go through `$HOME` (not `~` expansion in strings), so tests can point `HOME` at a fixture dir and exercise external-hop logic hermetically.

## Verification

Fixture tests, `scripts/tests/`, mirroring the init-clone harness (`test_helpers.sh` fixtures, `assert_*`, `print_summary`); `run_all.sh` stays green:

- `test_doctor_role_clones.sh`: build the existing clone fixture, wire via `init-clone.sh` (incl. `--self`), `doctor.sh --check` exits 0; then inject drifts one at a time - deleted mount, repointed hop, stale absolute path in `.codex/hooks.json`, dangling external hop under a fixture `$HOME`, a second suffixed clone claiming an already-mounted role - and assert each is named with exit 1, fix mode repairs the fixable ones, and an immediate re-`--check` is clean with the multi-candidate DRIFT (report-only) as the sole survivor.
- `test_doctor_embedded.sh` / `test_doctor_user_tier.sh`: same clean/drift/fix/re-check cycle on new `make_embedded_fixture` / `make_user_tier_fixture` helpers.
- `test_doctor_manifest.sh`: no manifest refuses with exit 2 and guessing nothing; unknown key, unknown topology, and unsupported `manifest_version` each refuse; `--init` writes a starter that immediately parses, and refuses to overwrite.
- `test_memory_cliff.sh` / `test_memory_cliff.py` extended: flat layout via flag and via manifest; no-manifest role discovery unchanged.

Live smoke (verify by running, read-only): `doctor.sh --check --root` against the real cerebrum and user-memory checkouts with hand-written manifests, and against a scratch constellation wired by `init-clone.sh`; findings feed back into this spec before the implementation PR merges.

Acceptance-criteria traceability (#42): drifted/clean check per topology and fix-then-clean land in the three topology tests; manifest refusal in `test_doctor_manifest.sh`; orphan sweep and multi-candidate flag in the constellation test; `memory_cliff.py` flat layout in the extended cliff tests; harness coverage is the test files themselves.

## Decision log

| Decision | Alternative rejected | Rationale |
|---|---|---|
| Manifest at `.agents/manifest`, all topologies | `.claude-personas/manifest` in the memory repo | Vendor-neutral payload dir, uniform across topologies, rename-proof; `.claude-personas/` is CC-branded and due for sub-project 4 |
| Flat `key=value`, never sourced | JSON or YAML manifest | Zero parse dependency (jq stays a check-time dep only), greppable, diff-friendly; a sourced file could execute code |
| Unknown key/value is an error | Ignore-unknown forward compatibility | A newer manifest on an older doctor must fail loudly, not silently skip checks; `manifest_version` covers format evolution |
| Fix by default, `--check` report-only | Check by default, `--fix` opt-in | Continuity with both proven sync.sh contracts and the AC wording; fix mode is already safe because real files are never touched |
| Fix what is derivable, report what is owned | Fix everything the doctor can write | `settings.json` and global opencode config carry user-owned content; regenerating them wholesale would clobber it |
| Orphan sweep removes dangling links only | Sweep any hop not matching this instance | A dangling link serves nobody by definition; a live link may belong to another instance, and a real directory may hold diverged memories |
| Multi-candidate flag is report-only | Fix mode picks the manifest-preferred workspace | Retiring a workspace discards a working tree someone may be using; that is a human decision, the doctor's job is to make it visible |
| One bash script, function per topology | Python rewrite, or one script per topology | Matches scripts/ toolchain, reuses proven idioms; per-topology scripts would re-fragment the seam this spec exists to close |
| `list-roles.sh` stays standalone | Absorb into `doctor --list` | Read-only glance should not require a manifest; revisit at the rename |
| `memory_cliff.py` defaults unchanged without a manifest | Require a manifest everywhere | Template repo and splice instance predate manifests; breaking them for symmetry buys nothing |
