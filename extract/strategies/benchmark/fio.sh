#!/bin/bash
## Name: fio
## Description: Extract IOPS, bandwidth, and latency from fio text output
## Version: 1.0
## Priority: 10
## Sample: samples/fio/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    # Reject JSON output -- let the json strategy handle that
    _is_json "$1" && return 1
    # fio version string: "fio-3.x" or "fio-2.x"
    if [[ "$text" =~ ^fio-[0-9] ]]; then
        return 0
    fi
    # Job output: "Starting N process" + IOPS/BW indicators
    if [[ "$text" == *"Starting"*"process"* ]] && \
       [[ "$text" == *[Ii][Oo][Pp][Ss]* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local job_num=0
    local current_job=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Job name line: "jobname: (groupid=0, jobs=1): ..."
        if [[ "$line" =~ ^[A-Za-z0-9_-]+:.*groupid= ]]; then
            job_num=$((job_num + 1))
            current_job="${line%%:*}"
            local prefix=""
            if [[ $job_num -gt 1 ]]; then
                prefix="job${job_num}."
            fi
            result+="${prefix}name ${current_job}"$'\n'
            continue
        fi

        # Determine prefix for multi-job output
        local prefix=""
        if [[ $job_num -gt 1 ]]; then
            prefix="job${job_num}."
        fi

        # Read line: "read: IOPS=12.3k, BW=48.1MiB/s (50.5MB/s)"
        if [[ "$line" =~ ^[[:space:]]*read:.*IOPS ]]; then
            local iops bw
            iops=$(_strat_fio_extract_iops "$line")
            bw=$(_strat_fio_extract_bw "$line")
            [[ -n "$iops" ]] && result+="${prefix}read_iops ${iops}"$'\n'
            [[ -n "$bw" ]] && result+="${prefix}read_bw ${bw}"$'\n'
            continue
        fi

        # Write line: "write: IOPS=4567, BW=17.8MiB/s (18.7MB/s)"
        if [[ "$line" =~ ^[[:space:]]*write:.*IOPS ]]; then
            local iops bw
            iops=$(_strat_fio_extract_iops "$line")
            bw=$(_strat_fio_extract_bw "$line")
            [[ -n "$iops" ]] && result+="${prefix}write_iops ${iops}"$'\n'
            [[ -n "$bw" ]] && result+="${prefix}write_bw ${bw}"$'\n'
            continue
        fi

        # Latency lines: "lat (usec): min=1, max=5000, avg=250.00, stdev=45.67"
        # or: "lat (msec): min=1, max=50, avg=25.00, stdev=4.56"
        if [[ "$line" =~ ^[[:space:]]*lat[[:space:]]*\( ]]; then
            local lat_unit="" lat_avg=""
            # Extract unit from parentheses
            local _lat_re='lat[[:space:]]*\(([^)]*)\)'
            if [[ "$line" =~ $_lat_re ]]; then
                lat_unit="${BASH_REMATCH[1]}"
            fi
            # Extract avg= value
            if [[ "$line" =~ avg=[[:space:]]*([^,]*) ]]; then
                lat_avg="${BASH_REMATCH[1]}"
            fi
            if [[ -n "$lat_avg" && -n "$lat_unit" ]]; then
                # Determine if read or write context by looking at recent output
                result+="${prefix}lat_avg ${lat_avg}_${lat_unit}"$'\n'
            fi
            continue
        fi

        # clat percentiles: "clat percentiles (usec):"
        # followed by lines like: "| 99.00th=[ 1234]"
        if [[ "$line" =~ 99\.00th|99\.0th ]]; then
            local p99=""
            # Extract value from 99.00th=[  1234] or 99.0th=[1234]
            if [[ "$line" =~ 99[.0]*th=\[[[:space:]]*([0-9]+) ]]; then
                p99="${BASH_REMATCH[1]}"
            fi
            [[ -n "$p99" ]] && result+="${prefix}lat_p99 ${p99}"$'\n'
            continue
        fi

        # IO depths line: "IO depths    : 1=100.0%"
        if [[ "$line" == *"IO depths"* ]]; then
            local _after="${line##*: }"
            local depth="${_after%%=*}"
            [[ -n "$depth" ]] && result+="${prefix}io_depth ${depth}"$'\n'
            continue
        fi

        # Aggregate bandwidth: "IOPS=12.3k, BW=48.1MiB/s" on run status lines
        if [[ "$line" =~ ^Run\ status ]]; then
            continue
        fi

        # Disk stats or summary bandwidth: "READ: bw=48.1MiB/s ..."
        if [[ "$line" =~ ^[[:space:]]*READ: ]]; then
            local bw="" iops=""
            local _bw_re='bw=([^[:space:],(]+)'
            if [[ "$line" =~ $_bw_re ]]; then
                bw="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ iops=([^,]*) ]]; then
                iops="${BASH_REMATCH[1]}"
            fi
            [[ -n "$bw" ]] && result+="summary_read_bw ${bw}"$'\n'
            [[ -n "$iops" ]] && result+="summary_read_iops ${iops}"$'\n'
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*WRITE: ]]; then
            local bw="" iops=""
            local _bw_re='bw=([^[:space:],(]+)'
            if [[ "$line" =~ $_bw_re ]]; then
                bw="${BASH_REMATCH[1]}"
            fi
            if [[ "$line" =~ iops=([^,]*) ]]; then
                iops="${BASH_REMATCH[1]}"
            fi
            [[ -n "$bw" ]] && result+="summary_write_bw ${bw}"$'\n'
            [[ -n "$iops" ]] && result+="summary_write_iops ${iops}"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}

_strat_fio_extract_iops () {
    local line="$1"
    # Extract value after "IOPS=" up to comma
    if [[ "$line" =~ IOPS=([^,]*) ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

_strat_fio_extract_bw () {
    local line="$1"
    # Extract value after "BW=" up to space or open paren
    local _BW_re='BW=([^[:space:],(]+)'
    if [[ "$line" =~ $_BW_re ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}
