#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: indent-tree
## Description: bare single-token indentation tree (mixed tabs/spaces) -> depth/parent/name rows; TAB-indented columns (comm) -> depth/name rows; an indented text outline (nested test output) -> depth/parent/name rows
## Version: 1.1
## Priority: 36
## Sample: samples/indent-tree/basic.txt

# A hierarchy drawn with indentation ALONE — one bare name per line, no
# box-drawing glyphs, no colons, tabs and spaces mixed freely:
#
#   app
#     server
#       handler
#   <TAB>logger
#     client
#       cache
#           pool
#
# tree-view needs branch glyphs and indented-hierarchy needs colons, so this
# fell to line-records as a flat list — "there is a tree here that you
# missed." Depth comes from an indent-width STACK (a tab counts 8 columns): a
# wider indent than the level above is one level deeper, an equal width is a
# sibling, a narrower one pops. Each node emits with its depth and parent:
#
#   depth  parent   name
#   0               app
#   1      app      server
#   2      server   handler
#
# Gates: every non-blank line is ONE bare token (`[A-Za-z0-9_./-]`), the
# first line is unindented, >=4 lines, and >=3 distinct indent widths (a flat
# or two-level list stays with the list parsers).

_it_width () {
    # Leading-whitespace display width of "$1" (tab advances to the next
    # 8-column stop) -> _IT_W
    local l="$1" i=0 w=0 ch
    while :; do
        ch="${l:$i:1}"
        if [[ "$ch" == " " ]]; then w=$((w + 1))
        elif [[ "$ch" == $'\t' ]]; then w=$(( (w / 8 + 1) * 8 ))
        else break; fi
        i=$((i + 1))
    done
    _IT_W=$w
}

# Depth by COLUMN (the second shape): TAB-indented lines whose indent is a
# column, not a nesting level — `comm`'s three columns (lines only in file 1
# unindented, only in file 2 one TAB in, in both two TABs in), where which
# column a line sits in is the whole output. The indent widths are not a
# tree there: the first line may already be indented, and a line may sit two
# levels deeper than the one above (`apple` then `<TAB><TAB>cherry`), which
# no nesting can do. Then each line is emitted with its column rank as
# `depth` (0 = the shallowest width seen) and no parent; the lines may hold
# blanks (whole lines of text), but the indentation is TABs only, and there
# are >=4 lines in >=2 widths.
#
# An OUTLINE of text lines (the third shape): nested test-runner output
# (RSpec's documentation format, mocha's spec reporter), an indented report
# whose nesting is the data — `User` / `  #full_name` / `    joins first and
# last name`. Read like the tree (depth from the indent stack, the enclosing
# line as parent, the line as name), when: 6+ lines, the first at the
# shallowest indent (mocha indents everything by two),
# 3+ indent widths of spaces only, 40%+ of the lines indented, at most 10%
# holding a column gap (a table is not an outline), at most 30% `label:`
# lines (a key/value report is not either), at most 10% jumping two levels,
# no line over 120 bytes, and the numeric first words of lines at different
# indents NOT ending in one column for 60%+ of the lines (that indent is
# right-alignment: systemd-analyze blame's `25.114s` over ` 8.902s`). Confidence 70 (see strategy_detect).
#
# _it_scan TEXT -> _IT_MODE: tree | column | outline | "" (not this shape)
_it_scan () {
    _IT_MODE=""
    local line n=0 first=1 firstw=-1 bare=1 tabonly=1 _w
    local gut=0 kvl=0 long=0 tabs=0 ind=0 _fe _fw _febest=0
    local -A fend=() fendi=() fendn=()
    local -a order=()
    local -A widths=()
    _fr_lines "$1"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        local body="${line#"${line%%[![:space:]]*}"}"
        body="${body%"${body##*[![:space:]]}"}"
        [[ "$body" =~ ^[A-Za-z0-9_./-]+$ ]] || bare=0
        [[ "$body" == *$'\t'* ]] && tabonly=0
        local lead="${line%%[![:space:]]*}"
        [[ "$lead" == *" "* ]] && tabonly=0
        [[ "$lead" == *$'\t'* ]] && tabs=1
        [[ -n "$lead" ]] && ind=$((ind + 1))
        [[ "$body" == *[![:space:]]"  "*[![:space:]]* ]] && gut=$((gut + 1))
        [[ "$body" =~ ^[A-Za-z][A-Za-z0-9_\ .-]*:([[:space:]]|$) ]] && kvl=$((kvl + 1))
        [[ ${#line} -gt 120 ]] && long=1
        # (where a numeric first word ENDS: a right-aligned number column —
        # `25.114s x` over ` 8.902s y` — indents its short values, which is
        # no nesting)
        _fe="${line%%[![:space:]]*}"; _fw="${body%%[[:space:]]*}"; _fe=$(( ${#_fe} + ${#_fw} ))
        if [[ "$_fw" == [0-9+-]* ]]; then
            fend[$_fe]=$(( ${fend[$_fe]:-0} + 1 ))
            [[ -n "${fendi[$_fe,${#lead}]:-}" ]] || { fendi[$_fe,${#lead}]=1; fendn[$_fe]=$(( ${fendn[$_fe]:-0} + 1 )); }
        fi
        _it_width "$line"
        [[ $firstw -lt 0 ]] && firstw=$_IT_W
        widths[$_IT_W]=1; order+=("$_IT_W")
        n=$((n + 1))
    done
    [[ $n -ge 4 ]] || return 1
    for _fe in "${!fend[@]}"; do
        [[ ${fendn[$_fe]} -ge 2 && ${fend[$_fe]} -gt $_febest ]] && _febest=${fend[$_fe]}
    done
    # rank of each width among the distinct widths; a nesting moves at most
    # one rank deeper per line and starts at rank 0
    local -A rank=(); local r=0 prev=-1 tree=1 jumps=0
    while IFS= read -r _w; do rank[$_w]=$r; r=$((r + 1)); done < <(printf '%s\n' "${!widths[@]}" | sort -n)
    for _w in "${order[@]}"; do
        if [[ $prev -lt 0 ]]; then [[ ${rank[$_w]} -eq 0 ]] || tree=0
        elif [[ ${rank[$_w]} -gt $((prev + 1)) ]]; then tree=0; jumps=$((jumps + 1)); fi
        prev=${rank[$_w]}
    done
    if [[ $tree -eq 0 && $tabonly -eq 1 && ${#widths[@]} -ge 2 ]]; then
        _IT_MODE=column
    elif [[ $bare -eq 1 && $firstw -eq 0 && ${#widths[@]} -ge 3 ]]; then
        _IT_MODE=tree
    elif [[ $bare -eq 0 && $tabs -eq 0 && $long -eq 0 && $n -ge 6 && ${rank[$firstw]} -eq 0 \
            && ${#widths[@]} -ge 3 && $(( ind * 100 )) -ge $(( n * 40 )) \
            && $(( gut * 100 )) -le $(( n * (10 + ${_FR_SLACK:-0}) )) \
            && $(( kvl * 100 )) -le $(( n * (30 + ${_FR_SLACK:-0}) )) \
            && $(( jumps * 100 )) -le $(( n * 10 )) && $(( _febest * 100 )) -lt $(( n * 60 )) ]]; then
        _IT_MODE=outline
    fi
    [[ -n "$_IT_MODE" ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _it_scan "$text" || return 1
    _STRATEGY_CONFIDENCE=80
    # (an outline of text lines is shape evidence only: under the
    # format-specific parsers, over the whitespace-table one, which reads a
    # gutter-free outline as a table of words)
    [[ "$_IT_MODE" == outline ]] && _STRATEGY_CONFIDENCE=70
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    local -a names=() ws=()
    local depth=-1
    _it_scan "$text" || return 0
    if [[ "$_IT_MODE" == column ]]; then
        local -A _cr=(); local _r=0 _w
        _fr_lines "$text"
        for line in "${_FR_LINES[@]}"; do
            [[ "${line}" != *[![:space:]]* ]] && continue
            _it_width "$line"; _cr[$_IT_W]=1
        done
        while IFS= read -r _w; do _cr[$_w]=$_r; _r=$((_r + 1)); done < <(printf '%s\n' "${!_cr[@]}" | sort -n)
        _fr_lines "$text"
        for line in "${_FR_LINES[@]}"; do
            [[ "${line}" != *[![:space:]]* ]] && continue
            local body="${line#"${line%%[![:space:]]*}"}"
            body="${body%"${body##*[![:space:]]}"}"
            _it_width "$line"
            entry=$((entry + 1))
            result+="entry${entry}.depth ${_cr[$_IT_W]}"$'\n'
            result+="entry${entry}.name ${body}"$'\n'
        done
        [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
        echo "$result"
        return 0
    fi
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "${line}" != *[![:space:]]* ]] && continue
        local body="${line#"${line%%[![:space:]]*}"}"
        body="${body%"${body##*[![:space:]]}"}"
        _it_width "$line"
        # Pop to the enclosing level, then push this node.
        while [[ $depth -ge 0 && $_IT_W -le ${ws[$depth]} ]]; do
            unset 'names[depth]' 'ws[depth]'
            depth=$((depth - 1))
        done
        depth=$((depth + 1))
        names[$depth]="$body"; ws[$depth]=$_IT_W
        entry=$((entry + 1))
        result+="entry${entry}.depth ${depth}"$'\n'
        [[ $depth -gt 0 ]] && result+="entry${entry}.parent ${names[$((depth - 1))]}"$'\n'
        result+="entry${entry}.name ${body}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
