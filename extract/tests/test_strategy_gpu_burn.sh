#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: gpu-burn"
echo "========================================"

test_gpu_burn_basic () {
    local output
    output=$(run_mfe -r -s gpu-burn "$SAMPLES_DIR/gpu-burn/basic.txt")
    assert_contains "$output" "gpu_name" "should extract GPU name"
    assert_contains "$output" "performance_GF_per_s" "should extract performance"
    assert_contains "$output" "max_temp_C" "should extract temperature"
}

test_gpu_burn_values () {
    local output
    output=$(run_mfe -r -s gpu-burn "$SAMPLES_DIR/gpu-burn/basic.txt")
    assert_contains "$output" "gpu_count 2" "should extract GPU count"
    assert_contains "$output" "burn_duration_seconds 60" "should extract burn duration"
    assert_contains "$output" "status OK" "should extract OK status"
    assert_contains "$output" "gpu2.status OK" "should extract second GPU status"
}

test_gpu_burn_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s gpu-burn "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "gpu-burn: basic extraction" test_gpu_burn_basic
run_test "gpu-burn: specific values" test_gpu_burn_values
run_test "gpu-burn: not detected for JSON" test_gpu_burn_not_json

print_summary
