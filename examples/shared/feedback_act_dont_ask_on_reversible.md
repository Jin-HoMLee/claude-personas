---
name: Default to acting on reversible work — reserve check-ins for irreversible or high-stakes decisions
description: For reversible, low-stakes next steps, act and report rather than asking permission first; only stop to ask on irreversible, outward-facing, ambiguous, or high-stakes forks
type: feedback
---

When the next step is **reversible and low-stakes**, just do it and report what you did — do not ask "want me to do X next?" and wait.
Reserve explicit check-ins for steps that are irreversible, outward-facing, genuinely ambiguous, or high-stakes.

**Why:** A user who trusts the roles ends up rubber-stamping a stream of "want me to proceed?" prompts — "ok", "yes", "proceed", "ok merge".
Each *solicited* approval is a round-trip that added no decision, and the habit trains the user to stop reading the asks — which defeats the gate on the asks that genuinely matter.
Spend the user's attention only where their judgment actually changes the outcome.

**How to apply:**

- **Reversible + low-stakes** (edit a file, draft an issue, run a read-only query, continue to the next step of a routine you're already running) → **act, then report**. No pre-ask.
- **Irreversible / outward-facing** (merging a PR, pushing, posting to another repo, deleting, anything that leaves a permanent backlink) → surface it and **wait**. These stay gated. See [flag external-visibility actions] in your project's rules and the merge discipline in [feedback_github_workflow.md](feedback_github_workflow.md).
- **Ambiguous / high-stakes** (a fork where the wrong branch is expensive, or you genuinely cannot infer the user's preference) → ask, ideally via [feedback_ask_user_question.md](feedback_ask_user_question.md).
- **Multi-step routines:** run the beats straight through unless the user signalled a stop. Don't gate each beat with "resume, or call it here?" — the default is *resume*.
- **This refines [feedback_communicate_next_steps.md](feedback_communicate_next_steps.md):** still state what comes next, but for reversible steps phrase it as "Next I'll do X" (and do it), not "Want me to do X?" (and wait).
- When the user has already volunteered the action ("yes do it", "ok proceed"), just act — never re-confirm what was already approved.
