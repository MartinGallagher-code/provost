#!/bin/bash
################################################################################
## Strategy Tests: pip-list
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: pip-list"
echo "========================================"

test_pip_list_basic () {
    local output
    output=$(run_mfe -r -s pip-list "$SAMPLES_DIR/pip-list/basic.txt")
    assert_contains "$output" "Package_pip 23.0.1" "should extract pip package"
    assert_contains "$output" "Package_setuptools 67.6.1" "should extract setuptools"
    assert_contains "$output" "Package_wheel 0.40.0" "should extract wheel"
    assert_contains "$output" "Package_requests 2.31.0" "should extract requests"
}

test_pip_freeze_format () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'requests==2.31.0\nnumpy==1.24.3\npandas==2.0.1\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s pip-list "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "Package_requests 2.31.0" "should extract from freeze format"
    assert_contains "$output" "Package_numpy 1.24.3" "should extract numpy from freeze format"
}

test_pip_list_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s pip-list "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "pip-list should not apply to JSON"
}

run_test "pip-list: basic extraction" test_pip_list_basic
run_test "pip-list: pip freeze format" test_pip_freeze_format
run_test "pip-list: not detected for JSON" test_pip_list_not_detected_for_json

print_summary
