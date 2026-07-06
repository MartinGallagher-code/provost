#!/bin/bash
################################################################################
## Strategy Tests: perf-bench
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: perf-bench"
echo "========================================"

test_perf_bench_sched_pipe () {
    local output
    output=$(run_mfe -r -s perf-bench "$SAMPLES_DIR/perf-bench/basic.txt")
    assert_contains "$output" "sched_pipe.ops_per_sec 195180" "should extract sched/pipe ops/sec"
    assert_contains "$output" "sched_pipe.usecs_per_op 5.123456" "should extract sched/pipe usecs/op"
}

test_perf_bench_mem_futex () {
    local output
    output=$(run_mfe -r -s perf-bench "$SAMPLES_DIR/perf-bench/basic.txt")
    assert_contains "$output" "mem_memcpy.throughput_GB_per_sec 8.901234" "should extract mem/memcpy throughput"
    assert_contains "$output" "futex_hash.avg_ops_per_sec 234567" "should extract futex/hash ops/sec"
}

test_perf_bench_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s perf-bench "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "perf-bench should not apply to JSON"
}

run_test "perf-bench: sched/pipe extraction" test_perf_bench_sched_pipe
run_test "perf-bench: mem and futex extraction" test_perf_bench_mem_futex
run_test "perf-bench: not detected for JSON" test_perf_bench_not_json

print_summary
