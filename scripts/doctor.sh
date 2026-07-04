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
# OPENCODE_MODE is a produced global not consumed in this file yet: it is
# read once the role-clones catalog's vendor wiring half lands (Task 6; see
# its shellcheck disable below). CHECK / MEMORY_LAYOUT / CLAUDE_HOOKS /
# CODEX_HOOKS are consumed by this file's shared check core (need_link,
# check_payload, check_hook_scripts). ADAPTERS and SKILLS_MOUNT are consumed
# by topology_user_tier_checks (Task 3) and topology_embedded_checks (Task 4).
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

SKILLS_MOUNT="$(manifest_get skills_mount)"
[ -n "$SKILLS_MOUNT" ] || SKILLS_MOUNT="false"

# shellcheck disable=SC2034 # consumed by topology_role_clones_checks (Task 6)
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

report_fixed() {
  echo "FIXED: $1"
}

report_error() {
  echo "ERROR: $1"
  DRIFT_COUNT=$((DRIFT_COUNT + 1))
}

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
  elif mkdir -p "$(dirname "$p")" 2>/dev/null && ln -sfn "$tgt" "$p" 2>/dev/null; then
    report_fixed "$label -> $tgt"
  else
    report_error "could not create $label -> $tgt"
  fi
}

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
  # its repo-relative path under $ROOT. The two failure modes get distinct
  # DRIFT lines: "missing" points at a wrong path or an undeployed script,
  # "not executable" at a chmod problem - different fixes.
  local hook

  _check_one_hook() { # $1=manifest key  $2=repo-relative hook path
    if [ ! -e "$ROOT/$2" ]; then
      report_drift "$1 '$2' missing at $ROOT/$2"
    elif [ ! -x "$ROOT/$2" ]; then
      report_drift "$1 '$2' not executable at $ROOT/$2 (chmod +x it)"
    fi
  }

  if [ "${#CLAUDE_HOOKS[@]}" -gt 0 ]; then
    for hook in "${CLAUDE_HOOKS[@]}"; do
      _check_one_hook claude_hook "$hook"
    done
  fi

  if [ "${#CODEX_HOOKS[@]}" -gt 0 ]; then
    for hook in "${CODEX_HOOKS[@]}"; do
      _check_one_hook codex_hook "$hook"
    done
  fi
}

# --- topology dispatch (stubs; catalogs land in later tasks) ---

_role_clones_find_workspace() {
  # _role_clones_find_workspace <root_abs> <parent> <memrepo_name>
  #                              <project_name-or-empty> <role>
  #
  # Candidate walk in list-roles.sh order: the memory repo itself (self-mount
  # candidate), then the no-suffix clone, then the suffixed clone (the last
  # two are only tried when project_name is non-empty - the naming-convention
  # DRIFT already fired once for the whole instance if it's empty). A
  # candidate claims the role when it has .git AND either its .agents/memory
  # (or, v3.1 fallback, its .claude/memory) symlink targets end in "/<role>"
  # or equal "<role>" outright, or - a broken-rewire fallback, matching
  # list-roles.sh - its own path ends in "-<role>". Stops at the FIRST
  # claimant (Task 7 makes this exhaustive for the multi-candidate flag).
  local root_abs="$1" parent="$2" memrepo_name="$3" project_name="$4" role="$5"
  local candidates cand link target

  candidates=("$root_abs")
  if [ -n "$project_name" ]; then
    candidates+=("$parent/$project_name" "$parent/$project_name-$role")
  fi

  for cand in "${candidates[@]}"; do
    [ -d "$cand/.git" ] || continue

    link=""
    if [ -L "$cand/.agents/memory" ]; then
      link="$cand/.agents/memory"
    elif [ -L "$cand/.claude/memory" ]; then
      link="$cand/.claude/memory"
    else
      continue
    fi

    target="$(readlink "$link")"
    case "$target" in
      *"/$role"|"$role")
        printf '%s\n' "$cand"
        return 0
        ;;
    esac

    case "$cand" in
      *"-$role")
        printf '%s\n' "$cand"
        return 0
        ;;
    esac
  done

  return 1
}

_role_clones_check_exclude() {
  # _role_clones_check_exclude <workspace> <line>...
  # .git/info/exclude carries the init-clone-owned lines, append-only:
  # missing is DRIFT in --check, appended (never a rewrite) in fix mode.
  local workspace="$1"
  shift
  local exclude="$workspace/.git/info/exclude" line

  for line in "$@"; do
    if [ -f "$exclude" ] && grep -qxF -- "$line" "$exclude" 2>/dev/null; then
      continue
    fi

    if [ "$CHECK" = 1 ]; then
      report_drift "$exclude missing '$line'"
    elif mkdir -p "$(dirname "$exclude")" 2>/dev/null && touch "$exclude" 2>/dev/null && printf '%s\n' "$line" >> "$exclude" 2>/dev/null; then
      report_fixed "$exclude appended '$line'"
    else
      report_error "could not append '$line' to $exclude"
    fi
  done
}

_role_clones_check_role() {
  # _role_clones_check_role <root_abs> <parent> <memrepo_name>
  #                          <project_name-or-empty> <role>
  local root_abs="$1" parent="$2" memrepo_name="$3" project_name="$4" role="$5"
  local workspace expected_mount lines

  workspace="$(_role_clones_find_workspace "$root_abs" "$parent" "$memrepo_name" "$project_name" "$role")"
  if [ -z "$workspace" ]; then
    echo "INFO: role $role - no workspace wired"
    return 0
  fi

  # Self-mount (workspace IS the memory repo) resolves ../<role> against
  # .agents/; a clone resolves ../../<memrepo>/<role> the same way - matching
  # init-clone.sh's MOUNT_TARGET for --self vs. clone mode exactly.
  if [ "$workspace" = "$root_abs" ]; then
    expected_mount="../$role"
  else
    expected_mount="../../$memrepo_name/$role"
  fi

  need_link "$workspace/.agents/memory" "$expected_mount" "$workspace/.agents/memory"
  need_link "$workspace/.claude/memory" "../.agents/memory" "$workspace/.claude/memory"

  lines=("/.agents/memory" "/.claude/memory")
  if [ -f "$workspace/.codex/hooks.json" ]; then
    lines+=("/.codex/hooks.json")
  fi
  if [ -f "$workspace/opencode.json" ]; then
    lines+=("/opencode.json")
  fi
  _role_clones_check_exclude "$workspace" "${lines[@]}"
}

topology_role_clones_checks() {
  # Role-clone constellation, doctored FROM the memory repo. This task's
  # slice: role discovery + the candidate walk + per-workspace mount/exclude
  # checks. Vendor wiring (external CC hop, codex hooks.json, opencode) is
  # Task 6; the multi-candidate flag is Task 7; the orphan sweep is Task 8.
  local root_abs parent memrepo_name project_name

  root_abs="$(cd "$ROOT" && pwd -P)"
  parent="$(dirname "$root_abs")"
  memrepo_name="$(basename "$root_abs")"

  case "$memrepo_name" in
    claude-personas-*)
      project_name="${memrepo_name#claude-personas-}"
      ;;
    *)
      report_drift "memory repo dir name '$memrepo_name' does not start with 'claude-personas-' - cannot derive the project name for the clone candidate walk (rename the memory repo to claude-personas-<project>, matching list-roles.sh's naming convention)"
      project_name=""
      ;;
  esac

  # Role discovery: same rule as check_payload / list-roles.sh / init-clone.sh
  # - a dir with MEMORY.md at the root, excluding shared and examples.
  local roles d n
  roles=()
  for d in "$root_abs"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    if [ -f "$d/MEMORY.md" ] && [ "$n" != "shared" ] && [ "$n" != "examples" ]; then
      roles+=("$n")
    fi
  done

  if [ "${#roles[@]}" -eq 0 ]; then
    return 0
  fi

  local role
  for role in "${roles[@]}"; do
    _role_clones_check_role "$root_abs" "$parent" "$memrepo_name" "$project_name" "$role"
  done
}

_embedded_check_claude_settings_hooks() {
  # Every declared claude_hook must be wired in .claude/settings.json via the
  # exact "$CLAUDE_PROJECT_DIR/<hook>" command string - including the
  # embedded literal double quotes, which is what Claude Code itself stores
  # (see cerebrum's .claude/settings.json). Report-only: doctor.sh never
  # rewrites a hand-authored settings.json.
  if ! require_jq "settings.json hook checks"; then
    return 0
  fi
  if [ "${#CLAUDE_HOOKS[@]}" -eq 0 ]; then
    return 0
  fi

  local cmds hook expected
  cmds="$(jq -r '.hooks.SessionStart[]?.hooks[]?.command' "$ROOT/.claude/settings.json" 2>/dev/null)"
  for hook in "${CLAUDE_HOOKS[@]}"; do
    expected="$(printf '"$CLAUDE_PROJECT_DIR/%s"' "$hook")"
    if ! printf '%s\n' "$cmds" | grep -qxF -- "$expected"; then
      report_drift ".claude/settings.json does not wire claude_hook '$hook' via \$CLAUDE_PROJECT_DIR"
    fi
  done
}

_embedded_check_external_cc_hop() {
  # External Claude Code auto-memory hop: $HOME/.claude/projects/<slug>/memory,
  # where <slug> is this root's absolute (symlink-resolved) path with '/' and
  # '.' replaced by '-' (matches Claude Code's own project-dir naming, and
  # test_helpers.sh's compute_hash). Load-bearing: without it, Claude Code
  # materializes a REAL directory there and memory silently diverges.
  #
  # A hop resolving (via pwd -P) to $ROOT/.agents/memory is OK whatever its
  # literal target; a wrong symlink is repaired via need_link; a real
  # directory is DRIFT, report-only (reconcile by hand); missing is DRIFT in
  # --check, created in fix mode.
  local root_abs slug ext canonical_ext canonical_root_memory
  root_abs="$(cd "$ROOT" && pwd -P)"
  slug="$(printf '%s' "$root_abs" | tr '/.' '-')"
  ext="$HOME/.claude/projects/$slug/memory"
  canonical_root_memory="$(cd "$root_abs/.agents/memory" 2>/dev/null && pwd -P)"

  if [ -e "$ext" ] || [ -L "$ext" ]; then
    canonical_ext="$(cd "$ext" 2>/dev/null && pwd -P)"
    if [ -n "$canonical_ext" ] && [ "$canonical_ext" = "$canonical_root_memory" ]; then
      return 0
    elif [ -L "$ext" ]; then
      need_link "$ext" "$root_abs/.claude/memory" "external CC auto-memory symlink"
    else
      report_drift "$ext is a real directory - Claude Code may have written memories there; reconcile by hand"
    fi
  elif [ "$CHECK" = 1 ]; then
    report_drift "external CC auto-memory symlink missing ($ext)"
  elif mkdir -p "$(dirname "$ext")" 2>/dev/null && ln -s "$root_abs/.claude/memory" "$ext" 2>/dev/null; then
    report_fixed "$ext -> $root_abs/.claude/memory"
  else
    report_error "could not create $ext"
  fi
}

_embedded_regen_codex_hooks_json() {
  # Regenerate .codex/hooks.json wholesale for THIS root: one hooks-array
  # entry per declared codex_hook, in manifest order, matching the JSON
  # shape cerebrum's sync.sh writes (single SessionStart entry, "timeout":
  # 10, statusMessage derived from the hook's basename).
  local root_abs="$1" out tmp_json i n hook base
  out="$ROOT/.codex/hooks.json"
  tmp_json="$(mktemp 2>/dev/null)"
  if [ -z "$tmp_json" ]; then
    report_error "could not create temp file for .codex/hooks.json regeneration"
    return 0
  fi

  {
    printf '{\n  "hooks": {\n    "SessionStart": [\n      {\n        "hooks": [\n'
    n="${#CODEX_HOOKS[@]}"
    i=0
    for hook in "${CODEX_HOOKS[@]}"; do
      i=$((i + 1))
      base="$(basename "$hook")"
      printf '          {\n'
      printf '            "type": "command",\n'
      printf '            "command": "'"'"'%s/%s'"'"'",\n' "$root_abs" "$hook"
      printf '            "timeout": 10,\n'
      printf '            "statusMessage": "Running %s…"\n' "$base"
      if [ "$i" -lt "$n" ]; then
        printf '          },\n'
      else
        printf '          }\n'
      fi
    done
    printf '        ]\n      }\n    ]\n  }\n}\n'
  } > "$tmp_json"

  if mkdir -p "$ROOT/.codex" 2>/dev/null && mv "$tmp_json" "$out" 2>/dev/null; then
    report_fixed ".codex/hooks.json regenerated for $root_abs"
  else
    rm -f "$tmp_json"
    report_error "could not regenerate .codex/hooks.json"
  fi
}

_embedded_check_codex_hooks_json() {
  # .codex/hooks.json must wire every declared codex_hook as an absolute,
  # single-quoted, exact-match command string rooted at THIS instance's path
  # - grep -qxF (whole-line exact match), never a substring check, which
  # would wrongly accept another machine's absolute prefix as long as the
  # hook's relative suffix happened to appear somewhere in the file.
  if ! require_jq "hooks.json checks"; then
    return 0
  fi
  if [ "${#CODEX_HOOKS[@]}" -eq 0 ]; then
    return 0
  fi

  local root_abs cmds hook expected codex_ok=1
  root_abs="$(cd "$ROOT" && pwd -P)"
  if [ -f "$ROOT/.codex/hooks.json" ]; then
    cmds="$(jq -r '.hooks.SessionStart[]?.hooks[]?.command' "$ROOT/.codex/hooks.json" 2>/dev/null)"
  else
    cmds=""
  fi
  for hook in "${CODEX_HOOKS[@]}"; do
    expected="'$root_abs/$hook'"
    if ! printf '%s\n' "$cmds" | grep -qxF -- "$expected"; then
      codex_ok=0
    fi
  done

  if [ "$codex_ok" = 1 ]; then
    return 0
  fi

  if [ "$CHECK" = 1 ]; then
    report_drift ".codex/hooks.json does not wire all declared codex_hook entries for this root ($root_abs)"
  else
    _embedded_regen_codex_hooks_json "$root_abs"
  fi
}

_embedded_check_opencode_instructions() {
  # Root opencode.json's instructions array must contain the flat memory
  # index path. Report-only: doctor.sh never rewrites a hand-authored
  # opencode.json, only names the exact line to add.
  if ! require_jq "opencode.json checks"; then
    return 0
  fi
  if ! jq -e '.instructions | index(".agents/memory/MEMORY.md")' "$ROOT/opencode.json" >/dev/null 2>&1; then
    report_drift "opencode.json missing or its instructions lack \".agents/memory/MEMORY.md\" - add it to the instructions array"
  fi
}

topology_embedded_checks() {
  # In-repo links: fixable regardless of which adapters are declared.
  need_link "$ROOT/.claude/memory" "../.agents/memory" ".claude/memory"
  need_link "$ROOT/CLAUDE.md" "AGENTS.md" "CLAUDE.md"
  if [ "$SKILLS_MOUNT" = "true" ]; then
    need_link "$ROOT/.claude/skills" "../.agents/skills" ".claude/skills"
  fi

  # Per-adapter wiring, each gated on its adapter= declaration. Length check
  # first: bash 3.2's `set -u` treats an empty array as unbound on
  # expansion (same guard as topology_user_tier_checks).
  local a
  if [ "${#ADAPTERS[@]}" -gt 0 ]; then
    for a in "${ADAPTERS[@]}"; do
      case "$a" in
        claude-code)
          _embedded_check_claude_settings_hooks
          _embedded_check_external_cc_hop
          ;;
        codex)
          _embedded_check_codex_hooks_json
          ;;
        opencode)
          _embedded_check_opencode_instructions
          ;;
      esac
    done
  fi
}

topology_user_tier_checks() {
  # Extra payload sanity beyond check_payload's memory-index check: the
  # tier's other core artifact, the home-hop source file itself.
  [ -f "$ROOT/AGENTS.md" ] || report_drift "AGENTS.md missing"

  # Canonical home hop: unconditional, not gated on any adapter declaration.
  need_link "$HOME/AGENTS.md" "$ROOT/AGENTS.md" "~/AGENTS.md"

  # Per-tool global adapters, each gated on its adapter= declaration.
  # bash 3.2's `set -u` treats an empty array as unbound on expansion, so
  # the length check comes first (same guard as check_hook_scripts' loops).
  local a
  if [ "${#ADAPTERS[@]}" -gt 0 ]; then
    for a in "${ADAPTERS[@]}"; do
      case "$a" in
        claude-code)
          need_link "$HOME/.claude/CLAUDE.md" "$HOME/AGENTS.md" "~/.claude/CLAUDE.md"
          ;;
        codex)
          need_link "$HOME/.codex/AGENTS.md" "$HOME/AGENTS.md" "~/.codex/AGENTS.md"
          ;;
        opencode)
          need_link "$HOME/.config/opencode/AGENTS.md" "$HOME/AGENTS.md" "~/.config/opencode/AGENTS.md"
          ;;
      esac
    done
  fi
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
