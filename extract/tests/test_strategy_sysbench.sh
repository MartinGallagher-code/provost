#!/bin/bash
################################################################################
## Strategy Tests: sysbench
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: sysbench"
echo "========================================"

test_sysbench_cpu () {
    local output
    output=$(run_mfe -r -s sysbench "$SAMPLES_DIR/sysbench/basic.txt")
    assert_contains "$output" "mode cpu" "should detect CPU mode"
    assert_contains "$output" "threads 4" "should extract thread count"
    assert_contains "$output" "cpu_events_per_sec 12345.67" "should extract events/sec"
    assert_contains "$output" "total_time 10.0001s" "should extract total time"
    assert_contains "$output" "latency_p95 0.39" "should extract p95 latency"
}

test_sysbench_memory () {
    local output
    output=$(run_mfe -r -s sysbench "$SAMPLES_DIR/sysbench/memory.txt")
    assert_contains "$output" "mode memory" "should detect memory mode"
    assert_contains "$output" "total_operations 104857600" "should extract total ops"
    assert_contains "$output" "operations_per_sec 12345678.90" "should extract ops/sec"
    assert_contains "$output" "transfer_rate_MiB_per_sec 12056.78" "should extract transfer rate"
}

test_sysbench_oltp () {
    local output
    output=$(run_mfe -r -s sysbench "$SAMPLES_DIR/sysbench/oltp.txt")
    assert_contains "$output" "mode oltp" "should detect OLTP mode"
    assert_contains "$output" "transactions 10000" "should extract transactions"
    assert_contains "$output" "transactions_per_sec 998.45" "should extract TPS"
    assert_contains "$output" "read_queries 140000" "should extract read queries"
    assert_contains "$output" "latency_avg 8.01" "should extract avg latency"
}

test_sysbench_cpu_no_field_concatenation () {
    # Regression test for subshell newline stripping bug:
    # result+=$(_strat_sysbench_extract_cpu "$text") lost trailing newline,
    # causing cpu_events_per_sec value to merge with total_time on the same line.
    local output
    output=$(run_mfe -r -s sysbench "$SAMPLES_DIR/sysbench/basic.txt")
    # Each field must be on its own line -- no concatenation
    assert_not_contains "$output" "12345.67total_time" \
        "cpu_events_per_sec value must not concatenate with total_time"
    assert_not_contains "$output" "12345.67mode" \
        "cpu_events_per_sec value must not concatenate with mode"
    # Verify the fields are separate lines by checking line-by-line
    local cpu_line total_line
    cpu_line=$(echo "$output" | grep "cpu_events_per_sec " || true)
    total_line=$(echo "$output" | grep "total_time " || true)
    [[ -n "$cpu_line" ]] || { echo "  ASSERT FAILED: cpu_events_per_sec line not found"; return 1; }
    [[ -n "$total_line" ]] || { echo "  ASSERT FAILED: total_time line not found"; return 1; }
    # The cpu line should contain ONLY the events value, not any other field
    assert_not_contains "$cpu_line" "total_time" \
        "cpu_events_per_sec line must not contain total_time"
}

test_sysbench_oltp_no_field_concatenation () {
    # Same regression test for OLTP mode
    local output
    output=$(run_mfe -r -s sysbench "$SAMPLES_DIR/sysbench/oltp.txt")
    # Verify no field concatenation between oltp helper output and general stats
    local last_oltp_field
    last_oltp_field=$(echo "$output" | grep "other_queries " || true)
    [[ -n "$last_oltp_field" ]] || { echo "  ASSERT FAILED: other_queries line not found"; return 1; }
    assert_not_contains "$last_oltp_field" "total_time" \
        "other_queries line must not contain total_time"
}

test_sysbench_memory_no_field_concatenation () {
    # Same regression test for memory mode
    local output
    output=$(run_mfe -r -s sysbench "$SAMPLES_DIR/sysbench/memory.txt")
    # Verify no field concatenation between memory helper output and general stats
    local rate_line
    rate_line=$(echo "$output" | grep "transfer_rate_MiB_per_sec " || true)
    [[ -n "$rate_line" ]] || { echo "  ASSERT FAILED: transfer_rate_MiB_per_sec line not found"; return 1; }
    assert_not_contains "$rate_line" "total_time" \
        "transfer_rate_MiB_per_sec line must not contain total_time"
}

test_sysbench_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s sysbench "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "sysbench should not apply to JSON"
}

run_test "sysbench: CPU mode extraction" test_sysbench_cpu
run_test "sysbench: memory mode extraction" test_sysbench_memory
run_test "sysbench: OLTP mode extraction" test_sysbench_oltp
run_test "sysbench: CPU no field concatenation (newline fix)" test_sysbench_cpu_no_field_concatenation
run_test "sysbench: OLTP no field concatenation (newline fix)" test_sysbench_oltp_no_field_concatenation
run_test "sysbench: memory no field concatenation (newline fix)" test_sysbench_memory_no_field_concatenation
run_test "sysbench: not detected for JSON" test_sysbench_not_json

print_summary
