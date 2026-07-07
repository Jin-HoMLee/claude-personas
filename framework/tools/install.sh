#!/usr/bin/env bash
# install.sh - get/refresh the framework payload in an instance.
#
# Part of the distributable payload (listed in framework/FILES), so installed
# instances self-update with their own copy. Distribution ONLY: copies exactly
# the framework/FILES set from the SOURCE CLONE'S GIT CONTENT AT A REF (never
# the working tree) and stamps the pin. It wires no symlinks - adapter wiring
# stays doctor.sh fix-mode's job, so exactly one place creates symlinks.
#
# Refusals are report-never-clobber:
#   SHADOWED  (--into)  destination exists and differs - kept, instance-owned
#   MODIFIED  (--sync)  destination differs from the PINNED copy - kept,
#                       override per file with --force-file <landing>
#   ORPHANED  (--sync)  pinned FILES entry dropped upstream - kept, remove
#                       with --prune (unmodified orphans only)
#
# Exit: 0 clean/up-to-date; 1 refusals or pending --check changes; 2 fatal.

set -u

usage() {
  cat <<'EOF'
Usage:
  install.sh --into <target> [--ref <ref>] [--check]
  install.sh --sync [--ref <ref>] [--check] [--force-file <landing>]... [--prune]

  --into <target>    First install. Run from inside a framework clone; copies
                     the framework/FILES set into <target>/.agents/... and
                     stamps framework_source + framework_ref in the target's
                     .agents/manifest.
  --sync             Update. Run from inside an installed instance; re-resolves
                     the framework source, re-copies the declared set at the
                     new ref, updates framework_ref (and nothing else).
  --check            Dry-run: report what would change, write nothing.
  --ref <ref>        Pin this tag/SHA instead of the newest framework/v* tag.
  --force-file <p>   (sync) Overwrite this locally-modified landing path.
  --prune            (sync) Delete orphaned framework files that still match
                     the pinned copy.
EOF
}

MODE= TARGET= CHECK=0 PRUNE=0 REF_OVERRIDE= REF=
FORCE_FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --into)
      [ $# -ge 2 ] || { echo "ERROR: --into needs a target path" >&2; exit 2; }
      MODE=into; TARGET="$2"; shift 2 ;;
    --sync) MODE=sync; shift ;;
    --check) CHECK=1; shift ;;
    --prune) PRUNE=1; shift ;;
    --force-file)
      [ $# -ge 2 ] || { echo "ERROR: --force-file needs a landing path" >&2; exit 2; }
      FORCE_FILES+=("$2"); shift 2 ;;
    --ref)
      [ $# -ge 2 ] || { echo "ERROR: --ref needs a value" >&2; exit 2; }
      REF_OVERRIDE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
  esac
done
if [ -z "$MODE" ]; then usage >&2; exit 2; fi

PENDING=0
APPLIED=0
report_apply()   { echo "$1"; APPLIED=$((APPLIED + 1)); }
report_pending() { echo "$1"; PENDING=$((PENDING + 1)); }
warn()  { echo "WARN: $1" >&2; }
fatal() { echo "ERROR: $1" >&2; exit 2; }

# --- resolve source clone (SRC) and instance (TARGET) ---

if [ "$MODE" = into ]; then
  SRC="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$SRC" ] && [ -f "$SRC/framework/FILES" ] \
    || fatal "--into must run from inside a framework clone (no framework/FILES at the git toplevel)"
  [ -d "$TARGET" ] || fatal "target '$TARGET' does not exist"
  TARGET="$(cd "$TARGET" && pwd -P)"
else
  TARGET="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$TARGET" ] || fatal "--sync must run from inside the instance (a git repo)"
fi

MANIFEST="$TARGET/.agents/manifest"
[ -f "$MANIFEST" ] || fatal "no manifest at $MANIFEST - declare the instance first (doctor.sh --init <topology>)"

# manifest_get <key>: first value wins (same semantics as doctor.sh).
manifest_get() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$1="*) printf '%s\n' "${line#"$1"=}"; return 0 ;;
    esac
  done < "$MANIFEST"
  return 0
}

PIN=
if [ "$MODE" = sync ]; then
  PIN="$(manifest_get framework_ref)"
  [ -n "$PIN" ] || fatal "no framework_ref in $MANIFEST - not installed yet (run install.sh --into <this-instance> from a framework clone)"
  SRC="$(manifest_get framework_source)"
  if [ -n "$SRC" ]; then
    case "$SRC" in
      /*) ;;
      *) SRC="$TARGET/$SRC" ;;
    esac
    [ -d "$SRC" ] || fatal "framework_source '$SRC' (from manifest) does not exist"
  else
    parent="$(dirname "$TARGET")"
    if [ -f "$parent/agent-personas/framework/FILES" ]; then
      SRC="$parent/agent-personas"
    elif [ -f "$parent/claude-personas/framework/FILES" ]; then
      SRC="$parent/claude-personas"
    else
      fatal "no framework_source in $MANIFEST and no sibling agent-personas/claude-personas clone next to $TARGET - set framework_source explicitly"
    fi
  fi
  SRC="$(cd "$SRC" && pwd)"
  [ -f "$SRC/framework/FILES" ] || fatal "'$SRC' is not a framework clone (no framework/FILES)"
  git -C "$SRC" fetch --tags --quiet 2>/dev/null || true
fi

# --- resolve the ref to pin ---

if [ -n "$REF_OVERRIDE" ]; then
  git -C "$SRC" rev-parse --verify --quiet "$REF_OVERRIDE^{commit}" >/dev/null \
    || fatal "ref '$REF_OVERRIDE' not found in $SRC"
  case "$REF_OVERRIDE" in
    framework/v*) ;;
    *) warn "pinning '$REF_OVERRIDE' - prefer a framework/v* tag" ;;
  esac
  REF="$REF_OVERRIDE"
else
  REF="$(git -C "$SRC" tag -l 'framework/v*' --sort=-v:refname | head -n 1)"
  if [ -z "$REF" ]; then
    REF="$(git -C "$SRC" rev-parse HEAD)"
    warn "no framework/v* tag in $SRC - pinning bare SHA $REF (prefer tags)"
  fi
fi

# --- read FILES at the refs ---

NEW_FILES="$(git -C "$SRC" show "$REF:framework/FILES" 2>/dev/null)" \
  || fatal "framework/FILES not found at ref '$REF' in $SRC"
PIN_FILES=""
if [ "$MODE" = sync ]; then
  PIN_FILES="$(git -C "$SRC" show "$PIN:framework/FILES" 2>/dev/null)" \
    || fatal "framework/FILES not found at pinned ref '$PIN' in $SRC - fetch the source or fix the pin"
fi

# parse_files: stdin FILES text -> "src<TAB>landing" lines; fatal on malformed.
parse_files() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      *' -> '*) printf '%s\t%s\n' "${line%% -> *}" "${line##* -> }" ;;
      *) return 1 ;;
    esac
  done
  return 0
}
NEW_TAB="$(printf '%s\n' "$NEW_FILES" | parse_files)" || fatal "malformed framework/FILES at '$REF'"
PIN_TAB=""
if [ "$MODE" = sync ]; then
  PIN_TAB="$(printf '%s\n' "$PIN_FILES" | parse_files)" || fatal "malformed framework/FILES at pin '$PIN'"
fi

pin_src_for_landing() {
  printf '%s\n' "$PIN_TAB" | awk -F'\t' -v l="$1" '$2 == l { print $1; exit }'
}
new_has_landing() {
  printf '%s\n' "$NEW_TAB" | awk -F'\t' -v l="$1" '$2 == l { found = 1 } END { exit found ? 0 : 1 }'
}
is_forced() {
  local f
  if [ "${#FORCE_FILES[@]}" -gt 0 ]; then
    for f in "${FORCE_FILES[@]}"; do
      [ "$f" = "$1" ] && return 0
    done
  fi
  return 1
}

# --- copy machinery ---

write_from_ref() { # write_from_ref <src_path> <landing> <label>
  local src_path="$1" landing="$2" label="$3" dest="$TARGET/$2" tmp mode
  if [ "$CHECK" = 1 ]; then
    case "$label" in
      INSTALLED) report_pending "WOULD-INSTALL: $landing (from $src_path @ $REF)" ;;
      *)         report_pending "WOULD-SYNC: $landing (from $src_path @ $REF)" ;;
    esac
    return 0
  fi
  tmp="$(mktemp 2>/dev/null)" || fatal "mktemp failed"
  if ! git -C "$SRC" show "$REF:$src_path" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    fatal "cannot read '$src_path' at '$REF' from $SRC (is it in framework/FILES but not committed?)"
  fi
  mkdir -p "$(dirname "$dest")" || { rm -f "$tmp"; fatal "cannot create $(dirname "$dest")"; }
  mv "$tmp" "$dest" || { rm -f "$tmp"; fatal "cannot write $dest"; }
  mode="$(git -C "$SRC" ls-tree "$REF" -- "$src_path" 2>/dev/null | awk '{ print $1 }')"
  if [ "$mode" = "100755" ]; then chmod +x "$dest"; fi
  report_apply "$label: $landing"
}

blob_at() { git -C "$SRC" show "$1:$2" 2>/dev/null; }

process_into() { # process_into <src_path> <landing>
  local src_path="$1" landing="$2" dest="$TARGET/$2"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ "$(cat "$dest" 2>/dev/null)" = "$(blob_at "$REF" "$src_path")" ]; then
      return 0   # identical content: already installed, idempotent re-run
    fi
    report_pending "SHADOWED: $landing exists and differs - kept, instance-owned (install never overwrites)"
  else
    write_from_ref "$src_path" "$landing" INSTALLED
  fi
}

process_sync() { # process_sync <src_path> <landing>
  local src_path="$1" landing="$2" dest="$TARGET/$2" new_blob cur pin_src pinned_blob
  if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
    write_from_ref "$src_path" "$landing" INSTALLED
    return 0
  fi
  new_blob="$(blob_at "$REF" "$src_path")"
  cur="$(cat "$dest" 2>/dev/null)"
  if [ "$cur" = "$new_blob" ]; then
    return 0   # up to date
  fi
  pin_src="$(pin_src_for_landing "$landing")"
  pinned_blob=""
  if [ -n "$pin_src" ]; then
    pinned_blob="$(blob_at "$PIN" "$pin_src")"
  fi
  if [ "$cur" = "$pinned_blob" ]; then
    write_from_ref "$src_path" "$landing" SYNCED
  elif is_forced "$landing"; then
    write_from_ref "$src_path" "$landing" FORCED
  else
    report_pending "MODIFIED: $landing differs from the pinned copy - kept (override: --force-file $landing)"
  fi
}

process_orphans() {
  local line src_path landing dest cur pinned_blob
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    src_path="${line%%$'\t'*}"
    landing="${line##*$'\t'}"
    if new_has_landing "$landing"; then continue; fi
    dest="$TARGET/$landing"
    if [ ! -e "$dest" ]; then continue; fi
    cur="$(cat "$dest" 2>/dev/null)"
    pinned_blob="$(blob_at "$PIN" "$src_path")"
    if [ "$PRUNE" = 1 ] && [ "$CHECK" = 0 ]; then
      if [ "$cur" = "$pinned_blob" ]; then
        rm "$dest" && report_apply "PRUNED: $landing" || fatal "cannot remove $dest"
      else
        report_pending "MODIFIED ORPHAN: $landing differs from the pinned copy - kept, delete by hand"
      fi
    else
      report_pending "ORPHANED: $landing no longer in framework/FILES - kept (remove with --prune)"
    fi
  done <<EOF_ORPHANS
$PIN_TAB
EOF_ORPHANS
}

# --- walk the declared set ---

while IFS= read -r line; do
  [ -n "$line" ] || continue
  src_path="${line%%$'\t'*}"
  landing="${line##*$'\t'}"
  case "$landing" in
    .agents/*) ;;
    *) fatal "FILES declares a landing outside .agents/: '$landing' - refusing" ;;
  esac
  if [ "$MODE" = into ]; then
    process_into "$src_path" "$landing"
  else
    process_sync "$src_path" "$landing"
  fi
done <<EOF_ENTRIES
$NEW_TAB
EOF_ENTRIES

if [ "$MODE" = sync ]; then
  process_orphans
fi

# --- stamp the pin (never in --check) ---

if [ "$CHECK" = 0 ]; then
  if [ "$MODE" = into ]; then
    if [ "$SRC" = "$TARGET" ]; then
      SOURCE_VALUE="."
    elif [ "$(dirname "$SRC")" = "$(dirname "$TARGET")" ]; then
      SOURCE_VALUE="../$(basename "$SRC")"
    else
      SOURCE_VALUE="$SRC"
    fi
  fi
  if [ "$(manifest_get framework_ref)" != "$REF" ] \
     || { [ "$MODE" = into ] && [ "$(manifest_get framework_source)" != "${SOURCE_VALUE:-}" ]; }; then
    tmp="$(mktemp 2>/dev/null)" || fatal "mktemp failed"
    awk -F= -v mode="$MODE" '
      $1 == "framework_ref" { next }
      $1 == "framework_source" && mode == "into" { next }
      { print }
    ' "$MANIFEST" > "$tmp" || { rm -f "$tmp"; fatal "cannot rewrite $MANIFEST"; }
    if [ "$MODE" = into ]; then
      printf 'framework_source=%s\n' "$SOURCE_VALUE" >> "$tmp"
    fi
    printf 'framework_ref=%s\n' "$REF" >> "$tmp"
    mv "$tmp" "$MANIFEST" || fatal "cannot write $MANIFEST"
    report_apply "PINNED: framework_ref=$REF"
  fi
fi

if [ "$PENDING" -gt 0 ]; then
  exit 1
fi
if [ "$APPLIED" -gt 0 ]; then
  echo "OK: framework payload at $REF in $TARGET ($APPLIED change(s))"
else
  echo "OK: framework payload up to date at $REF in $TARGET"
fi
exit 0
