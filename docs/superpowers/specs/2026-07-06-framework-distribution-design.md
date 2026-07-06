# Framework distribution design (issue #43)

**Date:** 2026-07-06
**Status:** draft - live-probe results recorded 2026-07-06 (section 9); locks at PR merge
**Issues:** #43 (parent), #50 (this spec), #21 + #17 (absorbed), #27 (epic), #49 (role tier - must not be foreclosed)

## 1. Identity: installable framework, not a template

claude-personas (agent-personas at rename, epic item 4) is an installable, versioned framework for vendor-neutral agent memory and skills across Claude Code, Codex, and OpenCode.
It is no longer a template repo.
Starter content becomes a scaffold feature (`--init`, examples), not the product identity.
Instances depend on the framework through a recorded pin and update explicitly.

Motivation: every instance today hand-assembles its kit (cerebrum carries a verbatim doctor.sh copy, user-memory another, splice its own skill variants, the user tier has drifted between `~/.agents/skills` and `~/.claude/skills`).
Fixes land in one place and reach the others by manual copying, or never.
This is the known "project drift" failure of copy-once templates; the scaffolding ecosystem's own answer (copier update, cruft) is to make templates updatable dependencies, and the config-framework world (oh-my-zsh) converged on installed framework + owned customization dir + updater.
We adopt that shape.

Mechanical consequence: the repo's GitHub `is_template` flag is switched off when the installer ships.
The repo description text is refreshed at the #4 rename, not now.

## 2. Three content classes, three contracts

| Class | Lives in this repo at | Lands in instance at | Update contract |
|---|---|---|---|
| Framework payload | `framework/` (`framework/skills/`, `framework/tools/`, `framework/hooks/`) | `.agents/tools/`, `.agents/skills/<name>/`, `.agents/hooks/lib/` | Installed + synced; upstream-owned; enumerated file-by-file in a committed `framework/FILES` manifest |
| Starter / example content | `examples/` | wherever the user copies it (or `--init` scaffolds it) | Copy-once; instance-owned forever; never synced |
| Instance content | never in this repo | `.agents/memory/`, `.agents/manifest`, instance-authored skills | Never distributed; never touched by sync |

The `FILES` manifest is the framework/content boundary made explicit - declaration over inference, same principle as `.agents/manifest`.
This hardens #21's non-negotiable invariant (framework scaffolding only, never memory content) into architecture.

**Precedence rule (the oh-my-zsh `$ZSH_CUSTOM` lesson):** framework and instance skills coexist in the instance's `.agents/skills/`.
On a name collision the instance's copy wins and sync refuses to overwrite it, reporting "shadowed, instance-owned".
Customizing never requires forking the framework payload.

Repo reshuffle implied: current `scripts/` (doctor.sh, memory_cliff.py, init-clone.sh, list-roles.sh) and the shipped `skills/load-persona-memory` move under `framework/`.
The `framework/hooks/` class has exactly one concrete member today: `scripts/inject-role-index.sh` (the SessionStart index-injection adapter script) moves to `framework/hooks/` and lands in `.agents/hooks/lib/`.
The split it encodes: the callable script library is framework payload (synced), while the adapter entries that invoke it (`.codex/hooks.json`, `.claude/settings.json`) stay instance-owned wiring - the doctor's territory, never sync's.
`examples/hooks/*.md` guidance stays copy-once example content (class 2); the two are different things.
`examples/` stays where it is.
Instances change nothing structurally; `.agents/` keeps its existing shape, so existing instances adopt by re-install, not re-layout.

## 3. Install / sync mechanics

One new distributed script: `framework/tools/install.sh`.
It is part of the payload, so instances self-update with it.
It is deliberately NOT folded into doctor.sh: doctor answers "is my wiring intact?" (integrity, #42), install answers "get/refresh the payload" (distribution, #43).
Same manifest, same conventions, separate verbs.

Commands:

- `install.sh --into <target>` (run from a framework clone): first install. Copies exactly the `FILES` set into the target's `.agents/` layout and stamps the pin. It wires no symlinks - adapter wiring stays the doctor's fix-mode job, so exactly one place creates symlinks.
- `install.sh --sync` (run from inside an instance): update. Re-resolves the framework source, re-copies the declared set at the new ref, updates the pin.
- `--check` on both: dry-run report only.

Sync refusal semantics (report, never clobber):

- instance-shadowed file: kept, reported as "shadowed, instance-owned".
- locally modified framework file (differs from the pinned ref's copy): kept, reported with `--force-file <path>` as the explicit override.
- file dropped upstream from `FILES`: reported as "orphaned framework file, remove with --prune"; never auto-deleted (same conservatism as the doctor's orphan sweep; avoids the #47 unreachable-target bug class).
- unknown/missing instance manifest: hard error (doctor's exit-2 convention).

Source resolution: new manifest key `framework_source=<path-or-url>`; git URLs allowed later.
Default when the key is absent: exactly one candidate, the sibling clone `<instance-toplevel>/../claude-personas` (post-rename `../agent-personas`, checked first, old name still accepted) - no wider candidate walk; any other topology requires an explicit `framework_source`, and install/sync exit-2 when the default candidate is missing.
Sync shells out to `git -C <source> fetch` and copies from a ref; no network code beyond git.

Manifest grows two doctor-validated keys: `framework_source` and `framework_ref=<tag-or-sha>` (stamped by install/sync).
These replace the hand-written provenance/re-sync header cerebrum's manifest carries today; that header retires at adoption.
`doctor --check` gains one staleness line: pin vs source HEAD ("framework N commits behind pinned source" / "pin not found in source - fetch or fix").

What sync never does: touch `.agents/memory/`, manifest values other than `framework_ref`, instance skills, or anything not in `FILES`.

**Role-tier readiness (#49):** the installer's mount vocabulary and manifest keys are written so a fourth mount source (role@global) slots in later without relayout.
Concretely: install/sync operate only on declared file sets and never assume `.agents/` has exactly three content sources; manifest key naming leaves room for `role_source`-style keys; nothing in this spec hardcodes the two-axis scope model away.

## 4. Vocabulary: instance repo, `<scope>-personas`

The repo hosting a project's agent-personas instance is the **instance repo** (abstract term, all topologies).
In the constellation topology it is a sibling repo conventionally named **`<scope>-personas`** (e.g. `splice-neoepitope-pipeline-personas`); prose may say "personas repo".
Substrate-only instances (no roles module, e.g. the user tier's `user-memory`) may keep a `-memory` name, where it remains accurate.
The term "memory repo" is retired (formerly-called note where helpful), because the instance repo now carries role identities, memory, AND the installed framework payload.
Epic item 4's naming proposal updates from `<scope>-memory` to `<scope>-personas`; whether/when splice's actual repo renames stays MM's call.
Retirement is forward-only by design: this spec fixes the target vocabulary; existing docs that still say "memory repo" (CONVENTIONS.md, README) migrate in the implementation and rename PRs, not in this one.

## 5. Why one instance repo per project (and when to split)

One instance repo with scoped role mounts matches both relevant bodies of practice:
the 2026 multi-agent-memory consensus (hybrid scoped multi-level memory - shared + isolated components in one system - is the production standard; fully-isolated per-agent stores are the known-fragmenting early pattern), and repo-architecture practice (split triggers are independent lifecycles, distinct access-control boundaries, differing retention, or scale - none of which hold between roles of one project).
The monorepo weakness (coarse write access) is neutralized by the MM-sole-committer governance model, itself web-verified against CODEOWNERS/zero-trust practice (2026-06-18).

Trip-wires that would justify splitting a role out (documented, not assumed away):

1. a role with different confidentiality (external collaborator, secrets others must not read) - repo-granular access is the only real isolation GitHub offers;
2. a role with an independent lifecycle (outlives or moves between projects) - **this one is already tripped as a felt restriction; it is addressed architecturally by the role tier (#49), not by splitting project instance repos**;
3. multiple humans owning different roles (repo-per-role then maps to real trust boundaries).

## 6. Per-topology skills wiring

Memory wiring is untouched; this adds the skills leg only.

| Topology | Codex / OpenCode | Claude Code |
|---|---|---|
| Embedded (e.g. cerebrum) | native scan of `.agents/skills/` | `.claude/skills -> ../.agents/skills` (already live, doctor-checked via `skills_mount=true`) |
| Role-clone constellation (e.g. splice) | per-clone `.agents/skills -> <instance-repo>/.agents/skills` (untracked, `.git/info/exclude`, like the memory mount) | `.claude/skills -> .agents/skills` hop beside it |
| User tier (`~`) | native scan of `~/.agents/skills/` | `~/.claude/skills -> ~/.agents/skills` whole-dir link - probe-gated (probe 3); fallback per-skill links, doctor-checked |

Constellation note: the instance repo carries the installed framework payload once; role clones mount it - single copy per project, consistent with the memory flow.
`init-clone.sh` grows the two skills links plus `list-roles.sh`/doctor awareness.
`install.sh --into` handles embedded, user-tier, and instance-repo targets.

## 7. examples/skills (#17 remainder)

`examples/hooks/` already exists (PR #19) and satisfies #17's hooks half (as `.md` files rather than the `.json` the issue text imagined - accepted deviation, noted when closing #17).
This sub-project lands the skills half:

- `examples/skills/morning-routine/` - pedagogical demo skill, the tier-3 mirror of `examples/pm/feedback_morning_routine.md` (greeting trigger, phased ritual, go-signal pacing), standard frontmatter.
- `examples/skills/README.md` - tier framing (skill = tier 3 in the visibility ladder), the memory<->skill relationship ("memory documents WHY; the skill carries the ritual"), how each of the three tools discovers skills, and one paragraph pointing at `framework/skills/load-persona-memory` as the production-grade reference.

Examples keep copy-once semantics (content class 2).

## 8. Versioning and releases (minimal)

- Annotated git tags on this repo: `framework/v1`, `framework/v2`, ...
- `framework/CHANGELOG.md`: one "what breaks / what to do" line per entry (the v3.1 layout-bump lesson, #14).
- `install.sh --sync` prefers a tag; syncing to a bare SHA works but warns.
- No semver ceremony while there is a single consumer.

Relation to the existing root `CHANGELOG.md` (semver headers up to `[3.1.0]`): that file versioned the **template era** and freezes at the identity switch, gaining one final entry that points forward to `framework/CHANGELOG.md`.
The tag line starts fresh at `framework/v1` because it versions a new artifact - the installed payload - not the template; it deliberately does not map onto the 3.x series.
The existing `v1.0`...`v3.1.0` tags keep marking template releases; the `framework/` tag prefix is a disjoint namespace, so the two lines cannot collide.
Post-switch changes outside the payload (examples, docs) are not changelogged anywhere; git history suffices.

## 9. Live probe (before spec lock)

Results are recorded here before the spec PR merges; expected defaults below, with the flip procedure if a probe surprises.

| # | Probe | Expected default | If it flips |
|---|---|---|---|
| 1 | `claude plugin init` scaffold shape: does our layout map onto the plugin structure? | partial mapping at best | informs #21 disposition only |
| 2 | Plugin scope: does CC treat `.claude/skills` plugins per-project or globally? (#21 crux) | effectively global | if cleanly per-project AND low-friction: document plugin as optional CC side door |
| 3 | Whole-dir symlink: does CC load skills through `~/.claude/skills -> ~/.agents/skills` (user tier) and through the repo-level hop? | works (repo-level already proven on cerebrum) | user tier falls back to per-skill links, doctor-checked |
| 4 | Codex + OpenCode user tier: do both actually scan `~/.agents/skills/`? | yes (repo-level scanning proven; user-level half-tested) | per-tool user-level adapter entries, doctor-checked |
| 5 | Shadowing: same-name skill in instance and framework - which wins per tool? | undefined/first-scan-wins | if a tool double-loads or errors: sync's install-time refusal remains the enforcement; document per-tool behavior |

**Probe results (recorded 2026-07-06; live runs on Claude Code 2.1.201, codex-cli 0.142.5, opencode 1.17.13):**

1. **CONFIRMED (partial mapping).** `claude plugin init` scaffolds `~/.claude/skills/<name>/` with `.claude-plugin/plugin.json`, a root `SKILL.md`, and optional `skills/`, `agents/`, `hooks/hooks.json` + TypeScript/bun `hooks-handlers/`, `.mcp.json`.
   Skills map 1:1 onto our layout; tools, memory, and the instance manifest have no plugin slot; the whole mechanism is CC-only, so it cannot carry the vendor-neutral payload.
2. **FLIPPED - plugins are cleanly per-project, via two mechanisms.** (a) `claude plugin install --scope user|project|local`: project scope commits only an `enabledPlugins` entry to `.claude/settings.json` (verified live in a scratch repo); content stays in the per-user cache, and since CC 2.1.195 teammates must explicitly consent-install.
   (b) Project-level skills-dir plugins: `./.claude/skills/<name>/.claude-plugin/plugin.json` auto-loads as `<name>@skills-dir` (since 2.1.157), workspace-trust-gated.
   Friction is low (one committed manifest file), so the flip clause applies - see the #21 disposition below.
3. **CONFIRMED (works).** With `~/.claude/skills -> ~/.agents/skills` as a whole-dir symlink, a live CC session discovered the discriminator skills that exist only in `~/.agents/skills` (`find-skills`, `skill-creator`); original layout restored after the probe.
4. **CONFIRMED (yes, both).** Codex natively scans `~/.agents/skills` at user level (listed exactly its valid skills; did not read `~/.claude/skills`).
   OpenCode scans both `~/.agents/skills` and `~/.claude/skills` at user level.
5. **CONFIRMED (divergent, no consistent winner).** Same-name skill at user tier and project tier: CC 2.1.201 loads a single entry and the **project** copy wins (replicated twice; contradicts the documented user>project skill precedence, so treat tool-tier shadowing as unstable across versions).
   Codex **double-loads both** entries.
   OpenCode loads a single entry and the **user** copy wins.
   Consequence per the flip clause: sync's install-time refusal is the only enforcement the framework relies on; per-tool behavior is documented here and must not be load-bearing.

**#21 disposition (decided by probes 1-2): documented optional CC install path.**
The plugin format is a CC-only side door on top of the framework payload (a committed `.claude-plugin/plugin.json` inside a skill dir, or a marketplace entry later), never the primary distribution channel - it cannot carry tools, memory wiring, or the manifest, and Codex/OpenCode ignore it.
#21 closes citing this section.

## 10. Testing

Same bash-fixture harness as #42:

- Per-topology fixture tests: install -> verify layout -> mutate upstream -> sync -> assert the content-class contracts (framework file updated; shadowed file refused; memory untouched; orphan reported, not deleted; pin stamped).
- Refusal-path tests: modified framework file, unknown manifest, missing source.
- Read-only live smoke on cerebrum + user-memory + a scratch constellation before the implementation PR merges.

## 11. Tracking, sequencing, non-goals

- This spec: PR closes #50 (Refs #43).
- Implementation: dev-linked branch so the PR auto-closes #43; multi-PR allowed if the reshuffle and the installer land separately.
- #17 closes when examples/skills lands; #21 closes from probe evidence.
- Adoption follow-ups on epic #27 (same pattern as #42): cerebrum and user-memory re-install via the installer (their manifest provenance headers retire); splice adoption = MM's call.
- Non-goals: wiring-integrity checks (stay with doctor, #42); the role tier itself (#49 - only readiness is in scope here); splice repo rename (MM).
