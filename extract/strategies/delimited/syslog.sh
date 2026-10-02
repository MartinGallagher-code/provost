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
    # An INDENTED line directly under a syslog line (or under another such
    # continuation) is that message continued — a Python traceback, a
    # wrapped stack — and is part of the record, not a separate line to
    # count (no blank line in between).
    local line total=0 hits=0 prev=0
    if (( ${#text} > _FR_BIG_BYTES )); then
        # BIG input: the same count in one awk pass (see _FR_BIG_BYTES)
        cat <<< "$text" | awk -v T=$(( 50 - ${_FR_SLACK:-0} )) '
            $0 !~ /[^ \t\n\v\f\r]/ { prev = 0; next }
            /^[ \t\n\v\f\r]*[A-Z][a-z][a-z] [ 0-9][ 0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] / { total++; hits++; prev = 1; next }
            prev && /^[ \t]/ { next }
            { total++; prev = 0 }
            END { exit !(total > 0 && int(hits * 100 / total) >= T) }'
        return
    fi
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && { prev=0; continue; }
        if [[ "$line" =~ ^[[:space:]]*[A-Z][a-z]{2}\ [\ 0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\  ]]; then
            total=$((total + 1)); hits=$((hits + 1)); prev=1; continue
        fi
        [[ $prev -eq 1 && "$line" == [' 	']* ]] && continue
        total=$((total + 1)); prev=0
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
            function flush() { if (msg != "") printf "%s.message %s\n", p, msg; msg = "" }
            $0 !~ /[^ \t\n\v\f\r]/ { chain = 0; next }
            $0 !~ /^[A-Z][a-z][a-z] [ 0-9][ 0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9] / {
                if (chain && $0 ~ /^[ \t]/) {
                    s = $0; sub(/^[ \t\n]+/, "", s); sub(/[ \t\n]+$/, "", s)
                    n = split(s, a, /[ \t\n]+/)
                    for (k = 1; k <= n; k++) msg = (msg == "") ? a[k] : msg " " a[k]
                } else chain = 0
                next
            }
            {
                flush(); chain = 1
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
            }
            END { if (!failed) flush() }')" || return 1
        printf '%s\n' "$_sl_out"
        return 0
    fi

    # The message is held until the record ends, so indented continuation
    # lines (see strategy_detect) can be appended to it, space-joined.
    local _sl_msg="" _sl_chain=0 prefix="" _sl_t
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && { _sl_chain=0; continue; }
        # Only process lines matching syslog format
        if [[ ! "$line" =~ ^[A-Z][a-z]{2}\ [\ 0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\  ]]; then
            if [[ $_sl_chain -eq 1 && "$line" == [' 	']* ]]; then
                _fr_tok "$line"
                for _sl_t in "${_FR_TOK[@]}"; do
                    [[ -z "$_sl_msg" ]] && _sl_msg="$_sl_t" || _sl_msg+=" $_sl_t"
                done
            else
                _sl_chain=0
            fi
            continue
        fi
        [[ -n "$_sl_msg" ]] && result+="${prefix}.message ${_sl_msg}"$'\n'
        _sl_msg=""; _sl_chain=1

        line_num=$((line_num + 1))
        prefix="line${line_num}"

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
        _sl_msg="$message"

    done
    [[ -n "$_sl_msg" ]] && result+="${prefix}.message ${_sl_msg}"$'\n'

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
