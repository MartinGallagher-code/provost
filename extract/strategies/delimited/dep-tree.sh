#!/bin/bash
## Name: dep-tree
## Description: pipdeptree/pipenv-graph dependency trees -> ancestor-path columns + required/installed
## Version: 1.0
## Priority: 32
## Sample: samples/dep-tree/basic.txt

# The pipdeptree family (pipdeptree, pipenv graph, pip-tree wrappers):
#
#   tensorflow==2.11.0
#     - grpcio [required: >=1.24.3,<2.0, installed: 1.51.1]
#         - six [required: >=1.5.2, installed: 1.16.0]
#
# The reviewer spelled the tidy shape out: the ancestor PATH fills columns
# A, B, C… (root in A; a first-level dep in B; its dep in C), and the
# bracket body splits into `required` and `installed` columns, brackets
# dropped. A root line's own version is its installed version.
#
# Root form:    NAME==VERSION                (unindented)
# Member form:  - NAME [required: R, installed: I]   (indented; deeper
#               indent = deeper in the tree)
# Detection requires >=1 root, >=2 members, and EVERY non-blank line to be
# one of the two forms — anything else is not this report.

_dt_root_re='^([A-Za-z0-9_.-]+)==([^=[:space:]]+)$'
_dt_member_re='^([[:space:]]+)-[[:space:]]+([A-Za-z0-9_.-]+)[[:space:]]+\[required:[[:space:]]*([^,]*(,[^,]*)*),[[:space:]]*installed:[[:space:]]*([^]]+)\]$'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line roots=0 members=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" =~ $_dt_root_re ]]; then
            roots=$((roots + 1))
        elif [[ "$line" =~ $_dt_member_re ]]; then
            members=$((members + 1))
        else
            return 1
        fi
    done <<< "$text"
    [[ $roots -ge 1 && $members -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=88
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0

    # The `required:` body may itself contain commas (`>=1.24.3,<2.0`), so the
    # bracket splits on the LAST `, installed:` instead of the first comma.
    # Ancestor stack: names[d] holds the name at depth d (root = depth 0);
    # a member's depth comes from its indent relative to the indents seen —
    # each new deeper indent is one level down, mirroring the drawing.
    local -a names=() indents=()
    local depth=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        if [[ "$line" =~ $_dt_root_re ]]; then
            names=("${BASH_REMATCH[1]}"); indents=(-1); depth=0
            entry=$((entry + 1))
            result+="entry${entry}.A ${BASH_REMATCH[1]}"$'\n'
            result+="entry${entry}.installed ${BASH_REMATCH[2]}"$'\n'
            continue
        fi
        [[ "$line" =~ ^([[:space:]]+)- ]] || continue
        local ind=${#BASH_REMATCH[1]}
        local body="${line#"${BASH_REMATCH[1]}"}"
        body="${body#- }"
        local name="${body%% *}"
        local br="${body#*\[required: }"
        br="${br%]}"
        local req="${br%, installed: *}"
        local inst="${br##*, installed: }"

        # Find this indent's depth: pop deeper/equal levels, then push.
        while [[ $depth -gt 0 && $ind -le ${indents[$depth]} ]]; do
            unset 'names[depth]' 'indents[depth]'
            depth=$((depth - 1))
        done
        depth=$((depth + 1))
        names[$depth]="$name"; indents[$depth]=$ind

        entry=$((entry + 1))
        local d col
        for ((d = 0; d <= depth; d++)); do
            # Column letters A, B, C… by depth.
            col=$(printf "\\$(printf '%03o' $((65 + d)))")
            result+="entry${entry}.${col} ${names[$d]}"$'\n'
        done
        result+="entry${entry}.required ${req}"$'\n'
        result+="entry${entry}.installed ${inst}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
