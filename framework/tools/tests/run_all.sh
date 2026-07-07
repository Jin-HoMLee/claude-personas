#!/usr/bin/env bash
# Run all test_*.sh files in this directory.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OVERALL_STATUS=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
  if [ -f "$test_file" ]; then
    echo "=== Running $(basename "$test_file") ==="
    if ! bash "$test_file"; then
      OVERALL_STATUS=1
    fi
    echo ""
  fi
done

exit $OVERALL_STATUS
