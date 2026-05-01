---
name: Context compact reminders
description: Remind user to consider compacting context at natural breakpoints
type: feedback
---
At natural breakpoints, suggest `/compact` with a short one-liner like "Good time to `/compact` before we start?"

**Triggers:**

- Before starting a new Issue / work package
- After finishing one (PR opened, review addressed, merged)
- At wind-down (signals: "that's all", "good night", "talk later", "bye", "see you")

**Never** suggest `/compact` mid-task — only at clean boundaries.

**Why:** User can see the context usage % in the UI but I can't. Proactive reminders at logical boundaries prevent hitting auto-compact mid-task and keep the JSONL compact summary fresh for next time `--continue` is used.

**How to apply:** Add a one-line `/compact` suggestion at the end of the reply when any trigger fires.
