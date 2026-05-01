---
name: Milestone management — PM responsibility
description: Rules for creating, naming, and maintaining milestones — PM only
type: feedback
---
Milestone management splits into two concerns with different owners:

- **Initial milestone assignment** (placing a new issue in an existing iteration at creation/triage time): **anyone** can do it. Other roles typically know the lifecycle stage their work fits. The rule is documented; for clear cases it doesn't need PM gating. PM validates during triage.

- **Iteration creation, milestone restructuring (moving issues across iterations, displacing under capacity), and milestone closing**: **PM-only.** These require the cross-cutting capacity + balance view across the whole portfolio. Other roles flag the need to PM instead of acting unilaterally.

If you're not sure which side a given action falls on, default to flagging PM.

## Naming convention

`i<iteration> - S<stage> - <Stage Name> - <Arc>` — e.g. `i2 - S5 - Build - Foundations`, `i3 - S3 - Design - Onboarding Flow`

- **Iteration first** — sorts the Roadmap view chronologically; active iterations surface at the top.
- **S number = lifecycle stage number, always** — e.g. S5 = Build (all iterations: i2, i3, …); S3 = Design (i2, i3, …). Never use a sequential creation number; always match the stage.
- **Iteration suffix = `i<N>`** (not v1/v2) — we use iterations, not versions. i1–i9 sorts cleanly; revisit padding if we ever reach i10.
- **Arc = short goal statement** — name after the dominant parent/epic of that iteration. If focus only crystallizes mid-iteration, a rename is allowed. Arc makes each milestone self-describing and motivating.

### Always use the full milestone name in user-facing text

Always write the full milestone name (e.g. `i2 - S5 - Build - Foundations`). Never the abbreviated `S5 i2`.

**Why:** The full name is self-explanatory — stage, iteration, and goal are all visible without looking anything up.

**How to apply:** in tables, prose, triage proposals, anywhere milestones come up. Bare abbreviation only acceptable inside code blocks or terse internal log lines.

## Lifecycle stages

Define your own lifecycle stages (e.g. S1–S7). The naming convention works for any number of stages. Pick the set that fits your project's natural phases (e.g. Discovery → Design → Build → Test → Launch).

## Rules

- **Every stage + every iteration gets its own milestone**
- **Backlog status** = issue is either unassignable to a milestone yet, or lowest priority — not a substitute for a milestone
- **Every new issue should get a milestone, a priority, a size, role label(s), and a priority rationale at triage** — questions in order: "which lifecycle stage?", "P0/P1/P2?", "XS/S/M/L/XL?", "which roles are involved?", "why this priority (one sentence)?"
- **Priority rationale in issue body:** add a `**Priority rationale:** <one sentence>` line near the bottom of every issue body. Captures why P0/P1/P2 was chosen — tactical (unblocks current work) vs strategic (long-term), urgency, dependency relationships. Update this line when re-prioritising. Lives on the issue (not memory) so it's visible to all roles and travels with the issue.
- **Monitor lifecycle balance** — flag to the user if one stage is getting disproportionately many iterations relative to others
- **Close completed milestones** — during triage, check for milestones with 0 open issues; flag them to the user and confirm before closing
- **Celebrate closed milestones** — immediately after closing a milestone on GitHub, post a `[MILESTONE ACHIEVED 🎉]` celebration message in `team_standup.md` addressed to all roles (see format below)

### Milestone celebration message

Post immediately after `gh api` closes the milestone. Mark `Status: Done` at write time (it's a FYI — no reply needed).

```
### [YYYY-MM-DD HH:MM UTC] From: PM → To: All [MILESTONE ACHIEVED 🎉]
Milestone closed: **i<iter> - S<N> - <Stage Name> - <Arc>**
<One sentence: what this arc delivered.> <One sentence: what it unlocks — next stage, next iteration, or next handoff.>
Huge thanks to everyone who contributed! 🎉
**Status:** Done
```

Keep it short: two content sentences max, one cheer line. Always use the full milestone name.

## Milestone assignment workflow

When assigning a new issue to a milestone, first determine its **lifecycle stage → S#**, then scan all existing iterations of that S# and classify each as:
- **①** has capacity + topic fit
- **②** has capacity, no topic fit
- **③** full (at capacity)

Capacity = size-weighted ~1 week budget: XS ≈ 0.5d, S ≈ 1d, M ≈ 2–3d, L ≈ 3–4d, XL ≈ 5d.

### Decision tree (in order):
1. **If ① exists** → assign to earliest ① iteration. Priority preference: P0/P1 → earlier, P2 → later. This is a **soft preference when capacity is available** — a P2 issue may still go into an iteration with P1 issues if there is room.
2. **If only ② exists** (capacity but no topic fit) → assign to earliest ②, accept mismatch, flag for re-arrangement.
3. **If all iterations are ③ (full):**
   - If new issue priority > any non-In Progress issue in any ③ iteration → displace that lower-priority issue to a later or new iteration; assign new issue to freed slot. **Never displace In Progress issues.**
   - Otherwise → create new iteration S# i(N+1).

**Priority is a hard gate only when capacity is full:** a P2 issue cannot displace a P1 issue, only a lower-priority one.

## Re-arrangement rule

Periodically review iterations for topic clustering and priority ordering. When re-arranging:
- Respect timebox constraints
- **Never move In Progress issues to higher/later iterations** — they stay put
- Higher-priority issues should end up in earlier iterations after re-arrangement
