#!/usr/bin/env bash
# Test the pi adapter's session-start memory-index injection extension
# (framework/hooks/pi-inject-memory-index.ts) by driving it through a fake
# ExtensionAPI under plain node (native TypeScript type stripping, node
# >= 23.6). The extension's contract, mirroring the Codex inject hooks:
#   - on before_agent_start, inject ONE persistent custom message
#     (customType personas-memory-index) carrying the always-loaded memory
#     index, resolved by walking up from cwd (.agents/memory first, then the
#     .claude/memory hop for role clones);
#   - bound the payload to the Claude Code native size guard (~200 lines /
#     ~25 KB, PERSONAS_INJECT_BYTE_CAP / PERSONAS_INJECT_LINE_CAP overrides)
#     with whole-line truncation and an explicit [TRUNCATED ...] trailer;
#   - append on-demand pointers for shared/ and user/ indexes when present;
#   - inject once per session (dedup against existing session entries, so
#     resume does not double-inject); no index found or any error -> no-op.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test_helpers.sh"
EXT="$(cd "$SCRIPT_DIR/../.." && pwd)/hooks/pi-inject-memory-index.ts"

# Gate: the extension is TypeScript run via node's native type stripping.
# Probe with a throwaway .ts import instead of a version check - distros
# and older nodes differ on when stripping became default-on.
if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed - pi extension tests not run"
  exit 0
fi
probe_dir="$(mktemp -d)"
echo "export default 42;" > "$probe_dir/probe.ts"
if ! node --input-type=module -e '
  import { pathToFileURL } from "node:url";
  const m = await import(pathToFileURL(process.argv[1]).href);
  process.exit(m.default === 42 ? 0 : 1);
' "$probe_dir/probe.ts" >/dev/null 2>&1; then
  echo "SKIP: this node cannot import TypeScript natively (need >= 23.6) - pi extension tests not run"
  rm -rf "$probe_dir"
  exit 0
fi
rm -rf "$probe_dir"

# Driver: loads the extension with a fake ExtensionAPI, fires
# before_agent_start with a fake ctx, prints the returned injection as JSON
# (or the literal NONE). argv: <ext-path> <cwd> <entries-json>.
DRIVER="$(mktemp -d)/driver.mjs"
cat > "$DRIVER" <<'EOF'
import { pathToFileURL } from "node:url";

const [extPath, cwd, entriesJson] = process.argv.slice(2);
const mod = await import(pathToFileURL(extPath).href);

const handlers = {};
const pi = {
  on(event, handler) { handlers[event] = handler; },
  registerTool() {}, registerCommand() {}, registerShortcut() {}, registerFlag() {},
};
mod.default(pi);

if (typeof handlers.before_agent_start !== "function") {
  console.error("extension did not subscribe to before_agent_start");
  process.exit(1);
}

const ctx = {
  cwd,
  hasUI: false,
  sessionManager: { getEntries: () => JSON.parse(entriesJson) },
};
const result = await handlers.before_agent_start({ prompt: "hi" }, ctx);
console.log(result === undefined ? "NONE" : JSON.stringify(result));
EOF

# run_ext <cwd> <entries-json>; sets EXT_OUT / EXT_EXIT.
run_ext() {
  EXT_OUT="$(node "$DRIVER" "$EXT" "$1" "$2" 2>&1)"
  EXT_EXIT=$?
}

echo "=== test_pi_inject_memory_index: embedded layout - index injected as one custom message ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/repo/.agents/memory" "$tmp/repo/sub/dir"
printf '# Memory Index\n\n- [A](a.md) - first hook line\n' > "$tmp/repo/.agents/memory/MEMORY.md"

run_ext "$tmp/repo" "[]"
assert_equal "0" "$EXT_EXIT" "driver exits 0"
assert_contains "$EXT_OUT" '"customType":"personas-memory-index"' "message carries the adapter customType"
assert_contains "$EXT_OUT" "# Memory Index" "index content present in the payload"
assert_contains "$EXT_OUT" "first hook line" "index body present in the payload"
assert_contains "$EXT_OUT" '"display":false' "message is not user-facing chatter"
assert_not_contains "$EXT_OUT" "TRUNCATED" "small index is not truncated"
assert_not_contains "$EXT_OUT" "Shared memory index" "no shared pointer when shared/ absent"

echo "=== test_pi_inject_memory_index: cwd below the repo root still resolves the index ==="
run_ext "$tmp/repo/sub/dir" "[]"
assert_equal "0" "$EXT_EXIT" "driver exits 0 from a subdir"
assert_contains "$EXT_OUT" "first hook line" "walk-up from a subdir finds the index"
rm -rf "$tmp"

echo "=== test_pi_inject_memory_index: role-clone shape - .claude/memory hop + shared/user pointers ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/memrepo/developer/shared" "$tmp/memrepo/developer/user" "$tmp/clone/.claude"
printf '# Dev Role Index\n' > "$tmp/memrepo/developer/MEMORY.md"
printf '# Shared Index\n' > "$tmp/memrepo/developer/shared/MEMORY.md"
printf '# User Index\n' > "$tmp/memrepo/developer/user/MEMORY.md"
ln -s "$tmp/memrepo/developer" "$tmp/clone/.claude/memory"

run_ext "$tmp/clone" "[]"
assert_equal "0" "$EXT_EXIT" "driver exits 0 for the role-clone shape"
assert_contains "$EXT_OUT" "# Dev Role Index" "role index reached through .claude/memory"
assert_contains "$EXT_OUT" "Shared memory index" "shared on-demand pointer present"
assert_contains "$EXT_OUT" "shared/MEMORY.md" "shared pointer names the file to read"
assert_contains "$EXT_OUT" "user/MEMORY.md" "user-tier on-demand pointer present"
rm -rf "$tmp"

echo "=== test_pi_inject_memory_index: already injected in this session - no duplicate ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/repo/.agents/memory"
printf '# Memory Index\n' > "$tmp/repo/.agents/memory/MEMORY.md"

run_ext "$tmp/repo" '[{"type":"custom_message","customType":"personas-memory-index","content":"already here"}]'
assert_equal "0" "$EXT_EXIT" "driver exits 0 on the dedup path"
assert_equal "NONE" "$EXT_OUT" "no second injection when the session already carries one"
rm -rf "$tmp"

echo "=== test_pi_inject_memory_index: line cap - whole-line cut + explicit trailer ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/repo/.agents/memory"
{ echo "# Big Index"; for i in $(seq 1 300); do echo "- line $i"; done; } > "$tmp/repo/.agents/memory/MEMORY.md"

PERSONAS_INJECT_LINE_CAP=10 run_ext "$tmp/repo" "[]"
assert_equal "0" "$EXT_EXIT" "driver exits 0 under a line cap"
assert_contains "$EXT_OUT" "# Big Index" "top of the index survives the cut"
assert_contains "$EXT_OUT" "- line 9" "whole lines kept up to the cap"
assert_not_contains "$EXT_OUT" "- line 11" "lines past the cap are cut"
assert_contains "$EXT_OUT" "TRUNCATED" "cut announces itself with a trailer"
assert_contains "$EXT_OUT" "MEMORY.md" "trailer points at the full index file"

echo "=== test_pi_inject_memory_index: byte cap - whole-line cut + explicit trailer ==="
PERSONAS_INJECT_BYTE_CAP=80 run_ext "$tmp/repo" "[]"
assert_equal "0" "$EXT_EXIT" "driver exits 0 under a byte cap"
assert_contains "$EXT_OUT" "# Big Index" "top of the index survives the byte cut"
assert_contains "$EXT_OUT" "TRUNCATED" "byte cut announces itself with a trailer"

echo "=== test_pi_inject_memory_index: garbage cap override falls back to defaults ==="
PERSONAS_INJECT_LINE_CAP=banana run_ext "$tmp/repo" "[]"
assert_equal "0" "$EXT_EXIT" "driver exits 0 on a non-numeric cap"
assert_contains "$EXT_OUT" "- line 150" "non-numeric cap falls back to the 200-line default instead of suppressing the index"
assert_not_contains "$EXT_OUT" "- line 250" "default 200-line cap still cuts the tail"
rm -rf "$tmp"

echo "=== test_pi_inject_memory_index: no index anywhere up the tree - silent no-op ==="
tmp="$(mktemp -d)"
mkdir -p "$tmp/bare"
run_ext "$tmp/bare" "[]"
assert_equal "0" "$EXT_EXIT" "driver exits 0 with no index"
assert_equal "NONE" "$EXT_OUT" "no injection when no index is found"
rm -rf "$tmp"

print_summary
