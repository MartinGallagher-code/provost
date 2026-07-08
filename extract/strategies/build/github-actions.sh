#!/bin/bash
## Name: github-actions
## Description: Extract errors, warnings, groups, and commands from GitHub Actions log output
## Version: 1.0
## Priority: 20
## Sample: samples/github-actions/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Reject JSON
    _is_json "$1" && return 1

    # Look for GitHub Actions-specific markers
    local found_marker=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        # Check for workflow commands
        if [[ "$_line" == "::error"* || "$_line" == "::warning::"* || "$_line" == "::notice::"* ]]; then
            found_marker=1
            break
        fi

        # Check for group markers
        if [[ "$_line" == "##[group]"* || "$_line" == "##[endgroup]"* ]]; then
            found_marker=1
            break
        fi
    done <<< "$text"

    [[ $found_marker -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local error_num=0
    local warning_num=0
    local notice_num=0
    local group_num=0
    local run_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Parse ##[group]name
        if [[ "$line" == "##[group]"* ]]; then
            group_num=$((group_num + 1))
            local gname="${line#\#\#\[group\]}"
            # Check if it's a "Run command" group
            if [[ "$gname" == "Run "* ]]; then
                run_num=$((run_num + 1))
                local cmd="${gname#Run }"
                result+="run${run_num}.command ${cmd}"$'\n'
            fi
            result+="group${group_num}.name ${gname}"$'\n'
            continue
        fi

        # Skip endgroup markers
        if [[ "$line" == "##[endgroup]"* ]]; then
            continue
        fi

        # Parse ::error file=F,line=L::message
        if [[ "$line" == "::error"* ]]; then
            error_num=$((error_num + 1))
            local prefix="error${error_num}"

            # Check if there are properties (file=, line=)
            if [[ "$line" == "::error "* ]]; then
                # Has properties: ::error file=F,line=L::message
                local rest="${line#::error }"
                local props="${rest%%::*}"
                local msg="${rest#*::}"

                # Parse properties
                local remaining_props="$props"
                while [[ -n "$remaining_props" ]]; do
                    local prop="${remaining_props%%,*}"
                    if [[ "$prop" == "file="* ]]; then
                        local fval="${prop#file=}"
                        result+="${prefix}.file ${fval}"$'\n'
                    elif [[ "$prop" == "line="* ]]; then
                        local lval="${prop#line=}"
                        result+="${prefix}.line ${lval}"$'\n'
                    elif [[ "$prop" == "col="* ]]; then
                        local cval="${prop#col=}"
                        result+="${prefix}.col ${cval}"$'\n'
                    fi
                    if [[ "$remaining_props" == *","* ]]; then
                        remaining_props="${remaining_props#*,}"
                    else
                        break
                    fi
                done

                result+="${prefix}.message ${msg}"$'\n'
            else
                # No properties: ::error::message
                local msg="${line#::error::}"
                result+="${prefix}.message ${msg}"$'\n'
            fi
            continue
        fi

        # Parse ::warning::message
        if [[ "$line" == "::warning::"* ]]; then
            warning_num=$((warning_num + 1))
            local msg="${line#::warning::}"
            result+="warning${warning_num}.message ${msg}"$'\n'
            continue
        fi

        # Parse ::notice::message
        if [[ "$line" == "::notice::"* ]]; then
            notice_num=$((notice_num + 1))
            local msg="${line#::notice::}"
            result+="notice${notice_num}.message ${msg}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}
