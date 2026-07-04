#!/bin/bash
################################################################################
## Strategy Tests: lscpu
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: lscpu"
echo "========================================"

test_lscpu_detect () {
    local output
    output=$(run_mfe -d -s lscpu "$SAMPLES_DIR/lscpu/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect lscpu output"
}

test_lscpu_values () {
    local output
    output=$(run_mfe -r -s lscpu "$SAMPLES_DIR/lscpu/basic.txt")
    assert_contains "$output" "architecture x86_64" "should extract architecture"
    assert_contains "$output" "cpus 64" "should extract CPU count"
    assert_contains "$output" "threads_per_core 2" "should extract threads per core"
    assert_contains "$output" "cores_per_socket 16" "should extract cores per socket"
    assert_contains "$output" "sockets 2" "should extract socket count"
    assert_contains "$output" "numa_nodes 2" "should extract NUMA node count"
    assert_contains "$output" "model_name Intel(R) Xeon(R) Gold 6326 CPU @ 2.90GHz" "should extract model name"
    assert_contains "$output" "cpu_mhz 2900.000" "should extract CPU MHz"
    assert_contains "$output" "l3_cache 24576K" "should extract L3 cache"
    assert_contains "$output" "bogomips 5800.00" "should extract BogoMIPS"
    assert_contains "$output" "vendor_id GenuineIntel" "should extract vendor ID"
}

test_lscpu_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s lscpu "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "lscpu: detection" test_lscpu_detect
run_test "lscpu: specific values" test_lscpu_values
run_test "lscpu: not detected for JSON" test_lscpu_not_json

print_summary
