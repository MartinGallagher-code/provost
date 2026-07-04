#!/bin/bash
## Name: flux
## Description: Extract job and resource information from Flux scheduler output (flux jobs, flux resource list, flux job info)
## Version: 1.0
## Priority: 15
## Sample: samples/flux/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Primary: flux jobs table with JOBID STATE NAME columns
    if [[ "$text" == *"flux jobs"* || "$text" == *"flux resource"* || "$text" == *"flux job info"* ]]; then
        return 0
    fi
    # flux jobs table header pattern
    if [[ "$text" == *"JOBID"* && "$text" == *"STATE"* && "$text" == *"NAME"* ]]; then
        if [[ "$text" == *"NTASKS"* || "$text" == *"NNODES"* || "$text" == *"RUNTIME"* ]]; then
            return 0
        fi
    fi
    # flux-job identifier or f: prefix on job IDs
    if [[ "$text" == *"flux-job"* ]]; then
        return 0
    fi
    if [[ "$text" == *"f:"* ]]; then
        if [[ "$text" == *"JOBID"* || "$text" == *"ntasks"* || "$text" == *"nnodes"* ]]; then
            return 0
        fi
    fi
    # flux resource list header
    if [[ "$text" == *"NNODES"* && "$text" == *"NCORES"* && "$text" == *"NGPUS"* ]]; then
        return 0
    fi
    # flux job info key=value with flux-specific keys
    if [[ "$text" == *"queue="* && "$text" == *"ntasks="* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Dispatch based on content type
    # flux jobs table
    if [[ "$text" == *"JOBID"* && "$text" == *"STATE"* && "$text" == *"NTASKS"* ]]; then
        local _out
        _out=$(_strat_flux_extract_jobs "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    fi

    # flux resource list
    if [[ "$text" == *"NNODES"* && "$text" == *"NCORES"* && "$text" == *"NGPUS"* ]]; then
        local _out
        _out=$(_strat_flux_extract_resources "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    fi

    # flux job info key=value
    if [[ "$text" == *"id="* && "$text" == *"ntasks="* ]]; then
        local _out
        _out=$(_strat_flux_extract_jobinfo "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    fi

    echo "$result"
}

_strat_flux_extract_jobs () {
    local text="$1"
    local result=""
    local header_found=0
    local col_names=()
    local job_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        # Skip command prompt lines
        [[ "$_line" == "\$"* ]] && continue

        if [[ $header_found -eq 0 && "$_line" == *"JOBID"* && "$_line" == *"STATE"* ]]; then
            header_found=1
            read -ra col_names <<< "$_line"
            continue
        fi

        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -eq 0 ]] && continue
            # Stop if we hit a non-data line (next command prompt or blank section)
            [[ "${_fields[0]}" == "\$" ]] && break

            job_num=$((job_num + 1))
            local prefix=""
            if [[ $job_num -gt 1 ]]; then
                prefix="job${job_num}."
            fi

            local i
            for i in "${!col_names[@]}"; do
                local col="${col_names[$i]}"
                local val="${_fields[$i]:-}"
                [[ -z "$val" || "$val" == "-" ]] && continue
                case "$col" in
                    JOBID)    result+="${prefix}job_id ${val}"$'\n' ;;
                    STATE)    result+="${prefix}state ${val}"$'\n' ;;
                    NAME)     result+="${prefix}name ${val}"$'\n' ;;
                    USER)     result+="${prefix}user ${val}"$'\n' ;;
                    NTASKS)   result+="${prefix}ntasks ${val}"$'\n' ;;
                    NNODES)   result+="${prefix}nnodes ${val}"$'\n' ;;
                    RUNTIME)  result+="${prefix}runtime ${val}"$'\n' ;;
                esac
            done
        fi
    done <<< "$text"

    echo "$result"
}

_strat_flux_extract_resources () {
    local text="$1"
    local result=""
    local header_found=0
    local col_names=()
    local res_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        [[ "$_line" == "\$"* ]] && continue

        if [[ $header_found -eq 0 && "$_line" == *"NNODES"* && "$_line" == *"NCORES"* ]]; then
            header_found=1
            read -ra col_names <<< "$_line"
            continue
        fi

        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -eq 0 ]] && continue
            [[ "${_fields[0]}" == "\$" ]] && break

            res_num=$((res_num + 1))
            local prefix="resource${res_num}."

            local i
            for i in "${!col_names[@]}"; do
                local col="${col_names[$i]}"
                local val="${_fields[$i]:-}"
                [[ -z "$val" ]] && continue
                case "$col" in
                    STATE)    result+="${prefix}state ${val}"$'\n' ;;
                    NNODES)   result+="${prefix}nnodes ${val}"$'\n' ;;
                    NCORES)   result+="${prefix}ncores ${val}"$'\n' ;;
                    NGPUS)    result+="${prefix}ngpus ${val}"$'\n' ;;
                    NODELIST) result+="${prefix}nodelist ${val}"$'\n' ;;
                esac
            done
        fi
    done <<< "$text"

    echo "$result"
}

_strat_flux_extract_jobinfo () {
    local text="$1"
    local result=""

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        [[ "$_line" == "\$"* ]] && continue

        # Parse key=value lines
        if [[ "$_line" == *"="* ]]; then
            local key="${_line%%=*}"
            local val="${_line#*=}"
            # Strip leading/trailing whitespace from key
            key="${key## }"
            key="${key%% }"
            val="${val## }"
            val="${val%% }"
            [[ -z "$key" || -z "$val" ]] && continue
            case "$key" in
                id)         result+="info.job_id ${val}"$'\n' ;;
                name)       result+="info.name ${val}"$'\n' ;;
                userid)     result+="info.userid ${val}"$'\n' ;;
                urgency)    result+="info.urgency ${val}"$'\n' ;;
                state)      result+="info.state ${val}"$'\n' ;;
                ntasks)     result+="info.ntasks ${val}"$'\n' ;;
                nnodes)     result+="info.nnodes ${val}"$'\n' ;;
                ncores)     result+="info.ncores ${val}"$'\n' ;;
                ngpus)      result+="info.ngpus ${val}"$'\n' ;;
                queue)      result+="info.queue ${val}"$'\n' ;;
                duration)   result+="info.duration ${val}"$'\n' ;;
            esac
        fi
    done <<< "$text"

    echo "$result"
}
