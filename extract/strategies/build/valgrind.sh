#!/bin/bash
## Name: valgrind
## Description: Extract fields from valgrind memcheck output
## Version: 1.0
## Priority: 15
## Sample: samples/valgrind/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Lines matching ==PID== (valgrind prefix)
    [[ "$text" =~ (^|$'\n')==[0-9]+== ]]
}

_strat_vg_strip_prefix () {
    # Strip the ==PID== prefix from a line
    local line="$1"
    line="${line#==}"
    line="${line#*==}"
    while [[ "$line" == " "* ]]; do line="${line# }"; done
    echo "$line"
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        # Only process valgrind-prefixed lines
        [[ "$line" =~ ^==[0-9]+== ]] || continue

        local stripped
        stripped=$(_strat_vg_strip_prefix "$line")
        [[ -z "$stripped" ]] && continue

        # Command: "./my_program"
        if [[ "$stripped" == "Command:"* ]]; then
            local cmd="${stripped#Command:}"
            while [[ "$cmd" == " "* ]]; do cmd="${cmd# }"; done
            cmd="${cmd// /_}"
            result+="command ${cmd}"$'\n'
            continue
        fi

        # Heap summary: "in use at exit: 1,234 bytes in 5 blocks"
        if [[ "$stripped" == *"in use at exit:"* ]]; then
            local heap_use="${stripped#*in use at exit:}"
            while [[ "$heap_use" == " "* ]]; do heap_use="${heap_use# }"; done
            heap_use="${heap_use// /_}"
            result+="heap_in_use ${heap_use}"$'\n'
            continue
        fi

        # Total heap usage: "42 allocs, 37 frees, 56,789 bytes allocated"
        if [[ "$stripped" == *"total heap usage:"* ]]; then
            local _after="${stripped#*total heap usage:}"
            while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
            read -ra _arr <<< "$_after"
            local allocs="${_arr[0]}"
            local frees="${_arr[2]}"
            result+="total_allocs ${allocs}"$'\n'
            result+="total_frees ${frees}"$'\n'
            continue
        fi

        # Leak summary fields
        if [[ "$stripped" == *"definitely lost:"* ]]; then
            local val="${stripped#*definitely lost:}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            val="${val// /_}"
            result+="definitely_lost ${val}"$'\n'
            continue
        fi

        if [[ "$stripped" == *"indirectly lost:"* ]]; then
            local val="${stripped#*indirectly lost:}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            val="${val// /_}"
            result+="indirectly_lost ${val}"$'\n'
            continue
        fi

        if [[ "$stripped" == *"possibly lost:"* ]]; then
            local val="${stripped#*possibly lost:}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            val="${val// /_}"
            result+="possibly_lost ${val}"$'\n'
            continue
        fi

        if [[ "$stripped" == *"still reachable:"* ]]; then
            local val="${stripped#*still reachable:}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            val="${val// /_}"
            result+="still_reachable ${val}"$'\n'
            continue
        fi

        # Error summary: "3 errors from 2 contexts"
        if [[ "$stripped" == "ERROR SUMMARY:"* ]]; then
            local _after="${stripped#ERROR SUMMARY:}"
            while [[ "$_after" == " "* ]]; do _after="${_after# }"; done
            read -ra _arr <<< "$_after"
            local total_errors="${_arr[0]}"
            result+="total_errors ${total_errors}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}
