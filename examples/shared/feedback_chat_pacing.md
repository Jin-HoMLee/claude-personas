---
name: Pause for the user to read after long messages, before tool calls that need approval
description: Don't fire a permission-prompting tool call immediately after a long chat message — the popup blocks the chat view
type: feedback
---
After posting a long chat message (multi-section, table, or detailed proposal), **wait for the user to react** before issuing the next tool call that triggers a permission popup (Bash with new commands, Edit/Write of unfamiliar paths, etc.).

**Why:** The permission popup overlays and blocks the chat. If it appears before the user has read the proposal, they have to dismiss it just to read what you wrote — broken UX. Especially bad when the message contains a triage proposal or plan they need to review *before* approving the action.

**How to apply:**
- Long message + tool needing approval → post the message, end with a clear action question ("Apply this?"), then **STOP**. Wait for confirmation.
- Short message (one or two lines) + tool → fine to chain immediately, since there's nothing significant to read.
- Already-allowlisted commands (no popup) → fine to chain immediately.
- Rule of thumb: if the user needs to read your message to decide whether to approve the next action, never let the popup land on top of the message.
