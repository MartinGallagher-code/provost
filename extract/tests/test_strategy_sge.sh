#!/bin/bash
################################################################################
## Strategy Tests: sge
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: sge"
echo "========================================"

test_sge_detect () {
    local output
    output=$(run_mfe -d -s sge "$SAMPLES_DIR/sge/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect sge qstat output"
}

test_sge_values () {
    local output
    output=$(run_mfe -r -s sge "$SAMPLES_DIR/sge/basic.txt")
    assert_contains "$output" "job_id 112450" "should extract first job-ID"
    assert_contains "$output" "priority 0.55500" "should extract first priority"
    assert_contains "$output" "name cfd_solve" "should extract first job name"
    assert_contains "$output" "user rjohnson" "should extract first user"
    assert_contains "$output" "state r" "should extract first state"
    assert_contains "$output" "slots 4" "should extract first slots"
    assert_contains "$output" "job2.job_id 112451" "should extract second job-ID"
    assert_contains "$output" "job2.name preprocess" "should extract second job name"
    assert_contains "$output" "job2.state qw" "should extract second state"
}

test_sge_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s sge "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "sge should not apply to JSON"
}

run_test "sge: detection" test_sge_detect
run_test "sge: specific values" test_sge_values
run_test "sge: not detected for JSON" test_sge_not_json

print_summary
