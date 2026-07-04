#!/bin/bash
################################################################################
## Strategy Tests: numactl
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: numactl"
echo "========================================"

test_numactl_detect () {
    local output
    output=$(run_mfe -d -s numactl "$SAMPLES_DIR/numactl/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect numactl output"
}

test_numactl_values () {
    local output
    output=$(run_mfe -r -s numactl "$SAMPLES_DIR/numactl/basic.txt")
    assert_contains "$output" "num_nodes 2" "should extract node count"
    assert_contains "$output" "node0.cpus 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15" "should extract node 0 cpus"
    assert_contains "$output" "node0.size_MB 32168" "should extract node 0 size"
    assert_contains "$output" "node0.free_MB 28456" "should extract node 0 free"
    assert_contains "$output" "node1.size_MB 32192" "should extract node 1 size"
    assert_contains "$output" "node1.free_MB 30124" "should extract node 1 free"
}

test_numactl_distances () {
    local output
    output=$(run_mfe -r -s numactl "$SAMPLES_DIR/numactl/basic.txt")
    assert_contains "$output" "distance.from0 10 21" "should extract node 0 distances"
    assert_contains "$output" "distance.from1 21 10" "should extract node 1 distances"
}

test_numactl_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s numactl "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "numactl: detection" test_numactl_detect
run_test "numactl: specific values" test_numactl_values
run_test "numactl: distance matrix" test_numactl_distances
run_test "numactl: not detected for JSON" test_numactl_not_json

print_summary
