#!/bin/bash
################################################################################
## Strategy Tests: coremark
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: coremark"
echo "========================================"

test_coremark_basic () {
    local output
    output=$(run_mfe -r -s coremark "$SAMPLES_DIR/coremark/basic.txt")
    assert_contains "$output" "iterations_per_sec 24291.616878" "should extract iterations/sec"
    assert_contains "$output" "total_time_secs 12.345000" "should extract total time"
    assert_contains "$output" "iterations 300000" "should extract iterations"
    assert_contains "$output" "coremark_size 666" "should extract CoreMark size"
}

test_coremark_compiler_info () {
    local output
    output=$(run_mfe -r -s coremark "$SAMPLES_DIR/coremark/basic.txt")
    assert_contains "$output" "compiler_version GCC10.2.0" "should extract compiler version"
    assert_contains "$output" "compiler_flags" "should extract compiler flags"
    assert_contains "$output" "parallel_threads 4" "should extract thread count"
}

test_coremark_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s coremark "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "coremark should not apply to JSON"
}

run_test "coremark: basic score extraction" test_coremark_basic
run_test "coremark: compiler info extraction" test_coremark_compiler_info
run_test "coremark: not detected for JSON" test_coremark_not_json

print_summary
