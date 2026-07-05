#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: redis-benchmark"
echo "========================================"

test_redis_bench_basic () {
    local output
    output=$(run_mfe -r -s redis-benchmark "$SAMPLES_DIR/redis-benchmark/basic.txt")
    assert_contains "$output" "command PING_INLINE" "should extract first command name"
    assert_contains "$output" "throughput_rps" "should extract throughput"
    assert_contains "$output" "cmd2.command SET" "should extract second command"
    assert_contains "$output" "cmd3.command GET" "should extract third command"
}

test_redis_bench_values () {
    local output
    output=$(run_mfe -r -s redis-benchmark "$SAMPLES_DIR/redis-benchmark/basic.txt")
    assert_contains "$output" "throughput_rps 81300.81" "should extract correct throughput"
    assert_contains "$output" "cmd2.throughput_rps 68965.52" "should extract SET throughput"
    assert_contains "$output" "parallel_clients 50" "should extract parallel clients"
}

test_redis_bench_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s redis-benchmark "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "redis-benchmark: basic extraction" test_redis_bench_basic
run_test "redis-benchmark: specific values" test_redis_bench_values
run_test "redis-benchmark: not detected for JSON" test_redis_bench_not_json

print_summary
