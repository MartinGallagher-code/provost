#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OVERALL_EXIT=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [[ -f "$test_file" ]] || continue
    echo "Running $(basename "$test_file")"
    bash "$test_file"
    if [[ $? -ne 0 ]]; then
        OVERALL_EXIT=1
    fi
    echo ""
done

exit $OVERALL_EXIT
