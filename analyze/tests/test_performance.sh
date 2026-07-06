#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$SCRIPT_DIR/helpers.sh"

################################################################################
## Performance regression tests
##
## Verifies envoy-analyze completes within time limits on generated datasets.
## Skip with: MDA_SKIP_PERF=1
################################################################################

if [[ "${MDA_SKIP_PERF:-0}" -eq 1 ]]; then
    echo "Performance tests skipped (MDA_SKIP_PERF=1)"
    exit 0
fi

generate_csv () {
    local rows="$1"
    local cols="$2"
    local output="$3"
    awk -v rows="$rows" -v cols="$cols" '
    BEGIN {
        srand(42)
        for (c=1; c<=cols; c++) {
            if (c>1) printf ","
            printf "col%d", c
        }
        print ""
        for (r=1; r<=rows; r++) {
            for (c=1; c<=cols; c++) {
                if (c>1) printf ","
                printf "%d", r*c + int(rand()*100)
            }
            print ""
        }
    }' > "$output"
}

test_perf_1k_rows () {
    local tmp
    tmp=$(mktemp -t perf-1k.XXXXXX.csv)
    generate_csv 1000 5 "$tmp"
    local start end elapsed
    start=$(date +%s)
    run_mda "$tmp" > /dev/null 2>&1 || true
    end=$(date +%s)
    elapsed=$((end - start))
    rm -f "$tmp"
    if [[ "$elapsed" -gt 10 ]]; then
        echo "  ASSERT FAILED: 1K rows should complete in <10s, took ${elapsed}s"
        return 1
    fi
}

test_perf_5k_rows () {
    local tmp
    tmp=$(mktemp -t perf-5k.XXXXXX.csv)
    generate_csv 5000 5 "$tmp"
    local start end elapsed
    start=$(date +%s)
    run_mda "$tmp" > /dev/null 2>&1 || true
    end=$(date +%s)
    elapsed=$((end - start))
    rm -f "$tmp"
    if [[ "$elapsed" -gt 30 ]]; then
        echo "  ASSERT FAILED: 5K rows should complete in <30s, took ${elapsed}s"
        return 1
    fi
}

test_perf_wide () {
    local tmp
    tmp=$(mktemp -t perf-wide.XXXXXX.csv)
    generate_csv 500 20 "$tmp"
    local start end elapsed
    start=$(date +%s)
    run_mda "$tmp" > /dev/null 2>&1 || true
    end=$(date +%s)
    elapsed=$((end - start))
    rm -f "$tmp"
    if [[ "$elapsed" -gt 10 ]]; then
        echo "  ASSERT FAILED: 500 rows x 20 cols should complete in <10s, took ${elapsed}s"
        return 1
    fi
}

########################################
## Run all performance tests
##

run_test "1K rows 5 cols in <10s" test_perf_1k_rows
run_test "5K rows 5 cols in <30s" test_perf_5k_rows
run_test "500 rows 20 cols in <10s" test_perf_wide

print_summary
