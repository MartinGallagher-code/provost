#!/bin/bash
################################################################################
## Strategy Tests: mpi-ranklog
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: mpi-ranklog"
echo "========================================"

SAMPLE_RANKLOG=$(cat <<'EOFSAMPLE'
[0] Starting computation on node01
[1] Starting computation on node01
[2] Starting computation on node02
[3] Starting computation on node02
[0] Iteration 1 complete
[1] Iteration 1 complete
[2] Error: memory allocation failed
[3] Iteration 1 complete
[0] Iteration 2 complete
[1] Iteration 2 complete
[3] Iteration 2 complete
EOFSAMPLE
)

SAMPLE_RANKLOG_VERBOSE=$(cat <<'EOFSAMPLE'
[rank 0] Initialized MPI
[rank 1] Initialized MPI
[rank 2] Initialized MPI
[rank 0] Processing data
[rank 1] Processing data
[rank 2] Abort: signal received
EOFSAMPLE
)

test_mpi_ranklog_detect () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_RANKLOG" > "$tmpfile"
    local output
    output=$(run_mfe -d -s mpi-ranklog "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "applicable" "mpi-ranklog should detect rank-prefixed output"
}

test_mpi_ranklog_extract () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_RANKLOG" > "$tmpfile"
    local output
    output=$(run_mfe -r -s mpi-ranklog "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "num_ranks 4" "should find 4 ranks (0-3)"
    assert_contains "$output" "rank.2.errors 1" "should find error on rank 2"
    assert_contains "$output" "total_errors 1" "should count 1 total error"
}

test_mpi_ranklog_verbose_format () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_RANKLOG_VERBOSE" > "$tmpfile"
    local output
    output=$(run_mfe -r -s mpi-ranklog "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "num_ranks 3" "should find 3 ranks with [rank N] format"
    assert_contains "$output" "rank.2.errors 1" "should detect abort as error"
}

test_mpi_ranklog_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s mpi-ranklog "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "mpi-ranklog should not apply to JSON"
}

run_test "mpi-ranklog: detection" test_mpi_ranklog_detect
run_test "mpi-ranklog: basic extraction" test_mpi_ranklog_extract
run_test "mpi-ranklog: verbose rank format" test_mpi_ranklog_verbose_format
run_test "mpi-ranklog: not detected for JSON" test_mpi_ranklog_not_json

print_summary
