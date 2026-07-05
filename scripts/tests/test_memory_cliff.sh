#!/usr/bin/env bash
# Shim so run_all.sh (which globs test_*.sh) runs the Python unittest suite for
# scripts/memory_cliff.py, PLUS a handful of CLI-level (subprocess, not import)
# checks for Task 9's --layout flat / manifest-driven flat behavior - the same
# split test_doctor_*.sh uses (Python-internal logic vs. actually invoking the
# script). Requires python3 (stdlib only); bash-3.2 compatible (no associative
# arrays, no `local -n`).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
MEMORY_CLIFF="$(cd "$SCRIPT_DIR/.." && pwd)/memory_cliff.py"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not found (required for memory_cliff tests)"
  exit 1
fi

python3 -m unittest discover -s "$SCRIPT_DIR" -p test_memory_cliff.py -v
unittest_exit=$?

# --- CLI-level flat-layout checks (Task 9) ---
# Fixture: a bare flat instance with just the single index file memory_cliff.py
# lints in flat layout - `$root/.agents/memory/MEMORY.md` - no role dirs at all.
echo ""
echo "=== CLI-level: memory_cliff.py --layout flat ==="

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/flat-repo/.agents/memory"
{
  for i in $(seq 1 3); do
    printf -- '- **R%s:** x\n' "$i"
  done
} > "$tmp/flat-repo/.agents/memory/MEMORY.md"

out="$(python3 "$MEMORY_CLIFF" --root "$tmp/flat-repo" --layout flat)"
rc=$?
assert_equal "0" "$rc" "flat happy path (under cliff) exits 0"
assert_contains "$out" "index" "flat happy path reports the 'index' row"
assert_contains "$out" "OK" "flat happy path reports OK status"

# Manifest-driven flat: no --layout flag, memory_layout=flat in .agents/manifest.
cat > "$tmp/flat-repo/.agents/manifest" <<'EOF'
manifest_version=1
topology=embedded
memory_layout=flat
EOF

out="$(python3 "$MEMORY_CLIFF" --root "$tmp/flat-repo")"
rc=$?
assert_equal "0" "$rc" "manifest-driven flat (no flag) exits 0"
assert_contains "$out" "index" "manifest-driven flat reports the 'index' row"

rm -rf "$tmp"
trap - EXIT

print_summary
summary_exit=$?

if [ "$unittest_exit" -ne 0 ] || [ "$summary_exit" -ne 0 ]; then
  exit 1
fi
exit 0
