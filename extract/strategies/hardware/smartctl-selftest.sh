#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: smartctl-selftest
## Description: Extract the SMART self-test log table from smartctl -l selftest output
## Version: 1.0
## Priority: 20
## Sample: samples/smartctl-selftest/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    _is_json "$text" && return 1
    if [[ "$text" == *"Self-test log"* ]] \
       || { [[ "$text" == *"Test_Description"* ]] && [[ "$text" == *"LBA_of_first_error"* ]]; }; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Data rows start with a "# N" test-number marker.
        [[ "$line" =~ ^#[[:space:]]*[0-9]+ ]] || continue

        # Fields are column-aligned; single spaces occur within a field
        # (e.g. "Extended offline") and 2+ spaces separate fields.
        local rest="$line"
        local -a cols=()
        while [[ -n "$rest" ]]; do
            # Trim leading whitespace.
            rest="${rest#"${rest%%[![:space:]]*}"}"
            [[ -z "$rest" ]] && break
            local seg
            if [[ "$rest" =~ ^([^[:space:]]([^[:space:]]|[[:space:]][^[:space:]])*) ]]; then
                seg="${BASH_REMATCH[1]}"
            else
                seg="$rest"
            fi
            cols+=("$seg")
            rest="${rest:${#seg}}"
        done

        # cols: [# N] [Test_Description] [Status] [Remaining] [LifeTime] [LBA]
        [[ ${#cols[@]} -lt 6 ]] && continue

        # num from "# N".
        local num="${cols[0]##*[[:space:]]}"

        n=$((n + 1))
        local p="entry${n}."
        result+="${p}num ${num}"$'\n'
        result+="${p}test_description ${cols[1]}"$'\n'
        result+="${p}status ${cols[2]}"$'\n'
        result+="${p}remaining ${cols[3]}"$'\n'
        result+="${p}lifetime ${cols[4]}"$'\n'
        result+="${p}lba ${cols[5]}"$'\n'
    done

    result+="total_entries ${n}"$'\n'
    echo "$result"
}
