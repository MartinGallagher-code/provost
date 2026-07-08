#!/bin/bash
## Name: iperf3-intervals
## Description: Extract per-interval rows from `iperf3 -c` client output
## Version: 1.0
## Priority: 20
## Technique: yes
## Sample: samples/iperf3-intervals/basic.txt

# `iperf3 -c` prints a "Connecting to host" banner, a stream header, then one row
# per measurement interval:
#   [  5]   0.00-1.00   sec   112 MBytes   940 Mbits/sec    0    412 KBytes
# followed by a "- - -" separator and a summary block (sender/receiver rows).
# Signature: the "Bitrate" + "Interval" + "Transfer" column labels. Emit ONE
# record per interval row; skip the connect/header lines, the separator, and the
# sender/receiver summary rows.

_iperf3_sanitize () {
    local v="$1"
    v="${v//$'\t'/_}"
    printf '%s' "$v"
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # NB: iperf3 rows are prefixed with "[  5]" etc, so the generic _is_json
    # (which flags any text beginning with '[') would wrongly decline it — the
    # Bitrate/Interval/Transfer signature below is specific enough on its own.
    [[ "$text" == *Bitrate* ]]  || return 1
    [[ "$text" == *Interval* ]] || return 1
    [[ "$text" == *Transfer* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line rest
    local -a t=()
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" == "["* ]] || continue                          # interval/summary rows
        [[ "$line" == *sender* || "$line" == *receiver* ]] && continue   # skip summary
        rest="${line#*]}"                                          # drop "[  5]" stream id
        read -ra t <<< "$rest"
        [[ "${t[1]}" == "sec" ]] || continue                       # data rows only
        [[ ${#t[@]} -ge 9 ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.interval $(_iperf3_sanitize "${t[0]}")"$'\n'
        result+="entry${entry}.transfer $(_iperf3_sanitize "${t[2]}")"$'\n'
        result+="entry${entry}.transfer_unit $(_iperf3_sanitize "${t[3]}")"$'\n'
        result+="entry${entry}.bitrate $(_iperf3_sanitize "${t[4]}")"$'\n'
        result+="entry${entry}.bitrate_unit $(_iperf3_sanitize "${t[5]}")"$'\n'
        result+="entry${entry}.retr $(_iperf3_sanitize "${t[6]}")"$'\n'
        result+="entry${entry}.cwnd $(_iperf3_sanitize "${t[7]}")"$'\n'
        result+="entry${entry}.cwnd_unit $(_iperf3_sanitize "${t[8]}")"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
