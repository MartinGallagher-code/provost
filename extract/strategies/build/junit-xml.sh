#!/bin/bash
## Name: junit-xml
## Description: Extract test suite results from JUnit/xUnit XML reports
## Version: 1.0
## Priority: 30
## Sample: samples/junit-xml/basic.txt

# Helper: extract the value of an XML attribute from a tag string.
# Usage: _strat_junit_attr "$tag_text" "attr_name"
# Sets _JUNIT_ATTR_VAL to the attribute value, or "" if not found.
# Matches only whole attribute names (preceded by space).
_strat_junit_attr () {
    local tag="$1"
    local attr="$2"
    _JUNIT_ATTR_VAL=""

    # Ensure we match whole attribute name by looking for ' attr="value"'
    # (space before the attribute name)
    local search=" ${attr}=\""
    local search_sq=" ${attr}='"

    case "$tag" in
        *"${search}"*)
            local after="${tag#*"${search}"}"
            _JUNIT_ATTR_VAL="${after%%\"*}"
            return 0
            ;;
        *"${search_sq}"*)
            local after="${tag#*"${search_sq}"}"
            _JUNIT_ATTR_VAL="${after%%\'*}"
            return 0
            ;;
    esac
    return 1
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Look for <testsuite or <testsuites tags
    local found=0

    while IFS= read -r line; do
        case "$line" in
            *'<testsuite'*)
                found=1
                break
                ;;
        esac
    done <<< "$text"

    if [[ $found -eq 1 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local test_num=0
    local current_test_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Strip leading whitespace
        local trimmed="$line"
        while [[ "$trimmed" == " "* || "$trimmed" == $'\t'* ]]; do
            trimmed="${trimmed#?}"
        done

        # Match <testsuite ...> tag (but not <testsuites>)
        case "$trimmed" in
            '<testsuite '*)
                # Extract suite-level attributes
                _strat_junit_attr "$trimmed" "name"
                [[ -n "$_JUNIT_ATTR_VAL" ]] && result+="suite.name ${_JUNIT_ATTR_VAL}"$'\n'

                _strat_junit_attr "$trimmed" "tests"
                [[ -n "$_JUNIT_ATTR_VAL" ]] && result+="suite.tests ${_JUNIT_ATTR_VAL}"$'\n'

                _strat_junit_attr "$trimmed" "failures"
                [[ -n "$_JUNIT_ATTR_VAL" ]] && result+="suite.failures ${_JUNIT_ATTR_VAL}"$'\n'

                _strat_junit_attr "$trimmed" "errors"
                [[ -n "$_JUNIT_ATTR_VAL" ]] && result+="suite.errors ${_JUNIT_ATTR_VAL}"$'\n'

                _strat_junit_attr "$trimmed" "time"
                [[ -n "$_JUNIT_ATTR_VAL" ]] && result+="suite.time ${_JUNIT_ATTR_VAL}"$'\n'

                _strat_junit_attr "$trimmed" "skipped"
                [[ -n "$_JUNIT_ATTR_VAL" ]] && result+="suite.skipped ${_JUNIT_ATTR_VAL}"$'\n'
                ;;
        esac

        # Match <testcase ...> tag
        case "$trimmed" in
            '<testcase '*)
                test_num=$((test_num + 1))
                current_test_num=$test_num

                _strat_junit_attr "$trimmed" "name"
                [[ -n "$_JUNIT_ATTR_VAL" ]] && result+="test${test_num}.name ${_JUNIT_ATTR_VAL}"$'\n'

                _strat_junit_attr "$trimmed" "classname"
                [[ -n "$_JUNIT_ATTR_VAL" ]] && result+="test${test_num}.classname ${_JUNIT_ATTR_VAL}"$'\n'

                _strat_junit_attr "$trimmed" "time"
                [[ -n "$_JUNIT_ATTR_VAL" ]] && result+="test${test_num}.time ${_JUNIT_ATTR_VAL}"$'\n'

                # Check if self-closing (ends with />) — means pass
                case "$trimmed" in
                    *'/>')
                        result+="test${test_num}.status pass"$'\n'
                        ;;
                esac
                ;;
        esac

        # Match <failure ...> tag — marks current testcase as failed
        case "$trimmed" in
            '<failure'*)
                if [[ $current_test_num -gt 0 ]]; then
                    result+="test${current_test_num}.status fail"$'\n'

                    # Extract failure message attribute if present
                    _strat_junit_attr "$trimmed" "message"
                    [[ -n "$_JUNIT_ATTR_VAL" ]] && result+="test${current_test_num}.failure_message ${_JUNIT_ATTR_VAL}"$'\n'
                fi
                ;;
        esac

        # Match <error ...> tag — marks current testcase as error
        case "$trimmed" in
            '<error'*)
                if [[ $current_test_num -gt 0 ]]; then
                    result+="test${current_test_num}.status error"$'\n'

                    _strat_junit_attr "$trimmed" "message"
                    [[ -n "$_JUNIT_ATTR_VAL" ]] && result+="test${current_test_num}.failure_message ${_JUNIT_ATTR_VAL}"$'\n'
                fi
                ;;
        esac

        # Match <skipped .../> tag — marks current testcase as skipped
        case "$trimmed" in
            '<skipped'*)
                if [[ $current_test_num -gt 0 ]]; then
                    result+="test${current_test_num}.status skipped"$'\n'
                fi
                ;;
        esac

        # Match </testcase> — reset current test context
        case "$trimmed" in
            '</testcase>'*)
                current_test_num=0
                ;;
        esac

    done <<< "$text"

    echo "$result"
}
