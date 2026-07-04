#!/bin/bash
################################################################################
## Strategy Tests: vtune
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: vtune"
echo "========================================"

test_vtune_detect () {
    local output
    output=$(run_mfe -d -s vtune "$SAMPLES_DIR/vtune/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect vtune output"
}

test_vtune_values () {
    local output
    output=$(run_mfe -r -s vtune "$SAMPLES_DIR/vtune/basic.txt")
    assert_contains "$output" "elapsed_time 12.345" "should extract elapsed time"
    assert_contains "$output" "cpu_time 10.892" "should extract cpu time"
    assert_contains "$output" "cpi_rate 0.85" "should extract CPI rate"
    assert_contains "$output" "hotspot1_function compute_matrix" "should extract hotspot1 function"
    assert_contains "$output" "hotspot1_self_time 4.560" "should extract hotspot1 self time"
    assert_contains "$output" "hotspot1_percent 41.8" "should extract hotspot1 percent"
    assert_contains "$output" "hotspot2_function transform_data" "should extract hotspot2 function"
    assert_contains "$output" "hotspot3_function sort_elements" "should extract hotspot3 function"
}

test_vtune_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s vtune "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "vtune: detection" test_vtune_detect
run_test "vtune: specific values" test_vtune_values
run_test "vtune: not detected for JSON" test_vtune_not_json

print_summary
