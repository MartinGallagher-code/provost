#!/bin/bash
## Name: scorep
## Description: Extract performance data from Score-P / Scalasca reports
## Version: 1.0
## Priority: 25
## Sample: samples/scorep/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Strong: Score-P or Scalasca name
    if [[ "$text" == *"Score-P"* ]] || [[ "$text" == *"SCOREP"* ]] || [[ "$text" == *"Scalasca"* ]]; then
        return 0
    fi
    # Detect Score-P profile table pattern: Region + Visits + Time columns
    if [[ "$text" == *"Region"* ]] && [[ "$text" == *"Visits"* ]] && [[ "$text" == *"Time"* ]]; then
        # Require additional Score-P indicators to avoid false positives
        if [[ "$text" == *"MPI"* ]] || [[ "$text" == *"OMP"* ]] || \
           [[ "$text" == *"USR"* ]] || [[ "$text" == *"COM"* ]] || \
           [[ "$text" == *"Execution"* ]]; then
            _STRATEGY_CONFIDENCE=75
            return 0
        fi
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local in_data=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Total execution time
        if [[ "$line" == *"Total"*"time"* ]] || [[ "$line" == *"Execution time"* ]] || \
           [[ "$line" == *"Total execution"* ]] || [[ "$line" == *"Wall-clock"* ]]; then
            local val
            val=$(_strat_scorep_extract_value "$line")
            [[ -n "$val" ]] && result+="total_execution_time ${val}"$'\n'
            continue
        fi

        # Detect region table header
        if [[ "$line" == *"Region"* ]] && [[ "$line" == *"Visits"* || "$line" == *"Time"* ]]; then
            in_data=0
            continue
        fi

        # Separator lines start data
        if [[ "$line" == ------* ]] || [[ "$line" == "==="* ]]; then
            if [[ $in_data -eq 0 ]]; then
                in_data=1
            fi
            continue
        fi

        # Parse region rows
        # Format: "region_name    visits    time    percent"
        # or:     "  MPI_Recv       1000    2.345    23.4%"
        if [[ $in_data -eq 1 ]]; then
            read -ra _arr <<< "$line"
            [[ ${#_arr[@]} -lt 2 ]] && continue

            # Find where numeric fields start
            local fname=""
            local visits=""
            local time_val=""
            local pct=""

            if [[ "${_arr[0]}" =~ ^[0-9] ]]; then
                # Numeric first - unusual but handle it
                continue
            fi

            # Region name is first token (may include type prefix like "USR", "MPI", "OMP")
            fname="${_arr[0]}"

            # Find first numeric field
            local i
            local num_start=-1
            for ((i=1; i<${#_arr[@]}; i++)); do
                if [[ "${_arr[$i]}" =~ ^[0-9] ]]; then
                    num_start=$i
                    break
                else
                    # Multi-word region name
                    fname+="_${_arr[$i]}"
                fi
            done

            [[ $num_start -eq -1 ]] && continue

            n=$((n + 1))
            result+="region${n}_name ${fname}"$'\n'

            visits="${_arr[$num_start]}"
            visits="${visits//,/}"
            result+="region${n}_visits ${visits}"$'\n'

            if [[ $((num_start + 1)) -lt ${#_arr[@]} ]]; then
                time_val="${_arr[$((num_start + 1))]}"
                time_val="${time_val%s}"
                result+="region${n}_time ${time_val}"$'\n'
            fi

            if [[ $((num_start + 2)) -lt ${#_arr[@]} ]]; then
                pct="${_arr[$((num_start + 2))]}"
                pct="${pct%%%}"
                result+="region${n}_percent ${pct}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}

_strat_scorep_extract_value () {
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
