#!/bin/bash
## Name: papi
## Description: Extract hardware performance counter data from PAPI output
## Version: 1.0
## Priority: 25
## Sample: samples/papi/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Strong: PAPI name
    if [[ "$text" == *"PAPI"* ]] || [[ "$text" == *"papi"* ]]; then
        # Confirm with counter names
        if [[ "$text" == *"PAPI_"* ]] || [[ "$text" == *"TOTAL"* ]] || \
           [[ "$text" == *"TOT_CYC"* ]] || [[ "$text" == *"TOT_INS"* ]]; then
            return 0
        fi
    fi
    # Detect by PAPI-specific counter name patterns
    local counter_count=0
    if [[ "$text" == *"PAPI_TOT_CYC"* ]] || [[ "$text" == *"TOTAL_CYC"* ]] || [[ "$text" == *"TOT_CYC"* ]]; then
        counter_count=$((counter_count + 1))
    fi
    if [[ "$text" == *"PAPI_TOT_INS"* ]] || [[ "$text" == *"TOTAL_INS"* ]] || [[ "$text" == *"TOT_INS"* ]]; then
        counter_count=$((counter_count + 1))
    fi
    if [[ "$text" == *"PAPI_L1_DCM"* ]] || [[ "$text" == *"PAPI_L2_DCM"* ]]; then
        counter_count=$((counter_count + 1))
    fi
    if [[ "$text" == *"PAPI_BR_MSP"* ]]; then
        counter_count=$((counter_count + 1))
    fi
    [[ $counter_count -ge 2 ]]
}

strategy_extract () {
    local text="$1"
    local result=""
    local total_cycles=""
    local total_instructions=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip header/comment lines
        [[ "$line" == "#"* ]] && continue
        [[ "$line" == ------* ]] && continue

        # Parse counter lines: "PAPI_TOT_CYC    123456789" or "PAPI_TOT_CYC : 123456789"
        # or "PAPI_TOT_CYC = 123456789"
        if [[ "$line" == *"PAPI_"* ]] || [[ "$line" == *"TOTAL_CYC"* ]] || \
           [[ "$line" == *"TOTAL_INS"* ]] || [[ "$line" == *"TOT_CYC"* ]] || \
           [[ "$line" == *"TOT_INS"* ]]; then
            local counter_name=""
            local counter_val=""

            # Extract name and value
            if [[ "$line" == *":"* ]]; then
                counter_name="${line%%:*}"
                counter_val="${line##*:}"
            elif [[ "$line" == *"="* ]]; then
                counter_name="${line%%=*}"
                counter_val="${line##*=}"
            else
                read -ra _arr <<< "$line"
                if [[ ${#_arr[@]} -ge 2 ]]; then
                    counter_name="${_arr[0]}"
                    counter_val="${_arr[${#_arr[@]}-1]}"
                fi
            fi

            # Trim
            counter_name="${counter_name#"${counter_name%%[![:space:]]*}"}"
            counter_name="${counter_name%"${counter_name##*[![:space:]]}"}"
            counter_val="${counter_val#"${counter_val%%[![:space:]]*}"}"
            counter_val="${counter_val%"${counter_val##*[![:space:]]}"}"
            counter_val="${counter_val//,/}"

            [[ -z "$counter_name" || -z "$counter_val" ]] && continue

            # Normalize counter name to lowercase with underscores
            local normalized="${counter_name//PAPI_/}"
            normalized="${normalized,,}"

            # Map common counters
            case "$normalized" in
                tot_cyc|total_cyc)
                    result+="total_cycles ${counter_val}"$'\n'
                    total_cycles="$counter_val"
                    ;;
                tot_ins|total_ins)
                    result+="total_instructions ${counter_val}"$'\n'
                    total_instructions="$counter_val"
                    ;;
                l1_dcm)
                    result+="l1_data_cache_misses ${counter_val}"$'\n'
                    ;;
                l2_dcm)
                    result+="l2_data_cache_misses ${counter_val}"$'\n'
                    ;;
                l3_tcm|l3_dcm)
                    result+="l3_cache_misses ${counter_val}"$'\n'
                    ;;
                br_msp)
                    result+="branch_mispredictions ${counter_val}"$'\n'
                    ;;
                br_ins)
                    result+="branch_instructions ${counter_val}"$'\n'
                    ;;
                tlb_dm)
                    result+="tlb_data_misses ${counter_val}"$'\n'
                    ;;
                fp_ins|fp_ops)
                    result+="floating_point_ops ${counter_val}"$'\n'
                    ;;
                *)
                    result+="${normalized} ${counter_val}"$'\n'
                    ;;
            esac
        fi
    done <<< "$text"

    # Compute IPC if we have both cycles and instructions
    if [[ -n "$total_cycles" && -n "$total_instructions" && "$total_cycles" != "0" ]]; then
        # Integer approximation: instructions * 1000 / cycles, then format
        local ipc_x1000=$(( (total_instructions * 1000) / total_cycles ))
        local ipc_int=$((ipc_x1000 / 1000))
        local ipc_frac=$((ipc_x1000 % 1000))
        result+="ipc ${ipc_int}.$(printf '%03d' $ipc_frac)"$'\n'
    fi

    echo "$result"
}
