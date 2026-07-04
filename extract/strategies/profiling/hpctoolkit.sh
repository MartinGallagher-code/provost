#!/bin/bash
## Name: hpctoolkit
## Description: Extract profiling data from HPCToolkit hpcrun/hpcprof summaries
## Version: 1.0
## Priority: 25
## Sample: samples/hpctoolkit/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Strong: HPCToolkit name
    if [[ "$text" == *"HPCToolkit"* ]] || [[ "$text" == *"hpctoolkit"* ]]; then
        return 0
    fi
    # hpcrun/hpcprof markers
    if [[ "$text" == *"hpcrun"* ]] || [[ "$text" == *"hpcprof"* ]]; then
        if [[ "$text" == *"SUMMARY"* ]] || [[ "$text" == *"Load Module"* ]] || \
           [[ "$text" == *"inclusive"* ]] || [[ "$text" == *"exclusive"* ]]; then
            return 0
        fi
    fi
    # SUMMARY with Load Module is distinctive
    if [[ "$text" == *"SUMMARY"* ]] && [[ "$text" == *"Load Module"* ]]; then
        _STRATEGY_CONFIDENCE=70
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local in_summary=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Total time
        if [[ "$line" == *"Total"*"time"* ]] || [[ "$line" == *"total time"* ]] || \
           [[ "$line" == *"Total Time"* ]]; then
            local val
            val=$(_strat_hpctoolkit_extract_value "$line")
            [[ -n "$val" ]] && result+="total_time ${val}"$'\n'
            continue
        fi

        # Application/program name
        if [[ "$line" == *"Application"* ]] || [[ "$line" == *"Program"* ]]; then
            if [[ "$line" == *":"* ]]; then
                local val="${line##*:}"
                val="${val#"${val%%[![:space:]]*}"}"
                val="${val%"${val##*[![:space:]]}"}"
                [[ -n "$val" ]] && result+="application ${val}"$'\n'
            fi
            continue
        fi

        # Detect summary/function table section
        if [[ "$line" == *"SUMMARY"* ]] || [[ "$line" == *"Procedure"* ]] || \
           [[ "$line" == *"Function"*"Inclusive"* ]] || [[ "$line" == *"Function"*"Exclusive"* ]]; then
            in_summary=1
            continue
        fi

        # Skip separator lines
        [[ "$line" == ------* ]] && continue
        [[ "$line" == "==="* ]] && continue

        # Parse function rows in summary
        # Format varies: "function_name    incl%    excl%    ..."
        # or "  45.2%    12.3%    function_name"
        if [[ $in_summary -eq 1 ]]; then
            read -ra _arr <<< "$line"
            [[ ${#_arr[@]} -lt 2 ]] && continue

            # Determine if percentage comes first or function name comes first
            if [[ "${_arr[0]}" =~ ^[0-9]+\.?[0-9]*%?$ ]]; then
                # Percentage first: "45.2%  12.3%  function_name"
                n=$((n + 1))
                local incl_pct="${_arr[0]}"
                incl_pct="${incl_pct%%%}"
                result+="func${n}_inclusive_percent ${incl_pct}"$'\n'
                if [[ ${#_arr[@]} -ge 3 ]]; then
                    local excl_pct="${_arr[1]}"
                    excl_pct="${excl_pct%%%}"
                    result+="func${n}_exclusive_percent ${excl_pct}"$'\n'
                    result+="func${n}_name ${_arr[${#_arr[@]}-1]}"$'\n'
                else
                    result+="func${n}_name ${_arr[${#_arr[@]}-1]}"$'\n'
                fi
            else
                # Function name first: "function_name  45.2%  12.3%"
                n=$((n + 1))
                local fname="${_arr[0]}"
                result+="func${n}_name ${fname}"$'\n'
                if [[ ${#_arr[@]} -ge 2 ]] && [[ "${_arr[1]}" =~ ^[0-9] ]]; then
                    local incl_pct="${_arr[1]}"
                    incl_pct="${incl_pct%%%}"
                    result+="func${n}_inclusive_percent ${incl_pct}"$'\n'
                fi
                if [[ ${#_arr[@]} -ge 3 ]] && [[ "${_arr[2]}" =~ ^[0-9] ]]; then
                    local excl_pct="${_arr[2]}"
                    excl_pct="${excl_pct%%%}"
                    result+="func${n}_exclusive_percent ${excl_pct}"$'\n'
                fi
            fi
        fi
    done <<< "$text"

    echo "$result"
}

_strat_hpctoolkit_extract_value () {
    local line="$1"
    local val=""
    if [[ "$line" == *":"* ]]; then
        val="${line##*:}"
    else
        read -ra _arr <<< "$line"
        local i
        for ((i=${#_arr[@]}-1; i>=0; i--)); do
            if [[ "${_arr[$i]}" =~ ^[0-9] ]]; then
                val="${_arr[$i]}"
                break
            fi
        done
    fi
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    val="${val%s}"
    echo "$val"
}
