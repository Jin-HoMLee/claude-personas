#!/usr/bin/env bash
# Shim so run_all.sh (which globs test_*.sh) runs the Python unittest suite for
# scripts/memory_cliff.py. Requires python3 (stdlib only).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not found (required for memory_cliff tests)"
  exit 1
fi

python3 -m unittest discover -s "$SCRIPT_DIR" -p test_memory_cliff.py -v
