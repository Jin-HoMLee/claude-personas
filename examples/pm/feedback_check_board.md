---
name: Check live project board at session start
description: Always query the live GitHub project board and issue list at the start of each session, not just memory snapshots
type: feedback
---
Always fetch the live board state at the start of each PM session using `gh issue list` and `gh project item-list`.

**Why:** Memory snapshots reflect the state at the end of the last session. Issues get created, closed, and updated between sessions. Decisions made from stale data lead to wrong priorities.

**How to apply:** At session start, after reading memory, run `gh issue list --state open` to get the current ground truth. Use memory for context and reasoning; use the live board for current status.

## Verify missing issues before declaring them absent

When a known issue number (from memory or notes) is absent from `gh issue list --state open`, always run `gh issue view <number>` to check if it's closed before concluding it doesn't exist. `--state open` silently excludes closed issues — absence from the list does not mean the issue doesn't exist.
