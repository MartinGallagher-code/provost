#!/bin/bash
################################################################################
## Strategy Tests: scorep
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: scorep"
echo "========================================"

test_scorep_detect () {
    local output
    output=$(run_mfe -d -s scorep "$SAMPLES_DIR/scorep/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect scorep output"
}

test_scorep_values () {
    local output
    output=$(run_mfe -r -s scorep "$SAMPLES_DIR/scorep/basic.txt")
    assert_contains "$output" "total_execution_time 42.560" "should extract total execution time"
    assert_contains "$output" "region1_name MPI_Recv" "should extract first region name"
    assert_contains "$output" "region1_visits 1000" "should extract first region visits"
    assert_contains "$output" "region1_time 12.345" "should extract first region time"
    assert_contains "$output" "region1_percent 29.0" "should extract first region percent"
    assert_contains "$output" "region2_name MPI_Send" "should extract second region name"
    assert_contains "$output" "region3_name compute" "should extract third region name"
    assert_contains "$output" "region4_name MPI_Barrier" "should extract fourth region name"
}

test_scorep_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s scorep "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "scorep: detection" test_scorep_detect
run_test "scorep: specific values" test_scorep_values
run_test "scorep: not detected for JSON" test_scorep_not_json

print_summary
