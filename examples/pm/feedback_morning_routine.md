---
name: Morning routine — PM session
description: What to do when the user says "good morning" in a PM session
type: feedback
---
## PM morning routine

**Step 1 — Motivating board recap:** Give an energizing summary of what happened on the project board the previous day. Highlight closures, merges, and progress. Keep it positive and momentum-building — this sets the tone for the day.

**Step 2 — Standup updates (dedicated section):** After the board recap, surface relevant standup activity in a separate `## Standup` section. Do NOT mix standup messages into the board recap — keep them visually distinct. Include: any messages addressed to PM (pending or new), and noteworthy cross-role activity (e.g. issue drafts under review, decisions in flight) even if not addressed to PM.

**Step 3 — Triage plan (after a short exchange):** Once the user has had a moment to react, proactively sketch a triage plan for the day. Focus on newly created issues that haven't been assigned a milestone, priority, or status yet. Propose where each one belongs and why.

**Why:** The user wants to start the day with a sense of progress, then move naturally into PM work (triage) rather than jumping straight into implementation tasks. Keeping the standup in its own section prevents board events and inter-role messages from blurring together — they have different mental categories.

**How to apply:**
- Pull the live board at session start (as always)
- For the recap: compare against last session state in memory — what closed, what moved, what was created
- For the standup section: read team_standup.md; list any messages To: PM (Pending) and any Pending messages between other roles worth flagging
- For the triage plan: flag issues with no milestone, priority, or status; propose assignments

## Visual formatting (make the post easy to scan)

The morning post sets the tone — it should look pleasant, not like a wall of text. Apply these formatting conventions every morning:

- **Top line:** one cheerful greeting + a single at-a-glance summary line (e.g. "17 open · 2 new overnight · 1 standup item to flag"). Lets the user grok the day's state in 2 seconds.
- **Section headers:** `## 📋 Board recap` · `## 💬 Standup` · `## 🎯 Triage plan` — use these exact emoji markers, they create instant visual landmarks.
- **Within each section:**
  - Use sub-bullets, not paragraphs. Each fact = its own line.
  - **Bold** the issue number + keyword phrase (e.g. **#42 (short keyword)**).
  - Keep one blank line between major bullets so the eye can rest.
  - For "what changed since yesterday," prefer a small markdown table with columns like `# | Title | Change` when there are 3+ items.
- **Closing line:** end with a single proposed next action phrased as a question, separated by `---` from the rest. Not buried in a paragraph.

**Why:** plain prose makes the user re-read to find what matters. A scannable layout means they can skim, react, and choose direction in one glance — which is the whole point of a morning routine.

**How to apply:** when in doubt, ask "could the user grok this in 5 seconds?" If not, break it up further. Emoji markers are intentional — they're visual landmarks, not decoration. Don't add other emojis to the body text.

## Triage plan format — use a before/after diff table

Triage proposals must be shown as a **single diff table**, not as bullet prose. The user wants to see exactly which fields move on which issues at a glance.

**Table columns:** `# | Title | Milestone | Size | Priority | Status` (add a `Parent` column if your project uses parent/sub-issue structures)

**Cell format:**
- Use `before → after` syntax in any cell that changes (e.g. `— → i1 - S6 - ...`, `Backlog → In progress`)
- Use `—` for "unset" (no value before)
- Use plain value with no arrow when the field doesn't change in this triage (or leave blank if it's not relevant for that row)
- Bold the issue number in the first column

**Row order (parent-first, sub-issues nested if applicable):**
- Parent issue on its own row first
- Sub-issues directly underneath, in the order they appear on GitHub. For not-yet-linked sub-issues, fall back to ascending issue number.
- Visually nest sub-issues with a `↳` prefix in the `#` column. Don't indent the title — only the issue-number cell shows the nesting.
- Show ALL sub-issues of the parent, even ones not being modified — gives the user the full family-tree context. Unchanged rows have no `→` arrows in any cell.

**Always verify before claiming linkage or content (don't assume):**
- Before stating "X is/isn't a sub-issue of Y" → run `gh api repos/.../issues/Y/sub_issues` and check.
- Before calling something a "placeholder" or "skeleton" → run `gh issue view N --json body` and read the actual scope. Issues with full scope + acceptance criteria are real work, not placeholders.
- Both verifications take one bash call each. Skipping them and hedging in prose ("might be just a placeholder") wastes the user's time.

For unrelated standalone issues being triaged in the same pass, list them after all parent-trees in ascending issue-number order, separated visually if needed (a horizontal rule between groups, or a blank row).

After the table, optionally add a short bullet list ONLY for reasoning the table cannot capture — cross-issue context, dependencies, scope concerns, follow-up risks. **Do NOT restate values that are already visible in cells**. If there's nothing the table can't capture, omit the notes section entirely. Then close with the standard one-line action question separated by `---`.

**Why:** the user works in field-level diffs (this changes, that doesn't). A diff table makes proposed changes immediately reviewable — the user can spot a wrong value in one column without re-reading prose. Parent-first nesting matches how the work is mentally grouped on GitHub, so the table reads in the same shape as the board.

**How to apply:** every triage proposal — morning warm-up or mid-day — uses this table. Even single-issue triages get a one-row table, not a paragraph.
