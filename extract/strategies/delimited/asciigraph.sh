#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: asciigraph
## Description: Line charts (asciigraph) — recover the axis labels + series values from the plot's footer, dropping the graphics
## Version: 1.0
## Priority: 46
## Sample: samples/asciigraph/basic.txt

# asciigraph renders a braille/box-drawing line chart with a numeric footer:
#
#    120 ┤                     ╭──
#    ...
#     20 ┤
#        00:00   04:00   08:00   12:00   16:00   20:00
#   req/s  18      44      61      85     102     118
#
# The plot body is graphics; the DATA is the bottom pair — an x-axis label row
# and a `<series> v v v …` value row. This drops the graphics and emits one row
# per point: the axis label and the series value. (reviewer: "extract the
# values, not the graphics".)

# A series footer line: a leading label token then >=3 numeric tokens. Sets
# _AG_LABEL and the _AG_VALS array.
_ag_series () {
    local line="$1"
    local -a t=(); { _fr_tok "$line"; t=("${_FR_TOK[@]}"); }
    [[ ${#t[@]} -ge 4 ]] || return 1
    local i nums=0
    for ((i = 1; i < ${#t[@]}; i++)); do
        [[ "${t[$i]}" =~ ^-?[0-9][0-9.]*$ ]] || return 1
        nums=$((nums + 1))
    done
    # the label token must NOT be numeric (it names the series)
    [[ "${t[0]}" =~ ^-?[0-9] ]] && return 1
    _AG_LABEL="${t[0]}"; _AG_VALS=("${t[@]:1}"); _AG_NUM=$nums
    return 0
}

# y-axis tick glyph asciigraph draws: `┤` (U+2524) / `┼` (U+253C). Their UTF-8
# lead bytes mark a plot line.
_ag_is_plot () {
    local l="$1"
    [[ "$l" == *$'\342\224\244'* || "$l" == *$'\342\224\274'* ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line plot=0 series=0
    # PREFILTER (exact): acceptance needs >=2 plot lines, and a plot line is
    # one carrying `┤` or `┼` — neither glyph anywhere means no plot line.
    [[ "$text" == *$'\342\224\244'* || "$text" == *$'\342\224\274'* ]] || return 1
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        _ag_is_plot "$line" && plot=$((plot + 1))
        _ag_series "$line" && series=1
    done
    # >=2 plot lines AND a numeric series footer — the asciigraph signature.
    [[ $plot -ge 2 && $series -eq 1 ]] || return 1
    _STRATEGY_CONFIDENCE=80
    return 0
}

strategy_extract () {
    local text="$1"
    local -a lines=(); local line
    _fr_lines "$text"; lines+=("${_FR_LINES[@]}"); line=""

    # Find the LAST series line; the nearest non-blank, non-plot line above it is
    # the x-axis label row.
    local n=${#lines[@]} i sidx=-1
    for ((i = n - 1; i >= 0; i--)); do
        if _ag_series "${lines[$i]}"; then sidx=$i; break; fi
    done
    [[ $sidx -lt 0 ]] && { echo ""; return 0; }
    _ag_series "${lines[$sidx]}"
    local label="$_AG_LABEL"; local -a vals=("${_AG_VALS[@]}")

    local aidx=-1
    for ((i = sidx - 1; i >= 0; i--)); do
        [[ "${lines[$i]}" != *[![:space:]]* ]] && continue
        _ag_is_plot "${lines[$i]}" && break
        aidx=$i; break
    done
    local -a axis=()
    [[ $aidx -ge 0 ]] && { _fr_tok "${lines[$aidx]}"; axis=("${_FR_TOK[@]}"); }

    local result="" entry=0 k
    for ((k = 0; k < ${#vals[@]}; k++)); do
        entry=$((entry + 1))
        [[ $k -lt ${#axis[@]} ]] && result+="entry${entry}.x ${axis[$k]}"$'\n'
        result+="entry${entry}.${label} ${vals[$k]}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
