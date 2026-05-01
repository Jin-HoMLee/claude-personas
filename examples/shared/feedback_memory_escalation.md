---
name: Memory escalation on repeat failure
description: When corrected for forgetting something, find the memory and promote it inline to the role's MEMORY.md if it only lives behind a link
type: feedback
---
**When the user says "you forgot X", "you did X again", "did you forget about X?", or any similar correction:**

1. Search for an existing memory on that topic across all memory files
2. If found **inline in this role's own MEMORY.md** → already at the right level; no promotion needed
3. If found **only via a link** (shared/MEMORY.md, a referenced feedback file, etc. — not inline in this role's MEMORY.md) → **promote it**: copy that specific rule inline into this role's MEMORY.md under `## Always in effect`
4. If **not found anywhere** → create a new memory AND add it inline to this role's MEMORY.md immediately

**Why:** Rules behind links require an explicit file read to fire. Inline rules in MEMORY.md are auto-loaded every session with no reads required. Promoting on repeat failure ensures the most-missed rules always fire.

**How to apply:** After every correction, search first — don't just create a new memory. If the rule already exists somewhere, promote it rather than duplicate it.
