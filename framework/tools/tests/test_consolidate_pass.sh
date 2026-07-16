#!/usr/bin/env bash
# Shim so run_all.sh (which globs test_*.sh) runs the Python unittest suite for
# framework/tools/consolidate_pass.py, PLUS CLI-level (subprocess, not import)
# checks - the same split test_memory_cliff.sh uses. bash-3.2 compatible.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
CP="$(cd "$SCRIPT_DIR/.." && pwd)/consolidate_pass.py"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not found (required for consolidate_pass tests)"
  exit 1
fi

python3 -m unittest discover -s "$SCRIPT_DIR" -p test_consolidate_pass.py -v
unittest_exit=$?

echo "=== CLI-level: consolidate_pass.py ==="
fixture="$(mktemp -d "${TMPDIR:-/tmp}/mem-XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
git -C "$fixture" init -q -b main .
# Local identity so the wrapper's own `git commit` works on machines with no
# global git config (the wrapper deliberately sets no identity itself).
git -C "$fixture" config user.email t@l
git -C "$fixture" config user.name t
mkdir "$fixture/mem"
printf '# Index\n\n- [Fact A](fact_a.md) - a fact\n' > "$fixture/mem/MEMORY.md"
printf -- '---\nname: fact-a\n---\n\nFact A body.\n' > "$fixture/mem/fact_a.md"
git -C "$fixture" add .
git -C "$fixture" commit -qm seed

(cd "$fixture" && python3 "$CP" begin --store mem >/dev/null)
assert_equal "0" "$?" "CLI begin exits 0 on a valid store"

printf -- '---\nname: fact-a\n---\n\nMerged.\n' > "$fixture/mem/fact_a.md"
(cd "$fixture" && python3 "$CP" commit --op dedupe -m "merge" >/dev/null)
assert_equal "0" "$?" "CLI commit lands a typed commit"

subject="$(git -C "$fixture" log -1 --format=%s)"
assert_equal "consolidate(dedupe): merge" "$subject" "typed commit subject is exact"

rc=0
(cd "$fixture" && python3 "$CP" commit --op dedupe -m "empty" >/dev/null 2>&1) || rc=$?
assert_matches "$rc" "^[1-9]" "CLI commit refuses with nothing to commit"

(cd "$fixture" && python3 "$CP" finish >/dev/null)
assert_equal "0" "$?" "CLI finish exits 0 remoteless"

rm -rf "$fixture"
trap - EXIT

print_summary
summary_exit=$?

if [ "$unittest_exit" -ne 0 ] || [ "$summary_exit" -ne 0 ]; then
  exit 1
fi
exit 0
