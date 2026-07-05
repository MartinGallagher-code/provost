#!/bin/bash
## Name: test-summary
## Description: Extract test result summaries from pytest, Jest, Go test, and Google Test output
## Version: 1.0
## Priority: 20
## Sample: samples/test-summary/basic.txt

# Helper: extract number before a keyword from a line
_strat_test_summary_extract_num () {
    local line="$1"
    local keyword="$2"
    # Find "N keyword" pattern and return N
    local _before="${line%% ${keyword}*}"
    # Get the last word of _before (the number)
    local _num=""
    read -ra _arr <<< "$_before"
    _num="${_arr[${#_arr[@]}-1]}"
    if [[ "$_num" =~ ^[0-9]+$ ]]; then
        echo "$_num"
    fi
}

# Helper: detect and extract pytest summary
_strat_test_summary_pytest () {
    local text="$1"
    local result=""

    # Look for pytest summary line: "N passed, N failed, N skipped in Xs"
    # or variants like "N passed in Xs" or "N passed, N warnings in Xs"
    local summary_line=""
    while IFS= read -r _line; do
        if [[ "$_line" =~ [0-9]+\ passed ]]; then
            summary_line="$_line"
        fi
    done <<< "$text"
    [[ -z "$summary_line" ]] && return 1

    local passed failed skipped duration

    passed=$(_strat_test_summary_extract_num "$summary_line" "passed")
    failed=$(_strat_test_summary_extract_num "$summary_line" "failed")
    skipped=$(_strat_test_summary_extract_num "$summary_line" "skipped")
    # Extract duration: find pattern like "1.23s"
    if [[ "$summary_line" =~ ([0-9]+\.[0-9]+s) ]]; then
        duration="${BASH_REMATCH[1]}"
    fi

    [[ -n "$passed" ]] && result+="total_passed ${passed}"$'\n'
    [[ -n "$failed" ]] && result+="total_failed ${failed}"$'\n'
    [[ -n "$skipped" ]] && result+="total_skipped ${skipped}"$'\n'
    [[ -n "$duration" ]] && result+="duration ${duration}"$'\n'

    # Extract framework
    result+="framework pytest"$'\n'

    echo "$result"
    return 0
}

# Helper: detect and extract Jest summary
_strat_test_summary_jest () {
    local text="$1"
    local result=""

    # Look for Jest summary: "Tests:  N failed, N passed, N total"
    local tests_line=""
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^Tests:\ *[0-9] ]]; then
            tests_line="$_line"
            break
        fi
    done <<< "$text"
    [[ -z "$tests_line" ]] && return 1

    local passed failed total

    passed=$(_strat_test_summary_extract_num "$tests_line" "passed")
    failed=$(_strat_test_summary_extract_num "$tests_line" "failed")
    total=$(_strat_test_summary_extract_num "$tests_line" "total")

    [[ -n "$passed" ]] && result+="total_passed ${passed}"$'\n'
    [[ -n "$failed" ]] && result+="total_failed ${failed}"$'\n'
    [[ -n "$total" ]] && result+="total_tests ${total}"$'\n'

    # Extract suite summary: "Test Suites:  N failed, N passed, N total"
    local suites_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == "Test Suites:"* ]]; then
            suites_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$suites_line" ]]; then
        local suites_passed suites_failed suites_total
        suites_passed=$(_strat_test_summary_extract_num "$suites_line" "passed")
        suites_failed=$(_strat_test_summary_extract_num "$suites_line" "failed")
        suites_total=$(_strat_test_summary_extract_num "$suites_line" "total")
        [[ -n "$suites_passed" ]] && result+="suites_passed ${suites_passed}"$'\n'
        [[ -n "$suites_failed" ]] && result+="suites_failed ${suites_failed}"$'\n'
        [[ -n "$suites_total" ]] && result+="suites_total ${suites_total}"$'\n'
    fi

    # Extract time
    local time_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == "Time:"* ]]; then
            time_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$time_line" ]]; then
        local duration=""
        # Try "N.Ns" or "N.N s" pattern
        if [[ "$time_line" =~ ([0-9]+\.[0-9]+)\ s ]]; then
            duration="${BASH_REMATCH[1]}s"
        elif [[ "$time_line" =~ ([0-9]+\.[0-9]+s) ]]; then
            duration="${BASH_REMATCH[1]}"
        fi
        [[ -n "$duration" ]] && result+="duration ${duration}"$'\n'
    fi

    result+="framework jest"$'\n'

    echo "$result"
    return 0
}

# Helper: detect and extract Go test summary
_strat_test_summary_gotest () {
    local text="$1"
    local result=""

    # Look for Go test output: "ok  pkg  0.123s" or "FAIL  pkg  0.456s"
    local ok_count=0 fail_count=0
    while IFS= read -r _line; do
        [[ "$_line" =~ ^ok\  ]] && ok_count=$((ok_count + 1))
        [[ "$_line" =~ ^FAIL\  ]] && fail_count=$((fail_count + 1))
    done <<< "$text"

    [[ $ok_count -eq 0 && $fail_count -eq 0 ]] && return 1

    [[ $ok_count -gt 0 ]] && result+="total_passed ${ok_count}"$'\n'
    [[ $fail_count -gt 0 ]] && result+="total_failed ${fail_count}"$'\n'

    result+="framework gotest"$'\n'

    echo "$result"
    return 0
}

# Helper: detect and extract Google Test summary
_strat_test_summary_gtest () {
    local text="$1"
    local result=""

    # Look for Google Test summary: "[  PASSED  ] N tests." / "[  FAILED  ] N tests."
    local passed_line=""
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^\[\ *PASSED\ *\] ]]; then
            passed_line="$_line"
            break
        fi
    done <<< "$text"
    [[ -z "$passed_line" ]] && return 1

    local passed=""
    # Extract first number from the line
    if [[ "$passed_line" =~ ([0-9]+) ]]; then
        passed="${BASH_REMATCH[1]}"
    fi
    [[ -n "$passed" ]] && result+="total_passed ${passed}"$'\n'

    local failed_line=""
    while IFS= read -r _line; do
        if [[ "$_line" =~ ^\[\ *FAILED\ *\] ]]; then
            failed_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$failed_line" ]]; then
        local failed=""
        if [[ "$failed_line" =~ ([0-9]+) ]]; then
            failed="${BASH_REMATCH[1]}"
        fi
        [[ -n "$failed" ]] && result+="total_failed ${failed}"$'\n'
    fi

    result+="framework gtest"$'\n'

    echo "$result"
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

    # pytest: "N passed" in summary
    [[ "$text" =~ [0-9]+\ passed ]] && return 0

    # Jest: "Tests:" summary line
    [[ "$text" =~ (^|$'\n')Tests:\ *[0-9] ]] && return 0

    # Go test: "ok " or "FAIL " at start of line
    [[ "$text" =~ (^|$'\n')(ok|FAIL)\  ]] && return 0

    # Google Test: "[  PASSED  ]" or "[  FAILED  ]"
    [[ "$text" =~ (^|$'\n')\[\ *(PASSED|FAILED)\ *\] ]] && return 0

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Try each framework's extractor in order; use the first that succeeds.
    # Jest is checked before pytest because Jest output also contains "N passed"
    # which would match the pytest extractor.
    result=$(_strat_test_summary_jest "$text") && [[ -n "$result" ]] && { echo "$result"; return; }
    result=$(_strat_test_summary_gtest "$text") && [[ -n "$result" ]] && { echo "$result"; return; }
    result=$(_strat_test_summary_pytest "$text") && [[ -n "$result" ]] && { echo "$result"; return; }
    result=$(_strat_test_summary_gotest "$text") && [[ -n "$result" ]] && { echo "$result"; return; }

    echo ""
}
