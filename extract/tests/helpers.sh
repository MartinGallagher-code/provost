#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Test Helpers for provost-extract
##
## Provides assertion utilities for testing provost-extract strategies and engine.
################################################################################

# Absolute path to the provost-extract script under test
PROVOST_EXTRACT_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/provost-extract"
SAMPLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/samples"
STRATEGIES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/strategies"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=()

# Colors (if terminal supports them)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
else
    GREEN='' RED='' YELLOW='' NC=''
fi

################################################################################
## Assertion functions
##

# A failed assertion is recorded in a FILE as well as returned, because the
# return value alone does not survive the way run_test invokes a test. run_test
# runs it as `( set -e; "$func" ) || result=$?`, and a command on the left of
# `||` has `set -e` SUPPRESSED for its whole body (POSIX: -e does not apply to
# any command in a `&&`/`||` list). So a test whose first assertion fails keeps
# running and exits with the status of its LAST command — which is usually 0,
# and the test then reported PASS with "ASSERT FAILED" printed right above it.
# The file crosses the subshell boundary that a variable cannot.
_ASSERT_FAIL_LOG=""
_assert_failed () {
    printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $1"
    [[ -n "$_ASSERT_FAIL_LOG" ]] && printf 'x' >> "$_ASSERT_FAIL_LOG"
    return 1
}

# Deliberately exercising an assertion's FAILURE path — helpers testing helpers
# — must not mark the surrounding test failed. Runs the assertion with
# recording suppressed and yields its return status.
expect_assert_failure () {
    local _saved="$_ASSERT_FAIL_LOG" _rc=0
    _ASSERT_FAIL_LOG=""
    "$@" >/dev/null 2>&1 || _rc=$?
    _ASSERT_FAIL_LOG="$_saved"
    return "$_rc"
}

assert_eq () {
    local expected="$1"
    local actual="$2"
    local msg="${3:-values should be equal}"
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        _assert_failed "$msg"
        echo "    expected: '$expected'"
        echo "    actual:   '$actual'"
        return 1
    fi
}

assert_contains () {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-output should contain string}"
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    else
        _assert_failed "$msg"
        echo "    looking for: '$needle'"
        echo "    in:          '$haystack'"
        return 1
    fi
}

assert_not_contains () {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-output should not contain string}"
    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    else
        _assert_failed "$msg"
        echo "    should not find: '$needle'"
        echo "    in:              '$haystack'"
        return 1
    fi
}

assert_exit_zero () {
    local code="$1"
    local msg="${2:-command should succeed (exit 0)}"
    if [[ "$code" -eq 0 ]]; then
        return 0
    else
        _assert_failed "$msg"
        echo "    exit code: $code"
        return 1
    fi
}

assert_exit_nonzero () {
    local code="$1"
    local msg="${2:-command should fail (exit non-zero)}"
    if [[ "$code" -ne 0 ]]; then
        return 0
    else
        _assert_failed "$msg"
        echo "    exit code: $code (expected non-zero)"
        return 1
    fi
}

assert_line_count () {
    local text="$1"
    local expected="$2"
    local msg="${3:-line count should match}"
    local actual
    actual=$(echo "$text" | sed '/^$/d' | wc -l | tr -d ' ')
    if [[ "$actual" -eq "$expected" ]]; then
        return 0
    else
        _assert_failed "$msg"
        echo "    expected lines: $expected"
        echo "    actual lines:   $actual"
        return 1
    fi
}

assert_match () {
    local actual="$1"
    local pattern="$2"
    local msg="${3:-output should match regex}"
    if [[ "$actual" =~ $pattern ]]; then
        return 0
    else
        _assert_failed "$msg"
        echo "    pattern: '$pattern'"
        echo "    actual:  '$actual'"
        return 1
    fi
}

assert_line_count_ge () {
    local text="$1"
    local min="$2"
    local msg="${3:-line count should be >= $min}"
    local actual
    actual=$(echo "$text" | sed '/^$/d' | wc -l | tr -d ' ')
    if [[ "$actual" -ge "$min" ]]; then
        return 0
    else
        _assert_failed "$msg"
        echo "    minimum expected: $min"
        echo "    actual lines:     $actual"
        return 1
    fi
}

assert_line_count_le () {
    local text="$1"
    local max="$2"
    local msg="${3:-line count should be <= $max}"
    local actual
    actual=$(echo "$text" | sed '/^$/d' | wc -l | tr -d ' ')
    if [[ "$actual" -le "$max" ]]; then
        return 0
    else
        _assert_failed "$msg"
        echo "    maximum expected: $max"
        echo "    actual lines:     $actual"
        return 1
    fi
}

assert_json_valid () {
    local text="$1"
    local msg="${2:-output should be valid JSON}"
    # Use jq for real validation if available
    if command -v jq >/dev/null 2>&1; then
        if echo "$text" | jq . >/dev/null 2>&1; then
            return 0
        fi
        _assert_failed "$msg"
        echo "    jq validation failed"
        echo "    text: '${text:0:80}'"
        return 1
    fi
    # Fallback: structural bracket check (when jq is not installed)
    local trimmed="$text"
    while [[ "$trimmed" == " "* || "$trimmed" == $'\n'* || "$trimmed" == $'\t'* ]]; do
        trimmed="${trimmed#[  	]}"
    done
    while [[ "$trimmed" == *" " || "$trimmed" == *$'\n' || "$trimmed" == *$'\t' ]]; do
        trimmed="${trimmed%[  	]}"
    done
    case "$trimmed" in
        '{'*'}'|'['*']') return 0 ;;
    esac
    _assert_failed "$msg"
    echo "    text: '${text:0:80}'"
    return 1
}

assert_output_empty () {
    local text="$1"
    local msg="${2:-output should be empty}"
    local trimmed="$text"
    # Strip all whitespace
    trimmed="${trimmed// /}"
    trimmed="${trimmed//$'\n'/}"
    trimmed="${trimmed//$'\t'/}"
    if [[ -z "$trimmed" ]]; then
        return 0
    else
        _assert_failed "$msg"
        echo "    output: '${text:0:80}'"
        return 1
    fi
}

################################################################################
## run_extract
##
## Run provost-extract with given arguments.
##
run_extract () {
    bash "$PROVOST_EXTRACT_SCRIPT" "$@"
}

################################################################################
## run_test
##
## Runs a test function and tracks results.
## Usage: run_test "test description" test_function_name
##
run_test () {
    local description="$1"
    local func="$2"
    TESTS_RUN=$((TESTS_RUN + 1))

    # `|| result=$?` instead of bare `( ... ); result=$?` so a
    # failing test subshell can't trip the caller's `set -e` before
    # we record the result. That form also disables the subshell's own
    # `set -e`, so the assertion log — not the exit status alone — is what
    # decides the verdict (see _assert_failed).
    _ASSERT_FAIL_LOG=$(mktemp)
    local result=0
    ( set -e; "$func" ) || result=$?
    [[ -s "$_ASSERT_FAIL_LOG" ]] && result=1
    rm -f "$_ASSERT_FAIL_LOG"; _ASSERT_FAIL_LOG=""

    if [[ $result -eq 0 ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        printf '%b\n' "  ${GREEN}PASS${NC}: $description"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_NAMES+=("$description")
        printf '%b\n' "  ${RED}FAIL${NC}: $description"
    fi
}

################################################################################
## print_summary
##
## Prints test run summary and exits with appropriate code.
##
print_summary () {
    echo ""
    echo "========================================"
    echo "Results: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed"
    if [[ $TESTS_FAILED -gt 0 ]]; then
        printf '%b\n' "${RED}Failed tests:${NC}"
        for name in "${FAILED_NAMES[@]}"; do
            echo "  - $name"
        done
        echo "========================================"
        return 1
    else
        printf '%b\n' "${GREEN}All tests passed.${NC}"
        echo "========================================"
        return 0
    fi
}
