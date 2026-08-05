#!/bin/bash
## Name: indent-tree
## Description: bare single-token indentation tree (mixed tabs/spaces) -> depth/parent/name rows
## Version: 1.0
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

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line n=0 first=1
    local -A widths=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        local body="${line#"${line%%[![:space:]]*}"}"
        body="${body%"${body##*[![:space:]]}"}"
        [[ "$body" =~ ^[A-Za-z0-9_./-]+$ ]] || return 1
        if [[ $first -eq 1 ]]; then
            [[ "$line" == [!$' \t']* ]] || return 1
            first=0
        fi
        _it_width "$line"
        widths[$_IT_W]=1
        n=$((n + 1))
    done <<< "$text"
    [[ $n -ge 4 && ${#widths[@]} -ge 3 ]] || return 1
    _STRATEGY_CONFIDENCE=78
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    local -a names=() ws=()
    local depth=-1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
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
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
