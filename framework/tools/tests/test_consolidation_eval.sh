#!/usr/bin/env bash
# Run the Python unit tests for the consolidation canary eval (#88).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 -m unittest discover -s "$SCRIPT_DIR" -p test_consolidation_eval.py -v
