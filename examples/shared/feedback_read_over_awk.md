---
name: Default to Read tool for inspecting file contents — not awk/sed/grep
description: When I want to see what's in a text file, the answer is Read, not a Bash one-liner that parses it
type: feedback
---
**Rule:** when the goal is to *see what's in a file* (read its contents, scan for messages, find a section), use the **Read** tool. Reach for `awk` / `sed` / `grep` / `cat` / `head` / `tail` only when the goal is genuinely shell-only — transformations, pipelines, or filtering output that's already in a stream.

**Why I keep slipping:** classic shell idioms train a reflex of "extract fields with awk" even when a structured Read does the job better. Awk parsing also introduces silent bugs (regex eating lines, missing fields when format drifts) that Read + my own eyes don't.

**How to apply:**

- Reading a file's contents → `Read`
- Looking for specific lines/symbols across files → `grep` via Bash is fine (search is shell-native)
- Reading a known section of a large file → `Read` with `offset` + `limit`
- Parsing JSON → `gh api ... --jq` (jq is structured, not text-regex)
- Transforming text in a pipeline → `awk`/`sed` in Bash is fine (the goal is transformation, not inspection)

**Red flag:** if the next thing I'd do is paste the awk output into prose for the user, the right tool was probably Read. Awk output is for further machine processing; human-readable inspection belongs in Read.
