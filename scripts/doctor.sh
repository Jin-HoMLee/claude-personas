#!/usr/bin/env bash
# doctor.sh - manifest-driven integrity check + fixer for a claude-personas
# instance (role-clone constellation, embedded, or user-tier).
#
# Usage:
#   doctor.sh [--check] [--root PATH]
#   doctor.sh --init <topology>
#
# The instance declares its topology in a committed $root/.agents/manifest
# file (flat key=value, never shell-sourced). doctor.sh never infers the
# topology from repo shape - see docs/superpowers/specs/
# 2026-07-04-toolbox-manifest-driven-doctor-design.md.
#
# Default mode fixes derivable drift; --check reports only and changes
# nothing. Output vocabulary is exactly DRIFT: / FIXED: / ERROR: / OK:.
# Exit codes: 0 clean, 1 drift or error, 2 missing/invalid manifest.
#
# Never uses `set -e`: one refusal must not hide others.
#
# ADAPTERS / SKILLS_MOUNT / OPENCODE_MODE are produced globals not consumed
# in this file yet: they are read by topology_*_checks once the per-topology
# catalogs land in Tasks 3-8 (see the per-assignment shellcheck disables at
# each of those globals below). CHECK / MEMORY_LAYOUT / CLAUDE_HOOKS /
# CODEX_HOOKS are consumed by this file's shared check core (need_link,
# check_payload, check_hook_scripts).
set -u

# --- constants: the manifest key vocabulary (the validation whitelist) ---

VALID_TOPOLOGIES="role-clones embedded user-tier"
VALID_MEMORY_LAYOUTS="roles flat"
VALID_ADAPTER_VALUES="claude-code codex opencode"
VALID_SKILLS_MOUNT_VALUES="true false"
VALID_OPENCODE_VALUES="global per-clone"
SUPPORTED_MANIFEST_VERSIONS="1"

# All keys this doctor understands, regardless of topology.
ALL_VALID_KEYS="manifest_version topology memory_layout adapter claude_hook codex_hook skills_mount opencode"

# Keys valid only for topology=embedded.
EMBEDDED_ONLY_KEYS="claude_hook codex_hook skills_mount"
# Keys valid only for topology=role-clones.
ROLE_CLONES_ONLY_KEYS="opencode"

usage() {
  cat <<'EOF'
Usage: doctor.sh [--check] [--root PATH]
       doctor.sh --init <topology>

  --check         Report only; do not fix anything. Exits nonzero on drift.
  --root PATH     Instance root to doctor (default: git toplevel of cwd, or cwd).
  --init TOPOLOGY Write a starter .agents/manifest for TOPOLOGY and exit.
                  TOPOLOGY is one of: role-clones, embedded, user-tier.
                  Refuses to overwrite an existing manifest.

Exit codes: 0 clean, 1 drift or error, 2 missing/invalid manifest.
EOF
}

_word_in_list() {
  # _word_in_list <word> <space-separated-list>
  local word="$1" list="$2"
  case " $list " in
    *" $word "*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- argument parsing ---

CHECK=0
ROOT_ARG=""
INIT_TOPOLOGY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --check)
      CHECK=1
      shift
      ;;
    --root)
      if [ $# -lt 2 ]; then
        echo "ERROR: --root requires a PATH argument" >&2
        exit 2
      fi
      ROOT_ARG="$2"
      shift 2
      ;;
    --init)
      if [ $# -lt 2 ]; then
        echo "ERROR: --init requires a TOPOLOGY argument" >&2
        exit 2
      fi
      INIT_TOPOLOGY="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# --- root resolution ---

default_root() {
  local toplevel
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
  if [ -n "$toplevel" ]; then
    printf '%s\n' "$toplevel"
    return 0
  fi
  pwd
}

if [ -n "$ROOT_ARG" ]; then
  ROOT="$(cd "$ROOT_ARG" 2>/dev/null && pwd)"
  if [ -z "$ROOT" ]; then
    echo "ERROR: --root path does not exist: $ROOT_ARG" >&2
    exit 2
  fi
else
  ROOT="$(default_root)"
fi

MANIFEST="$ROOT/.agents/manifest"

# --- manifest readers (grep/cut line readers; the manifest is never sourced) ---

manifest_get() {
  # First value for key $1 (non-comment, non-blank lines only).
  local key="$1"
  grep -v '^[[:space:]]*#' "$MANIFEST" 2>/dev/null \
    | grep -v '^[[:space:]]*$' \
    | grep "^${key}=" \
    | head -n1 \
    | cut -d= -f2-
}

manifest_get_all() {
  # All values for repeatable key $1, one per line.
  local key="$1"
  grep -v '^[[:space:]]*#' "$MANIFEST" 2>/dev/null \
    | grep -v '^[[:space:]]*$' \
    | grep "^${key}=" \
    | cut -d= -f2-
}

# --- starter manifests for --init ---

write_starter_role_clones() {
  cat > "$1" <<'EOF'
# claude-personas manifest - written by doctor.sh --init role-clones
# Flat key=value, strict (no spaces around =); # comments and blank lines
# are ignored. See docs/superpowers/specs/
# 2026-07-04-toolbox-manifest-driven-doctor-design.md for the full key table.

manifest_version=1
topology=role-clones
memory_layout=roles

# Declare each vendor adapter this instance wires. Remove a line if that
# vendor is not used here.
adapter=claude-code
adapter=codex
adapter=opencode

# Optional keys for topology=role-clones:
# opencode=global      # or: per-clone (default: global)
EOF
}

write_starter_embedded() {
  cat > "$1" <<'EOF'
# claude-personas manifest - written by doctor.sh --init embedded
# Flat key=value, strict (no spaces around =); # comments and blank lines
# are ignored. See docs/superpowers/specs/
# 2026-07-04-toolbox-manifest-driven-doctor-design.md for the full key table.

manifest_version=1
topology=embedded
memory_layout=flat

# Declare each vendor adapter this instance wires. Remove a line if that
# vendor is not used here.
adapter=claude-code
adapter=codex
adapter=opencode

# Optional keys for topology=embedded:
# claude_hook=scripts/some-hook.sh   # repeatable; repo-relative script path
# codex_hook=scripts/some-hook.sh    # repeatable; repo-relative script path
# skills_mount=true                  # or: false (default)
EOF
}

write_starter_user_tier() {
  cat > "$1" <<'EOF'
# claude-personas manifest - written by doctor.sh --init user-tier
# Flat key=value, strict (no spaces around =); # comments and blank lines
# are ignored. See docs/superpowers/specs/
# 2026-07-04-toolbox-manifest-driven-doctor-design.md for the full key table.

manifest_version=1
topology=user-tier
memory_layout=flat

# Declare each vendor adapter this instance wires. Remove a line if that
# vendor is not used here.
adapter=claude-code
adapter=codex
adapter=opencode

# No topology-specific optional keys for user-tier.
EOF
}

do_init() {
  local topology="$1"

  if ! _word_in_list "$topology" "$VALID_TOPOLOGIES"; then
    echo "ERROR: unknown topology '$topology' for --init (valid: role-clones, embedded, user-tier)" >&2
    exit 2
  fi

  if [ -e "$MANIFEST" ]; then
    echo "ERROR: manifest already exists at $MANIFEST (refusing to overwrite; edit it directly)" >&2
    exit 2
  fi

  mkdir -p "$(dirname "$MANIFEST")"

  case "$topology" in
    role-clones) write_starter_role_clones "$MANIFEST" ;;
    embedded) write_starter_embedded "$MANIFEST" ;;
    user-tier) write_starter_user_tier "$MANIFEST" ;;
  esac

  echo "Wrote starter manifest: $MANIFEST"
  exit 0
}

if [ -n "$INIT_TOPOLOGY" ]; then
  do_init "$INIT_TOPOLOGY"
fi

# --- refuse if there is no manifest to doctor (static, never inspects repo shape) ---

if [ ! -f "$MANIFEST" ]; then
  cat >&2 <<EOF
ERROR: no manifest at $MANIFEST
This instance has not declared its topology. doctor.sh never guesses the
topology from repo shape - declare it explicitly. Supported topologies:

  role-clones  memory repo + per-role clones (the claude-personas constellation)
  embedded     a single repo carries .agents/ alongside its own project code
  user-tier    global user-level memory, not tied to a single project repo

Run: doctor.sh --init <topology>   (role-clones | embedded | user-tier)
EOF
  exit 2
fi

# --- manifest validation ---

validate_manifest_syntax() {
  # Pass 1: strict line syntax + unknown-key check over the raw file.
  # Every non-comment, non-blank line must match ^[a-z_]+=[^[:space:]]+$
  # (no spaces around =, non-empty value, no embedded whitespace, no
  # trailing whitespace). Comment/blank lines are ignored outright.
  local line lineno=0 key trimmed
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))

    # Blank (or whitespace-only) line: ignored.
    if [ -z "${line//[[:space:]]/}" ]; then
      continue
    fi

    # Comment line: ignored, even when indented - only a pure key=value line
    # is held to the no-leading/trailing-whitespace rule.
    trimmed="$line"
    while true; do
      case "$trimmed" in
        [\ $'\t']*) trimmed="${trimmed#?}" ;;
        *) break ;;
      esac
    done
    case "$trimmed" in
      '#'*) continue ;;
    esac

    if ! printf '%s\n' "$line" | grep -qE '^[a-z_]+=[^[:space:]]+$'; then
      echo "ERROR: invalid manifest line $lineno in $MANIFEST: '$line' (expected strict key=value, no spaces)" >&2
      exit 2
    fi

    key="${line%%=*}"
    if ! _word_in_list "$key" "$ALL_VALID_KEYS"; then
      echo "ERROR: unknown manifest key '$key' (line $lineno in $MANIFEST: $line)" >&2
      exit 2
    fi
  done < "$MANIFEST"
}

validate_manifest_semantics() {
  local k v version topology layout adapter_value hook

  # Required keys present.
  for k in manifest_version topology memory_layout; do
    v="$(manifest_get "$k")"
    if [ -z "$v" ]; then
      echo "ERROR: missing required manifest key '$k' in $MANIFEST" >&2
      exit 2
    fi
  done

  # manifest_version: the escape hatch for future format changes.
  version="$(manifest_get manifest_version)"
  if ! _word_in_list "$version" "$SUPPORTED_MANIFEST_VERSIONS"; then
    echo "ERROR: unsupported manifest_version '$version' in $MANIFEST (this doctor supports: $SUPPORTED_MANIFEST_VERSIONS)" >&2
    exit 2
  fi

  # topology: selects the check catalog, never inferred.
  topology="$(manifest_get topology)"
  if ! _word_in_list "$topology" "$VALID_TOPOLOGIES"; then
    echo "ERROR: unknown topology '$topology' in $MANIFEST (valid: role-clones, embedded, user-tier)" >&2
    exit 2
  fi

  # memory_layout.
  layout="$(manifest_get memory_layout)"
  if ! _word_in_list "$layout" "$VALID_MEMORY_LAYOUTS"; then
    echo "ERROR: unknown memory_layout '$layout' in $MANIFEST (valid: roles, flat)" >&2
    exit 2
  fi

  # adapter values (repeatable, optional).
  while IFS= read -r adapter_value; do
    [ -n "$adapter_value" ] || continue
    if ! _word_in_list "$adapter_value" "$VALID_ADAPTER_VALUES"; then
      echo "ERROR: unknown adapter '$adapter_value' in $MANIFEST (valid: claude-code, codex, opencode)" >&2
      exit 2
    fi
  done < <(manifest_get_all adapter)

  # Per-topology key validity: a key valid only for another topology is an
  # invalid manifest, not a soft warning.
  for k in $EMBEDDED_ONLY_KEYS; do
    if [ -n "$(manifest_get "$k")" ] && [ "$topology" != "embedded" ]; then
      echo "ERROR: key '$k' is only valid for topology=embedded (this manifest declares topology=$topology) in $MANIFEST" >&2
      exit 2
    fi
  done
  for k in $ROLE_CLONES_ONLY_KEYS; do
    if [ -n "$(manifest_get "$k")" ] && [ "$topology" != "role-clones" ]; then
      echo "ERROR: key '$k' is only valid for topology=role-clones (this manifest declares topology=$topology) in $MANIFEST" >&2
      exit 2
    fi
  done

  # skills_mount value (embedded only, already confirmed permitted above).
  v="$(manifest_get skills_mount)"
  if [ -n "$v" ] && ! _word_in_list "$v" "$VALID_SKILLS_MOUNT_VALUES"; then
    echo "ERROR: invalid skills_mount '$v' in $MANIFEST (valid: true, false)" >&2
    exit 2
  fi

  # opencode value (role-clones only, already confirmed permitted above).
  v="$(manifest_get opencode)"
  if [ -n "$v" ] && ! _word_in_list "$v" "$VALID_OPENCODE_VALUES"; then
    echo "ERROR: invalid opencode '$v' in $MANIFEST (valid: global, per-clone)" >&2
    exit 2
  fi

  # claude_hook / codex_hook must be repo-relative paths, not absolute.
  for k in claude_hook codex_hook; do
    while IFS= read -r hook; do
      [ -n "$hook" ] || continue
      case "$hook" in
        /*)
          echo "ERROR: $k '$hook' in $MANIFEST must be a repo-relative path, not absolute" >&2
          exit 2
          ;;
      esac
    done < <(manifest_get_all "$k")
  done
}

validate_manifest_syntax
validate_manifest_semantics

# --- populate globals for topology check functions (Tasks 2-8) ---

TOPOLOGY="$(manifest_get topology)"
MEMORY_LAYOUT="$(manifest_get memory_layout)"

# shellcheck disable=SC2034 # consumed by topology_*_checks (Tasks 3-8)
ADAPTERS=()
while IFS= read -r _v; do
  [ -n "$_v" ] && ADAPTERS+=("$_v")
done < <(manifest_get_all adapter)

CLAUDE_HOOKS=()
while IFS= read -r _v; do
  [ -n "$_v" ] && CLAUDE_HOOKS+=("$_v")
done < <(manifest_get_all claude_hook)

CODEX_HOOKS=()
while IFS= read -r _v; do
  [ -n "$_v" ] && CODEX_HOOKS+=("$_v")
done < <(manifest_get_all codex_hook)

# shellcheck disable=SC2034 # consumed by topology_*_checks (Tasks 3-8)
SKILLS_MOUNT="$(manifest_get skills_mount)"
[ -n "$SKILLS_MOUNT" ] || SKILLS_MOUNT="false"

# shellcheck disable=SC2034 # consumed by topology_*_checks (Tasks 3-8)
OPENCODE_MODE="$(manifest_get opencode)"
[ -n "$OPENCODE_MODE" ] || OPENCODE_MODE="global"

# --- shared check core (Task 2): counters, reporters, link/payload/hook checks ---

# Single counter driving the final exit code. FIXED lines never touch it: a
# repaired instance still exits 0 and prints the final OK line.
DRIFT_COUNT=0

report_drift() {
  echo "DRIFT: $1"
  DRIFT_COUNT=$((DRIFT_COUNT + 1))
}

# shellcheck disable=SC2329 # called by need_link, which topology_*_checks wire in from Task 3
report_fixed() {
  echo "FIXED: $1"
}

# shellcheck disable=SC2329 # called by need_link, which topology_*_checks wire in from Task 3
report_error() {
  echo "ERROR: $1"
  DRIFT_COUNT=$((DRIFT_COUNT + 1))
}

# shellcheck disable=SC2329 # this task's shared machinery; topology_*_checks call it from Task 3
need_link() {
  # need_link <path> <target> <label>
  #
  # Correct symlink (right target): silent, does nothing.
  # Real (non-symlink) file or dir at <path>: DRIFT, never touched in either
  # mode - that path is owned by something else.
  # Wrong or missing symlink: --check reports drift; default (fix) mode
  # mkdir -p's the parent then ln -sfn's the target.
  local p="$1" tgt="$2" label="$3"

  if [ -L "$p" ] && [ "$(readlink "$p")" = "$tgt" ]; then
    return 0
  fi

  if [ -e "$p" ] && [ ! -L "$p" ]; then
    report_drift "$label exists and is not a symlink (refusing to touch)"
    return 0
  fi

  if [ "$CHECK" = 1 ]; then
    report_drift "$label -> $(readlink "$p" 2>/dev/null || echo MISSING), expected $tgt"
  elif mkdir -p "$(dirname "$p")" && ln -sfn "$tgt" "$p" 2>/dev/null; then
    report_fixed "$label -> $tgt"
  else
    report_error "could not create $label -> $tgt"
  fi
}

# shellcheck disable=SC2329 # this task's shared machinery; first CLI consumer lands in Task 4
require_jq() {
  # require_jq <what-for>
  # jq present: silent, returns 0. jq absent: one DRIFT line naming what the
  # skipped checks were for, returns 1 - callers skip their jq-dependent
  # checks loudly instead of silently swallowing them.
  if command -v jq >/dev/null 2>&1; then
    return 0
  fi
  report_drift "jq not installed (needed for $1) - skipping those checks"
  return 1
}

check_payload() {
  # Payload sanity, keyed off the declared memory_layout. flat: a single
  # always-loaded index. roles: every role dir (same discovery rule as
  # list-roles.sh / init-clone.sh - a dir with MEMORY.md, excluding shared
  # and examples) plus shared/MEMORY.md.
  case "$MEMORY_LAYOUT" in
    flat)
      [ -f "$ROOT/.agents/memory/MEMORY.md" ] \
        || report_drift ".agents/memory/MEMORY.md missing"
      ;;
    roles)
      local d n role_count=0
      for d in "$ROOT"/*/; do
        [ -d "$d" ] || continue
        n="$(basename "$d")"
        if [ -f "$d/MEMORY.md" ] && [ "$n" != "shared" ] && [ "$n" != "examples" ]; then
          role_count=$((role_count + 1))
        fi
      done
      if [ "$role_count" -eq 0 ]; then
        report_drift "roles layout declared but no role dirs found"
      fi
      [ -f "$ROOT/shared/MEMORY.md" ] \
        || report_drift "shared/MEMORY.md missing"
      ;;
  esac
}

check_hook_scripts() {
  # Every declared claude_hook / codex_hook must exist and be executable at
  # its repo-relative path under $ROOT.
  local hook

  if [ "${#CLAUDE_HOOKS[@]}" -gt 0 ]; then
    for hook in "${CLAUDE_HOOKS[@]}"; do
      [ -x "$ROOT/$hook" ] \
        || report_drift "claude_hook '$hook' missing or not executable at $ROOT/$hook"
    done
  fi

  if [ "${#CODEX_HOOKS[@]}" -gt 0 ]; then
    for hook in "${CODEX_HOOKS[@]}"; do
      [ -x "$ROOT/$hook" ] \
        || report_drift "codex_hook '$hook' missing or not executable at $ROOT/$hook"
    done
  fi
}

# --- topology dispatch (stubs; catalogs land in later tasks) ---

topology_role_clones_checks() {
  :
}

topology_embedded_checks() {
  :
}

topology_user_tier_checks() {
  :
}

# Shared floor for every topology, run before the topology-specific catalog.
check_payload
check_hook_scripts

case "$TOPOLOGY" in
  role-clones) topology_role_clones_checks ;;
  embedded) topology_embedded_checks ;;
  user-tier) topology_user_tier_checks ;;
esac

if [ "$DRIFT_COUNT" -gt 0 ]; then
  exit 1
fi

echo "OK: $TOPOLOGY instance at $ROOT - all declared wiring verified"
exit 0
