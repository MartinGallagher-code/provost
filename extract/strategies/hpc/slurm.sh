#!/bin/bash
## Name: slurm
## Description: Extract job and node information from Slurm scheduler output (sacct, squeue, sinfo, scontrol)
## Version: 1.0
## Priority: 15
## Sample: samples/slurm/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Primary: sacct/scontrol output
    if [[ "$text" == *"sacct"* || "$text" == *"scontrol"* ]]; then
        if [[ "$text" == *"JobID"* || "$text" == *"AllocCPUS"* || "$text" == *"Partition"* ]]; then
            return 0
        fi
    fi
    # squeue output
    if [[ "$text" == *"squeue"* || "$text" == *"JOBID"* ]]; then
        if [[ "$text" == *"PARTITION"* || "$text" == *"NODELIST"* ]]; then
            return 0
        fi
    fi
    # sinfo output
    if [[ "$text" == *"sinfo"* ]]; then
        if [[ "$text" == *"PARTITION"* || "$text" == *"AVAIL"* || "$text" == *"NODELIST"* ]]; then
            return 0
        fi
    fi
    # scontrol show job output
    if [[ "$text" == *"SLURM"* || "$text" == *"JobId="* ]]; then
        if [[ "$text" == *"Partition="* || "$text" == *"JobState="* || "$text" == *"NumCPUs="* ]]; then
            return 0
        fi
    fi
    # Generic Slurm keywords
    if [[ "$text" == *"AllocCPUS"* && "$text" == *"JobID"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Detect output type and dispatch
    if [[ "$text" == *"JobId="* && "$text" == *"JobState="* ]]; then
        local _out
        _out=$(_strat_slurm_extract_scontrol "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    elif [[ "$text" == *"PARTITION"* && "$text" == *"AVAIL"* && "$text" == *"NODELIST"* ]]; then
        local _out
        _out=$(_strat_slurm_extract_sinfo "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    elif [[ "$text" == *"JobID"* && "$text" == *"AllocCPUS"* ]]; then
        local _out
        _out=$(_strat_slurm_extract_sacct "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    elif [[ "$text" == *"JOBID"* && "$text" == *"PARTITION"* ]]; then
        local _out
        _out=$(_strat_slurm_extract_squeue "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    fi

    echo "$result"
}

_strat_slurm_extract_scontrol () {
    local text="$1"
    local result=""

    # Parse "Key=Value" pairs from scontrol show job output
    local job_id="" job_name="" partition="" state="" elapsed=""
    local ncpus="" nnodes="" mem="" exit_code=""

    while IFS= read -r _line; do
        # JobId=12345
        if [[ "$_line" == *"JobId="* && -z "$job_id" ]]; then
            local _val="${_line#*JobId=}"
            job_id="${_val%% *}"
        fi
        # JobName=test_job
        if [[ "$_line" == *"JobName="* && -z "$job_name" ]]; then
            local _val="${_line#*JobName=}"
            job_name="${_val%% *}"
        fi
        # Partition=compute
        if [[ "$_line" == *"Partition="* && -z "$partition" ]]; then
            local _val="${_line#*Partition=}"
            partition="${_val%% *}"
        fi
        # JobState=COMPLETED
        if [[ "$_line" == *"JobState="* && -z "$state" ]]; then
            local _val="${_line#*JobState=}"
            state="${_val%% *}"
        fi
        # RunTime=00:05:30
        if [[ "$_line" == *"RunTime="* && -z "$elapsed" ]]; then
            local _val="${_line#*RunTime=}"
            elapsed="${_val%% *}"
        fi
        # NumCPUs=16
        if [[ "$_line" == *"NumCPUs="* && -z "$ncpus" ]]; then
            local _val="${_line#*NumCPUs=}"
            ncpus="${_val%% *}"
        fi
        # NumNodes=2
        if [[ "$_line" == *"NumNodes="* && -z "$nnodes" ]]; then
            local _val="${_line#*NumNodes=}"
            nnodes="${_val%% *}"
        fi
        # MinMemoryNode=4G or Mem=4096M
        if [[ "$_line" == *"MinMemoryNode="* && -z "$mem" ]]; then
            local _val="${_line#*MinMemoryNode=}"
            mem="${_val%% *}"
        fi
        # ExitCode=0:0
        if [[ "$_line" == *"ExitCode="* && -z "$exit_code" ]]; then
            local _val="${_line#*ExitCode=}"
            exit_code="${_val%% *}"
        fi
    done <<< "$text"

    [[ -n "$job_id" ]] && result+="job_id ${job_id}"$'\n'
    [[ -n "$job_name" ]] && result+="job_name ${job_name}"$'\n'
    [[ -n "$partition" ]] && result+="partition ${partition}"$'\n'
    [[ -n "$state" ]] && result+="state ${state}"$'\n'
    [[ -n "$elapsed" ]] && result+="elapsed ${elapsed}"$'\n'
    [[ -n "$ncpus" ]] && result+="ncpus ${ncpus}"$'\n'
    [[ -n "$nnodes" ]] && result+="nnodes ${nnodes}"$'\n'
    [[ -n "$mem" ]] && result+="mem ${mem}"$'\n'
    [[ -n "$exit_code" ]] && result+="exit_code ${exit_code}"$'\n'

    echo "$result"
}

_strat_slurm_extract_sacct () {
    local text="$1"
    local result=""
    local header_found=0
    local col_positions=()
    local col_names=()
    local job_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        # Find header line with JobID
        if [[ $header_found -eq 0 && "$_line" == *"JobID"* ]]; then
            header_found=1
            # Parse column names from header
            read -ra col_names <<< "$_line"
            continue
        fi

        # Skip separator line (-------)
        if [[ $header_found -eq 1 && "$_line" == *"------"* ]]; then
            continue
        fi

        # Data rows
        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -eq 0 ]] && continue
            # Skip sub-job lines (e.g., 12345.batch)
            [[ "${_fields[0]}" == *"."* ]] && continue

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
                    JobID)     result+="${prefix}job_id ${val}"$'\n' ;;
                    JobName)   result+="${prefix}job_name ${val}"$'\n' ;;
                    Partition) result+="${prefix}partition ${val}"$'\n' ;;
                    State)     result+="${prefix}state ${val}"$'\n' ;;
                    Elapsed)   result+="${prefix}elapsed ${val}"$'\n' ;;
                    AllocCPUS) result+="${prefix}ncpus ${val}"$'\n' ;;
                    NNodes)    result+="${prefix}nnodes ${val}"$'\n' ;;
                    MaxRSS)    result+="${prefix}mem ${val}"$'\n' ;;
                    ExitCode)  result+="${prefix}exit_code ${val}"$'\n' ;;
                esac
            done
        fi
    done <<< "$text"

    echo "$result"
}

_strat_slurm_extract_squeue () {
    local text="$1"
    local result=""
    local header_found=0
    local col_names=()
    local job_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

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
                    JOBID)     result+="${prefix}job_id ${val}"$'\n' ;;
                    PARTITION) result+="${prefix}partition ${val}"$'\n' ;;
                    NAME)      result+="${prefix}job_name ${val}"$'\n' ;;
                    USER)      result+="${prefix}user ${val}"$'\n' ;;
                    ST)        result+="${prefix}state ${val}"$'\n' ;;
                    TIME)      result+="${prefix}elapsed ${val}"$'\n' ;;
                    NODES)     result+="${prefix}nnodes ${val}"$'\n' ;;
                    NODELIST*) result+="${prefix}nodelist ${val}"$'\n' ;;
                esac
            done
        fi
    done <<< "$text"

    echo "$result"
}

_strat_slurm_extract_sinfo () {
    local text="$1"
    local result=""
    local header_found=0
    local col_names=()
    local part_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        if [[ $header_found -eq 0 && "$_line" == *"PARTITION"* ]]; then
            header_found=1
            read -ra col_names <<< "$_line"
            continue
        fi

        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -eq 0 ]] && continue

            part_num=$((part_num + 1))
            local prefix=""
            if [[ $part_num -gt 1 ]]; then
                prefix="part${part_num}."
            fi

            local i
            for i in "${!col_names[@]}"; do
                local col="${col_names[$i]}"
                local val="${_fields[$i]:-}"
                [[ -z "$val" ]] && continue
                case "$col" in
                    PARTITION) result+="${prefix}partition ${val}"$'\n' ;;
                    AVAIL)     result+="${prefix}state ${val}"$'\n' ;;
                    TIMELIMIT) result+="${prefix}timelimit ${val}"$'\n' ;;
                    NODES)     result+="${prefix}nodes ${val}"$'\n' ;;
                    STATE)     result+="${prefix}node_state ${val}"$'\n' ;;
                    NODELIST)  result+="${prefix}nodelist ${val}"$'\n' ;;
                    CPUS)      result+="${prefix}cpus ${val}"$'\n' ;;
                    MEMORY)    result+="${prefix}memory ${val}"$'\n' ;;
                esac
            done
        fi
    done <<< "$text"

    echo "$result"
}
