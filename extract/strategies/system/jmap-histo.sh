#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: jmap-histo
## Description: jmap -histo class histogram → one tidy row per class
## Version: 1.0
## Priority: 22
## Sample: samples/jmap-histo/basic.txt

# `jmap -histo` prints a " num  #instances  #bytes  class name" header, a rule of
# dashes, then one numbered row per class ("  1:  184213  12048224  [C"), and a
# trailing "Total ..." footer. A class row's first field is "<num>:" — that
# distinguishes it from the header, the dashes and the Total line.

_jmap_histo_is_row () {
    [[ "$1" =~ ^[0-9]+:$ ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    [[ "$text" == *"#instances"* && "$text" == *"#bytes"* && "$text" == *"class name"* ]] || return 1
    _STRATEGY_CONFIDENCE=86
    return 0
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local toks
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        toks=(); { _fr_tok "$line"; toks=("${_FR_TOK[@]}"); }
        [[ ${#toks[@]} -ge 4 ]] || continue
        _jmap_histo_is_row "${toks[0]}" || continue
        local num="${toks[0]%:}"
        local class="${toks[*]:3}"
        entry=$((entry + 1))
        result+="entry${entry}.num ${num}"$'\n'
        result+="entry${entry}.instances ${toks[1]}"$'\n'
        result+="entry${entry}.bytes ${toks[2]}"$'\n'
        result+="entry${entry}.class ${class}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
