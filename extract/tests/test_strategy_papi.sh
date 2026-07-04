#!/bin/bash
################################################################################
## Strategy Tests: papi
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: papi"
echo "========================================"

test_papi_detect () {
    local output
    output=$(run_mfe -d -s papi "$SAMPLES_DIR/papi/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect papi output"
}

test_papi_values () {
    local output
    output=$(run_mfe -r -s papi "$SAMPLES_DIR/papi/basic.txt")
    assert_contains "$output" "total_cycles 9876543210" "should extract total cycles"
    assert_contains "$output" "total_instructions 4523456789" "should extract total instructions"
    assert_contains "$output" "l1_data_cache_misses 12345678" "should extract L1 data cache misses"
    assert_contains "$output" "l2_data_cache_misses 3456789" "should extract L2 data cache misses"
    assert_contains "$output" "branch_mispredictions 567890" "should extract branch mispredictions"
    assert_contains "$output" "branch_instructions 45678901" "should extract branch instructions"
    assert_contains "$output" "ipc 0.457" "should compute IPC from cycles and instructions"
}

test_papi_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s papi "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "papi: detection" test_papi_detect
run_test "papi: specific values" test_papi_values
run_test "papi: not detected for JSON" test_papi_not_json

print_summary
