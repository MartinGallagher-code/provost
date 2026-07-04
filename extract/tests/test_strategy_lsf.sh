#!/bin/bash
################################################################################
## Strategy Tests: lsf
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: lsf"
echo "========================================"

test_lsf_detect () {
    local output
    output=$(run_mfe -d -s lsf "$SAMPLES_DIR/lsf/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect lsf bjobs -l output"
}

test_lsf_values () {
    local output
    output=$(run_mfe -r -s lsf "$SAMPLES_DIR/lsf/basic.txt")
    assert_contains "$output" "job_id 204851" "should extract Job ID"
    assert_contains "$output" "stat DONE" "should extract Status"
    assert_contains "$output" "queue normal" "should extract Queue"
    assert_contains "$output" "from_host login02" "should extract submitted from host"
    assert_contains "$output" "exec_host compute05" "should extract execution host"
    assert_contains "$output" "job_name protein_fold" "should extract Job Name"
}

test_lsf_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s lsf "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "lsf should not apply to JSON"
}

run_test "lsf: detection" test_lsf_detect
run_test "lsf: specific values" test_lsf_values
run_test "lsf: not detected for JSON" test_lsf_not_json

print_summary
