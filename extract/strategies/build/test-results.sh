#!/bin/bash
## Name: test-results
## Description: Extract test results from Go (go test) or Rust (cargo test) test output
## Version: 1.0
## Priority: 18
## Sample: samples/go-test/basic.txt

# Merges go-test and cargo-test strategies.
# go test output:   "--- PASS: TestName (0.00s)" -> testN.name/testN.result/testN.time
# cargo test output: "test tests::name ... ok"   -> testN.name/testN.result (normalized to dot)

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Reject JSON
    _is_json "$1" && return 1

    local has_go_test_marker=0
    local has_result_line=0

    while IFS= read -r line; do
        # go test markers
        case "$line" in
            "--- PASS:"*|"--- FAIL:"*|"=== RUN"*) has_go_test_marker=1 ;;
        esac
        case "$line" in
            "ok "*|"PASS"|"FAIL") has_result_line=1 ;;
        esac
        if [[ $has_go_test_marker -eq 1 && $has_result_line -eq 1 ]]; then
            return 0
        fi

        # cargo test markers
        case "$line" in
            "running "*" test"*) return 0 ;;
            "test result:"*)     return 0 ;;
        esac
    done <<< "$text"

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Determine format: go test has "--- PASS:", "--- FAIL:", or "=== RUN" lines
    local _is_go=0
    while IFS= read -r _line; do
        case "$_line" in
            "--- PASS:"*|"--- FAIL:"*|"=== RUN"*)
                _is_go=1
                break
                ;;
        esac
    done <<< "$text"

    if [[ $_is_go -eq 1 ]]; then
        # --- go test format ---
        local test_num=0

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            # --- PASS: TestName (0.00s)
            case "$line" in
                "--- PASS: "*)
                    test_num=$((test_num + 1))
                    local rest="${line#--- PASS: }"
                    local tname="${rest%% (*}"
                    local ttime="${rest##*(}"
                    ttime="${ttime%)}"
                    result+="test${test_num}.name ${tname}"$'\n'
                    result+="test${test_num}.result PASS"$'\n'
                    result+="test${test_num}.time ${ttime}"$'\n'
                    ;;
            esac

            # --- FAIL: TestName (0.05s)
            case "$line" in
                "--- FAIL: "*)
                    test_num=$((test_num + 1))
                    local rest="${line#--- FAIL: }"
                    local tname="${rest%% (*}"
                    local ttime="${rest##*(}"
                    ttime="${ttime%)}"
                    result+="test${test_num}.name ${tname}"$'\n'
                    result+="test${test_num}.result FAIL"$'\n'
                    result+="test${test_num}.time ${ttime}"$'\n'
                    ;;
            esac

            # coverage: 87.5% of statements
            case "$line" in
                "coverage: "*)
                    local rest="${line#coverage: }"
                    local pct="${rest%% of*}"
                    result+="coverage ${pct}"$'\n'
                    ;;
            esac

            # ok      github.com/user/mathlib 0.234s
            case "$line" in
                "ok"*)
                    local rest="${line#ok}"
                    while [[ "$rest" == " "* || "$rest" == $'\t'* ]]; do
                        rest="${rest# }"
                        rest="${rest#$'\t'}"
                    done
                    local pkg="${rest%% *}"
                    rest="${rest#* }"
                    while [[ "$rest" == " "* || "$rest" == $'\t'* ]]; do
                        rest="${rest# }"
                        rest="${rest#$'\t'}"
                    done
                    local ttime="${rest%% *}"
                    if [[ -n "$pkg" ]]; then
                        result+="package ${pkg}"$'\n'
                    fi
                    if [[ -n "$ttime" && "$ttime" != "$pkg" ]]; then
                        result+="total_time ${ttime}"$'\n'
                    fi
                    ;;
            esac

        done <<< "$text"

    else
        # --- cargo test format ---
        local test_num=0

        while IFS= read -r line; do
            [[ -z "$line" ]] && continue

            # Individual test line: "test tests::test_add ... ok"
            case "$line" in
                "test "*" ... "*)
                    test_num=$((test_num + 1))
                    local rest="${line#test }"
                    local tname="${rest%% ... *}"
                    local tresult="${rest##* ... }"
                    result+="test${test_num}.name ${tname}"$'\n'
                    result+="test${test_num}.result ${tresult}"$'\n'
                    ;;
            esac

            # Summary: "test result: ok. 5 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.10s"
            case "$line" in
                "test result:"*)
                    local rest="${line#test result: }"
                    local status="${rest%%.*}"
                    result+="status ${status}"$'\n'

                    local after_status="${rest#*.}"
                    while [[ "$after_status" == " "* ]]; do after_status="${after_status# }"; done

                    local remaining="$after_status"
                    while [[ -n "$remaining" ]]; do
                        local segment="${remaining%%;*}"
                        if [[ "$segment" == "$remaining" ]]; then
                            remaining=""
                        else
                            remaining="${remaining#*;}"
                            while [[ "$remaining" == " "* ]]; do remaining="${remaining# }"; done
                        fi
                        while [[ "$segment" == " "* ]]; do segment="${segment# }"; done
                        while [[ "$segment" == *" " ]]; do segment="${segment% }"; done

                        case "$segment" in
                            *" passed"*)
                                local val="${segment%% passed*}"
                                result+="passed ${val}"$'\n'
                                ;;
                            *" failed"*)
                                local val="${segment%% failed*}"
                                result+="failed ${val}"$'\n'
                                ;;
                            *" ignored"*)
                                local val="${segment%% ignored*}"
                                result+="ignored ${val}"$'\n'
                                ;;
                            *" measured"*)
                                local val="${segment%% measured*}"
                                result+="measured ${val}"$'\n'
                                ;;
                            *" filtered out"*)
                                local val="${segment%% filtered out*}"
                                result+="filtered_out ${val}"$'\n'
                                ;;
                            "finished in "*)
                                local dur="${segment#finished in }"
                                result+="duration ${dur}"$'\n'
                                ;;
                        esac
                    done

                    # Calculate total_tests from passed + failed
                    local _passed=0 _failed=0
                    while IFS= read -r _rline; do
                        case "$_rline" in
                            "passed "*)  _passed="${_rline#passed }" ;;
                            "failed "*)  _failed="${_rline#failed }" ;;
                        esac
                    done <<< "$result"
                    local total=$((_passed + _failed))
                    result+="total_tests ${total}"$'\n'
                    ;;
            esac

        done <<< "$text"
    fi

    echo "$result"
}
