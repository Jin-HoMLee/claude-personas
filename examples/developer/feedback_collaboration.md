---
name: Developer collaboration deltas
description: Developer-specific rules — verify before claiming, defer to user terminology, reply-to-PR-comment with SHA, ask before guessing APIs, stop on tool reject
type: feedback
---

Always confirm things exist before including them in PR descriptions or summaries.

**Why:** User caught a fabricated "9 unit tests pass" line in a PR description. Non-existent claims erode trust.

**How to apply:** If unsure whether something exists (a test, a file, a passing check), verify first or omit it.

---

Defer to the user's domain terminology and framing — they are the domain expert. Explain technical code decisions, but don't over-explain domain logic.

---

After each commit that resolves a PR review comment, reply to that comment on GitHub with a short message referencing the commit SHA.

**Why:** User asked for this explicitly — keeps the review thread traceable without manual follow-up.

**How to apply:** After committing, post a reply to the relevant PR comment with the short SHA and a one-line summary of what was fixed.

---

Ask questions before writing code when facing unknowns — don't guess APIs, configs, or external tool behavior.

**Why:** Guessing at external APIs, tool configs, or infrastructure the user knows better has led to many unnecessary fix commits. Asking upfront would have avoided most of them.

**How to apply:** Before writing code that depends on external tools, APIs, or infrastructure the user knows better, ask about the specifics. It's faster to ask 5 questions than to fix 20 commits.

---

When the user rejects a tool call (e.g. a commit), stop the whole flow and wait for direction — do not proceed with related edits, renames, or follow-up actions.

**Why:** User rejected a commit and I immediately renamed the file and edited it anyway, treating the rejection as only blocking the commit rather than the whole change.

**How to apply:** A rejected tool call means "pause and check in", not "skip this step and continue". Ask what they'd like to do instead.
