#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: sbt-dependencytree
## Description: Extract dependencies from `sbt dependencyTree` output
## Version: 1.0
## Priority: 20
## Sample: samples/sbt-dependencytree/basic.txt

# `sbt dependencyTree` prefixes every line with "[info]"; the root project is a
# bare "[info] <org>:<name>:<ver>" line and each dependency is drawn with a
# "+-" tree marker ("[info]   +-<org>:<name>:<ver>"). Only the "+-" dependency
# lines are records; the cleaned value is the coordinate after the marker
# (single column).

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # NB: no _is_json guard — sbt's "[info]"-prefixed lines start with '[' and
    # would be mis-flagged as a JSON array. The "[info] ... +-" signature below
    # is specific enough on its own.
    if [[ "$text" == *"[info]"* && "$text" == *"+-"* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line s
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        # Only dependency lines carry the "+-" marker.
        [[ "$line" != *"+-"* ]] && continue
        s="${line##*+-}"
        s="${s#"${s%%[![:space:]]*}"}"
        s="${s%"${s##*[![:space:]]}"}"
        [[ -z "$s" ]] && continue
        entry=$((entry + 1))
        result+="entry${entry}.A ${s}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
