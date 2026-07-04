#!/bin/bash
## Name: mpi-profile
## Description: Extract MPI profiling data from mpiP summaries and Intel MPI statistics
## Version: 1.0
## Priority: 15
## Sample: samples/mpi-profile/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # mpiP output
    if [[ "$text" == *"mpiP"* ]]; then
        if [[ "$text" == *"MPI_"* || "$text" == *"Comm_size"* ]]; then
            return 0
        fi
    fi

    # Intel MPI statistics
    if [[ "$text" == *"MPI Statistics"* ]]; then
        return 0
    fi

    # Generic MPI profiling with function breakdown
    if [[ "$text" == *"Message Coverage"* && "$text" == *"MPI_"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local in_callsite_table=0
    local func_count=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # mpiP header line: "@ mpiP" or "mpiP"
        if [[ "$line" =~ ^@?[[:space:]]*mpiP[[:space:]]*$ ]]; then
            result+="mpi_profiler mpiP"$'\n'
            continue
        fi
        # mpiP inline version: "mpiP v3.5"
        if [[ "$line" =~ mpiP[[:space:]]*v?([0-9]+\.[0-9]+[0-9.]*) ]]; then
            result+="mpi_profiler mpiP"$'\n'
            result+="mpi_profiler_version ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        # Standalone version line: "@ Version : 3.5"
        if [[ "$line" =~ ^@[[:space:]]+Version[[:space:]]*[:=][[:space:]]*([0-9]+\.[0-9]+[0-9.]*) ]]; then
            result+="mpi_profiler_version ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Comm size / number of ranks
        if [[ "$line" =~ Comm_size[[:space:]]*[:=][[:space:]]*([0-9]+) ]]; then
            result+="comm_size ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        if [[ "$line" =~ "MPI tasks"[[:space:]]*[:=][[:space:]]*([0-9]+) ]]; then
            result+="comm_size ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # MPI version string
        if [[ "$line" =~ "MPI Version"[[:space:]]*[:=][[:space:]]*(.*) ]]; then
            result+="mpi_version ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Total application time / wall clock
        # Handles: "App Time (s) : 120.5", "App Time: 120.5", "Wall Clock = 120.5"
        if [[ "$line" =~ [Aa]pp[[:space:]]+[Tt]ime[^:=]*[:=][[:space:]]*([0-9]+\.?[0-9]*) ]]; then
            result+="total_time ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        if [[ "$line" =~ [Ww]all[[:space:]]*[Cc]lock[^:=]*[:=][[:space:]]*([0-9]+\.?[0-9]*) ]]; then
            result+="total_time ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # MPI time: "MPI Time (s) : 45.2"
        if [[ "$line" =~ MPI[[:space:]]+[Tt]ime[^:=]*[:=][[:space:]]*([0-9]+\.?[0-9]*) ]]; then
            result+="mpi_time ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # MPI percentage: "MPI % : 37.5" or "MPI Percent : 37.5"
        if [[ "$line" =~ MPI[[:space:]]+%[^:=]*[:=][[:space:]]*([0-9]+\.?[0-9]*) ]]; then
            result+="mpi_percent ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        if [[ "$line" =~ MPI[[:space:]]+[Pp]ercent[^:=]*[:=][[:space:]]*([0-9]+\.?[0-9]*) ]]; then
            result+="mpi_percent ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # mpiP callsite summary table rows
        # Format: MPI_Function  Site  Time  App%  MPI%
        if [[ "$line" == *"@--- Callsite"* ]]; then
            in_callsite_table=1
            func_count=0
            continue
        fi
        if [[ $in_callsite_table -eq 1 && "$line" == *"---@"* ]]; then
            in_callsite_table=0
            continue
        fi
        if [[ $in_callsite_table -eq 1 ]]; then
            _strat_mpi_profile_parse_callsite "$line"
            continue
        fi

        # Aggregate function summary lines (mpiP style)
        # Format: MPI_Bcast   23.45   12.3
        if [[ "$line" =~ ^[[:space:]]*(MPI_[A-Za-z_]+)[[:space:]]+([0-9]+\.?[0-9]*)[[:space:]]+([0-9]+\.?[0-9]*) ]]; then
            local func="${BASH_REMATCH[1]}"
            local ftime="${BASH_REMATCH[2]}"
            local fpct="${BASH_REMATCH[3]}"
            func_count=$((func_count + 1))
            result+="func.${func_count}.name ${func}"$'\n'
            result+="func.${func_count}.time ${ftime}"$'\n'
            result+="func.${func_count}.percent ${fpct}"$'\n'
            continue
        fi

    done <<< "$text"

    echo "$result"
}

_strat_mpi_profile_parse_callsite () {
    local line="$1"

    # Skip header/separator lines
    [[ "$line" == *"---"* ]] && return
    [[ "$line" == *"Name"* && "$line" == *"Site"* ]] && return
    [[ "$line" =~ ^[[:space:]]*$ ]] && return

    # Parse: MPI_Bcast  1  0.234  12.5  34.2
    if [[ "$line" =~ ^[[:space:]]*(MPI_[A-Za-z_]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+\.?[0-9]*)[[:space:]]+([0-9]+\.?[0-9]*) ]]; then
        func_count=$((func_count + 1))
        result+="callsite.${func_count}.name ${BASH_REMATCH[1]}"$'\n'
        result+="callsite.${func_count}.site ${BASH_REMATCH[2]}"$'\n'
        result+="callsite.${func_count}.time ${BASH_REMATCH[3]}"$'\n'
        result+="callsite.${func_count}.percent ${BASH_REMATCH[4]}"$'\n'
    fi
}
