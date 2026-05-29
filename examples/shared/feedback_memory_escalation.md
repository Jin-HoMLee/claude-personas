---
name: Memory escalation on repeat failure
description: When corrected for forgetting something, find the memory and promote it inline to the role's MEMORY.md if it only lives behind a link
type: feedback
---
**When the user says "you forgot X", "you did X again", "did you forget about X?", or any similar correction:**

1. Search for an existing memory on that topic across all memory files
2. If found **inline in this role's own MEMORY.md** → already at the right level; no promotion needed (consider sharpening the wording instead)
3. **Before promoting to inline, ask: hookable? skillable?** (See [Choose tier before promoting](#choose-tier-before-promoting) below.)
4. If found **only via a link** (shared/MEMORY.md, a referenced feedback file, etc. — not inline in this role's MEMORY.md) and the tier check lands on tier 1 → **promote it**: copy that specific rule inline into this role's MEMORY.md under `## Always in effect`, with a drift annotation pointing back to the source file
5. If **not found anywhere** → create a new memory AND wire it at the right tier (hook, skill, or inline)

**Why:** Rules behind links require an explicit file read to fire. Inline rules in MEMORY.md are auto-loaded every session with no reads required. **But** always-loaded rules cost tokens every turn even when irrelevant, and compliance degrades past ~14 rules per session (see [`CONVENTIONS.md`](../../CONVENTIONS.md)). Without a tier-down step, the escalation pattern becomes a one-way ratchet: every miss promotes a rule inline, "Always in effect" grows unboundedly, and the rules that genuinely need to fire on every turn get drowned out by ones that should have been hooks or skills.

**How to apply:** After every correction, search first — don't just create a new memory. If the rule already exists somewhere, promote it to the **right tier**, not automatically to inline.

## Delete entirely — the rule may not need to exist

Before choosing a tier, check the cheapest verdict of all: **does this rule just restate what a built-in tool already enforces?** Claude Code's built-in tools carry their own docstrings, and some "rules" are verbatim echoes of them:

- "Use `AskUserQuestion` for 2–4 choices; mark the default `(Recommended)`" — the tool's own docstring already says this.
- "Keep one `TodoWrite` item `in_progress` at a time" — same.
- "Read a file before editing it" — the `Edit` tool already enforces this and errors otherwise.

When a rule duplicates a built-in tool's docstring, the verdict is **delete entirely**, not demote. The two are different: demoting moves a *load-bearing* rule to a cheaper tier; deleting removes a rule that was never doing work — the tool enforces the behavior regardless, so the inline copy is pure token cost with zero added reliability. Think of "delete entirely" as the rung below tier 4 on the ladder: **tier 0, the rule that shouldn't exist**.

Detecting these mechanically is the job of a `check-tool-docstring-overlap` lint — see [issue #18](https://github.com/Jin-HoMLee/claude-personas/issues/18).

## Choose tier before promoting

Before copying a rule into "Always in effect", run this triage:

1. **Hookable?** Does the rule have a discrete trigger — a specific Bash command, a specific file edit, a specific gh CLI call?
   - Yes → **tier 4 (hook)**, not inline. The harness enforces it deterministically; Claude can't drift past it; cost is zero tokens. See [`examples/hooks/`](../hooks/) for starter configs.
   - Common shapes: "never run X", "always run Y before Z", "edits to file F must be appended only, never modified in place".

2. **Skillable?** Does the rule belong to a session-mode workflow (morning routine, end-of-day handoff, triage flow, code review)?
   - Yes → **tier 3 (skill)**, not inline. Skills load only when invoked; they don't burn tokens between invocations. They give free invocation telemetry (you can grep JSONL to see when each fired).
   - Common shapes: "on 'good morning', do these 5 steps", "when triaging issues, follow this checklist", "before opening a PR, run this verification sequence".

3. **Lazy-loadable?** Does the rule apply in specific situations only (only on PRs, only when writing tests, only when the topic surfaces)?
   - Yes → **tier 2 (reference)** is fine; keep it as a linked `feedback_*.md` and don't promote inline. The user's "you forgot X" correction may be a one-off rather than a systemic miss.

4. **Otherwise** → **tier 1 (always-loaded)**. Use for ambient defaults (tone, style), identity priors, cross-cutting rules with no specific trigger, and the index function itself. Budget carefully — past ~14 rules in a session's combined load, compliance starts degrading.

**Heuristic shortcut:** if the rule is phrased "**never** do X" or "**always** do Y before Z" with a specific command, it's almost certainly a hook. If it's phrased "**prefer** X" or "**when** Y, **consider** Z", it's a memory rule.

**Counterexample to the heuristic:** rules phrased as "**never** do X" but where X requires knowing intent, branch context, or PR-level judgment to apply correctly. Example: "never push directly to main" — phrased as never-X but depends on which branch you're on, and a regex matcher catches legitimate uses like `git push origin feature:main` for a PR-bound merge. Or "never use `gh pr merge --admin`" — the `--admin` flag is a specific command (heuristic predicts hook) but the right judgment depends on PR-specific context (was this an emergency hotfix? did the failing check apply?). In these cases, keep the rule as a memory entry even though the phrasing matches the hook heuristic. The hook is for **trigger × no-judgment-needed** intersections; rules where judgment is needed go in tier 1 or tier 2 — never tier 4.

## When the same rule slips twice

The first slip might be a one-off; the second is a pattern. If you've already escalated once (memory rule added, hook installed, or skill registered) and the same shape of mistake recurs:

- Hook installed but rule slipped → the hook's regex didn't catch this variant. Tighten the matcher; add a test case to verify.
- Memory rule inlined but rule slipped → the rule is in the wrong tier; consider whether it should have been a hook instead.
- Same rule slipped via a workflow Claude doesn't normally take → consider whether the rule should be promoted (in the original sense) AND the workflow itself moved to a skill that surfaces the rule explicitly.
