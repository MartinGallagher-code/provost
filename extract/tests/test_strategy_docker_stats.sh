#!/bin/bash
################################################################################
## Strategy Tests: docker-stats
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Docker Stats Strategy Tests"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s docker-stats "$SAMPLES_DIR/docker-stats/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "docker-stats should detect basic sample"

    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output2
    output2=$(run_mfe -d -s docker-stats "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output2" "not applicable" "docker-stats should not apply to JSON"
}

test_extract () {
    local output
    output=$(run_mfe -r -s docker-stats "$SAMPLES_DIR/docker-stats/basic.txt")
    assert_contains "$output" "container1_name web-app" "should extract first container name"
    assert_contains "$output" "container1_cpu 2.50%" "should extract first container CPU"
    assert_contains "$output" "container1_mem_usage 256MiB" "should extract first container mem usage"
    assert_contains "$output" "container1_mem_limit 4GiB" "should extract first container mem limit"
    assert_contains "$output" "container1_mem_pct 6.25%" "should extract first container mem pct"
    assert_contains "$output" "container1_pids 25" "should extract first container pids"
    assert_contains "$output" "container2_name redis-cache" "should extract second container name"
    assert_contains "$output" "container3_name postgres-db" "should extract third container name"
    assert_contains "$output" "container3_cpu 5.00%" "should extract third container CPU"
    assert_contains "$output" "container3_pids 50" "should extract third container pids"
}

test_field_selection () {
    local output
    output=$(run_mfe -r -s docker-stats "$SAMPLES_DIR/docker-stats/single.txt")
    assert_contains "$output" "container1_name nginx-proxy" "should extract single container name"
    assert_contains "$output" "container1_cpu 0.05%" "should extract single container CPU"
    assert_not_contains "$output" "container2_" "should not have second container"
}

run_test "docker-stats: detection" test_detect
run_test "docker-stats: extraction" test_extract
run_test "docker-stats: field selection" test_field_selection

print_summary
