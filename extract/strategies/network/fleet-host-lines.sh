#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: fleet-host-lines
## Description: Extract per-host/per-check rows from fleet-orchestrator output ([tool] section headers + indented two-column host lines, e.g. mx/netmesh status|doctor|run)
## Version: 1.0
## Priority: 41
## Sample: samples/fleet-host-lines/basic.txt

# Fleet orchestrators (`mx`, `netmesh`, ...) share one output shape across all
# of their subcommands (status, start, stop, clean, collect, logs, doctor,
# run): a `[tool] <label>` section header, then indented two-column lines whose
# first column is space-padded to the widest name, then an optional
# `[tool] FAILED on N/M hosts: <names>` footer. Blank lines separate sections:
#
#   [netmesh] local checks
#     python           3.11.15
#     path-MTU probing supported (IP_MTU_DISCOVER accepted)
#     agent file       /workspace/.../netmesh.py
#
#   [netmesh] remote checks on 2 hosts
#     web01  [Errno 2] No such file or directory: 'ssh'
#     db01   [Errno 2] No such file or directory: 'ssh'
#   [netmesh] FAILED on 2/2 hosts: web01 db01
#
# One record per indented line, across all sections: the enclosing section
# label, the first column (a hostname in remote sections, a check label in
# local-checks sections), and the remainder of the line. The tool tag and the
# FAILED tallies broadcast. The minimal case (`mx status`) is just host lines
# plus the FAILED footer, with no header line at all.
#
# Columns are split on a run of 2+ spaces — the padding guarantees at least
# two — so a first column may itself contain single spaces ("agent file"). A
# line with no 2+-space run is all name and no value.

# Regexes live in variables: the format is full of [ ] ( ) that would otherwise
# have to be escaped inside [[ =~ ]].
_fhl_re_tag='^\[([a-z][a-z0-9_-]*)\][[:space:]](.*)$'
_fhl_re_failed='^FAILED[[:space:]]+on[[:space:]]+([0-9]+)/([0-9]+)[[:space:]]+hosts:[[:space:]]*(.*)$'
_fhl_re_indent='^[[:space:]][[:space:]][^[:space:]]'
_fhl_re_gap='[^[:space:]][[:space:]][[:space:]]+[^[:space:]]'
# Maximal run of non-space chars in which single spaces are allowed — i.e. the
# text up to (but not including) the first run of 2+ spaces.
_fhl_re_firstcol='^([^[:space:]]([^[:space:]]|[[:space:]][^[:space:]])*)'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=82

    # No _is_json guard: it only tests the first character, and this format's
    # own header line starts with '['. A real JSON array never matches the tag
    # regex (a lowercase bare word then ']' then a space).

    local tags=0 indented=0 gapped=0 tool="" line
    while IFS= read -r line; do
        line="${line%$'\r'}"
        if [[ "$line" =~ $_fhl_re_tag ]]; then
            # Every bracketed tag must name the same tool; a log with mixed or
            # per-line tags is bracket-log's business, not ours.
            if [[ -z "$tool" ]]; then
                tool="${BASH_REMATCH[1]}"
            elif [[ "$tool" != "${BASH_REMATCH[1]}" ]]; then
                return 1
            fi
            tags=$((tags + 1))
        elif [[ "$line" =~ $_fhl_re_indent ]]; then
            indented=$((indented + 1))
            [[ "$line" =~ $_fhl_re_gap ]] && gapped=$((gapped + 1))
        fi
    done <<< "$text"

    # Both halves of the shape are required: a bracketed tool tag AND indented
    # two-column body lines. Indented lines alone are ordinary aligned columns.
    [[ $tags -ge 1 ]] || return 1
    [[ $indented -ge 2 ]] || return 1
    [[ $gapped -ge 1 ]] || return 1
    return 0
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local tool="" section=""
    local failed_count="" total_count="" failed_hosts=""
    local line

    while IFS= read -r line; do
        line="${line%$'\r'}"

        if [[ "$line" =~ $_fhl_re_tag ]]; then
            [[ -z "$tool" ]] && tool="${BASH_REMATCH[1]}"
            local rest="${BASH_REMATCH[2]}"
            if [[ "$rest" =~ $_fhl_re_failed ]]; then
                failed_count="${BASH_REMATCH[1]}"
                total_count="${BASH_REMATCH[2]}"
                _trim "${BASH_REMATCH[3]}"
                failed_hosts="$_TRIMMED"
            else
                _trim "$rest"
                section="$_TRIMMED"
            fi
            continue
        fi

        [[ "$line" =~ $_fhl_re_indent ]] || continue

        # Trim the indent and any trailing whitespace.
        local content="$line"
        content="${content#"${content%%[![:space:]]*}"}"
        content="${content%"${content##*[![:space:]]}"}"
        [[ -n "$content" ]] || continue

        local name="$content" value=""
        if [[ "$content" =~ $_fhl_re_firstcol ]]; then
            name="${BASH_REMATCH[1]}"
            value="${content:${#name}}"
            value="${value#"${value%%[![:space:]]*}"}"
        fi

        n=$((n + 1))
        local p="entry${n}."
        result+="${p}section ${section}"$'\n'
        result+="${p}name ${name}"$'\n'
        result+="${p}value ${value}"$'\n'
    done <<< "$text"

    [[ -n "$tool" ]] && result+="tool ${tool}"$'\n'
    if [[ -n "$failed_count" ]]; then
        result+="failed_count ${failed_count}"$'\n'
        result+="total_count ${total_count}"$'\n'
        result+="failed_hosts ${failed_hosts}"$'\n'
    fi
    result+="total_entries ${n}"$'\n'
    echo "$result"
}
