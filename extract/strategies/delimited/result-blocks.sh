#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: result-blocks
## Description: tfsec `Result N` blocks (`[rule][SEVERITY]` + message + file:lines) -> rule/severity/message/location rows
## Version: 1.0
## Priority: 39
## Sample: samples/result-blocks/basic.txt

# Scanner findings, one block per result:
#
#   Result 1
#     [aws-s3-enable-bucket-encryption][HIGH]
#     Bucket does not have encryption enabled
#     main.tf:14-22
#     1 passed, 3 potential problems detected.
#
# indented-hierarchy kept only `main.tf: 14-22` — the reviewer's "you lost
# information". The block decomposes: the `[rule][SEVERITY]` bracket pair, the
# prose message, and the `file:lines` location each carry a field:
#
#   result  rule                             severity  message               location
#   1       aws-s3-enable-bucket-encryption  HIGH      Bucket does not have  main.tf:14-22
#
# Detection: >=1 `Result N` header whose NEXT non-blank line is a
# `[x][Y]` double-bracket pair. Trailing summary prose (`N passed, …`) and
# other loose lines are dropped.

_rb_hdr_re='^Result[[:space:]]+([0-9]+)[[:space:]]*$'
_rb_brk_re='^[[:space:]]*\[([^]]+)\]\[([^]]+)\][[:space:]]*$'
_rb_loc_re='^[[:space:]]*([^[:space:]]+:[0-9]+([-,][0-9]+)?)[[:space:]]*$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line want_brk=0 blocks=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" =~ $_rb_hdr_re ]]; then want_brk=1; continue; fi
        if [[ $want_brk -eq 1 ]]; then
            [[ "$line" =~ $_rb_brk_re ]] || return 1
            blocks=$((blocks + 1)); want_brk=0
        fi
    done
    [[ $blocks -ge 1 ]] || return 1
    _STRATEGY_CONFIDENCE=84
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0 in_block=0 msg=""
    _rb_flush () {
        [[ $entry -gt 0 && -n "$msg" ]] && result+="entry${entry}.message ${msg}"$'\n'
        msg=""
    }
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        if [[ "$line" =~ $_rb_hdr_re ]]; then
            _rb_flush
            entry=$((entry + 1)); in_block=1
            result+="entry${entry}.result ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        [[ $in_block -eq 1 ]] || continue
        if [[ "$line" =~ $_rb_brk_re ]]; then
            result+="entry${entry}.rule ${BASH_REMATCH[1]}"$'\n'
            result+="entry${entry}.severity ${BASH_REMATCH[2]}"$'\n'
            continue
        fi
        if [[ "$line" =~ $_rb_loc_re ]]; then
            _rb_flush
            result+="entry${entry}.location ${BASH_REMATCH[1]}"$'\n'
            in_block=0
            continue
        fi
        # Prose inside the block joins into the message.
        local b="${line#"${line%%[![:space:]]*}"}"
        b="${b%"${b##*[![:space:]]}"}"
        [[ -n "$msg" ]] && msg+=" "
        msg+="$b"
    done
    _rb_flush
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
