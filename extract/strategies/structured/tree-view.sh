#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: tree-view
## Description: Tree-structured output (tree, pstree, npm ls) — one row per node
## Version: 1.1
## Priority: 38
## Sample: samples/tree-view/basic.txt

# Priority 38 (was 50): the engine dispatches in priority order, first-match
# wins, so a genuine glyph tree must be tried BEFORE the generic block-records
# (40) and indented-hierarchy (50) parsers — otherwise those grab the preamble
# or the first `label:` line and collapse the tree to a single record. The
# detect gate (>=60% of non-blank lines carry a ├/└/┬ branch marker, and no
# ALL-CAPS columnar header) is specific enough that only real trees flip here.

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

    # NUMBERED-HOP decline: `mtr` / `traceroute` draw `1.|-- host …` — the
    # `|--` is a hop-number connector, not tree indentation, and every line
    # carries a columnar `Loss% Snt Last …` record. A real tree never prefixes
    # its branch marker with `N.`. When most node lines match `^ *NN.|--`,
    # this is a numbered report → decline so aligned-columns reads the columns.
    local _hop=0 _hl
    while IFS= read -r _hl; do
        [[ "$_hl" =~ ^[[:space:]]*[0-9]+\.\|?[[:space:]]*[|\\+]?-- ]] && _hop=$((_hop + 1))
    done <<< "$text"
    (( _hop * 2 >= nodes )) && return 1

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
    # Drop a small cosmetic left-margin (some tools indent the whole tree a few
    # spaces) so it is not mistaken for a depth level.
    while [[ "$s" == '  '* && "$s" != '    '* ]]; do s="${s#'  '}"; done
    while true; do
        case "$s" in
            # A VERTICAL-BAR indent cell: the connector plus its trailing
            # spaces up to the next glyph, however many (`│   `, `│  `, `│ `,
            # ASCII `|  `, `|   `). Consume the bar then any run of spaces.
            "$_TV_VERT"*)
                s="${s#"$_TV_VERT"}"
                while [[ "$s" == ' '* ]]; do s="${s# }"; done
                depth=$((depth + 1)) ;;
            '|'*)
                # ASCII bar, but NOT the `|--`/`|  |--` branch marker itself.
                if [[ "$s" == '|--'* ]]; then depth=$((depth + 1)); break; fi
                s="${s#'|'}"
                while [[ "$s" == ' '* ]]; do s="${s# }"; done
                depth=$((depth + 1)) ;;
            # 4- / 2-column blank indent cells.
            '    '*)           s="${s#'    '}";                        depth=$((depth + 1)) ;;
            '  '*)             s="${s#'  '}";                          depth=$((depth + 1)) ;;
            # Branch markers of any dash count (├──/├─/└─/├─┬), then the label.
            "$_TV_BRANCH"*|"$_TV_LAST"*) depth=$((depth + 1)); break ;;
            '\--'*|'+--'*|'`--'*)        depth=$((depth + 1)); break ;;
            *) break ;;
        esac
    done
    printf '%s' "$depth"
}

# Strip tree glyphs and leading connector debris but PRESERVE internal spacing,
# so a trailing `   1.2 kB` value gap survives for the value split. (`_tv_name`
# collapses runs; this variant does not.)
_tv_label_raw () {
    local s="$1"
    s="${s//$_TV_VERT/ }"; s="${s//$_TV_BRANCH/ }"; s="${s//$_TV_LAST/ }"
    s="${s//$_TV_HORZ/ }"; s="${s//$_TV_TDOWN/ }"; s="${s//|/ }"; s="${s//\\/ }"
    s="${s#"${s%%[![:space:]]*}"}"
    while [[ "$s" == '+'* || "$s" == '`'* || "$s" == '-'* ]]; do s="${s#?}"; done
    s="${s#"${s%%[![:space:]]*}"}"
    printf '%s' "$s"
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
    # Strip a LEADING ASCII branch marker (`+---`, `` `-- ``, leading dashes left
    # by the box-glyph pass) so the name isn't prefixed with connector debris.
    # Only leading runs are removed — an internal hyphen (dbus-daemon) survives.
    s="${s#"${s%%[![:space:]]*}"}"
    while [[ "$s" == '+'* || "$s" == '`'* || "$s" == '-'* ]]; do s="${s#?}"; done
    # collapse + trim via word-splitting
    local -a parts
    read -r -a parts <<< "$s"
    printf '%s' "${parts[*]}"
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line nm d

    # ANCESTOR tracking: a tree is only tidy if each node carries its context.
    # A depth-keyed stack holds the name at each level so every row gets its
    # immediate `parent` (the reviewer's "the thing one level up") — turning a
    # flat depth/name dump into a navigable parent -> child edge list. A
    # trailing metric on the label (broot's `main.rs   1.2 kB`, a size after a
    # 2+-space gap) is split off into a `value` column so the number isn't
    # welded to the name. The implicit depth-0 root (the bare first line) is
    # seeded as the parent of depth-1 nodes.
    local -a _stack=()
    local _root=""
    local _first; _first="$(printf '%s\n' "$text" | sed -n '/[^[:space:]]/{p;q}')"
    if ! _tv_is_node "$_first"; then
        _root="$(_tv_name "$_first")"
        _stack[0]="$_root"
    fi

    while IFS= read -r line; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _tv_is_node "$line" || continue

        d="$(_tv_depth "$line")"
        # Split a trailing value off the RAW (uncollapsed) label so the 2+-space
        # gap before a metric survives (broot's `main.rs   1.2 kB`).
        local _raw _val=""
        _raw="$(_tv_label_raw "$line")"
        if [[ "$_raw" =~ ^(.*[^[:space:]])[[:space:]][[:space:]]+([0-9].*)$ ]]; then
            _raw="${BASH_REMATCH[1]}"; _val="${BASH_REMATCH[2]}"
        fi
        # collapse the (value-stripped) label to the clean name
        local _np; read -r -a _np <<< "$_raw"; nm="${_np[*]}"
        [[ -z "$nm" ]] && continue

        # parent = the name recorded at the level just above this node.
        local _parent="${_stack[$((d - 1))]:-$_root}"
        _stack[$d]="$nm"
        # a deeper level's stale entries can't be this node's ancestors
        local _si
        for _si in "${!_stack[@]}"; do [[ $_si -gt $d ]] && unset '_stack[$_si]'; done

        entry=$((entry + 1))
        result+="entry${entry}.depth ${d}"$'\n'
        [[ -n "$_parent" ]] && result+="entry${entry}.parent ${_parent}"$'\n'
        result+="entry${entry}.name ${nm}"$'\n'
        [[ -n "$_val" ]] && result+="entry${entry}.value ${_val}"$'\n'
    done <<< "$text"

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
