# Knowledge consolidation + two-module architecture (sub-project #6)

**Date:** 2026-07-02
**Status:** Draft for review
**Tracking:** [claude-personas#28](https://github.com/Jin-HoMLee/claude-personas/issues/28), sub-project #6 of epic [claude-personas#27](https://github.com/Jin-HoMLee/claude-personas/issues/27)
**Sequenced after:** sub-project #1 ([cerebrum#75](https://github.com/Jin-HoMLee/cerebrum/issues/75), substrate proven on cerebrum at project scope)

Naming note: this doc says **agent-personas** when speaking of the framework's end state; the rename from claude-personas is itself sub-project #4 and has not happened yet.
Bare `#N` references are claude-personas issues / sub-projects under epic #27.

## Problem

The splice endeavor accumulated a large body of hard-won knowledge and tooling that is trapped in its repos and invisible to every other project:

- ~84 shared feedback rules + 4 references in `claude-personas-splice-neoepitope-pipeline/shared/`, many project-independent (branch naming, GitHub workflow, pacing, memory hygiene).
- Role-dir rules: developer 30 / pm 21 / scientist 46 / memory_manager 27 files (a mix of portable and splice-specific).
- Tooling absent from the template: `memory_corpus.py`, `memory_engram.py`, `memory_xref.py`, git hooks (`commit-msg`, `pre-commit` + tests), the `personas-memory` plugin (3 skills), 7 Python guard hooks and a `coordination.md` command in the splice code clones.
- Domain knowledge (splice biology, pipeline specifics) - explicitly not portable.

Goal: the portable part becomes available to all repos and projects, on Claude Code, Codex, and OpenCode, without breaking governance boundaries (the splice project's dedicated **Memory Manager (MM)** is sole committer of the splice memory repo).

## Architecture: two decoupled modules + a toolbox

The consolidation surfaces a structural fact: claude-personas has been bundling two orthogonal things.
agent-personas makes the split explicit.

1. **Substrate module** - the memory pattern, with no content and no identity in it:
   - Storage format: one fact per Markdown file, YAML frontmatter (`name`, `description`, `type`), `[[links]]`, filename prefixes.
   - The index: `MEMORY.md`, always loaded, one line per file; the `description` hooks drive selection.
   - Loading tiers: always-loaded index, lazy per-file read, git history as deep provenance.
   - Mounting: `.agents/` payload + thin per-vendor adapters (spec #1; whether `.agents/` also supersedes the 2026-05-17 memory-under-`.claude` convention for the template's own role clones is decided in specs #1/#2, not here).
   - Write + lifecycle convention: valid frontmatter, index line added, dedup-check first, delete-when-wrong.
   The substrate is usable roleless (cerebrum is the existence proof) and instantiable at any scope.
2. **Roles module** - identity prompts + the clones topology, layered on top of substrate mounts.
   A role = an identity + a set of mounts.
   Roles consume memory; they are not made of it.
3. **Toolbox** - `sync`/`doctor`, memory scripts, hooks, skills - serving both modules.

This matches the field's split (standalone memory layers such as Zep/Mem0/TiMem vs agent frameworks such as CrewAI/AutoGen/native subagents; per the adversarially-verified field map in cerebrum's `reference_agentic_memory_landscape_2026-06-30`), while keeping our wedge: the *binding* - file-based, git-provenance, role-scoped, human-auditable memory.
Someone can adopt the substrate module alone and never create a role; that is a legitimate, complete use of agent-personas.

## Memory tier hierarchy

Converged terminology (verified 2026-07-02 against Claude Code docs, Codex AGENTS.md guide, OpenCode rules docs, Mem0/Zep scope tags):

| Tier | Field terms | Our unit |
|---|---|---|
| Role memory | agent-scoped (`agent_id`) | Role dirs inside a project instance |
| Project memory | CC "project memory", Codex/OpenCode project rules | One instance per *endeavor* (embedded or separate repo) |
| User memory | CC "user memory", Codex/OpenCode global rules, Mem0 `user_id` | One private instance per human: `Jin-HoMLee/user-memory` |
| Org memory | CC managed policy; org-scoped tags (`org_id`/`app_id`) in the 2026 multi-scope memory-layer guides (not a single vendor's API) | **Reserved.** Team-shared policy tier; not built (solo lab) |

Precedence on conflict: **role > project > user** (more specific wins).
"User memory" is named by its *scope*, not its consumer: every tier is agent-consumed; they differ only in whose context they carry.
User memory and org memory are near-opposites in ownership (one human's private preferences vs team-shared policy); do not conflate them.

### Vocabulary

| Term | Means | Splice example |
|---|---|---|
| Scope | Whose context a tier carries (user / project / role) | "the splice endeavor" |
| Instance | One actual corpus in substrate format: an index + its memory files; one per scope | The content of the splice memory repo: `shared/` + 4 role dirs |
| Repo | Where an instance is stored and version-controlled | `claude-personas-splice-neoepitope-pipeline` on GitHub |
| Clone | A local working copy of a repo; pure git mechanics, no architectural meaning | `splice-neoepitope-pipeline-pm/` etc. |
| Mount | An adapter making an instance visible to a session (symlink / `instructions` entry / SessionStart hook) | A splice PM session mounts user-memory + splice project memory + its `pm/` role dir |

A "project" in the tier sense is the **endeavor**, not the repo and not a GitHub Project board.
Boundary test: would a decision recorded while working in repo A change what an agent should do in repo B?
If yes, same project scope, same memory instance.

## Repo topology: repo = boundary unit, tier = mount unit

Repos follow ownership/access/lifecycle boundaries, not hierarchy levels:

- **Sharing:** repos are GitHub's unit of access control; a future collaborator gets the project memory repo, never the user memory repo. CC docs draw the same line (user memory = "anything teammates should not see").
- **Governance:** the splice memory repo has MM as sole committer; user memory is written by any of the owner's sessions. One repo cannot hold two commit authorities.
- **Write concurrency:** concurrent role/project sessions push to independent remotes instead of competing for one `main`.
- **Lifecycle:** project memory is archived with its project; user memory outlives every project.

Role memory is **not** a separate repo (roles share all boundaries with their project).
Project memory has two legitimate forms; same substrate either way:

| Form | Example | When |
|---|---|---|
| Embedded: `.agents/memory/` inside the code repo | cerebrum (first adopter, migration tracked in cerebrum#75; today still `.claude/memory/`); marginalia + claude-tools are planned targets | Single repo, single role, no separate governance (default for small projects) |
| Separate `<endeavor>-memory` repo | splice | Multi-repo endeavor, multiple role clones, or own governance (MM) |

Graduating from embedded to separate is a supported toolbox migration (splice already made this move; cerebrum ran the all-in-one counterfactual and unbundled it 2026-05-13 when governance diverged).

### Instance naming convention

`<scope>-memory`, named for the thing whose memory it is, with no framework prefix:

- User tier: `Jin-HoMLee/user-memory` (the GitHub namespace already says whose).
- Project tier: `<endeavor>-memory`; proposal to MM at rename time (sub-project #4): `claude-personas-splice-neoepitope-pipeline` -> `splice-neoepitope-pipeline-memory` (GitHub redirects make this low-risk; MM's call).

## The new piece: user-memory tier

1. **Create `Jin-HoMLee/user-memory` (private):** standard substrate layout, `MEMORY.md` index + one-fact-per-file, cloned once to a fixed path (`~/dev/GitHub/Jin-HoMLee/user-memory`).
2. **Global mounting mechanism (shipped by agent-personas):** the spec #1 thin-adapter trick, one level up:
   - Claude Code: `~/.claude/CLAUDE.md` references the user-memory index (user memory is CC's native global tier).
   - Codex: `~/.codex/AGENTS.md` (native global tier).
   - OpenCode: `~/.config/opencode/AGENTS.md` (native global rules).
   Exact wiring (reference vs symlink vs injected content) is decided during implementation against each tool's live loading behavior, mirroring spec #1's verified-by-running rule.
3. `~/OPINIONS.md` and `~/VOICE.md` stay in place in v1; the index gets pointer entries to them.

## Content migration

1. **Triage:** read every splice `shared/` rule and role-dir rule; produce a table classifying each PORTABLE / SPLICE-SPECIFIC / BORDERLINE with one line of reasoning. Human review of the table is the gate.
2. **Adapt, not copy:** portable rules are rewritten to generic form (splice-specific references removed), each migrated file carrying a provenance line back to its splice source file + commit.
3. **Splice keeps its copies.** Once splice mounts user-memory, deduping local copies is MM's decision; we hand over the candidate list via an issue in the splice memory repo. No commit by us into that repo.
4. **Tooling ports** are routed to existing sub-projects: guard hooks + role-resolution to #2, memory scripts + git hooks + plugin skills to #3 (with #18/#21 context). Ports are adaptations run against live target data, never verbatim copies.
5. Domain knowledge never moves.

## Verification (by running, not static review)

- A fresh scratch repo with zero local setup: session in each of CC / Codex / OpenCode sees the user-memory index and can lazy-read one migrated rule.
- Precedence: a deliberately conflicting rule planted at project scope wins over the user-scope rule in-session.
- A new memory written from a non-CC tool lands in `user-memory` with valid frontmatter + updated index.
- Existing splice sessions are unaffected before MM opts in (no splice repo is touched).

## Not in scope

- Org-memory tier (no second human; reserved slot only).
- The rename itself (sub-project #4) and the MCP write path (#5).
- Any commit into the splice memory repo (MM is sole committer).
- Retrieval/vector layers (the retrieval-vs-hand-index experiment, [cerebrum#65](https://github.com/Jin-HoMLee/cerebrum/issues/65), showed the index's job is summary + provenance, not recall).

## Decision log

| Decision | Alternatives rejected | Why |
|---|---|---|
| Two decoupled modules (substrate + roles) | Keep bundled | Field-validated split; substrate provably useful roleless (cerebrum); roles = identity + mounts |
| User memory = new private repo | Grow inside cerebrum; loose files in `~/.claude/` | Cerebrum's memory only loads in its worktree + scope conflation; `~/.claude/` is unversioned, CC-only, no index tiering |
| Tier names role/project/user (+org reserved) | "organization memory" as top tier; `jin-ho-memory` | Field convergence (CC/Codex/OpenCode/Mem0); org memory means team-shared policy, the opposite of personal; name the tier by scope |
| Repo per boundary, not per tier | One monorepo for all memory | Sharing/governance/concurrency/lifecycle forces; cerebrum-as-monorepo already failed this in practice (2026-05-13 unbundling) |
| Embedded and separate project-memory forms both legitimate | Always require a `*-memory` repo | Small projects should not pay the multi-repo tax; graduation is a supported migration |
| Adapt-not-copy migration with provenance lines | Bulk copy of `shared/` | Porting rule (Content migration step 2): instance-to-target ports must be rewritten to target conventions - verbatim copies silently no-op; provenance is the product wedge |
| Splice dedup deferred to MM | Delete splice copies during migration | MM is sole committer; governance boundary is load-bearing |
