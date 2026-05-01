---
name: CLI style — gh + jq over python -c
description: When parsing JSON in shell commands, use jq (not python -c one-liners); prefer gh CLI over ad-hoc scripts
type: feedback
---
Use `gh` CLI commands with `jq` for JSON parsing — never `python -c` one-liners.

**Why:** `gh` + `jq` is more readable, composable, and consistent. `python -c` one-liners are harder to read at a glance, fragile with quoting, and unnecessary when `jq` handles the same task cleanly.

**How to apply:**
- Parse `gh` JSON output with `jq` (e.g. `gh issue list --json number,title | jq '[.[] | ...]'`)
- Never use `python -c` or `python3 -c` as an inline JSON filter in a shell command
- This applies to all roles and all contexts — board queries, API responses, config parsing
