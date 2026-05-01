---
name: Multi-file feature workflow
description: The collaboration style the user finds efficient and understandable for multi-file changes
type: feedback
---
For multi-file feature work, use this workflow:

1. **Plan inline first** — lay out the full change map (file → what changes) before touching any code. Get user agreement on design before writing.
2. **Docs before code** — update work log or notebook with rationale first, commit separately. This locks in design decisions and surfaces disagreements early.
3. **TodoWrite for tracking** — create a todo list at the start of implementation; mark each item completed immediately after committing it. One `in_progress` at a time.
4. **One file per commit** — commit each file as soon as it's done, with a descriptive message. Never batch unrelated files. Small commits give the user reviewable progress and let individual pieces be reverted if something goes wrong. (Incident: batching multiple unrelated files before the user spoke up — individual pieces couldn't be reverted cleanly.)
5. **Short status between steps** — after each commit, one sentence on what was done and what's next. Don't be silent.
6. **Finish the current unit before compacting** — when context is low, don't leave files half-edited; commit the logical unit, then compact.

**Why:** User finds this efficient and understandable — progress is visible, each change is reviewable, and context handoffs are clean.

**How to apply:** Any issue touching 4+ files. Especially when changes span scripts, rules, config, and tests.
