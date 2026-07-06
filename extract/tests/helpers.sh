#!/bin/bash
################################################################################
## Test Helpers for Envoy:Explore
##
## Provides assertion utilities for testing envoy-extract strategies and engine.
################################################################################

# Absolute path to the mfe script under test
MFE_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/envoy-extract"
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

assert_eq () {
    local expected="$1"
    local actual="$2"
    local msg="${3:-values should be equal}"
    if [[ "$expected" == "$actual" ]]; then
        return 0
    else
        printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
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
        printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
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
        printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
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
        printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
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
        printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
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
        printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
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
        printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
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
        printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
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
        printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
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
        printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
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
    printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
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
        printf '%b\n' "  ${RED}ASSERT FAILED${NC}: $msg"
        echo "    output: '${text:0:80}'"
        return 1
    fi
}

################################################################################
## run_mfe
##
## Run envoy-extract with given arguments.
##
run_mfe () {
    bash "$MFE_SCRIPT" "$@"
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
    # we record the result.
    local result=0
    ( set -e; "$func" ) || result=$?

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
