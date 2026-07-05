#!/bin/bash
## Name: htcondor
## Description: Extract job and machine information from HTCondor output (condor_q, condor_status, classad key=value)
## Version: 1.0
## Priority: 15
## Sample: samples/htcondor/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Primary: condor commands
    if [[ "$text" == *"condor_q"* || "$text" == *"condor_status"* ]]; then
        return 0
    fi
    # HTCondor keyword
    if [[ "$text" == *"HTCondor"* ]]; then
        return 0
    fi
    # Schedd header line
    if [[ "$text" == *"Schedd"* && "$text" == *"OWNER"* ]]; then
        return 0
    fi
    # condor_q table header
    if [[ "$text" == *"OWNER"* && "$text" == *"SUBMITTED"* && "$text" == *"RUN_TIME"* ]]; then
        if [[ "$text" == *"ST"* && "$text" == *"CMD"* ]]; then
            return 0
        fi
    fi
    # condor_status table header
    if [[ "$text" == *"OpSys"* && "$text" == *"Arch"* && "$text" == *"Activity"* ]]; then
        return 0
    fi
    # classad format with ClusterId or Owner
    if [[ "$text" == *"ClusterId"* ]]; then
        return 0
    fi
    # Summary line pattern: "N jobs; N idle, N running, N held"
    if [[ "$text" == *"jobs;"* && "$text" == *"idle"* && "$text" == *"running"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # condor_q table
    if [[ "$text" == *"OWNER"* && "$text" == *"RUN_TIME"* && "$text" == *"ST"* ]]; then
        local _out
        _out=$(_strat_htcondor_extract_condor_q "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    fi

    # condor_status table
    if [[ "$text" == *"OpSys"* && "$text" == *"Arch"* && "$text" == *"Activity"* ]]; then
        local _out
        _out=$(_strat_htcondor_extract_condor_status "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    fi

    # Summary line: "N jobs; N idle, N running, N held"
    if [[ "$text" == *"jobs;"* ]]; then
        local _out
        _out=$(_strat_htcondor_extract_summary "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    fi

    # classad format: Key = Value
    if [[ "$text" == *"ClusterId"* && "$text" == *"Owner"* ]]; then
        local _out
        _out=$(_strat_htcondor_extract_classad "$text")
        [[ -n "$_out" ]] && result+="${_out}"
    fi

    echo "$result"
}

_strat_htcondor_extract_condor_q () {
    local text="$1"
    local result=""
    local header_found=0
    local job_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        [[ "$_line" == "\$"* ]] && continue
        [[ "$_line" == "--"* ]] && continue

        # Detect header line (ID OWNER SUBMITTED ...)
        if [[ $header_found -eq 0 && "$_line" == *"ID"* && "$_line" == *"OWNER"* && "$_line" == *"RUN_TIME"* ]]; then
            header_found=1
            continue
        fi

        # Stop at summary line
        if [[ $header_found -eq 1 && "$_line" == *"jobs;"* ]]; then
            break
        fi

        # condor_q data lines: ID OWNER DATE TIME RUN_TIME ST PRI SIZE CMD
        # SUBMITTED is 2 tokens (date time), so we parse positionally with that offset
        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -lt 9 ]] && continue

            job_num=$((job_num + 1))
            local prefix=""
            if [[ $job_num -gt 1 ]]; then
                prefix="job${job_num}."
            fi

            result+="${prefix}cluster_id ${_fields[0]}"$'\n'
            result+="${prefix}owner ${_fields[1]}"$'\n'
            result+="${prefix}submitted ${_fields[2]} ${_fields[3]}"$'\n'
            result+="${prefix}run_time ${_fields[4]}"$'\n'
            result+="${prefix}status ${_fields[5]}"$'\n'
            result+="${prefix}priority ${_fields[6]}"$'\n'
            result+="${prefix}size ${_fields[7]}"$'\n'
            result+="${prefix}cmd ${_fields[8]}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}

_strat_htcondor_extract_condor_status () {
    local text="$1"
    local result=""
    local header_found=0
    local col_names=()
    local slot_num=0

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        [[ "$_line" == "\$"* ]] && continue

        if [[ $header_found -eq 0 && "$_line" == *"Name"* && "$_line" == *"OpSys"* && "$_line" == *"Activity"* ]]; then
            header_found=1
            read -ra col_names <<< "$_line"
            continue
        fi

        # Stop at summary table (starts with whitespace + "Total")
        if [[ $header_found -eq 1 && "$_line" == *"Total"* && "$_line" == *"Owner"* && "$_line" == *"Claimed"* ]]; then
            break
        fi

        if [[ $header_found -eq 1 ]]; then
            read -ra _fields <<< "$_line"
            [[ ${#_fields[@]} -eq 0 ]] && continue

            slot_num=$((slot_num + 1))
            local prefix="slot${slot_num}."

            local i
            for i in "${!col_names[@]}"; do
                local col="${col_names[$i]}"
                local val="${_fields[$i]:-}"
                [[ -z "$val" ]] && continue
                case "$col" in
                    Name)       result+="${prefix}name ${val}"$'\n' ;;
                    OpSys)      result+="${prefix}opsys ${val}"$'\n' ;;
                    Arch)       result+="${prefix}arch ${val}"$'\n' ;;
                    State)      result+="${prefix}state ${val}"$'\n' ;;
                    Activity)   result+="${prefix}activity ${val}"$'\n' ;;
                    LoadAv)     result+="${prefix}loadav ${val}"$'\n' ;;
                    Mem)        result+="${prefix}mem ${val}"$'\n' ;;
                    ActvtyTime) result+="${prefix}activity_time ${val}"$'\n' ;;
                esac
            done
        fi
    done <<< "$text"

    echo "$result"
}

_strat_htcondor_extract_summary () {
    local text="$1"
    local result=""

    while IFS= read -r _line; do
        # Match: "5 jobs; 1 idle, 3 running, 1 held"
        if [[ "$_line" == *"jobs;"* ]]; then
            local total_jobs="" idle="" running="" held=""

            # Extract total jobs
            if [[ "$_line" =~ ([0-9]+)\ jobs ]]; then
                total_jobs="${BASH_REMATCH[1]}"
            fi
            # Extract idle
            if [[ "$_line" =~ ([0-9]+)\ idle ]]; then
                idle="${BASH_REMATCH[1]}"
            fi
            # Extract running
            if [[ "$_line" =~ ([0-9]+)\ running ]]; then
                running="${BASH_REMATCH[1]}"
            fi
            # Extract held
            if [[ "$_line" =~ ([0-9]+)\ held ]]; then
                held="${BASH_REMATCH[1]}"
            fi

            [[ -n "$total_jobs" ]] && result+="total_jobs ${total_jobs}"$'\n'
            [[ -n "$idle" ]] && result+="idle ${idle}"$'\n'
            [[ -n "$running" ]] && result+="running ${running}"$'\n'
            [[ -n "$held" ]] && result+="held ${held}"$'\n'
            break
        fi
    done <<< "$text"

    echo "$result"
}

_strat_htcondor_extract_classad () {
    local text="$1"
    local result=""

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        [[ "$_line" == "\$"* ]] && continue

        # Parse "Key = Value" classad format
        if [[ "$_line" == *" = "* ]]; then
            local key="${_line%% = *}"
            local val="${_line#* = }"
            # Strip leading/trailing whitespace
            key="${key## }"
            key="${key%% }"
            val="${val## }"
            val="${val%% }"
            # Strip quotes from string values
            if [[ "$val" == \"*\" ]]; then
                val="${val#\"}"
                val="${val%\"}"
            fi
            [[ -z "$key" || -z "$val" ]] && continue
            case "$key" in
                ClusterId)      result+="classad.cluster_id ${val}"$'\n' ;;
                Owner)          result+="classad.owner ${val}"$'\n' ;;
                JobStatus)      result+="classad.job_status ${val}"$'\n' ;;
                Cmd)            result+="classad.cmd ${val}"$'\n' ;;
                RequestMemory)  result+="classad.request_memory ${val}"$'\n' ;;
                RequestCpus)    result+="classad.request_cpus ${val}"$'\n' ;;
                RequestDisk)    result+="classad.request_disk ${val}"$'\n' ;;
                RemoteHost)     result+="classad.remote_host ${val}"$'\n' ;;
                ImageSize)      result+="classad.image_size ${val}"$'\n' ;;
                DiskUsage)      result+="classad.disk_usage ${val}"$'\n' ;;
            esac
        fi
    done <<< "$text"

    echo "$result"
}
