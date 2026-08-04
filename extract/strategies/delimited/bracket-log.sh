#!/bin/bash
## Name: bracket-log
## Description: Log lines prefixed with a [bracketed] timestamp/tag (dmesg, kernel ring buffer, many app logs); traceback continuations absorbed as detail
## Version: 1.1
## Priority: 48
## Sample: samples/bracket-log/dmesg.txt

# Matches lines shaped like `[<tag>] <message>` — dmesg / kernel ring buffer
# (`[    0.000000] Linux version …`), and app logs that lead with a bracketed
# timestamp or level. Tidied to one row per line: (timestamp, message).
#
# v1.1 — CONTINUATION runs. A log may interleave a multi-line block that
# belongs to the entry above it — the defining case is a Python traceback
# under an ERROR line:
#
#   [2026-07-11 04:20:05] ERROR task failed id=t-5521
#   Traceback (most recent call last):
#     File "/app/worker.py", line 88, in run
#       result = handler(payload)
#   KeyError: 'key'
#   [2026-07-11 04:20:06] INFO worker retry id=t-5521 attempt=2
#
# Such a run used to break the 80% bracketed-majority gate and the whole input
# fell to text-lines. Now: a contiguous non-bracketed run whose FIRST line is
# indented or ends in `:` (`Traceback (most recent call last):`) is a
# CONTINUATION of the entry above — absorbed into that entry's `detail`
# column, lines joined with `; `. Detection accepts either the classic 80%
# majority (pure logs — unchanged output), or >=3 bracketed lines starting at
# line 1 where EVERY non-bracketed run is continuation-shaped. A report that
# merely opens with a [tag] line keeps falling through: its table/prose lines
# are unindented and not colon-terminated.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local nonblank=0 bracketed=0 _l
    local first_br=-1 runs_ok=1 in_run=0
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        nonblank=$((nonblank + 1))
        # leading (optional ws) '[', some content, ']', then a space + message
        if [[ "$_l" =~ ^[[:space:]]*\[[^]]+\][[:space:]]+[^[:space:]] ]]; then
            bracketed=$((bracketed + 1)); in_run=0
            [[ $first_br -lt 0 ]] && first_br=$nonblank
        else
            # First line of a non-bracketed run must be continuation-shaped:
            # indented, or ending in ':'.
            if [[ $in_run -eq 0 ]]; then
                [[ "$_l" == [' '$'\t']* || "$_l" == *: ]] || runs_ok=0
                in_run=1
            fi
        fi
        [[ $nonblank -ge 40 ]] && break
    done <<< "$text"

    [[ $nonblank -lt 2 ]] && return 1
    if [[ $(( bracketed * 100 / nonblank )) -ge 80 ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    # Continuation arm: log starts bracketed, >=3 bracketed entries, every
    # non-bracketed run opens continuation-shaped.
    if [[ $first_br -eq 1 && $bracketed -ge 3 && $runs_ok -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 _l detail=""
    # flush the pending detail of the previous entry
    _bl_flush () {
        if [[ -n "$detail" && $entry -gt 0 ]]; then
            result+="entry${entry}.detail ${detail}"$'\n'
        fi
        detail=""
    }
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        if [[ ! "$_l" =~ ^[[:space:]]*\[[^]]+\][[:space:]]+[^[:space:]] ]]; then
            # A BARE `[tag]` line (no message) is an empty log line — chrome,
            # not a continuation; skip it (mvn's lone `[INFO]` spacers).
            [[ "$_l" =~ ^[[:space:]]*\[[^]]+\][[:space:]]*$ ]] && continue
            # continuation line -> the previous entry's detail (joined `; `)
            [[ $entry -gt 0 ]] || continue
            local c="$_l"
            c="${c#"${c%%[![:space:]]*}"}"; c="${c%"${c##*[![:space:]]}"}"
            [[ -n "$c" ]] && detail+="${detail:+; }$c"
            continue
        fi
        _bl_flush

        # timestamp/tag = text between the first '[' and ']'
        local ts="${_l#*[}"; ts="${ts%%]*}"
        # message = everything after the first ']'
        local msg="${_l#*]}"
        # trim surrounding whitespace
        ts="${ts#"${ts%%[![:space:]]*}"}"; ts="${ts%"${ts##*[![:space:]]}"}"
        msg="${msg#"${msg%%[![:space:]]*}"}"; msg="${msg%"${msg##*[![:space:]]}"}"

        entry=$((entry + 1))
        result+="entry${entry}.timestamp ${ts}"$'\n'
        [[ -n "$msg" ]] && result+="entry${entry}.message ${msg}"$'\n'
    done <<< "$text"
    _bl_flush

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
