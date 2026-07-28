# CLS build: episodic memory layer + consolidation bridge

**Date:** 2026-07-28
**Status:** design approved (brainstorming sessions 2026-07-24 + 2026-07-28).
**Scope decision:** spec lands now; the framework implementation MERGE is gated on the claude-mem pilot's AC1 verdict (cerebrum#107, review ~2026-08-06).
If the pilot concludes episodic capture does not earn its keep, this spec archives unmerged, by design.
**Issue:** #65 (memory layer axis). This spec covers the episodic layer and consolidation bridge in full, and the prospective layer's lifecycle only.

## Problem

The framework ships only the slow memory store: a curated, reviewed, always-indexed corpus (`feedback_*`, `project_*`, `reference_*`, `user_*`).
The flagship instance (splice) organically grew two more layers, episodes and post-its, which the framework does not define (#65).
Splice also demonstrated the failure modes an upstreamed design must prevent:
capture was indiscriminate (~250 episodes accumulated),
no bridge existed from episodes to the curated store,
and the forgetting half never fired (0 episodes archived; post-its rotted add-only).

## Frame: Complementary Learning Systems

The design maps the memory architecture onto the CLS model (community-grounded, web-verified 2026-07-24):

- **Neocortex = the curated git-native store** (slow, selective, reviewed). Holds both semantic rules (`feedback_*`) and consolidated episode summaries (`project_*`).
- **Hippocampus = fast episodic capture** (new). Salience-weighted at encoding, never indiscriminate.
- **Consolidation bridge = the genuinely new mechanism.** Replay promotes selected episodes into the neocortex through the existing human review gate, and clears the hippocampus in the same pass.

### Locked design principles

1. Neocortex substrate is markdown-as-truth, non-negotiable. A DB-as-truth substrate destroys git-as-truth, the review gate, and per-line provenance.
2. A vector/FTS DB is at most a derived, rebuildable index, never the source of truth.
3. Salience-gated promotion is first-class: the bridge promotes novel/surprising/decision-relevant episodes, not all of them, and capture itself is salience-weighted.
4. The reviewability boundary is the consolidation step, not raw capture. External capture substrates may be opaque, provided promotion flows through the git gate.
5. Forgetting is designed in, coupled to consolidation, so it cannot independently go unfired.

## Architecture

The framework payload (`.agents/memory/`) gains one new area and one extended mechanism.

```
.agents/memory/
├── MEMORY.md                  # index (unchanged; episodes NEVER indexed here)
├── feedback_* / project_* ... # neocortex - curated, reviewed (unchanged)
├── episodes/                  # NEW: hippocampus - fast, git-native
│   ├── YYYY-MM-DD-<slug>.md   #   one episode per file, salience-tagged
│   ├── inbox/                 #   feeder drop-zone for external capturers
│   └── archive/               #   forgotten episodes (moved, not deleted)
└── postits.md                 # prospective - lifecycle rules only (this spec)
```

The CLS loop:

1. **Encode.** At session wind-down the agent writes 0-3 salient episodes to `episodes/`.
2. **Trip-wire.** The session-start hook counts pending episodes and days since the last consolidation, and surfaces a "replay due" nudge past threshold. It never auto-runs anything.
3. **Replay.** Explicitly invoked `consolidate-memory` (extended episodic mode of `consolidate_pass.py`) triages every pending item and emits promotion plus forgetting proposals.
4. **Gate.** Proposals land as one `consolidate/*` branch PR. The human merge updates the neocortex and clears the hippocampus in one atomic, reviewable diff.

Episodes are never added to `MEMORY.md` and never auto-loaded into context.
Their only readers are the consolidation pass and humans.
This also keeps the index clear of the 200-line cliff.

## Episode format

One episode per file in `episodes/`, named `YYYY-MM-DD-<topic-slug>.md` (matching the session-naming convention; same-day same-topic collisions get a numeric suffix).

```markdown
---
name: 2026-07-28-example-episode
description: one-line gist used by the consolidation pass to triage
type: episode
salience: [surprise, decision]
session: <session date+topic or id>
---
3-15 lines, past tense: context, what happened, outcome,
and why it mattered. A distillation, never a transcript.
```

Frontmatter is flat, matching the convention of all shipped example files for the four existing types.
(Some downstream instance corpora nest fields under a `metadata:` block; that is an instance-local variant, not the framework canon. Episode validation in `consolidate_pass.py` treats the flat form as canonical.)

- `episode` becomes a fifth memory type alongside `user | feedback | project | reference`.
- Lifecycle state is expressed by location, not frontmatter: `episodes/` = pending, `archive/` = forgotten. A state change is a file move, visible in a PR diff.
- Episodes may `[[link]]` to curated memories. Neocortex files never link to episodes: the ephemeral layer points at the durable one, never the reverse.

## Capture rules

Defined once in the memory-contract section of the adopting repo's `AGENTS.md`, so every adapter (Claude Code, Codex, OpenCode, pi) inherits them identically.

- At wind-down, write 0-3 episodes.
- An episode must claim at least one salience tag: `novelty` (first-time event), `surprise` (expectation violated, error caught), `decision` (choice plus rationale future sessions will need), `correction` (human corrected the agent).
- Nothing qualifies -> write nothing. A routine session producing zero episodes is the expected common case.

## Feeder interface (inbox contract)

`episodes/inbox/` is the landing zone for external capture tools (claude-mem is the live example; any future capturer qualifies).

- A feeder contributes by writing files in the episode format above to `inbox/`. There is no code coupling and no dependency: an absent feeder means an empty inbox and a fully functional system.
- Inbox items are candidates, not episodes. They have not passed a salience or accuracy judgment (the cerebrum#107 pilot observed automatic capture recording a factual error).
- The consolidation pass screens each inbox item first (accurate? salient at all?) and either adopts it (into `episodes/` or directly into a promotion proposal) or discards it, noted in the PR body.
- Feeders write only to `inbox/`, never to the neocortex. Screening plus PR review form the trust boundary (the write-audit-publish / landing-zone pattern; also the memory-poisoning mitigation recommended in the 2026 literature).

## Consolidation bridge

### Trip-wire

The session-start hook adds one deterministic check:
count files in `episodes/` + `inbox/` (excluding `archive/`), and days since the last consolidation merge (read from git log via the `consolidate/*` commit convention).
Threshold: **>=10 pending episodes OR >=14 days with >=1 pending** (adjustable constants).
Past threshold it surfaces one line: `episodic: replay due (N pending, last pass D days ago)`.
The hook follows the existing defensive pattern: always exits 0, never blocks session start.

### Replay pass

Explicitly invoking `consolidate-memory` runs the episodic mode of `consolidate_pass.py` over `episodes/` + `inbox/`.
Every pending item gets exactly one fate:

| Fate | Criterion | Effect |
|---|---|---|
| Promote to rule | Durable lesson; recurring pattern or correction (the "2nd bite" bar) | New/updated `feedback_*` + index line |
| Fold into summary | Belongs to ongoing tracked work | Edit to the relevant `project_*` |
| Archive only | Salient at capture, no durable residue | Move to `archive/` |
| Keep pending | Genuinely too fresh to judge (rare) | Stays; kept twice -> auto-flagged for archival next pass |
| Discard (inbox only) | Fails accuracy/salience screening | Deleted; noted in PR body |

### Coupled forgetting

In the same pass and the same PR:

- Every promoted or folded episode moves to `archive/` in the same diff (consume = archive).
- Unpromoted episodes older than ~30 days (adjustable constant) archive as low-salience.
- Overdue, moot, or completed post-its are expired (removed; git history preserves them).
- `archive/` stays grep-able and is never auto-deleted. Git history is the true archive; a deletion policy is deferred.

### Output

One `consolidate/*` branch PR carrying promotions, moves, and expiries.
The human merge is the gate, identical to the existing consolidation machinery's human/MM merge gate.

## Prospective layer (minimal scope)

The framework defines a single `postits.md` in the payload: one entry per post-it with created date, trigger condition, and action.
This spec fixes only its lifecycle:

- The consolidation pass expires overdue/moot/completed entries in the same PR.
- The trip-wire flags the file when it exceeds ~20 entries (adjustable constant).

Trigger semantics and capture conventions (the TriggerBench-informed design) are explicitly deferred to a follow-up issue.

## Failure modes

- **Hook failure:** defensive exit 0; a lost nudge never blocks a session.
- **Silent zero-capture:** salience-gating makes zero episodes legal, so a wind-down that silently stops capturing is undetectable by the trip-wire. Known limitation; the periodic meta-audit is the backstop.
- **Inbox poisoning:** feeders cannot reach the neocortex; screening plus PR review are the trust boundary.
- **Pending rot:** the keep-pending fate auto-flags on its second pass, so "pending" cannot become the new add-only accumulation.
- **Concurrent sessions:** per-file episodes with date+slug names make collisions unlikely; the suffix rule covers same-day same-topic.

## Testing and acceptance

- Unit tests for `consolidate_pass.py` episodic mode against a fixture corpus covering all five fates, asserting every proposal set couples forgetting (no promotion without its archive move).
- Episode-file validation lives in `consolidate_pass.py` (the layer's only programmatic reader): frontmatter shape, salience-tag presence, and the no-reverse-link rule are validated at replay time. The framework ships no separate lint; instance-level linters (e.g. cerebrum's `memory_lint.py`) may adopt the same rules.
- Trip-wire hook exercised with fixture counts and dates (review by running, not static reading).
- **Live AC:** one real wind-down capture and one real replay pass producing a reviewable PR on a live instance.
- **Merge gate:** framework implementation merges only after the cerebrum#107 pilot AC1 verdict (~2026-08-06) supports the layer.

## Out of scope

- Full prospective-layer design (trigger semantics, capture conventions): follow-up issue.
- Any DB or vector index (derived indexes remain legitimate future work, never truth).
- Automatic/background consolidation (AutoDream-style): contradicts the trip-wire/explicit philosophy; revisit only with evidence.
- Migrating the splice instance: the framework ships the pattern; instance adoption is its Memory Manager's call.
- `archive/` deletion policy: deferred until archive size is felt.
