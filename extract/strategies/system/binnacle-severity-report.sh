#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: binnacle-severity-report
## Description: Extract findings (severity/title/detail) from binnacle-suite diagnostic reports (why-slow, resolve, during, skew, ...)
## Version: 1.0
## Priority: 12
## Sample: samples/binnacle-severity-report/basic.txt

# The binnacle sibling tools (why-slow, resolve, during, skew, ...) share one
# report shape:
#
#   <tool> -- <context>
#
#     VERDICT   <wrapped paragraph>
#
#     CRITICAL  <title>     <detail>
#     WARN      <title>     <detail>
#     ok        <comma-separated list, no detail>
#     skipped   <reason, no detail>
#
#     <tool-specific ALL-CAPS sections -- out of scope, not parsed>
#
#     WHAT TO DO NEXT
#       * ...
#
# Detection keys on the two distinctive, shape-defining markers: a "  VERDICT"
# line and at least one "  CRITICAL/WARN/INFO/ok/skipped" finding line.
#
# Extraction emits one row per finding line. title/detail split on the first
# run of 2+ spaces after the severity token (mirrors smartctl-selftest.sh's
# column-alignment technique); when there is no such run, the whole remainder
# is the title and detail is empty (the normal case for ok/skipped). A finding
# whose detail wraps onto a following, more deeply indented continuation line
# (no severity token) has that continuation appended to its detail. Parsing
# stops at the first ALL-CAPS section header (2-space indent, e.g. EVIDENCE,
# RESOLVERS, TIMELINE, WHAT TO DO NEXT) -- those sections are tool-specific
# and out of scope for this strategy.

_bsr_re_verdict='(^|'$'\n''  )VERDICT[[:space:]]'
_bsr_re_sev='(^|'$'\n''  )(CRITICAL|WARN|INFO|ok|skipped)[[:space:]]'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    [[ "$text" =~ $_bsr_re_verdict ]] || return 1
    [[ "$text" =~ $_bsr_re_sev ]] || return 1
    # Above csv's 90: a healthy-box report is mostly prose, and its `ok` line
    # lists the passing checks comma-separated across wrapped lines, which is
    # regular enough for the generic comma-consistency scan to claim the whole
    # report as CSV. Requiring BOTH a VERDICT block and a severity-label line
    # is far more specific than that heuristic, so this wins the tie.
    _STRATEGY_CONFIDENCE=92
    return 0
}

# Trim leading+trailing whitespace from $1, echo the result.
_bsr_trim () {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

strategy_extract () {
    local text="$1"
    local result="" n=0
    local tool="" context="" verdict="" cur_detail=""
    local state="pre_verdict"
    local line

    # Header: "<tool> -- <context>" is the first non-blank line.
    local first_line=""
    while IFS= read -r line; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        first_line="$line"
        break
    done <<< "$text"
    if [[ "$first_line" == *" -- "* ]]; then
        tool="${first_line%% -- *}"
        context="${first_line#* -- }"
    else
        tool="$first_line"
    fi
    tool="$(_bsr_trim "$tool")"
    context="$(_bsr_trim "$context")"

    local re_verdict_line='^  VERDICT[[:space:]]+(.*)$'
    local re_sev_line='^  (CRITICAL|WARN|INFO|ok|skipped)[[:space:]]*(.*)$'
    local re_section='^  [A-Z][A-Z]*([[:space:]]|$)'

    _bsr_flush_detail () {
        [[ $n -gt 0 ]] && result+="entry${n}.detail ${cur_detail}"$'\n'
    }

    while IFS= read -r line; do
        case "$state" in
            pre_verdict)
                if [[ "$line" =~ $re_verdict_line ]]; then
                    verdict="$(_bsr_trim "${BASH_REMATCH[1]}")"
                    state="verdict"
                fi
                ;;
            verdict)
                if [[ "${line}" != *[![:space:]]* ]]; then
                    state="findings"
                else
                    local t
                    t="$(_bsr_trim "$line")"
                    [[ -n "$verdict" ]] && verdict+=" "
                    verdict+="$t"
                fi
                ;;
            findings)
                [[ "${line}" != *[![:space:]]* ]] && continue
                if [[ "$line" =~ $re_sev_line ]]; then
                    _bsr_flush_detail
                    n=$((n + 1))
                    local sev="${BASH_REMATCH[1]}"
                    local rem
                    rem="$(_bsr_trim "${BASH_REMATCH[2]}")"
                    local title="$rem"
                    cur_detail=""
                    if [[ "$rem" == *"  "* ]]; then
                        title="${rem%%[[:space:]][[:space:]]*}"
                        local remainder="${rem:${#title}}"
                        cur_detail="$(_bsr_trim "$remainder")"
                    fi
                    result+="entry${n}.severity ${sev}"$'\n'
                    result+="entry${n}.title ${title}"$'\n'
                elif [[ "$line" =~ $re_section ]]; then
                    state="done"
                    break
                elif [[ $n -gt 0 ]]; then
                    local t
                    t="$(_bsr_trim "$line")"
                    if [[ -n "$cur_detail" ]]; then
                        cur_detail+=" $t"
                    else
                        cur_detail="$t"
                    fi
                fi
                ;;
            done)
                break
                ;;
        esac
    done <<< "$text"
    _bsr_flush_detail

    result+="tool ${tool}"$'\n'
    result+="context ${context}"$'\n'
    result+="verdict ${verdict}"$'\n'
    result+="total_entries ${n}"$'\n'
    echo "$result"
}
