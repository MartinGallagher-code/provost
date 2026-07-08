#!/bin/bash
## Name: make-stats
## Description: Extract fields from build system output (make/ninja/cmake)
## Version: 1.0
## Priority: 25
## Sample: samples/make-stats/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=75
    # Lines matching [N/M] (ninja format) or make[ (make format)
    [[ "$text" =~ $'\n'"["[0-9]+/[0-9]+"]" ]] && return 0
    [[ "$text" == "["[0-9]* ]] && return 0
    [[ "$text" == *$'\n'"make["* ]] && return 0
    [[ "$text" == "make["* ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local total_steps=0
    local completed=0
    local step_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Parse ninja-style build steps: "[1/5] Compiling src/main.c"
        if [[ "$line" =~ ^\[([0-9]+)/([0-9]+)\] ]]; then
            local current="${BASH_REMATCH[1]}"
            local max="${BASH_REMATCH[2]}"
            # Action is the first word after "]"
            local after_bracket="${line#*] }"
            read -ra _arr <<< "$after_bracket"
            local action="${_arr[0]}"
            # Target is everything from field 2 onward
            local target=""
            local i
            for ((i=1; i<${#_arr[@]}; i++)); do
                if [[ -n "$target" ]]; then
                    target+="_"
                fi
                target+="${_arr[$i]}"
            done

            if [[ $max -gt $total_steps ]]; then
                total_steps=$max
            fi
            completed=$current

            step_num=$((step_num + 1))
            result+="step${step_num}.action ${action}"$'\n'
            [[ -n "$target" ]] && result+="step${step_num}.target ${target}"$'\n'
            continue
        fi

        # Parse make-style steps: "make[1]: Entering directory '/foo'"
        if [[ "$line" == "make["* ]]; then
            step_num=$((step_num + 1))
            local make_msg="${line#make\[*\]: }"
            # Handle cases where the pattern doesn't match exactly
            if [[ "$make_msg" == "$line" ]]; then
                # Try alternate: strip make[N]:
                make_msg="${line#*]: }"
            fi
            result+="step${step_num}.action ${make_msg}"$'\n'
            continue
        fi

        # Parse build summary: "Build finished successfully in 3.45s"
        local line_lower
        line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]')
        if [[ "$line_lower" == *"build"* ]] && [[ "$line_lower" == *"finished"* || "$line_lower" == *"completed"* || "$line_lower" == *"succeeded"* ]]; then
            local build_time=""
            if [[ "$line" =~ ([0-9]+\.[0-9]+s) ]]; then
                build_time="${BASH_REMATCH[1]}"
            fi
            [[ -n "$build_time" ]] && result+="build_time ${build_time}"$'\n'
        fi

    done <<< "$text"

    # Add summary fields
    if [[ $total_steps -gt 0 ]]; then
        result+="total_steps ${total_steps}"$'\n'
        result+="completed_steps ${completed}"$'\n'
    fi

    echo "$result"
}
