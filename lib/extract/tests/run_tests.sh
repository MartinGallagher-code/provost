#!/bin/bash
################################################################################
## Envoy:Explore Test Runner
##
## Runs all test suites and reports combined results.
##
## Usage: bash run_tests.sh [OPTIONS]
##
## Options:
##   --filter PATTERN   Only run test files matching PATTERN
##   --timing           Show elapsed time per test file
##   --fail-fast        Stop on first test file failure
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OVERALL_EXIT=0
FILES_RUN=0
FILES_FAILED=0
FAILED_FILES=()
opt_filter=""
opt_timing=0
opt_fail_fast=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --filter)   opt_filter="$2"; shift 2 ;;
        --timing)   opt_timing=1; shift ;;
        --fail-fast) opt_fail_fast=1; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

echo "========================================"
echo "Envoy:Explore Test Suite"
echo "========================================"

# Auto-discover all test files
for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [[ -f "$test_file" ]] || continue

    # Apply filter if set
    if [[ -n "$opt_filter" ]]; then
        case "$test_file" in
            *"$opt_filter"*) ;;
            *) continue ;;
        esac
    fi

    FILES_RUN=$((FILES_RUN + 1))

    if [[ $opt_timing -eq 1 ]]; then
        _start=$SECONDS
    fi

    bash "$test_file"
    _rc=$?

    if [[ $opt_timing -eq 1 ]]; then
        _elapsed=$((SECONDS - _start))
        echo "  [timing] $(basename "$test_file"): ${_elapsed}s"
    fi

    if [[ $_rc -ne 0 ]]; then
        OVERALL_EXIT=1
        FILES_FAILED=$((FILES_FAILED + 1))
        FAILED_FILES+=("$(basename "$test_file")")
        if [[ $opt_fail_fast -eq 1 ]]; then
            echo ""
            echo "FAIL-FAST: Stopping after $(basename "$test_file")"
            break
        fi
    fi
done

# Run golden output verification (if no filter is set, or filter matches)
if [[ -z "$opt_filter" || "verify_strategy_outputs" == *"$opt_filter"* ]]; then
    FILES_RUN=$((FILES_RUN + 1))
    bash "$SCRIPT_DIR/verify_strategy_outputs.sh" --check
    if [[ $? -ne 0 ]]; then
        OVERALL_EXIT=1
        FILES_FAILED=$((FILES_FAILED + 1))
        FAILED_FILES+=("verify_strategy_outputs.sh")
    fi
fi

echo ""
echo "========================================"
echo "Overall: $((FILES_RUN - FILES_FAILED))/$FILES_RUN test files passed"
if [[ $FILES_FAILED -gt 0 ]]; then
    echo "Failed files:"
    for f in "${FAILED_FILES[@]}"; do
        echo "  - $f"
    done
    echo "========================================"
    echo "Some test suites had failures."
else
    echo "========================================"
    echo "All test suites passed."
fi

exit $OVERALL_EXIT
