#!/bin/bash
################################################################################
## Strategy Tests: hwloc
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: hwloc"
echo "========================================"

test_hwloc_detect () {
    local output
    output=$(run_mfe -d -s hwloc "$SAMPLES_DIR/hwloc/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect hwloc output"
}

test_hwloc_values () {
    local output
    output=$(run_mfe -r -s hwloc "$SAMPLES_DIR/hwloc/basic.txt")
    assert_contains "$output" "machine_memory 128GB total" "should extract machine memory"
    assert_contains "$output" "num_packages 2" "should extract package count"
    assert_contains "$output" "num_numa_nodes 2" "should extract NUMA node count"
    assert_contains "$output" "num_cores 8" "should extract core count"
    assert_contains "$output" "num_pus 16" "should extract PU count"
}

test_hwloc_caches () {
    local output
    output=$(run_mfe -r -s hwloc "$SAMPLES_DIR/hwloc/basic.txt")
    assert_contains "$output" "package0.l3_cache 32MB" "should extract L3 cache"
    assert_contains "$output" "package0.l2_cache 256KB" "should extract L2 cache"
    assert_contains "$output" "package0.l1d_cache 32KB" "should extract L1d cache"
    assert_contains "$output" "package0.l1i_cache 32KB" "should extract L1i cache"
}

test_hwloc_numa_memory () {
    local output
    output=$(run_mfe -r -s hwloc "$SAMPLES_DIR/hwloc/basic.txt")
    assert_contains "$output" "numa1.memory_MB 65536" "should extract NUMA node 0 memory"
    assert_contains "$output" "numa2.memory_MB 65536" "should extract NUMA node 1 memory"
}

test_hwloc_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s hwloc "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "hwloc: detection" test_hwloc_detect
run_test "hwloc: topology counts" test_hwloc_values
run_test "hwloc: cache extraction" test_hwloc_caches
run_test "hwloc: NUMA memory" test_hwloc_numa_memory
run_test "hwloc: not detected for JSON" test_hwloc_not_json

print_summary
