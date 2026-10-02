#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: cargo-search
## Description: cargo search results — `name = "version"    # description` lines -> name/version/description rows
## Version: 1.0
## Priority: 20
## Sample: samples/cargo-search/basic.txt

# `cargo search QUERY` prints one crate per line as a Cargo.toml dependency
# line with the crate's description in a trailing comment, then a footer:
#
#   serde = "1.0.203"           # A generic serialization/deserialization framework
#   serde_json = "1.0.117"      # A JSON serialization file format
#   ... and 1274 crates more (use --limit N to see more)
#
# One row per crate: name, version (quotes dropped), description (the
# comment, `# ` dropped). The footer is chrome. The generic parsers see
# `key = value` pairs and weld version and comment into one value. The
# quoted-version + `#` comment line, every line, is cargo's own layout
# (92, bespoke strong).

_cs_re='^([A-Za-z0-9_-]+) = "([^"]*)"[[:space:]]*(#[[:space:]]?(.*))?$'
_cs_foot_re='^\.\.\. and [0-9]+ crates? more'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    # PREFILTER (exact): a crate line holds ` = "`
    [[ "$text" == *' = "'* ]] || return 1
    local line hits=0 cmt=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        [[ "$line" =~ $_cs_foot_re ]] && continue
        [[ "$line" =~ $_cs_re ]] || return 1
        hits=$((hits + 1))
        [[ -n "${BASH_REMATCH[3]}" ]] && cmt=$((cmt + 1))
    done
    # >= 2 crate lines, most carrying the description comment (a plain
    # `key = "value"` list is TOML/INI, not a search result)
    [[ $hits -ge 2 && $(( cmt * 100 )) -gt $(( (50 - ${_FR_SLACK:-0}) * hits )) ]] || return 1
    _STRATEGY_CONFIDENCE=92
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 line desc
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" =~ $_cs_re ]] || continue
        entry=$((entry + 1))
        result+="entry${entry}.name ${BASH_REMATCH[1]}"$'\n'
        result+="entry${entry}.version ${BASH_REMATCH[2]}"$'\n'
        desc="${BASH_REMATCH[4]}"
        desc="${desc%"${desc##*[![:space:]]}"}"
        [[ -n "$desc" ]] && result+="entry${entry}.description ${desc}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}
