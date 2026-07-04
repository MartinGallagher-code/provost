#!/bin/bash
################################################################################
## Strategy Tests: gradle-output
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: gradle-output"
echo "========================================"

test_gradle_output_basic () {
    local output
    output=$(run_mfe -r -s gradle-output "$SAMPLES_DIR/gradle-output/basic.txt")
    assert_contains "$output" "build.result SUCCESS" "should extract build result"
    assert_contains "$output" "build.time 12s" "should extract build time"
    assert_contains "$output" "task1.name compileJava" "should extract first task name"
    assert_contains "$output" "task1.status UP-TO-DATE" "should extract first task status"
    assert_contains "$output" "task4.name compileTestJava" "should extract executed task"
    assert_contains "$output" "task4.status EXECUTED" "should mark executed task"
    assert_contains "$output" "task5.status NO-SOURCE" "should extract NO-SOURCE status"
    assert_contains "$output" "tasks.total 9" "should extract total tasks"
    assert_contains "$output" "tasks.executed 3" "should extract executed count"
    assert_contains "$output" "tasks.up_to_date 6" "should extract up-to-date count"
}

test_gradle_output_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s gradle-output "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_gradle_output_not_make () {
    local output
    output=$(run_mfe -d -s gradle-output "$SAMPLES_DIR/make-stats/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to make output"
}

run_test "gradle-output: basic extraction" test_gradle_output_basic
run_test "gradle-output: not detected for JSON" test_gradle_output_not_json
run_test "gradle-output: not detected for make output" test_gradle_output_not_make

print_summary
