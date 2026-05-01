---
name: Lab notebook conventions
description: Format, timestamps, editor attribution, and update reminders for <your-lab-notebook-path>
type: feedback
---
## Insertion order — ALWAYS newest first

**New entries go at the TOP — never the bottom.**

- New date (`## YYYY-MM-DD`) → insert at the very top of the file, above all previous dates
- New time entry (`### HH:MM UTC`) for an existing date → insert directly under the `## YYYY-MM-DD` header, above earlier entries that day


If you find yourself scrolling to the bottom to add an entry, stop — you're doing it wrong.

## Format and timestamps

Always use a nested heading structure:

- `## YYYY-MM-DD` — date-level section (one per day)
- `### HH:MM UTC — Editor: <Role>` — time + attribution on the same line
- `####` — individual topic entries nested under the time

Always run `date -u +"%H:%M UTC"` via Bash to get the current UTC time before writing an entry — never guess or omit the timestamp.

Timed runs get an event timestamp table in the body.

**Why:** Nested date/time headings clearly separate multiple entries per day; event timestamps allow wall-clock reconstruction and cross-reference with log files; editor attribution shows who wrote each entry at a glance since multiple roles contribute.

## Update reminders — write the work log or notebook entry before the action that "ships" the work

The notebook entry must precede whatever step makes the work durable / public. The exact step depends on what the work produced:

- **Standard issue with a PR:** notebook entry → commit → push → `gh pr merge`. The PR merge is what ships, so the notebook lands in the same PR. Never ask "want to merge?" without checking the notebook first.
- **Decomposition issue (no PR — work product is the new sub-issues):** notebook entry → `gh issue close`. The issue close is what ships, so the notebook commit happens in a small docs branch beforehand (or rolls into another open PR if one exists for adjacent work).
- **Session winding down with no merge or close:** still prompt for an entry covering the session's reasoning — the next session needs it.

**Why:** The notebook is the durable record of *why* a decision was made. If we close/merge first and write the notebook later, the entry tends to get skipped or written from memory, losing the original reasoning.
