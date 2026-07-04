#!/bin/bash
## Name: lsf
## Description: Extract job and host information from IBM LSF scheduler output (bjobs, bhosts, bqueues)
## Version: 1.0
## Priority: 15
## Sample: samples/lsf/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # bjobs output
    if [[ "$text" == *"bjobs"* || "$text" == *"JOBID"* ]]; then
        if [[ "$text" == *"STAT"* && "$text" == *"QUEUE"* ]]; then
            return 0
        fi
    fi
    # bjobs -l long format
    if [[ "$text" == *"Job <"* && "$text" == *"Queue <"* ]]; then
        return 0
    fi
    # bhosts output
    if [[ "$text" == *"bhosts"* ]]; then
        if [[ "$text" == *"HOST_NAME"* || "$text" == *"STATUS"* ]]; then
            return 0
        fi
    fi
    # bqueues output
    if [[ "$text" == *"bqueues"* || "$text" == *"QUEUE_NAME"* ]]; then
        if [[ "$text" == *"PEND"* || "$text" == *"NJOBS"* ]]; then
            return 0
        fi
    fi
    # LSF-specific keywords
    if [[ "$text" == *"PEND"* && "$text" == *"STAT"* && "$text" == *"QUEUE"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Detect output type and dispatch
    if [[ "$text" == *"Job <"* && "$text" == *"Queue <"* ]]; then
        local _out
        _out=$(_strat_lsf_extract_bjobs_long "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    elif [[ "$text" == *"HOST_NAME"* && "$text" == *"STATUS"* ]]; then
        local _out
        _out=$(_strat_lsf_extract_bhosts "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    elif [[ "$text" == *"QUEUE_NAME"* && "$text" == *"NJOBS"* ]]; then
        local _out
        _out=$(_strat_lsf_extract_bqueues "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    elif [[ "$text" == *"JOBID"* && "$text" == *"STAT"* ]]; then
        local _out
        _out=$(_strat_lsf_extract_bjobs_table "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    fi

    echo "$result"
}

_strat_lsf_extract_bjobs_table () {
    local text="$1"
    local result=""
    local header_found=0
    local col_names=()
    local job_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        # Header: JOBID USER STAT QUEUE FROM_HOST EXEC_HOST JOB_NAME SUBMIT_TIME
        if [[ $header_found -eq 0 && "$_line" == *"JOBID"* ]]; then
            header_found=1
            read -ra col_names <<< "$_line"
            continue
        fi

        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -eq 0 ]] && continue

            job_num=$((job_num + 1))
            local prefix=""
            if [[ $job_num -gt 1 ]]; then
                prefix="job${job_num}."
            fi

            local i
            for i in "${!col_names[@]}"; do
                local col="${col_names[$i]}"
                local val="${_fields[$i]:-}"
                [[ -z "$val" ]] && continue
                case "$col" in
                    JOBID)       result+="${prefix}job_id ${val}"$'\n' ;;
                    USER)        result+="${prefix}user ${val}"$'\n' ;;
                    STAT)        result+="${prefix}stat ${val}"$'\n' ;;
                    QUEUE)       result+="${prefix}queue ${val}"$'\n' ;;
                    FROM_HOST)   result+="${prefix}from_host ${val}"$'\n' ;;
                    EXEC_HOST)   result+="${prefix}exec_host ${val}"$'\n' ;;
                    JOB_NAME)    result+="${prefix}job_name ${val}"$'\n' ;;
                    SUBMIT_TIME) result+="${prefix}submit_time ${val}"$'\n' ;;
                esac
            done
        fi
    done <<< "$text"

    echo "$result"
}

_strat_lsf_extract_bjobs_long () {
    local text="$1"
    local result=""

    local job_id="" stat="" queue="" from_host="" exec_host=""
    local job_name="" submit_time=""

    while IFS= read -r _line; do
        # Job <12345>, User <user1>, ...
        if [[ "$_line" == *"Job <"* && -z "$job_id" ]]; then
            local _val="${_line#*Job <}"
            job_id="${_val%%>*}"
        fi
        # Status <DONE>
        if [[ "$_line" == *"Status <"* && -z "$stat" ]]; then
            local _val="${_line#*Status <}"
            stat="${_val%%>*}"
        fi
        # Queue <normal>
        if [[ "$_line" == *"Queue <"* && -z "$queue" ]]; then
            local _val="${_line#*Queue <}"
            queue="${_val%%>*}"
        fi
        # Job Name <test_job>
        if [[ "$_line" == *"Job Name <"* && -z "$job_name" ]]; then
            local _val="${_line#*Job Name <}"
            job_name="${_val%%>*}"
        fi
        # Submitted from host <login1>
        if [[ "$_line" == *"Submitted from host <"* && -z "$from_host" ]]; then
            local _val="${_line#*Submitted from host <}"
            from_host="${_val%%>*}"
        fi
        # Started on <host1>
        if [[ "$_line" == *"Started on <"* && -z "$exec_host" ]]; then
            local _val="${_line#*Started on <}"
            exec_host="${_val%%>*}"
        fi
        # Mon Mar 20 10:30:00 2026
        if [[ "$_line" == *"Submitted from host"* && -z "$submit_time" ]]; then
            # submit time is often on the same or next line as "submitted"
            :
        fi
    done <<< "$text"

    [[ -n "$job_id" ]] && result+="job_id ${job_id}"$'\n'
    [[ -n "$stat" ]] && result+="stat ${stat}"$'\n'
    [[ -n "$queue" ]] && result+="queue ${queue}"$'\n'
    [[ -n "$from_host" ]] && result+="from_host ${from_host}"$'\n'
    [[ -n "$exec_host" ]] && result+="exec_host ${exec_host}"$'\n'
    [[ -n "$job_name" ]] && result+="job_name ${job_name}"$'\n'

    echo "$result"
}

_strat_lsf_extract_bhosts () {
    local text="$1"
    local result=""
    local header_found=0
    local col_names=()
    local host_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        # Header: HOST_NAME STATUS JL/U MAX NJOBS RUN SSUSP USUSP RSV
        if [[ $header_found -eq 0 && "$_line" == *"HOST_NAME"* ]]; then
            header_found=1
            read -ra col_names <<< "$_line"
            continue
        fi

        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -eq 0 ]] && continue

            host_num=$((host_num + 1))
            local prefix=""
            if [[ $host_num -gt 1 ]]; then
                prefix="host${host_num}."
            fi

            local i
            for i in "${!col_names[@]}"; do
                local col="${col_names[$i]}"
                local val="${_fields[$i]:-}"
                [[ -z "$val" ]] && continue
                case "$col" in
                    HOST_NAME) result+="${prefix}hostname ${val}"$'\n' ;;
                    STATUS)    result+="${prefix}status ${val}"$'\n' ;;
                    MAX)       result+="${prefix}max_slots ${val}"$'\n' ;;
                    NJOBS)     result+="${prefix}njobs ${val}"$'\n' ;;
                    RUN)       result+="${prefix}running ${val}"$'\n' ;;
                    JL/U)      result+="${prefix}jl_u ${val}"$'\n' ;;
                esac
            done
        fi
    done <<< "$text"

    echo "$result"
}

_strat_lsf_extract_bqueues () {
    local text="$1"
    local result=""
    local header_found=0
    local col_names=()
    local queue_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        # Header: QUEUE_NAME PRIO STATUS MAX JL/U JL/P JL/H NJOBS PEND RUN SUSP
        if [[ $header_found -eq 0 && "$_line" == *"QUEUE_NAME"* ]]; then
            header_found=1
            read -ra col_names <<< "$_line"
            continue
        fi

        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -eq 0 ]] && continue

            queue_num=$((queue_num + 1))
            local prefix=""
            if [[ $queue_num -gt 1 ]]; then
                prefix="queue${queue_num}."
            fi

            local i
            for i in "${!col_names[@]}"; do
                local col="${col_names[$i]}"
                local val="${_fields[$i]:-}"
                [[ -z "$val" ]] && continue
                case "$col" in
                    QUEUE_NAME) result+="${prefix}queue_name ${val}"$'\n' ;;
                    PRIO)       result+="${prefix}priority ${val}"$'\n' ;;
                    STATUS)     result+="${prefix}status ${val}"$'\n' ;;
                    MAX)        result+="${prefix}max_slots ${val}"$'\n' ;;
                    NJOBS)      result+="${prefix}njobs ${val}"$'\n' ;;
                    PEND)       result+="${prefix}pending ${val}"$'\n' ;;
                    RUN)        result+="${prefix}running ${val}"$'\n' ;;
                    SUSP)       result+="${prefix}suspended ${val}"$'\n' ;;
                esac
            done
        fi
    done <<< "$text"

    echo "$result"
}
