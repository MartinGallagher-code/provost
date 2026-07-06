#!/bin/bash
################################################################################
## Strategy Tests: slurm
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: slurm"
echo "========================================"

test_slurm_detect () {
    local output
    output=$(run_mfe -d -s slurm "$SAMPLES_DIR/slurm/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect slurm scontrol output"
}

test_slurm_values () {
    local output
    output=$(run_mfe -r -s slurm "$SAMPLES_DIR/slurm/basic.txt")
    assert_contains "$output" "job_id 987654" "should extract JobId"
    assert_contains "$output" "job_name climate_sim" "should extract JobName"
    assert_contains "$output" "partition compute" "should extract Partition"
    assert_contains "$output" "state COMPLETED" "should extract JobState"
    assert_contains "$output" "elapsed 02:34:17" "should extract RunTime"
    assert_contains "$output" "ncpus 128" "should extract NumCPUs"
    assert_contains "$output" "nnodes 4" "should extract NumNodes"
    assert_contains "$output" "mem 64G" "should extract MinMemoryNode"
    assert_contains "$output" "exit_code 0:0" "should extract ExitCode"
}

test_slurm_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s slurm "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "slurm should not apply to JSON"
}

run_test "slurm: detection" test_slurm_detect
run_test "slurm: specific values" test_slurm_values
run_test "slurm: not detected for JSON" test_slurm_not_json

print_summary
