#!/bin/bash
## Name: tree-view
## Description: Tree-structured output (tree, pstree, npm ls) — one row per node
## Version: 1.0
## Priority: 50
## Sample: samples/tree-view/basic.txt

# A single generic strategy for the many commands that draw a hierarchy with
# box-drawing branch characters: `tree`, `pstree`, `npm ls`, `cargo tree`,
# `pnpm ls`, etc. Rather than a bespoke strategy per command, this captures ANY
# such listing as indexed node row groups (entry<N>.depth / entry<N>.name) so
# the capture tidy melt renders one clean row per node with two columns
# (depth, name) instead of one unreadable wide record.
#
# A "node line" is any line carrying a branch marker: the Unicode connectors
# ├ (U+251C), └ (U+2514) or ┬ (U+252C), or the ASCII variants `|--`, `\--`,
# `+--`. The bare root line that some tools print on its own (tree's `.`, the
# `pkg@ver /path` header from `npm ls`) has no branch marker and is treated as
# the implicit depth-0 parent — it is not emitted as its own row. Depth is the
# indentation level (0-based) measured from the leading box-drawing cells.

# Byte sequences of the box-drawing chars (works regardless of locale — both the
# literals here and the sampled input are the same UTF-8 bytes).
_TV_VERT='│'        # U+2502
_TV_BRANCH='├'      # U+251C
_TV_LAST='└'        # U+2514
_TV_HORZ='─'        # U+2500
_TV_TDOWN='┬'       # U+252C

# Does this line carry a branch marker?
_tv_is_node () {
    local t="$1"
    case "$t" in
        *"$_TV_BRANCH"*|*"$_TV_LAST"*|*"$_TV_TDOWN"*) return 0 ;;
        *'|--'*|*'\--'*|*'+--'*)                      return 0 ;;
    esac
    return 1
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local line nonblank=0 nodes=0
    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        nonblank=$((nonblank + 1))
        _tv_is_node "$line" && nodes=$((nodes + 1))
    done <<< "$text"

    # Need a few real branch lines, and a strong majority of the non-blank lines
    # must carry a marker (root + trailing summary lines are the only allowance).
    [[ $nodes -lt 2 ]] && return 1
    (( nodes * 10 < nonblank * 6 )) && return 1

    # Decline columnar tables that merely use tree chars in their first column
    # (e.g. findmnt): if the first non-blank line is not itself a node and looks
    # like an ALL-CAPS column header, this belongs to aligned-columns, not here.
    local first; first="$(printf '%s\n' "$text" | sed -n '/[^[:space:]]/{p;q}')"
    if ! _tv_is_node "$first"; then
        local _ft; _ft=(); read -ra _ft <<< "$first"
        local _up=0 _t
        for _t in "${_ft[@]}"; do [[ "$_t" =~ ^[A-Z][A-Z0-9_/-]*$ ]] && _up=$((_up + 1)); done
        [[ ${#_ft[@]} -ge 2 && $_up -ge 2 ]] && return 1
    fi

    _STRATEGY_CONFIDENCE=85
    return 0
}

# Depth = number of 4-column indentation cells before the node label.
# Continuation cells are "│   " or four spaces; the marker cell is "├── "/"└── ".
_tv_depth () {
    local s="$1" depth=0
    while true; do
        case "$s" in
            "$_TV_VERT"'   '*) s="${s#"$_TV_VERT"'   '}";              depth=$((depth + 1)) ;;
            '    '*)           s="${s#'    '}";                        depth=$((depth + 1)) ;;
            "$_TV_BRANCH$_TV_HORZ$_TV_HORZ"' '*) depth=$((depth + 1)); break ;;
            "$_TV_LAST$_TV_HORZ$_TV_HORZ"' '*)   depth=$((depth + 1)); break ;;
            *) break ;;
        esac
    done
    printf '%s' "$depth"
}

# Strip all box-drawing chars (and the ASCII `|`,`\` connectors) to a space,
# then collapse runs of whitespace and trim. ASCII hyphens are preserved so
# names like "dbus-daemon" survive.
_tv_name () {
    local s="$1"
    s="${s//$_TV_VERT/ }"
    s="${s//$_TV_BRANCH/ }"
    s="${s//$_TV_LAST/ }"
    s="${s//$_TV_HORZ/ }"
    s="${s//$_TV_TDOWN/ }"
    s="${s//|/ }"
    s="${s//\\/ }"
    # collapse + trim via word-splitting
    local -a parts
    read -r -a parts <<< "$s"
    printf '%s' "${parts[*]}"
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line nm d

    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _tv_is_node "$line" || continue

        d="$(_tv_depth "$line")"
        nm="$(_tv_name "$line")"
        [[ -z "$nm" ]] && continue

        entry=$((entry + 1))
        result+="entry${entry}.depth ${d}"$'\n'
        result+="entry${entry}.name ${nm}"$'\n'
    done <<< "$text"

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
