#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: mix-deps
## Description: Extract dependencies from Elixir `mix deps` output
## Version: 1.0
## Priority: 26
## Sample: samples/mix-deps/basic.txt

# `mix deps` lists each dependency as a "* name version (Hex package) (mix)"
# bullet, followed by indented continuation lines ("locked at ...", "ok").
# Only the bullet lines are records; the single field is the dependency name.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    # Distinctive: hex-package bullets with a "locked at" lockfile continuation.
    [[ "$text" == *"(Hex package)"* ]] || return 1
    [[ "$text" == *"locked at "* ]] || return 1
    local deps=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" =~ ^\*[[:space:]]+[A-Za-z0-9_.-]+[[:space:]] ]] && deps=$((deps + 1))
    done
    [[ $deps -ge 1 ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        # Only bullet lines; skip "locked at ..." / "ok" continuation lines.
        [[ "$line" =~ ^\*[[:space:]]+([A-Za-z0-9_.-]+) ]] || continue
        local name="${BASH_REMATCH[1]}"
        entry=$((entry + 1))
        result+="entry${entry}.A ${name}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
