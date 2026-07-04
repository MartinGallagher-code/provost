#!/bin/bash
################################################################################
## Strategy Tests: env-vars
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: env-vars"
echo "========================================"

test_env_vars_basic () {
    local output
    output=$(run_mfe -r -s env-vars "$SAMPLES_DIR/env-vars/basic.txt")
    assert_contains "$output" "HOME /Users/john" "should extract HOME"
    assert_contains "$output" "SHELL /bin/bash" "should extract SHELL"
    assert_contains "$output" "EDITOR vim" "should extract EDITOR"
}

test_env_vars_equals_in_value () {
    local output
    output=$(run_mfe -r -s env-vars "$SAMPLES_DIR/env-vars/basic.txt")
    # DB_URL contains = in the value (postgres://user:pass@localhost/db)
    assert_contains "$output" "DB_URL postgres://user:pass@localhost/db" "should handle = in value"
}

test_env_vars_export_prefix () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'export FOO=bar\nexport BAZ=qux\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s env-vars "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "FOO bar" "should strip export prefix"
    assert_contains "$output" "BAZ qux" "should extract after stripping export"
}

test_env_vars_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s env-vars "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "env-vars should not apply to JSON"
}

run_test "env-vars: basic extraction" test_env_vars_basic
run_test "env-vars: values containing equals signs" test_env_vars_equals_in_value
run_test "env-vars: export prefix stripping" test_env_vars_export_prefix
run_test "env-vars: not detected for JSON" test_env_vars_not_detected_for_json

print_summary
