#!/bin/bash
################################################################################
## Strategy Tests: compiler-diagnostics
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: compiler-diagnostics"
echo "========================================"

test_compiler_diagnostics_basic () {
    local output
    output=$(run_mfe -r -s compiler-diagnostics "$SAMPLES_DIR/compiler-diagnostics/basic.txt")
    # Check first diagnostic
    assert_contains "$output" "diag1.file src/main.c" "should extract first file"
    assert_contains "$output" "diag1.line 42" "should extract first line number"
    assert_contains "$output" "diag1.column 15" "should extract first column"
    assert_contains "$output" "diag1.severity error" "should extract first severity as error"
    # Check second diagnostic
    assert_contains "$output" "diag2.severity warning" "should extract second severity as warning"
    assert_contains "$output" "diag2.line 58" "should extract second line number"
    # Check third diagnostic
    assert_contains "$output" "diag3.file src/utils.c" "should extract third file"
    assert_contains "$output" "diag3.severity note" "should extract third severity as note"
}

test_compiler_diagnostics_summary () {
    local output
    output=$(run_mfe -r -s compiler-diagnostics "$SAMPLES_DIR/compiler-diagnostics/basic.txt")
    assert_contains "$output" "total_errors 2" "should extract total error count"
}

test_compiler_diagnostics_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s compiler-diagnostics "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "compiler-diagnostics should not apply to JSON"
}

run_test "compiler-diagnostics: basic extraction" test_compiler_diagnostics_basic
run_test "compiler-diagnostics: summary extraction" test_compiler_diagnostics_summary
run_test "compiler-diagnostics: not detected for JSON" test_compiler_diagnostics_not_json

print_summary
