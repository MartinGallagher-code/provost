#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: syslog
## Description: Extract fields from BSD/RFC 3164 syslog format log lines
## Version: 1.0
## Priority: 20
## Sample: samples/syslog/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # A syslog CAPTURE is syslog lines throughout — require a majority of
    # non-blank lines to open with the BSD timestamp (Mon DD HH:MM:SS).
    # A status block that merely EMBEDS a few journal lines (systemctl
    # status's log tail) is not a syslog capture and belongs to other
    # parsers.
    local line total=0 hits=0
    if (( ${#text} > _FR_BIG_BYTES )); then
        # BIG input: the same count in one awk pass (see _FR_BIG_BYTES)
        cat <<< "$text" | awk -v T=$(( 50 - ${_FR_SLACK:-0} )) '
            /[^ \t\n\v\f\r]/ {
                total++
                if ($0 ~ /^[ \t\n\v\f\r]*[A-Z][a-z][a-z] [ 0-9][ 0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] /) hits++
            }
            END { exit !(total > 0 && int(hits * 100 / total) >= T) }'
        return
    fi
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        total=$((total + 1))
        [[ "$line" =~ ^[[:space:]]*[A-Z][a-z]{2}\ [\ 0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\  ]] && hits=$((hits + 1))
    done
    [[ $total -gt 0 && $((hits * 100 / total)) -ge $(( 50 - ${_FR_SLACK:-0} )) ]]
}

strategy_extract () {
    local text="$1"
    local result=""
    local line_num=0

    if (( ${#text} > _FR_BIG_BYTES )); then
        # BIG input: the loop below in one awk pass, byte-identical output
        # (tokens split on blank runs as _fr_tok's default IFS does). A
        # matching line with fewer than 5 tokens makes the bash loop abort
        # under `set -u` (`${_arr[4]}` unbound) with NO output and status 1 —
        # the awk twin reports that the same way.
        local _sl_out
        _sl_out="$(cat <<< "$text" | awk '
            $0 == "" { next }
            $0 !~ /^[A-Z][a-z][a-z] [ 0-9][ 0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] / { next }
            {
                ln++; p = "line" ln
                printf "%s.timestamp %s\n", p, substr($0, 1, 15)
                s = $0; sub(/[ \t\n]+$/, "", s)
                n = split(s, a, /[ \t\n]+/)
                if (n < 5) { failed = 1; exit 1 }
                printf "%s.hostname %s\n", p, a[4]
                pp = a[5]; proc = pp
                i = index(proc, "["); if (i) proc = substr(proc, 1, i - 1)
                sub(/:$/, "", proc)
                pid = ""
                i = index(pp, "[")
                if (i && index(substr(pp, i + 1), "]")) {
                    pid = substr(pp, i + 1); pid = substr(pid, 1, index(pid, "]") - 1)
                }
                printf "%s.process %s\n", p, proc
                if (pid != "") printf "%s.pid %s\n", p, pid
                msg = ""
                for (k = 6; k <= n; k++) msg = (msg == "") ? a[k] : msg " " a[k]
                if (msg != "") printf "%s.message %s\n", p, msg
            }')" || return 1
        printf '%s\n' "$_sl_out"
        return 0
    fi

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        # Only process lines matching syslog format
        [[ "$line" =~ ^[A-Z][a-z]{2}\ [\ 0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\  ]] || continue

        line_num=$((line_num + 1))
        local prefix="line${line_num}"

        # Extract timestamp (first 15 chars: "Mon DD HH:MM:SS")
        local timestamp
        timestamp=$(_strat_syslog_get_timestamp "$line")
        result+="${prefix}.timestamp ${timestamp}"$'\n'

        # Extract hostname (word after timestamp)
        { _fr_tok "$line"; _arr=("${_FR_TOK[@]}"); }
        local hostname="${_arr[3]}"
        result+="${prefix}.hostname ${hostname}"$'\n'

        # Extract process and PID
        local process_part="${_arr[4]}"
        local process pid
        process="${process_part%%[*}"
        process="${process%:}"
        # Extract PID from brackets if present
        pid=""
        if [[ "$process_part" == *"["*"]"* ]]; then
            pid="${process_part#*[}"
            pid="${pid%%]*}"
        fi
        result+="${prefix}.process ${process}"$'\n'
        if [[ -n "$pid" ]]; then
            result+="${prefix}.pid ${pid}"$'\n'
        fi

        # Extract message (everything after process/pid field)
        local message
        message=$(_strat_syslog_get_message "$line")
        if [[ -n "$message" ]]; then
            result+="${prefix}.message ${message}"$'\n'
        fi

    done

    echo "$result"
}

_strat_syslog_get_timestamp () {
    local line="$1"
    # The caller only passes lines that open with the fixed-width 15-char
    # "Mon DD HH:MM:SS" stamp; emit it verbatim (a value keeps its spaces and
    # colons — the field stream splits on the FIRST space only).
    echo "${line:0:15}"
}

_strat_syslog_get_message () {
    local line="$1"
    # Message is everything after the 5th field's colon/bracket
    # Remove timestamp (3 fields), hostname (1 field), process[pid]: (1 field)
    { _fr_tok "$line"; _arr=("${_FR_TOK[@]}"); }
    # Reconstruct message from field 5 onwards
    local msg=""
    local i
    for ((i=5; i<${#_arr[@]}; i++)); do
        if [[ -z "$msg" ]]; then
            msg="${_arr[$i]}"
        else
            msg="${msg} ${_arr[$i]}"
        fi
    done
    # Also check if field 4 has trailing content after ":"
    local field4="${_arr[4]}"
    if [[ "$field4" == *":" ]]; then
        # Colon is at end, message starts at field 5 (already handled)
        :
    elif [[ "$field4" == *"]:" ]]; then
        # PID bracket + colon at end, message starts at field 5 (already handled)
        :
    fi
    echo "$msg"
}
