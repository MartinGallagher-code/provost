#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: jsonl
## Description: Extract key/value pairs from JSON Lines (one JSON object per line)
## Version: 1.2
## Priority: 9
## Sample: samples/jsonl/basic.jsonl
##
## Priority 9 places JSON Lines ahead of the single-document `json` strategy
## (p10): a `.jsonl` file is NOT one JSON document, and `json` would flatten its
## objects into a wide row with duplicate columns. `jsonl`'s detector requires
## 2+ lines that are each a complete `{...}` object, so single-line or
## pretty-printed JSON (whose lines are not standalone objects) is left to json.
## Each line is emitted as a `line<N>.<field>` group so the capture tidy melt
## renders one row per record.
##
## v1.2 — `#` comment lines (a header a tool prints above its records:
## `# dcprobe scan …`) are skipped, in detection and extraction alike, and
## not counted in N: they used to push the JSON lines out of the detector's
## first-three window and the file fell to aligned-columns. Without jq, the
## lines are read by _json_walk (_helpers.sh), which prints what the jq
## filter prints, nested values as compact JSON; the old fallback stopped at
## the first nested value.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Strip a UTF-8 BOM (EF BB BF) if present — common in JSON exported from
    # Windows tools — so it doesn't hide the first line's leading '{'.
    local bom; bom=$'\xef\xbb\xbf'
    # (prefix test first: a non-matching `#"$bom"` scans every prefix — quadratic)
    if [[ "$text" == "$bom"* ]]; then text="${text#"$bom"}"; fi

    # Must have 2+ lines, each looking like a JSON object (comments aside)
    local line_count=0 trimmed
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        trimmed="${_line#"${_line%%[!$' \t']*}"}"
        [[ -n "$trimmed" && "$trimmed" != '#'* ]] && line_count=$((line_count + 1))
        # only `>= 2` matters below — stop counting there
        [[ $line_count -ge 2 ]] && break
    done
    _line=""
    [[ $line_count -lt 2 ]] && return 1

    # Check the first 3 lines that are not blank or comments are JSON objects
    local json_lines=0
    local checked=0
    while IFS= read -r _line; do
        trimmed="${_line#"${_line%%[!$' \t']*}"}"
        [[ -z "$trimmed" || "$trimmed" == '#'* ]] && continue
        checked=$((checked + 1))
        if [[ "$trimmed" == "{"*"}" ]]; then
            json_lines=$((json_lines + 1))
        fi
        [[ $checked -ge 3 ]] && break
    done <<< "$text"

    [[ $json_lines -ge 2 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"

    # No jq: one awk pass, printing what the loop below prints with jq
    if ! command -v jq &>/dev/null; then
        _json_walk entries "$text"
        echo
        return 0
    fi

    local result="" line_num=0 trimmed
    while IFS= read -r line; do
        trimmed="${line#"${line%%[!$' \t']*}"}"
        [[ -z "$trimmed" || "$trimmed" == '#'* ]] && continue
        line_num=$((line_num + 1))
        local fields
        fields=$(echo "$line" | jq -r '
            to_entries[] | "\(.key) \(.value)"
        ' 2>/dev/null)
        if [[ -n "$fields" ]]; then
            _fr_lines "$fields"
            for field_line in "${_FR_LINES[@]}"; do
                [[ -z "$field_line" ]] && continue
                { _fr_tok "$field_line"; _arr=("${_FR_TOK[@]}"); }
                local fname="${_arr[0]}"
                local fval="${field_line#"$fname" }"
                result+="line${line_num}.${fname} ${fval}"$'\n'
            done
        fi
    done <<< "$text"

    echo "$result"
}
