#!/bin/bash
################################################################################
## Strategy Tests: flux
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: flux"
echo "========================================"

test_flux_detect () {
    local output
    output=$(run_mfe -d -s flux "$SAMPLES_DIR/flux/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "flux should detect flux scheduler output"
}

test_flux_values () {
    local output
    output=$(run_mfe -r -s flux "$SAMPLES_DIR/flux/basic.txt")
    assert_contains "$output" "job_id f:abcdef12" "should extract first job ID"
    assert_contains "$output" "state RUNNING" "should extract first job state"
    assert_contains "$output" "name weather_sim" "should extract first job name"
    assert_contains "$output" "user jdoe" "should extract first job user"
    assert_contains "$output" "ntasks 64" "should extract first job ntasks"
    assert_contains "$output" "nnodes 4" "should extract first job nnodes"
    assert_contains "$output" "runtime 01:23:45" "should extract first job runtime"
}

test_flux_multi_job () {
    local output
    output=$(run_mfe -r -s flux "$SAMPLES_DIR/flux/basic.txt")
    assert_contains "$output" "job2.state COMPLETED" "should extract second job state"
    assert_contains "$output" "job2.name climate_model" "should extract second job name"
    assert_contains "$output" "job3.state PENDING" "should extract third job state"
}

test_flux_resources () {
    local output
    output=$(run_mfe -r -s flux "$SAMPLES_DIR/flux/basic.txt")
    assert_contains "$output" "resource1.state free" "should extract first resource state"
    assert_contains "$output" "resource1.nnodes 12" "should extract free node count"
    assert_contains "$output" "resource1.ncores 384" "should extract free core count"
    assert_contains "$output" "resource1.ngpus 48" "should extract free GPU count"
    assert_contains "$output" "resource2.state allocated" "should extract allocated state"
    assert_contains "$output" "resource3.state down" "should extract down state"
}

test_flux_jobinfo () {
    local output
    output=$(run_mfe -r -s flux "$SAMPLES_DIR/flux/basic.txt")
    assert_contains "$output" "info.job_id f:abcdef12" "should extract job info ID"
    assert_contains "$output" "info.queue batch" "should extract queue from job info"
    assert_contains "$output" "info.ntasks 64" "should extract ntasks from job info"
    assert_contains "$output" "info.ngpus 8" "should extract ngpus from job info"
}

test_flux_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s flux "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "flux should not apply to JSON"
}

run_test "flux: detect flux scheduler output" test_flux_detect
run_test "flux: basic job extraction" test_flux_values
run_test "flux: multi-job extraction" test_flux_multi_job
run_test "flux: resource list extraction" test_flux_resources
run_test "flux: job info key=value extraction" test_flux_jobinfo
run_test "flux: not detected for JSON" test_flux_not_json

print_summary
