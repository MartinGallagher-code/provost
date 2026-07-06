#!/bin/bash
################################################################################
## Strategy Tests: valgrind
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: valgrind"
echo "========================================"

test_valgrind_basic () {
    local output
    output=$(run_mfe -r -s valgrind "$SAMPLES_DIR/valgrind/basic.txt")
    assert_contains "$output" "command ./my_program" "should extract command"
    assert_contains "$output" "total_allocs 42" "should extract total allocs"
    assert_contains "$output" "total_frees 37" "should extract total frees"
    assert_contains "$output" "total_errors 3" "should extract total errors"
}

test_valgrind_leak_summary () {
    local output
    output=$(run_mfe -r -s valgrind "$SAMPLES_DIR/valgrind/basic.txt")
    assert_contains "$output" "definitely_lost 456_bytes_in_2_blocks" "should extract definitely lost"
    assert_contains "$output" "indirectly_lost 0_bytes_in_0_blocks" "should extract indirectly lost"
    assert_contains "$output" "possibly_lost 234_bytes_in_1_blocks" "should extract possibly lost"
    assert_contains "$output" "still_reachable 544_bytes_in_2_blocks" "should extract still reachable"
    assert_contains "$output" "heap_in_use 1,234_bytes_in_5_blocks" "should extract heap in use"
}

test_valgrind_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s valgrind "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "valgrind should not apply to JSON"
}

run_test "valgrind: basic extraction" test_valgrind_basic
run_test "valgrind: leak summary" test_valgrind_leak_summary
run_test "valgrind: not detected for JSON" test_valgrind_not_detected_for_json

print_summary
