#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: two-col-gap
## Description: Two-column tables split by a 2+-space gap where the last column is free text
## Version: 1.0
## Priority: 54
## Sample: samples/two-col-gap/basic.txt

# The "2-col table, free-text last column" shape (a long-documented gap class):
#
#   unit                 execstart
#   nginx.service        /usr/sbin/nginx -g 'daemon off; master_process on;'
#   app.service          /opt/app --flags "--a=1 --b=2,3"
#
# A single-token key column, a run of >=2 spaces, then a value column that
# freely contains SINGLE spaces (shell commands, JSON arrays, descriptions).
# aligned-columns can't take these: the value's word count varies per row, so
# no consistent grid exists — it either declines (falling to line-records,
# which welds key and value into one cell) or grabs the first data row as a
# fake header. Splitting each line on its FIRST 2+-space run is exact here.
#
# Detection is deliberately strict — every non-blank line must fit, and at
# least one value must actually contain a space (a plain 2-col table without
# spacey values stays with aligned-columns, which already handles it):
#   - >=3 non-blank lines, all UNINDENTED
#   - every line: single-token first cell, a 2+-space gap, non-empty rest
#   - no tabs (tsv territory), first cells not colon-labels (colons territory)

# Split $1 on its FIRST run of >=2 spaces -> _TCG_KEY / _TCG_VAL (val trimmed).
_tcg_split () {
    local line="$1"
    _TCG_KEY=""; _TCG_VAL=""
    [[ "$line" =~ ^([^[:space:]]+)[\ ]{2,}(.+)$ ]] || return 1
    _TCG_KEY="${BASH_REMATCH[1]}"
    _TCG_VAL="${BASH_REMATCH[2]}"
    _TCG_VAL="${_TCG_VAL%"${_TCG_VAL##*[![:space:]]}"}"
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _STRATEGY_CONFIDENCE_REASON="2-col gap table (single-token key, free-text value)"
    local _l lines=0 spacey=0 colonish=0 vcounts=()
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        [[ "$_l" == [' 	']* ]] && return 1          # indented => not this shape
        [[ "$_l" == *'	'* ]] && return 1            # tabs => tsv territory
        _tcg_split "$_l" || return 1
        # The value must be ONE free-text column: a further 2+-space run inside
        # it means this is really a >=3-column aligned grid (zfs list, velero
        # get, any wide table) — aligned-columns' shape, never ours.
        [[ "$_TCG_VAL" =~ [\ ]{2,} ]] && return 1
        lines=$((lines + 1))
        # Free-text evidence must come from a DATA row (line >=2) — a 2-word
        # HEADER cell (`VOLUME NAME`, `CREATED AT`) over single-token values is
        # a plain 2-col table that aligned-columns already tidies perfectly.
        [[ $lines -ge 2 && "$_TCG_VAL" == *" "* ]] && spacey=$((spacey + 1))
        [[ "$_TCG_KEY" == *: ]] && colonish=$((colonish + 1))
        # Track each DATA value's word count — a value column whose counts are
        # (near-)uniform at >=2 tokens (`a1b2c3d [main]` on every git-worktree
        # row, rpm -V's `c /etc/...`) is a single-space-aligned GRID whose words
        # are really separate columns; welding them would LOSE structure. Free
        # text varies word to word; grids don't.
        if [[ $lines -ge 2 ]]; then
            local _vt; _vt=(); { _fr_tok "$_TCG_VAL"; _vt=("${_FR_TOK[@]}"); }
            vcounts+=("${#_vt[@]}")
        fi
    done
    _l=""
    [[ $lines -ge 3 ]] || return 1
    # Modal-share grid test: if one >=2-token count covers >=2/3 of the data
    # rows, this is a grid with at most a ragged straggler (git-worktree-list's
    # `(detached HEAD)` row among `sha [branch]` rows) — decline. Genuinely
    # free-text values (commands, JSON arrays) spread their counts wider, and
    # a modal count of 1 (mostly single-token values with a few multi-word
    # stragglers, getent-services style) is not a grid signal at all.
    if [[ ${#vcounts[@]} -ge 3 ]]; then
        local modal=0 best=0
        _fr_modal "${vcounts[@]}"; modal=$_FR_MODE; best=$_FR_MODE_N
        [[ $modal -ge 2 && $((best * 100 / ${#vcounts[@]})) -ge 66 ]] && return 1
        # A multi-token ROW-1 value whose word count EQUALS the modal data count
        # is a single-space-aligned grid whose header names line up over the
        # value words (lsblk's `NAME  SIZE TYPE MOUNTPOINT` over `500G disk …`)
        # — that's a real >=3-column table, aligned-columns' to keep.
        if [[ $modal -ge 2 ]]; then
            local _h1; _h1=""
            while IFS= read -r _l; do
                [[ "${_l}" != *[![:space:]]* ]] && continue
                _h1="$_l"; break
            done <<< "$text"
            if _tcg_split "$_h1"; then
                local _ht; _ht=(); { _fr_tok "$_TCG_VAL"; _ht=("${_FR_TOK[@]}"); }
                [[ ${#_ht[@]} -eq $modal ]] && return 1
            fi
        fi
    fi
    # At least one free-text DATA value — otherwise it's a plain 2-col grid
    # that aligned-columns already tidies; don't steal those.
    [[ $spacey -ge 1 ]] || return 1
    # Majority colon-suffixed keys is a `Label: value` block — colons' shape.
    [[ $((colonish * 2)) -ge $lines ]] && return 1
    _STRATEGY_CONFIDENCE=78
    return 0
}

strategy_extract () {
    local text="$1" result="" entry=0 _l
    # Header: row 1 when BOTH its cells are single tokens AND neither is
    # digit-leading — a `127.0.0.1  localhost` or `ssh  22/tcp` first row is
    # DATA (getent hosts/services style headerless lists); otherwise
    # synthesize A/B.
    local k1="" v1="" have=0 hk="A" hv="B" first=1
    _fr_lines "$text"
    for _l in "${_FR_LINES[@]}"; do
        [[ "${_l}" != *[![:space:]]* ]] && continue
        _tcg_split "$_l" || continue
        if [[ $first -eq 1 ]]; then
            first=0
            if [[ "$_TCG_VAL" != *" "* && "$_TCG_KEY" != [0-9]* && "$_TCG_VAL" != [0-9]* ]]; then
                hk="${_TCG_KEY//./_}"; hv="${_TCG_VAL//./_}"
                continue
            fi
        fi
        entry=$((entry + 1))
        result+="entry${entry}.${hk} ${_TCG_KEY}"$'\n'
        result+="entry${entry}.${hv} ${_TCG_VAL}"$'\n'
    done
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
