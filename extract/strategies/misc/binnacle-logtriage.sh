#!/bin/bash
## Name: binnacle-logtriage
## Description: Extract ranked template entries from binnacle's `logtriage` output (score, severity, count, template text, first/last seen, burst; source file + totals broadcast)
## Version: 1.0
## Priority: 20
## Sample: samples/binnacle-logtriage/basic.txt

# logtriage clusters a log file into templates and prints a ranked list of the
# ones that matter. Each ranked entry spans several lines:
#   #1  score 8.4   NEW   sev=error   1,204x   <sparkline>
#       <template text with placeholders>
#       first HH:MM:SS   last HH:MM:SS   burst Nx
#       not seen before HH:MM:SS; N since        (optional)
# `NEW`, `burst Nx`, and the "not seen before" line are all optional per
# entry. Extraction stops at the "WHAT TO DO NEXT" section.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    [[ "$text" == "logtriage --"* ]] || return 1
    local re_rank='(^|'$'\n'')[[:space:]]*#[0-9]+[[:space:]]+score[[:space:]]+[0-9]+(\.[0-9]+)?'
    [[ "$text" =~ $re_rank ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" n=0
    local source="" total_lines="" total_templates=""

    local re_header='^logtriage --[[:space:]]+([^,]+),[[:space:]]+([^[:space:]]+)[[:space:]]+lines,[[:space:]]+([0-9,]+)[[:space:]]+templates'
    local re_rank='^[[:space:]]*#([0-9]+)[[:space:]]+score[[:space:]]+([0-9]+(\.[0-9]+)?)[[:space:]]+(.*)$'
    local re_sev='sev=([^[:space:]]+)'
    local re_new='(^|[[:space:]])NEW([[:space:]]|$)'
    local re_count='([0-9][0-9,]*)x([[:space:]]|$)'
    local re_firstlast='^[[:space:]]*first[[:space:]]+([0-9:]+)[[:space:]]+last[[:space:]]+([0-9:]+)([[:space:]]+burst[[:space:]]+([0-9,]+)x)?'

    # State: what we expect the next non-blank line to be, per entry.
    local expect="header"   # header -> template -> firstlast -> done

    while IFS= read -r line; do
        [[ "$line" == *"WHAT TO DO NEXT"* ]] && break

        if [[ -z "$source" && "$line" =~ $re_header ]]; then
            source="${BASH_REMATCH[1]}"
            total_lines="${BASH_REMATCH[2]}"
            total_templates="${BASH_REMATCH[3]}"
            continue
        fi

        if [[ "$line" =~ $re_rank ]]; then
            n=$((n + 1))
            local p="entry${n}."
            local rest="${BASH_REMATCH[4]}"

            result+="${p}rank ${BASH_REMATCH[1]}"$'\n'
            result+="${p}score ${BASH_REMATCH[2]}"$'\n'

            if [[ "$rest" =~ $re_new ]]; then
                result+="${p}is_new 1"$'\n'
            else
                result+="${p}is_new 0"$'\n'
            fi

            if [[ "$rest" =~ $re_sev ]]; then
                result+="${p}severity ${BASH_REMATCH[1]}"$'\n'
            else
                result+="${p}severity "$'\n'
            fi

            if [[ "$rest" =~ $re_count ]]; then
                result+="${p}count ${BASH_REMATCH[1]}"$'\n'
            else
                result+="${p}count "$'\n'
            fi

            expect="template"
            continue
        fi

        if [[ "$expect" == "template" ]]; then
            [[ -z "${line//[[:space:]]/}" ]] && continue
            local template="$line"
            # Trim leading/trailing whitespace.
            template="${template#"${template%%[![:space:]]*}"}"
            template="${template%"${template##*[![:space:]]}"}"
            result+="entry${n}.template ${template}"$'\n'
            expect="firstlast"
            continue
        fi

        if [[ "$expect" == "firstlast" ]]; then
            [[ -z "${line//[[:space:]]/}" ]] && continue
            if [[ "$line" =~ $re_firstlast ]]; then
                result+="entry${n}.first_seen ${BASH_REMATCH[1]}"$'\n'
                result+="entry${n}.last_seen ${BASH_REMATCH[2]}"$'\n'
                result+="entry${n}.burst ${BASH_REMATCH[4]}"$'\n'
            fi
            expect="done"
            continue
        fi
    done <<< "$text"

    [[ -n "$source" ]] && result+="source ${source}"$'\n'
    [[ -n "$total_lines" ]] && result+="total_lines ${total_lines}"$'\n'
    [[ -n "$total_templates" ]] && result+="total_templates ${total_templates}"$'\n'
    result+="total_entries ${n}"$'\n'
    echo "$result"
}
