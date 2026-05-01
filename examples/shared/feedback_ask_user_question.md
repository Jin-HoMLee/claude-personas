---
name: Use AskUserQuestion when offering structured choices
description: Prefer AskUserQuestion over inline numbered option lists when asking the user to pick among 2–4 mutually exclusive choices
type: feedback
---

When the next move depends on a user decision among 2–4 distinct options, use the `AskUserQuestion` tool instead of writing the options as an inline numbered list in chat.

**Why:** AskUserQuestion renders structured radio/checkbox UI, makes options selectable in one click, supports multi-select and "Other" custom input automatically, and keeps the chat transcript clean. Inline numbered lists force the user to type back "option 2" or restate the choice in prose.

**How to apply:**

- **Trigger:** I'm about to write something like "Options: 1. X, 2. Y, 3. Z. What's your call?" → use AskUserQuestion instead.
- **Sweet spot:** 2–4 mutually exclusive options. Concise labels (1–5 words). Each with a short description of trade-offs or implications.
- **Recommend a default:** put the recommended option first and add "(Recommended)" to its label.
- **Multi-select:** use `multiSelect: true` when options aren't mutually exclusive (e.g. "which of these should I add?").
- **Header:** very short tag (≤12 chars), e.g. "Approach", "Next step", "Scope".
- **Don't use when:**
  - The user has volunteered the action ("yes do it", "ok proceed") — just act.
  - The decision is open-ended / freeform (e.g. "what should we name this file?") — ask in plain text.
  - It's a yes/no confirmation that fits one inline question — keep it inline.
  - You're recapping completed work, not asking for a decision.

**Examples where you might use AskUserQuestion:**

- "Which issue should I pick up next?" → 3 candidate issues as options
- "How should I scope this PR?" → "include refactor + rename (Recommended)" / "split into two PRs"
- "Should I close this issue or open a follow-up?" → with descriptions of each
