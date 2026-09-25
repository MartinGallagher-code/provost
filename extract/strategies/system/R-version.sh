#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: R-version
## Description: Extract version fields from `R --version` banner
## Version: 1.1
## Priority: 20
## Sample: samples/R-version/basic.txt

# `R --version` opens with 'R version 4.3.2 (2023-10-31) -- "Eye Holes"' and a
# "Platform: <triple> (...)" line, followed by license text. One wide key/value
# record: product, version, date, nickname, platform.
#
# v1.1 also keeps `Running under: <os>`, which `sessionInfo()` prints under the
# Platform line and v1.0 dropped on the floor — the reviewer's "lost the
# Running Under entry" on R-sessioninfo. Emitted empty for `R --version`
# proper, which has no such line.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local first="" line
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        first="$line"; break
    done
    if [[ "$first" == "R version "* && "$text" == *"Platform:"* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" ver="" date="" nick="" plat="" running=""
    if [[ "$text" =~ R[[:space:]]version[[:space:]]([0-9][0-9A-Za-z.+-]*) ]]; then
        ver="${BASH_REMATCH[1]}"
    fi
    if [[ "$text" =~ \(([0-9]{4}-[0-9]{2}-[0-9]{2})\) ]]; then
        date="${BASH_REMATCH[1]}"
    fi
    if [[ "$text" =~ \"([^\"]+)\" ]]; then
        nick="${BASH_REMATCH[1]}"
    fi
    if [[ "$text" =~ Platform:[[:space:]]*([^[:space:]]+) ]]; then
        plat="${BASH_REMATCH[1]}"
    fi
    result+="entry1.product R"$'\n'
    result+="entry1.version ${ver}"$'\n'
    result+="entry1.date ${date}"$'\n'
    result+="entry1.nickname ${nick}"$'\n'
    # `Running under: Ubuntu 24.04 LTS` — a whole line, not one token, so it is
    # matched line-wise rather than with the token pattern used for Platform.
    if [[ "$text" =~ Running[[:space:]]under:[[:space:]]*([^$'\n']+) ]]; then
        running="${BASH_REMATCH[1]}"
        running="${running%"${running##*[![:space:]]}"}"
    fi
    result+="entry1.platform ${plat}"$'\n'
    result+="entry1.running_under ${running}"$'\n'
    result+="total_entries 1"$'\n'
    echo "$result"
}
