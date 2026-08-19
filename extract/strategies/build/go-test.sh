#!/bin/bash
## Name: go-test
## Description: Extract per-test results from `go test -v` output (test name, status, duration; package summary broadcast)
## Version: 1.0
## Priority: 20
## Sample: samples/go-test/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=88
    [[ "$text" == *$'\n=== RUN'* || "$text" == "=== RUN"* ]] || return 1
    [[ "$text" =~ (^|$'\n')[[:space:]]*---[[:space:]](PASS|FAIL|SKIP): ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local overall_result="" package="" package_result="" package_duration="" coverage_pct=""

    local re_result='^[[:space:]]*---[[:space:]](PASS|FAIL|SKIP):[[:space:]]+([^[:space:]]+)[[:space:]]+\(([^)]*)\)[[:space:]]*$'
    local re_coverage='^coverage:[[:space:]]+([0-9.]+)%[[:space:]]+of[[:space:]]+statements'
    local re_package='^(ok|FAIL)[[:space:]]+([^[:space:]]+)[[:space:]]+([0-9.]+s)([[:space:]]|$)'

    while IFS= read -r line; do
        if [[ "$line" =~ $re_result ]]; then
            n=$((n + 1))
            local p="entry${n}."
            result+="${p}test ${BASH_REMATCH[2]}"$'\n'
            result+="${p}status ${BASH_REMATCH[1]}"$'\n'
            result+="${p}duration ${BASH_REMATCH[3]}"$'\n'
        elif [[ "$line" =~ $re_coverage ]]; then
            coverage_pct="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ $re_package ]]; then
            package_result="${BASH_REMATCH[1]}"
            package="${BASH_REMATCH[2]}"
            package_duration="${BASH_REMATCH[3]}"
        elif [[ "$line" == "PASS" || "$line" == "FAIL" ]]; then
            overall_result="$line"
        fi
    done <<< "$text"

    [[ -n "$overall_result" ]] && result+="overall_result ${overall_result}"$'\n'
    [[ -n "$package" ]] && result+="package ${package}"$'\n'
    [[ -n "$package_result" ]] && result+="package_result ${package_result}"$'\n'
    [[ -n "$package_duration" ]] && result+="package_duration ${package_duration}"$'\n'
    [[ -n "$coverage_pct" ]] && result+="coverage_pct ${coverage_pct}"$'\n'
    result+="total_entries ${n}"$'\n'
    echo "$result"
}
