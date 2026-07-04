#!/bin/bash
################################################################################
## Strategy Tests: perf-report
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: perf-report"
echo "========================================"

test_perf_report_detect () {
    local output
    output=$(run_mfe -d -s perf-report "$SAMPLES_DIR/perf-report/basic.txt" 2>&1)
    assert_contains "$output" "applicable" "should detect perf-report output"
}

test_perf_report_values () {
    local output
    output=$(run_mfe -r -s perf-report "$SAMPLES_DIR/perf-report/basic.txt")
    assert_contains "$output" "total_samples 12K" "should extract total samples"
    assert_contains "$output" "event_type cycles" "should extract event type"
    assert_contains "$output" "sym1_overhead_percent 32.45" "should extract first symbol overhead"
    assert_contains "$output" "sym1_shared_object libc.so.6" "should extract first shared object"
    assert_contains "$output" "sym1_symbol __memmove_avx_unaligned" "should extract first symbol name"
    assert_contains "$output" "sym2_overhead_percent 21.30" "should extract second symbol overhead"
    assert_contains "$output" "sym2_shared_object benchmark" "should extract second shared object"
    assert_contains "$output" "sym2_symbol compute_inner" "should extract second symbol name"
    assert_contains "$output" "sym3_symbol __ieee754_exp_fma" "should extract third symbol name"
    assert_contains "$output" "sym4_symbol transform_data" "should extract fourth symbol name"
}

test_perf_report_not_json () {
    local tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s perf-report "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not match JSON"
}

run_test "perf-report: detection" test_perf_report_detect
run_test "perf-report: specific values" test_perf_report_values
run_test "perf-report: not detected for JSON" test_perf_report_not_json

print_summary
