#!/bin/bash
## Name: sge
## Description: Extract job and host information from SGE/UGE scheduler output (qstat, qhost)
## Version: 1.0
## Priority: 15
## Sample: samples/sge/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # qstat output (SGE style has "job-ID" header)
    if [[ "$text" == *"job-ID"* ]]; then
        if [[ "$text" == *"prior"* || "$text" == *"state"* || "$text" == *"queue"* ]]; then
            return 0
        fi
    fi
    # qhost output
    if [[ "$text" == *"qhost"* || "$text" == *"HOSTNAME"* ]]; then
        if [[ "$text" == *"ARCH"* || "$text" == *"NCPU"* || "$text" == *"MEMTOT"* ]]; then
            return 0
        fi
    fi
    # qstat -j (job detail) output
    if [[ "$text" == *"job_number"* && "$text" == *"job_name"* ]]; then
        if [[ "$text" == *"sge"* || "$text" == *"qmaster"* || "$text" == *"hard resource_list"* ]]; then
            return 0
        fi
    fi
    # SGE environment variables
    if [[ "$text" == *"SGE_ROOT"* || "$text" == *"SGE_CELL"* ]]; then
        return 0
    fi
    # Generic SGE keywords
    if [[ "$text" == *"sge"* && "$text" == *"qmaster"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Detect output type and dispatch
    if [[ "$text" == *"job_number"* && "$text" == *"job_name"* ]]; then
        local _out
        _out=$(_strat_sge_extract_qstat_detail "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    elif [[ "$text" == *"HOSTNAME"* && "$text" == *"ARCH"* ]]; then
        local _out
        _out=$(_strat_sge_extract_qhost "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    elif [[ "$text" == *"job-ID"* ]]; then
        local _out
        _out=$(_strat_sge_extract_qstat_table "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    fi

    echo "$result"
}

_strat_sge_extract_qstat_table () {
    local text="$1"
    local result=""
    local header_found=0
    local job_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        # Header: job-ID prior name user state submit/start queue slots ja-task-ID
        if [[ $header_found -eq 0 && "$_line" == *"job-ID"* ]]; then
            header_found=1
            continue
        fi

        # Skip separator line
        if [[ $header_found -eq 1 && "$_line" == *"------"* ]]; then
            continue
        fi

        # Data rows
        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -lt 5 ]] && continue

            job_num=$((job_num + 1))
            local prefix=""
            if [[ $job_num -gt 1 ]]; then
                prefix="job${job_num}."
            fi

            # Standard qstat columns: job-ID prior name user state submit/start queue slots
            result+="${prefix}job_id ${_fields[0]}"$'\n'
            [[ ${#_fields[@]} -ge 2 ]] && result+="${prefix}priority ${_fields[1]}"$'\n'
            [[ ${#_fields[@]} -ge 3 ]] && result+="${prefix}name ${_fields[2]}"$'\n'
            [[ ${#_fields[@]} -ge 4 ]] && result+="${prefix}user ${_fields[3]}"$'\n'
            [[ ${#_fields[@]} -ge 5 ]] && result+="${prefix}state ${_fields[4]}"$'\n'

            # Date fields may span two columns (MM/DD/YYYY HH:MM:SS)
            # Queue is after the date
            local qi
            for qi in "${!_fields[@]}"; do
                if [[ "${_fields[$qi]}" == *"@"* ]]; then
                    result+="${prefix}queue ${_fields[$qi]}"$'\n'
                    break
                fi
            done

            # Slots is typically the last or second-to-last field
            local last_idx=$(( ${#_fields[@]} - 1 ))
            local slots="${_fields[$last_idx]}"
            if [[ "$slots" =~ ^[0-9]+$ ]]; then
                result+="${prefix}slots ${slots}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}

_strat_sge_extract_qstat_detail () {
    local text="$1"
    local result=""
    local job_id="" job_name="" user="" state="" queue="" priority=""

    while IFS= read -r _line; do
        # job_number: 12345
        if [[ "$_line" == *"job_number"*":"* && -z "$job_id" ]]; then
            job_id="${_line#*: }"
            while [[ "$job_id" == " "* ]]; do job_id="${job_id# }"; done
        fi
        # job_name: test_job
        if [[ "$_line" == *"job_name"*":"* && -z "$job_name" ]]; then
            job_name="${_line#*: }"
            while [[ "$job_name" == " "* ]]; do job_name="${job_name# }"; done
        fi
        # owner: user1
        if [[ "$_line" == *"owner"*":"* && -z "$user" ]]; then
            user="${_line#*: }"
            while [[ "$user" == " "* ]]; do user="${user# }"; done
        fi
        # state: r (or scheduling info: ...)
        if [[ "$_line" == "state"*":"* || "$_line" == *" state"*":"* ]]; then
            if [[ -z "$state" ]]; then
                state="${_line#*: }"
                while [[ "$state" == " "* ]]; do state="${state# }"; done
            fi
        fi
        # hard_queue_list: all.q
        if [[ "$_line" == *"hard_queue_list"*":"* && -z "$queue" ]]; then
            queue="${_line#*: }"
            while [[ "$queue" == " "* ]]; do queue="${queue# }"; done
        fi
        # priority: 0.55500
        if [[ "$_line" == *"priority"*":"* && -z "$priority" ]]; then
            priority="${_line#*: }"
            while [[ "$priority" == " "* ]]; do priority="${priority# }"; done
        fi
    done <<< "$text"

    [[ -n "$job_id" ]] && result+="job_id ${job_id}"$'\n'
    [[ -n "$job_name" ]] && result+="name ${job_name}"$'\n'
    [[ -n "$user" ]] && result+="user ${user}"$'\n'
    [[ -n "$state" ]] && result+="state ${state}"$'\n'
    [[ -n "$queue" ]] && result+="queue ${queue}"$'\n'
    [[ -n "$priority" ]] && result+="priority ${priority}"$'\n'

    echo "$result"
}

_strat_sge_extract_qhost () {
    local text="$1"
    local result=""
    local header_found=0
    local col_names=()
    local host_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue

        # Header: HOSTNAME ARCH NCPU NSOC NCOR NTHR LOAD MEMTOT MEMUSE SWAPTO SWAPUS
        if [[ $header_found -eq 0 && "$_line" == *"HOSTNAME"* ]]; then
            header_found=1
            read -ra col_names <<< "$_line"
            continue
        fi

        # Skip separator
        if [[ $header_found -eq 1 && "$_line" == *"------"* ]]; then
            continue
        fi

        # Skip 'global' line
        if [[ $header_found -eq 1 && "$_line" == "global"* ]]; then
            continue
        fi

        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -eq 0 ]] && continue
            # Skip indented job lines
            [[ "$_line" == " "* || "$_line" == $'\t'* ]] && continue

            host_num=$((host_num + 1))
            local prefix=""
            if [[ $host_num -gt 1 ]]; then
                prefix="host${host_num}."
            fi

            local i
            for i in "${!col_names[@]}"; do
                local col="${col_names[$i]}"
                local val="${_fields[$i]:-}"
                [[ -z "$val" || "$val" == "-" ]] && continue
                case "$col" in
                    HOSTNAME) result+="${prefix}hostname ${val}"$'\n' ;;
                    ARCH)     result+="${prefix}arch ${val}"$'\n' ;;
                    NCPU)     result+="${prefix}ncpu ${val}"$'\n' ;;
                    NSOC)     result+="${prefix}nsockets ${val}"$'\n' ;;
                    NCOR)     result+="${prefix}ncores ${val}"$'\n' ;;
                    NTHR)     result+="${prefix}nthreads ${val}"$'\n' ;;
                    LOAD)     result+="${prefix}load ${val}"$'\n' ;;
                    MEMTOT)   result+="${prefix}mem_total ${val}"$'\n' ;;
                    MEMUSE)   result+="${prefix}mem_used ${val}"$'\n' ;;
                    SWAPTO)   result+="${prefix}swap_total ${val}"$'\n' ;;
                    SWAPUS)   result+="${prefix}swap_used ${val}"$'\n' ;;
                esac
            done
        fi
    done <<< "$text"

    echo "$result"
}
