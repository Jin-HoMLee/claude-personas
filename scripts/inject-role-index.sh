#!/usr/bin/env bash
# inject-role-index.sh - Codex SessionStart hook payload for a role clone:
# inject the role's always-loaded memory indices (role + shared) as
# additionalContext. Ships in the memory repo; the per-clone generated
# .codex/hooks.json (see init-clone.sh) calls it with the absolute role dir.
#
# Usage: inject-role-index.sh <absolute-role-dir>
#
# Codex truncates hook additionalContext hard (live test 2 in
# docs/vendor-caveats.md records the current ceiling), so this script bounds
# its own payload: whole lines only, role index first, then shared index,
# with an explicit [TRUNCATED ...] trailer when it cuts - the cut is curated
# instead of Codex slicing arbitrarily through the middle.
# Defensive by design: never fails the session start - always exits 0.

set -u

role_dir="${1:-}"
[ -n "$role_dir" ] && [ -d "$role_dir" ] || exit 0
command -v jq >/dev/null 2>&1 || {
  echo "inject-role-index: jq not found - index NOT injected; read $role_dir/MEMORY.md manually" >&2
  exit 0
}

cap=9000
payload=""
truncated=0

# Append $2 as a header, then whole lines of file $1 until the cap.
append_bounded() {
  local f="$1" hdr="$2" remaining chunk kept total
  [ -r "$f" ] || return 0
  remaining=$(( cap - ${#payload} - ${#hdr} ))
  if [ "$remaining" -le 0 ]; then truncated=1; return 0; fi
  payload="$payload$hdr"
  total="$(wc -l < "$f" | tr -d ' ')"
  chunk="$(awk -v cap="$remaining" '{n += length($0) + 1; if (n > cap) exit} {print}' "$f")"
  kept="$(printf '%s\n' "$chunk" | wc -l | tr -d ' ')"
  payload="$payload$chunk
"
  [ "$kept" -lt "$total" ] && truncated=1
}

append_bounded "$role_dir/MEMORY.md" "# Role memory index
"
append_bounded "$role_dir/shared/MEMORY.md" "
# Shared memory index
"

[ -n "$payload" ] || exit 0
if [ "$truncated" -eq 1 ]; then
  payload="$payload
[TRUNCATED by the Codex adapter - read $role_dir/MEMORY.md and $role_dir/shared/MEMORY.md for the full indices]"
fi

jq -nc --arg ctx "$payload" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' 2>/dev/null || true
exit 0
