---
name: Team standup protocol
description: How each role should handle team_standup.md — checked after the morning routine each day
type: feedback
---

Before posting a message, always run `date -u +"%Y-%m-%d %H:%M UTC"` via Bash to get the real timestamp — never guess or invent the time.

Message format: `### [YYYY-MM-DD HH:MM UTC] From: <Role> → To: <Role>` — always include time so messages stay chronological within a day.

**New messages always go at the TOP of the file** (right after the format/header block, before all existing messages). No need to check dates to decide insertion point — newest at top is the rule, chronology is maintained automatically. Same convention as the lab notebook.

**Why:** Messages from other roles may be outdated or need adjustment by the time they're read. The user is the final decision-maker.

**How to apply:**

1. Read any pending messages addressed to your role
2. Bring them up with the user: summarize what the message asks and confirm whether to proceed
3. Only act after the user confirms
4. Reply via a **follow-up message** when the request is actioned — never edit the original sender's message. The follow-up explains the resolution and gives the sender the signal they need.
5. **Each role manages the Status of their own messages (From: <Role>).** The sender — not the recipient — flips Status: Pending → Done once they're satisfied with the resolution. Recipient never edits the sender's message.
6. Each role should delete their own messages (indicated by From: <Role>) with **Status: Done** when they get older than 3 days.
7. Each role should re-raise their own messages (indicated by From: <Role>) with **Status: Pending** when they get older than 1 day — they are stale and should be re-raised fresh if still relevant.

**Why sender-owned Status:** the sender is the one who knows whether the resolution actually satisfied their concern. A recipient marking Done prematurely closes the loop before the sender has had a chance to push back or follow up.

**FYI messages are marked Done at write time.** If a message contains no open question and requests no action from the recipient (pure informational: "here's what I did", confirmation of a completed task, heads-up with no reply needed), the sender marks it `**Status:** Done` immediately when posting. This prevents orphaned Pending messages that have no natural trigger to close. The invariant: **Pending always means "I am waiting for a reply."** If you're not waiting, mark Done now.

**Why these thresholds:** Sessions happen ~1–2 times per day. A Pending message that hasn't been answered in 1 day means the recipient has had multiple session opportunities to reply — a nudge is warranted. Done messages older than 3 days are pure history; the durable record lives in commit messages, the lab notebook, and the project board — the standup is for active conversation only.


**Special message types:**

- `[MILESTONE ACHIEVED 🎉]` — posted by PM when a project milestone is closed. Addressed to All. Always `Status: Done`.

**Never edit a posted message.** Once a message is written, it is immutable. If you need to clarify or correct it, post a new message. Editing breaks the async workflow — the recipient may have already read the original.

If you have new information to add, post a follow-up: `### [timestamp] From: <Role> → To: <Role> (follow-up to [original timestamp])`.
