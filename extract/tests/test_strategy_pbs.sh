#!/bin/bash
################################################################################
## Strategy Tests: pbs
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: pbs"
echo "========================================"

test_pbs_detect () {
    local output
    output=$(run_mfe -d -s pbs "$SAMPLES_DIR/pbs/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect pbs qstat -f output"
}

test_pbs_values () {
    local output
    output=$(run_mfe -r -s pbs "$SAMPLES_DIR/pbs/basic.txt")
    assert_contains "$output" "job_id 54321.pbs-head" "should extract Job Id"
    assert_contains "$output" "job_name molecular_dynamics" "should extract Job_Name"
    assert_contains "$output" "queue batch" "should extract queue"
    assert_contains "$output" "state R" "should extract job_state"
    assert_contains "$output" "nodes 2:ppn=8" "should extract Resource_List.nodes"
    assert_contains "$output" "walltime 04:00:00" "should extract Resource_List.walltime"
    assert_contains "$output" "cput 01:45:30" "should extract resources_used.cput"
    assert_contains "$output" "exit_status 0" "should extract exit_status"
    assert_contains "$output" "walltime_used 01:52:18" "should extract resources_used.walltime"
}

test_pbs_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s pbs "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "pbs should not apply to JSON"
}

run_test "pbs: detection" test_pbs_detect
run_test "pbs: specific values" test_pbs_values
run_test "pbs: not detected for JSON" test_pbs_not_json

print_summary
