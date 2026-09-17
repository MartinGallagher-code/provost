#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for strategy validation tooling (--validate-strategy, --validate-all)
################################################################################

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

TMPDIR_V="${TMPDIR:-/tmp}/validation_$$"
mkdir -p "$TMPDIR_V"

################################################################################
## --validate-strategy tests
################################################################################

test_validate_valid_strategy () {
    # Pick a known good strategy
    local out
    out=$(run_mfe --validate-strategy "$STRATEGIES_DIR/structured/json.sh" 2>&1)
    assert_contains "$out" "PASS: Has ## Name: header" "should pass Name check"
    assert_contains "$out" "PASS: Has ## Description: header" "should pass Description check"
    assert_contains "$out" "PASS: Has strategy_detect function" "should pass detect check"
    assert_contains "$out" "PASS: Has strategy_extract function" "should pass extract check"
}

test_validate_missing_function () {
    # Create a strategy missing strategy_detect
    cat > "$TMPDIR_V/no-detect.sh" <<'EOF'
#!/bin/bash
## Name: no-detect
## Description: Test strategy missing detect
## Version: 1.0
## Priority: 50
## Sample: json/basic.json

strategy_extract () {
    echo "field value"
}
EOF
    local out rc=0
    out=$(run_mfe --validate-strategy "$TMPDIR_V/no-detect.sh" 2>&1) || rc=$?
    assert_contains "$out" "FAIL: Missing strategy_detect function" "should fail on missing detect"
    assert_contains "$out" "PASS: Has strategy_extract function" "should pass extract check"
    [[ $rc -ne 0 ]] || { echo "expected non-zero exit code"; return 1; }
}

test_validate_missing_headers () {
    # Create a strategy with no metadata headers
    cat > "$TMPDIR_V/bare.sh" <<'EOF'
#!/bin/bash
strategy_detect () { return 0; }
strategy_extract () { echo "field value"; }
EOF
    local out rc=0
    out=$(run_mfe --validate-strategy "$TMPDIR_V/bare.sh" 2>&1) || rc=$?
    assert_contains "$out" "FAIL: Missing ## Name: header" "should fail on missing Name"
    assert_contains "$out" "FAIL: Missing ## Description: header" "should fail on missing Description"
    assert_contains "$out" "FAIL: Missing ## Version: header" "should fail on missing Version"
    assert_contains "$out" "FAIL: Missing ## Priority: header" "should fail on missing Priority"
    [[ $rc -ne 0 ]] || { echo "expected non-zero exit code"; return 1; }
}

test_validate_bad_version_format () {
    cat > "$TMPDIR_V/bad-version.sh" <<'EOF'
#!/bin/bash
## Name: bad-version
## Description: Test bad version
## Version: abc
## Priority: 50

strategy_detect () { return 0; }
strategy_extract () { echo "field value"; }
EOF
    local out rc=0
    out=$(run_mfe --validate-strategy "$TMPDIR_V/bad-version.sh" 2>&1) || rc=$?
    assert_contains "$out" "FAIL: Version format should be N.N" "should fail on bad version"
    [[ $rc -ne 0 ]] || { echo "expected non-zero exit code"; return 1; }
}

test_validate_name_mismatch () {
    cat > "$TMPDIR_V/actual-name.sh" <<'EOF'
#!/bin/bash
## Name: different-name
## Description: Test name mismatch
## Version: 1.0
## Priority: 50

strategy_detect () { return 0; }
strategy_extract () { echo "field value"; }
EOF
    local out rc=0
    out=$(run_mfe --validate-strategy "$TMPDIR_V/actual-name.sh" 2>&1) || rc=$?
    assert_contains "$out" "FAIL: Filename 'actual-name' does not match ## Name: 'different-name'" "should fail on name mismatch"
    [[ $rc -ne 0 ]] || { echo "expected non-zero exit code"; return 1; }
}

test_validate_file_not_found () {
    local out rc=0
    out=$(run_mfe --validate-strategy "$TMPDIR_V/nonexistent.sh" 2>&1) || rc=$?
    assert_contains "$out" "FAIL: File not found" "should fail on missing file"
    [[ $rc -ne 0 ]] || { echo "expected non-zero exit code"; return 1; }
}

################################################################################
## --validate-all tests
################################################################################

test_validate_all_runs () {
    local out rc=0
    out=$(run_mfe --validate-all 2>&1) || rc=$?
    assert_contains "$out" "Validation:" "should show validation summary"
    assert_contains "$out" "strategies" "should mention strategy count"
}

################################################################################
## Run all tests
################################################################################

echo "Strategy Validation Tests"
echo "========================="

run_test "validate valid strategy" test_validate_valid_strategy
run_test "validate missing function" test_validate_missing_function
run_test "validate missing headers" test_validate_missing_headers
run_test "validate bad version format" test_validate_bad_version_format
run_test "validate name mismatch" test_validate_name_mismatch
run_test "validate file not found" test_validate_file_not_found
run_test "validate-all runs" test_validate_all_runs

print_summary

# Cleanup
rm -rf "$TMPDIR_V"
