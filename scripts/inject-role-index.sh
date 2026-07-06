#!/usr/bin/env bash
# inject-role-index.sh - Codex SessionStart hook payload for a role clone:
# inject the role's always-loaded memory INDEX (its MEMORY.md) as
# additionalContext, mirroring Claude Code's native auto-load of the role file.
# Ships in the memory repo; the per-clone generated .codex/hooks.json (see
# init-clone.sh) calls it with the absolute role dir.
#
# Usage: inject-role-index.sh <absolute-role-dir>
#
# SCOPE - role index only, NOT shared (claude-personas#52). Claude Code
# auto-injects the role MEMORY.md but not shared/MEMORY.md; shared reaches
# context lazily via the load-persona-memory skill and file-relative links.
# This script mirrors that for cross-vendor parity: it injects only the role
# index and appends a one-line pointer to the on-demand shared index.
#
# CAP - adopts Claude Code's native MEMORY.md size guard rather than an invented
# figure (CC v2.1.186 truncates the auto-injected role index at ~200 lines /
# ~25 KB, whichever first; source: the splice MM reference
# reference_native_memory_compaction.md, cross-checked in claude-personas#48).
# The payload is bounded to whole lines only, with an explicit [TRUNCATED ...]
# trailer when it cuts, so the cut is curated instead of the vendor slicing
# arbitrarily through the middle. Both thresholds are overridable via
# PERSONAS_INJECT_BYTE_CAP / PERSONAS_INJECT_LINE_CAP (a single canonical source
# for the CC figure is the #48 fast-follow).
#
# Defensive by design: never fails the session start - always exits 0.

set -u

role_dir="${1:-}"
[ -n "$role_dir" ] && [ -d "$role_dir" ] || exit 0
command -v jq >/dev/null 2>&1 || {
  echo "inject-role-index: jq not found - index NOT injected; read $role_dir/MEMORY.md manually" >&2
  exit 0
}

# Claude Code native role-index truncation thresholds (whichever hits first).
byte_cap="${PERSONAS_INJECT_BYTE_CAP:-25000}"
line_cap="${PERSONAS_INJECT_LINE_CAP:-200}"

role_index="$role_dir/MEMORY.md"
[ -r "$role_index" ] || exit 0

hdr="# Role memory index
"
# Byte budget left for role-index lines after the header.
remaining=$(( byte_cap - ${#hdr} ))
[ "$remaining" -le 0 ] && exit 0

# grep -c '' counts lines (not newlines), so a final line with no trailing
# newline is not undercounted (which would silently skip the truncation flag).
total="$(grep -c '' "$role_index")"
# Keep whole lines while BOTH the byte budget and the line cap still hold; awk's
# exit fires before printing the line that would breach either.
chunk="$(awk -v bcap="$remaining" -v lcap="$line_cap" '
  { n += length($0) + 1; if (n > bcap || NR > lcap) exit } { print }
' "$role_index")"
kept="$(printf '%s\n' "$chunk" | wc -l | tr -d ' ')"
# awk emits nothing when even the FIRST line overflows; printf '%s\n' "" | wc -l
# still reports 1, so force kept=0 for an empty chunk or the trailer silently
# does not fire on a whole-line drop.
[ -z "$chunk" ] && kept=0

payload="$hdr$chunk
"
truncated=0
[ "$kept" -lt "$total" ] && truncated=1

# Shared index is loaded on demand (parity with CC, which does not auto-inject
# shared). Point at it when it exists - the model reaches it via the
# load-persona-memory skill or file-relative links, not this payload.
if [ -r "$role_dir/shared/MEMORY.md" ]; then
  payload="$payload
# Shared memory index (loaded on demand): read $role_dir/shared/MEMORY.md"
fi

if [ "$truncated" -eq 1 ]; then
  payload="$payload
[TRUNCATED by the Codex adapter at the Claude Code native cap - read $role_index for the full role index]"
fi

jq -nc --arg ctx "$payload" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' 2>/dev/null || true
exit 0
