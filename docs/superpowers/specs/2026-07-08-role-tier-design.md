# Role tier design - cross-project role identity and memory (issue #49)

**Date:** 2026-07-08 - 2026-07-12 (design window; drafted 2026-07-12)
**Status:** draft - all design sections locked in the #49 brainstorm; awaiting spec sub-issue + review; locks at PR merge
**Issues:** #49 (parent), spec sub-issue TBD, #64 (evidence pilot, closed), #27 (epic; item 4 holds the naming grammar), #58 (hook delivery mechanism), #43 (framework distribution spec, foundation)
**Boundaries:** #65 (layer axis), #66 (org tier + migration triage), #67 (cross-harness mount parity)

## 1. Identity: what the role tier is

A role (developer, pm, scientist) today exists only inside one project's memory instance.
When the same role recurs in the next project, its accumulated craft and its calibration to the human start from zero.
The role tier gives each role a home that outlives any single project: `role@user`, hosted in the user-scope instance repo (`user-memory`).

The model behind it is two-axis: **scope** (user / project / repo) x **plane** (shared / role).
Bare tier names denote the shared plane; `role@<scope>` denotes the identity plane.
"Shared" widens with scope: project-shared spans that project's roles, user-shared spans roles and projects.
Five of the six grid cells are instantiated; `role@repo` stays reserved with no use case (addable without redesign).

This spec covers the model, the `role@user` home, mount wiring, manifest/doctor support, promotion rules (the complete routing model; its org-scope destinations are forward references to #66), and the repo tier's definition.
It deliberately does not cover the org tier (#66) or the memory layer axis (#65); see section 10.

## 2. The scope model and precedence chain

**One rule generates the chain:** walk scopes most-specific-first; within a scope, the role plane beats the shared plane.

```
[role@repo >] repo > role@project > project > role@user > user
```

Every scope reads `role@X > X`; there are no special cases.
The rationale for shared-above-imported-role at each step: a scope's conventions must not be silently overridden by role craft imported from a wider scope.

**Degeneracy property:** for a single-repo endeavor, the repo and project tiers coincide and the chain collapses to exactly the vendor model (role > project > user).
We deviate from vendor behavior only where it demonstrably breaks.

**Terminology settlement** (usage rules for all framework docs):
- Unqualified "project" always means our endeavor tier, never Anthropic's sense and never a tracker board.
- Anthropic's "project" is our repo tier (their true key is the checkout directory); vendor cites are translated inline as "Anthropic-project (= our repo tier)".
- "GitHub Project" is always written with the qualifier and is a work-tracking view with no authority for memory scoping; board-vs-manifest misalignment is a prompt-to-check, never a definition.

**Naming:** the role plane is written `role@<tier-name>` uniformly, so `role@user`, not `role@global`.
"User" matches modern tooling consensus (Claude Code, VS Code, Cursor, Copilot); "global" is git's criticized outlier and would squat on the natural name for a future org tier.
The wider naming grammar (`<scope>-personas` instance repos, the `project_name` manifest key, one-repo-per-scope, primary-repo-privilege) is specified in the #27 item-4 spec seed and referenced here, not restated.

**Cohabitation rule:** a plane gets a marked directory only where two planes cohabit in one store.
Instance repos hosting both planes mark the shared plane as `shared/`; a single-plane store stays bare.
Consequence: moving roles into `user-memory` crosses the cohabitation line, which drives section 3's layout.

## 3. The role@user home: user-memory grows a roles module

**Decision: Approach A - the roles module lives inside `user-memory`**, the user scope's existing instance repo.
This matches #43's own forward-reference (user-memory as a "substrate-only instance (no roles module)" that can grow one) and keeps one instance repo per scope.
A dedicated roles repo (B) and per-role repos (C) are rejected for now; C stays reachable via #43 section-5 trip-wires (confidentiality, multi-human ownership).
The independent-lifecycle trip-wire is answered by the role tier itself, not by a repo split.
Web cross-check (2026-07-08): single store + hierarchical namespaces is the field consensus (AWS AgentCore, LangGraph/LangMem, Mem0); no surveyed system has an analogue of B.

**Layout: mirror the instance layout** - top-level role dirs plus `shared/`:

```
user-memory/
  shared/          # the current flat user tier, moved
    MEMORY.md
  developer/       # role@user homes, created lazily
    MEMORY.md
    shared -> ../shared
  .agents/manifest # memory_layout flips flat -> roles
```

The recon inverted the assumed costs of this option:
- The user-tier import path is one file, not three (`~/.claude/CLAUDE.md -> ~/AGENTS.md -> user-memory/AGENTS.md`); a single edit repoints it.
- `memory_layout=roles` already exists and is already implemented in doctor (role dirs + `shared/MEMORY.md`); option A is a one-word manifest flip onto a shipped, checked code path, with zero framework code.
- The rejected "mark the newcomer only" option is the one that would need a new enum value, a new doctor path, and permanent asymmetry.

**Migration is one atomic commit** (doctor drifts on "roles declared but no role dirs"): `git mv .agents/memory/* shared/`, create the first role dir(s), flip the manifest, repoint the import line.
Depth-safety was verified: the current user-tier files carry no `../` links, only sibling links that move together.

**Role dirs are created lazily.**
An empty `role@user/MEMORY.md` would assert craft that does not exist and make section 6's promotion gate decorative.
Doctor's requirement of at least one role dir under `memory_layout=roles` is therefore a feature: the manifest flip is impossible until real content exists.
Sequencing consequence: the migration cannot execute until the first real role dir exists - seeded by declared facts (section 6) or by the #66 triage.
All three current roles (developer, pm, scientist) are expected to recur across projects and to get homes eventually; expectation does not exempt them from lazy creation.

## 4. Mount wiring: role@user mounts the way shared/ already does

Evidence base: the #64 pilot (section 9).
Its one-line verdict: **injection works, but a mount must be a pointer the agent Reads, never an injected payload.**

### 4a. Main sessions (read side)

**One committed symlink in the project memory repo:** `<memory-repo>/<role>/user -> ../../user-memory/<role>`.
The relative path encodes the same sibling-layout assumption `role_source` (section 5) declares, so doctor validates both with one check.
A symlink resolves against its own location, not the session's cwd - the reason it beats a bare relative path in a pointer line, which breaks the moment a clone's cwd assumption shifts.

**Surfaced by one pointer line in the role index**, ordered to mirror the precedence chain: role index (auto-loaded) -> `shared/MEMORY.md` pointer -> `user/MEMORY.md` pointer.
Reading order is the chain, so conflict resolution needs no extra rule.

Per vendor, near-zero new wiring:
- Claude Code and OpenCode follow the pointer with Read; the `load-persona-memory` skill gains the one extra hop.
- Codex's `inject-role-index.sh` appends one more conditional pointer line when `<role_dir>/user/MEMORY.md` exists (~60 bytes, no cap risk).

This is the #64 vendor-neutral rule verbatim: either the harness loads your memory for you, or the agent must be able to read it itself.

### 4b. Subagents

A new framework hook, sibling to `inject-role-index.sh` and delivered via the #58 mechanism: **SubagentStart, keyed on `agent_type`, injecting a ~250-byte pointer** naming the role's memory path.
Never the payload: Claude Code silently clips hook `additionalContext` at ~2 KB on this path (#64, section 9).

**`tools:` is an identity primitive.**
A role subagent that cannot Read cannot mount its own memory; framework role-subagent definitions must grant Read, and doctor can lint that.
Belt-and-braces: truly always-in-effect rules stay within the pointer's first 2 KB.

### 4c. Write side (scoped)

The mount is read-only by convention.
A promotion to role@user (section 6) is an explicit write into the user-memory repo, committed there; git never absorbs cross-repo symlinked content into the clone.

### 4d. Laziness

The `user/` symlink is created lazily at first promotion; a dangling committed symlink would assert craft that does not exist.
A missing symlink or missing role@user dir is not drift (section 5).
Creation is doctor fix-mode's job: materialize the symlink from `role_source` once the target role dir exists - mechanical and fully manifest-derivable, never hand-typed.

**Evidence boundary:** pointer-following is live-verified on Claude Code only; Codex and OpenCode parity is tracked as #67, this section's validation follow-up.
The user-shared plane (chain bottom) rides the existing user-scope import and needs no per-clone wiring.

## 5. Manifest and doctor

**Zero new keys for user-memory itself.**
`topology` (mount) and `memory_layout` (payload) were 1:1 correlated across all live instances; user-memory becomes the first to decouple them (`user-tier` + `roles`), retro-justifying the two-key split.

**One new consumer-side key: `role_source`** (e.g. `role_source=../user-memory`), mirroring `framework_source`.
- **Optional** (locked 2026-07-12): the key appears when the tier does, per the lazy-mounts spine; an instance that never grows role@user declares nothing.
  The typo risk is already covered: doctor hard-errors on any unknown manifest key, so the only silent case is omitting the key while intending the tier, which surfaces loudly and self-describingly at first promotion.
- **No `role_ref` pin companion:** the framework is a released artifact worth pinning; the role@user store is a live sibling always wanted at HEAD.
- **Scoping:** valid on `role-clones` and `embedded`, hard error on `user-tier` (self-reference), via the existing key-scoping lists.

**Doctor gains a "Role-tier readiness" section**, active only when `role_source` is present:
- The path resolves, is a git repo, and its manifest says `memory_layout=roles`; a `flat` target is a hard error (pointer wired before the section-3 migration).
- When a `<role>/user` symlink exists: it resolves and its target matches `role_source` + role name.
- A role with no role@user dir is **not** drift; lazy creation makes that the normal state, and reporting it would make every clone cry wolf from day one.

## 6. Promotion rules: routing by coordinate release

The current single-destination rule ("a lesson that bites in a second project promotes to the user tier") is itself the bug this section fixes: one destination means everything general lands in one bag.

**Coordinate-release model.**
A discovered fact is born at (role R, project P, human H).
Each recurrence differing in one coordinate releases that coordinate; the destination is the scope defined by whatever stays bound:

| 2nd bite | releases | lands at |
|---|---|---|
| same role, different project | project | role@org / role@user |
| same project, different role | role | project (shared) |
| different role and project | both | org (shared) |
| different human, same role | human | role@org (confirmed) |

This is inductive generalization; the existing 2-strike rule becomes a special case rather than being discarded.

The table states the complete routing model; its org-scope destinations are forward references.
The org tier has no home yet (section 8, #66), so those rows become exercisable only once #66 defines the tier - until then, a fact routed to an org cell is recorded on #66 rather than written.

**The unobservable coordinate.**
With one human, the human coordinate can never be released by evidence.
Until human #2 arrives, `role@user` vs `role@org` is a judgment test: "would the second human need this?" (yes -> role@org, tracked in #66; no -> role@user).
The same shape one rung up: "would any developer anywhere need this?" -> the shipped `examples/<role>/` template.

**Declared vs discovered - two write paths, only one promotes.**
Declared facts are true by construction and are written directly at the scope their subject implies, never promoted ("prefers plain dashes" = user; "wants the PM leaning recommending" = role@user).
This is how role@user gets seeded: by writing down what was never written, not by triaging existing files.
Discovered facts (lessons) are born maximally specific and promote only by coordinate release.

**Also owed:** demotion (tier-down already shipped in v4; an over-promoted fact falls back without deletion) and governance (cross-scope promotion is an owned, audited write - the highest blast radius in the system).
**Default = stay put.** Promotion needs evidence or a declaration; "it feels general" is not a trigger.

## 7. Repo tier: defined, not wired

The repo tier stays defined in the model and the chain (a lazy mount costs nothing, and the chain is rule-generated, so removing the tier would be a special case).
It is **not mounted anywhere**, and the previously planned MM trial handoff is cancelled.

The premise audit that settled this: across the flagship project's shared memory, instance-repo wiring facts are the subject of zero files - a committer boundary already draws the line the repo tier was meant to draw.
And for a single-repo endeavor, section 2's degeneracy property says repo and project coincide; wiring a tier its own premise says degenerates would be a contradiction.

**Materialization trigger:** a genuine multi-repo endeavor - N code repos with distinct conventions and the same roles.
A satellite memory repo does not make one.

## 8. What role@user holds (and does not)

role@user is the human x role interaction calibration: how this human wants this role to behave, plus role craft that is genuinely personal.
Cross-project role **craft** (how to be a good developer anywhere in the lab) is role@org, a different cell that currently has no home; that gap, the org tier, and the triage of role craft squatting in today's user tier are #66's scope, deliberately outside this spec.
Getting this boundary wrong re-creates the current mess one tier up.

## 9. Evidence base: the #64 pilot (closed 2026-07-11, descoped 2026-07-12)

Eight headless runs on Claude Code 2.1.207, toy sentinels plus real 18 KB role indexes:
- `SubagentStart` fires per-agent with `agent_type` and its `additionalContext` lands in the subagent's context (undocumented); `SessionStart` does not fire per-subagent (contradicting the docs). SubagentStart is the injection point.
- Identity fidelity positive: injection changes outputs, is role-keyed, and does not leak across roles.
- Hook `additionalContext` above ~2 KB is silently spilled to a file with only a 2 KB preview inlined: ~89% of a real 18 KB role identity was invisible, and the failure is silent on both sides.
- The pointer mount (inject ~250 B naming the memory path + grant Read) recovered 4/4 deep facts with no cross-role contamination.
- The ceiling is Claude-Code-specific: Codex delivered a full 17.9 KB payload intact; OpenCode's `instructions:` mount is a pointer by construction. Hence the vendor-neutral rule in section 4a.
- The literal Agent Teams path was descoped at close: section 4 wires the subagent path, an AT result would change none of it, and the open AT question (which hook event teammates fire) is recorded on #64 with reviving triggers.

## 10. Non-goals

- The org tier, and the triage of role craft currently in the user tier (both #66).
- The memory layer axis - episodes, post-its (#65).
- The write side of subagent/teammate memory (observation point noted: `SubagentStop` carries `last_assistant_message` + `agent_transcript_path`).
- Dispatch-layer orchestration (firstmate-style clone fan-out; #15 context).
- The user-personas rename and naming-grammar execution (#27 item 4).
- Cerebrum's own identity under the new model (open question logged in the brainstorm; decide alongside the rename).
- Flagship-instance memory content changes (MM's lane).

## 11. Acceptance criteria

Behavior-gated, not documentation-gated:

- [ ] Doctor, on an instance whose manifest has `role_source`, runs the readiness checks: a resolving `roles`-layout target passes; a `flat` target hard-errors; a `role_source` line on a `user-tier` manifest hard-errors.
- [ ] Doctor, on an instance without `role_source`, emits zero role-tier findings (lazy default, no cry-wolf).
- [ ] Doctor fix-mode materializes `<role>/user` from `role_source` when the target role dir exists, and treats its absence as not-drift when it does not.
- [ ] After the user-memory migration commit, the user tier still loads: the import chain resolves and a session can quote a user-tier fact without manual steps.
- [ ] In a role clone with a materialized `user/` symlink, a Claude Code session follows the index pointer and quotes a role@user fact on demand (the #67 run extends this to Codex and OpenCode).
- [ ] A role subagent defined by the framework recalls a deep (beyond-2KB-offset) role fact via the SubagentStart pointer hook + Read, and refuses another role's fact.
- [ ] The two org-free routing paths fire on real facts: a declared role preference is written directly into role@user (the section-6 seeding path), and a discovered lesson's second bite in a different project promotes into role@user. Rows with org-scope destinations gate in #66, not here.

## 12. Sequencing

1. Spec sub-issue filed under #49; this spec lands by PR closing it.
2. Seed the first role@user dir by declared facts (section 6 write path; no triage dependency).
3. The user-memory migration commit (section 3), enabled by step 2.
4. Manifest + doctor changes (section 5), then mount wiring (section 4) in the flagship instance.
5. The #67 cross-harness parity run validates section 4a on Codex and OpenCode.
6. Implementation planning via superpowers:writing-plans after this spec locks at PR merge.
