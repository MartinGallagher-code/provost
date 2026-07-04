#!/bin/bash
################################################################################
## Strategy Tests: make-stats
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: make-stats"
echo "========================================"

test_make_basic_ninja () {
    local output
    output=$(run_mfe -r -s make-stats "$SAMPLES_DIR/make-stats/basic.txt")
    assert_contains "$output" "step1.action Compiling" "should extract step1 action"
    assert_contains "$output" "step1.target src/main.c" "should extract step1 target"
    assert_contains "$output" "step2.action Compiling" "should extract step2 action"
    assert_contains "$output" "step4.action Linking" "should extract step4 action"
    assert_contains "$output" "step5.action Linking" "should extract step5 action"
}

test_make_build_summary () {
    local output
    output=$(run_mfe -r -s make-stats "$SAMPLES_DIR/make-stats/basic.txt")
    assert_contains "$output" "total_steps 5" "should extract total steps"
    assert_contains "$output" "completed_steps 5" "should extract completed steps"
    assert_contains "$output" "build_time 3.45s" "should extract build time"
}

test_make_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s make-stats "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "make-stats should not apply to JSON"
}

run_test "make-stats: basic ninja format" test_make_basic_ninja
run_test "make-stats: build summary" test_make_build_summary
run_test "make-stats: not detected for JSON" test_make_not_detected_for_json

print_summary
