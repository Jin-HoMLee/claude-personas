---
name: Scope discipline for in-flight Issues
description: Once an Issue is in flight, further scope expansions are filed as separate Issues (or added to existing ones) — never bolted onto the active Issue silently
type: feedback
---

When a new requirement, refinement, or scope expansion surfaces while you are working on an active Issue, there are exactly three legitimate places it can go:

1. **Inside the active Issue** — only if the new requirement is *coherent with the Issue's stated spirit* AND the Issue has not yet been actively coded against. In this case, **update the Issue body explicitly** (do not silently expand) AND **post a standup heads-up to PM** so milestone capacity gets re-evaluated.
2. **Into another existing Issue** — if there's an open Issue that already covers the new requirement, add the new detail there (with a comment explaining the cross-link) and reference it from the active Issue.
3. **As a new Issue** — for everything else. New Issue with `--project "<your-project-board>"` + `--label role:<role>` + `**Created by:** <Role>` line, scoped tightly.

**Never silently expand the active Issue mid-implementation.** Even if the addition feels small.

**Why:**

- Milestone capacity is a useful reference point that PM uses to triage and balance iterations. Silent scope expansion makes capacity unreliable and surprises PM at iteration close.
- Active Issues that grow during implementation tend to drift, lose focus, and produce sprawling PRs that are hard to review.
- Future readers (hiring managers, cofounders, peers) reading commit/PR/Issue history want to see disciplined scope per Issue, not catch-all containers.
- The same Issue having a "scope at creation" and a different "scope at close" is hard to audit retroactively. Scope changes should be explicit, dated, and trackable.

**How to apply:**

- Notice the urge to add "while we're here, also ..." — that's the trigger.
- Stop. Categorise the addition into one of the three buckets above.
- If bucket 1 (active Issue, before-coding): update Issue body + post PM heads-up. Surface the size impact ("M → M+/L") and let PM re-triage.
- If bucket 2 (existing Issue): comment on the other Issue, cross-reference, do not expand the active one.
- If bucket 3 (new Issue): file it. Even if it's tiny. Cheap to file, expensive to undo silently-expanded scope.
- **Once the active Issue has been actively coded against** (commits exist on the branch), bucket 1 is closed too. From that point, ALL further additions go into bucket 2 or 3. The active Issue's scope is locked.
