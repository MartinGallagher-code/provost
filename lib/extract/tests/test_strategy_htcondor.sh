#!/bin/bash
################################################################################
## Strategy Tests: htcondor
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: htcondor"
echo "========================================"

test_htcondor_detect () {
    local output
    output=$(run_mfe -d -s htcondor "$SAMPLES_DIR/htcondor/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "htcondor should detect condor output"
}

test_htcondor_values () {
    local output
    output=$(run_mfe -r -s htcondor "$SAMPLES_DIR/htcondor/basic.txt")
    assert_contains "$output" "cluster_id 1234567.0" "should extract first cluster ID"
    assert_contains "$output" "owner jdoe" "should extract first job owner"
    assert_contains "$output" "status R" "should extract first job status"
    assert_contains "$output" "submitted 3/18 10:00" "should extract first job submitted"
    assert_contains "$output" "cmd run_analysis.sh" "should extract first job cmd"
}

test_htcondor_multi_job () {
    local output
    output=$(run_mfe -r -s htcondor "$SAMPLES_DIR/htcondor/basic.txt")
    assert_contains "$output" "job2.owner jdoe" "should extract second job owner"
    assert_contains "$output" "job2.status R" "should extract second job status"
    assert_contains "$output" "job3.status I" "should extract third job status (idle)"
    assert_contains "$output" "job5.status H" "should extract fifth job status (held)"
}

test_htcondor_summary () {
    local output
    output=$(run_mfe -r -s htcondor "$SAMPLES_DIR/htcondor/basic.txt")
    assert_contains "$output" "total_jobs 5" "should extract total jobs from summary"
    assert_contains "$output" "idle 1" "should extract idle count"
    assert_contains "$output" "running 3" "should extract running count"
    assert_contains "$output" "held 1" "should extract held count"
}

test_htcondor_condor_status () {
    local output
    output=$(run_mfe -r -s htcondor "$SAMPLES_DIR/htcondor/basic.txt")
    assert_contains "$output" "slot1.name slot1@node001" "should extract first slot name"
    assert_contains "$output" "slot1.state Claimed" "should extract first slot state"
    assert_contains "$output" "slot1.activity Busy" "should extract first slot activity"
    assert_contains "$output" "slot3.state Unclaimed" "should extract third slot state"
    assert_contains "$output" "slot3.activity Idle" "should extract third slot activity"
}

test_htcondor_classad () {
    local output
    output=$(run_mfe -r -s htcondor "$SAMPLES_DIR/htcondor/basic.txt")
    assert_contains "$output" "classad.cluster_id 1234567" "should extract classad cluster ID"
    assert_contains "$output" "classad.owner jdoe" "should extract classad owner"
    assert_contains "$output" "classad.job_status 2" "should extract classad job status"
    assert_contains "$output" "classad.request_cpus 4" "should extract classad request cpus"
}

test_htcondor_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s htcondor "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "htcondor should not apply to JSON"
}

run_test "htcondor: detect condor output" test_htcondor_detect
run_test "htcondor: basic job extraction" test_htcondor_values
run_test "htcondor: multi-job extraction" test_htcondor_multi_job
run_test "htcondor: summary line extraction" test_htcondor_summary
run_test "htcondor: condor_status extraction" test_htcondor_condor_status
run_test "htcondor: classad key=value extraction" test_htcondor_classad
run_test "htcondor: not detected for JSON" test_htcondor_not_json

print_summary
