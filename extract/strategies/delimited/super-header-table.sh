#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: super-header-table
## Description: monitoring snapshots whose columns carry a GROUP header row above the column names (amdgpu-top) -> group/metric/value rows — hint-routed
## Version: 1.0
## Priority: 45
## Sample: samples/super-header-table/basic.txt

# `amdgpu-top` heads its counters with TWO header rows — a group row spanning
# several columns each, then the column names:
#
#   GRBM              GRBM2             VRAM (MiB)        GTT (MiB)
#   GFX  Comp  Vertex  TA   TC   EA    Used   Total     Used   Total
#    98    44      12   88   90   76  22018   24560     1204   16384
#
# `Used` and `Total` appear twice and mean different things, so the column
# names alone are not a key — the reviewer's super-header note. Neither header
# row is a record, and no row parser could see that, so the whole thing came out
# as seven verbatim lines of `text-lines`.
#
# The tidy form is long, which is also the honest shape for a snapshot that has
# exactly one sample per column:
#
#   group        metric   value
#   GRBM         GFX      98
#   VRAM (MiB)   Used     22018
#   GTT (MiB)    Used     1204
#
# Everything else in the input is kept too, or this would trade one kind of
# loss for another: a `Key: value` line becomes a group-less row, and a bare
# label over a single-header table (`Sensors`) becomes that table's group.
#
# GROUP ASSIGNMENT is by nearest column start, not by containment: a group
# label sits roughly, not exactly, over its first column (`VRAM (MiB)` starts
# at 36 above a `Used` at 35). So each group label claims the column whose start
# is closest to its own, and the columns between two claims belong to the
# earlier one.
#
# HINT-ONLY: two stacked header rows are too weak a signal to auto-fire on.

# Is this line data rather than header? Data if most of its tokens are numeric.
_sht_is_data () {
    local n=0 num=0 tok
    for tok in $1; do
        n=$((n + 1))
        [[ "$tok" =~ ^[+-]?[0-9][0-9.,]*[%a-zA-Z/]*$ ]] && num=$((num + 1))
    done
    [[ $n -gt 0 && $((num * 2)) -ge $n ]]
}

# Start offsets of each whitespace-separated token, into _SHT_POS.
_sht_starts () {
    local l="$1"
    local i n=0 c prev=' '
    n=${#l}
    _SHT_POS=()
    for ((i = 0; i < n; i++)); do
        c="${l:i:1}"
        [[ "$c" != ' ' && "$c" != $'\t' && ( "$prev" == ' ' || "$prev" == $'\t' ) ]] && _SHT_POS+=("$i")
        prev="$c"
    done
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    local -a blk=()

    _sht_flush () {
        # One blank-line block: optional label / kv lines, then header row(s),
        # then data rows.
        local nb=${#blk[@]}
        [[ $nb -gt 0 ]] || return 0
        local i first_data=-1
        for ((i = 0; i < nb; i++)); do
            if _sht_is_data "${blk[$i]}"; then first_data=$i; break; fi
        done
        if [[ $first_data -lt 1 ]]; then
            # No header above data (or no data at all): keep any `Key: value`
            # lines rather than dropping the block.
            for ((i = 0; i < nb; i++)); do
                if [[ "${blk[$i]}" == *": "* ]]; then
                    local k="${blk[$i]%%: *}" v="${blk[$i]#*: }"
                    entry=$((entry + 1))
                    result+="entry${entry}.metric ${k}"$'\n'
                    result+="entry${entry}.value ${v}"$'\n'
                fi
            done
            return 0
        fi

        # The header is the run of lines immediately above the first data row;
        # anything before that is preamble (a `Key: value` line, or a label).
        local hdr2=$((first_data - 1))
        local hdr1=$((hdr2 - 1))
        local -a names=() groups=()
        local nnames
        read -ra names <<< "${blk[$hdr2]}"
        nnames=${#names[@]}

        local label="" have_super=0
        local -a gname=() gpos=()
        if [[ $hdr1 -ge 0 ]] && ! _sht_is_data "${blk[$hdr1]}"; then
            local -a h1=()
            read -ra h1 <<< "${blk[$hdr1]}"
            if [[ ${#h1[@]} -gt 1 && ${#h1[@]} -lt $nnames ]]; then
                have_super=1
            elif [[ ${#h1[@]} -ge 1 && ${#h1[@]} -lt $nnames ]]; then
                label="${blk[$hdr1]}"
            fi
        fi

        if [[ $have_super -eq 1 ]]; then
            # Group labels may themselves contain spaces (`VRAM (MiB)`), so they
            # are read off by their start offsets: a new group begins wherever
            # the previous one's text ends and 2+ spaces separate them.
            local -a _SHT_POS=()
            local seg rest="${blk[$hdr1]}"
            # Split the super-header on runs of 2+ spaces.
            local tmp="$rest" g start=0 idx
            gname=(); gpos=()
            idx=0
            while [[ -n "${tmp//[[:space:]]/}" ]]; do
                # advance to first non-space
                while [[ "${tmp:0:1}" == " " ]]; do tmp="${tmp:1}"; idx=$((idx + 1)); done
                g=""
                # take until 2+ spaces
                while [[ -n "$tmp" ]]; do
                    if [[ "${tmp:0:2}" == "  " ]]; then break; fi
                    g+="${tmp:0:1}"; tmp="${tmp:1}"; idx=$((idx + 1))
                done
                g="${g%"${g##*[![:space:]]}"}"
                [[ -n "$g" ]] && { gname+=("$g"); gpos+=("$((idx - ${#g}))"); }
            done

            # Column start offsets of the NAME row.
            _sht_starts "${blk[$hdr2]}"
            local -a cpos=("${_SHT_POS[@]}")
            # Each group claims the column whose start is nearest its own.
            local gi ci best bestd d
            groups=()
            for ((ci = 0; ci < nnames; ci++)); do groups[$ci]=""; done
            for ((gi = 0; gi < ${#gname[@]}; gi++)); do
                best=0; bestd=999999
                for ((ci = 0; ci < nnames && ci < ${#cpos[@]}; ci++)); do
                    d=$(( ${cpos[$ci]} - ${gpos[$gi]} )); [[ $d -lt 0 ]] && d=$((-d))
                    if [[ $d -lt $bestd ]]; then bestd=$d; best=$ci; fi
                done
                groups[$best]="${gname[$gi]}"
            done
            # Columns between claims belong to the group that claimed earlier.
            local carry=""
            for ((ci = 0; ci < nnames; ci++)); do
                if [[ -n "${groups[$ci]}" ]]; then carry="${groups[$ci]}"; else groups[$ci]="$carry"; fi
            done
        else
            local ci
            for ((ci = 0; ci < nnames; ci++)); do groups[$ci]="$label"; done
        fi

        # Preamble above the header: keep `Key: value` lines.
        local top=$((hdr2 - 1)); [[ $have_super -eq 1 ]] && top=$((hdr1 - 1))
        [[ -n "$label" ]] && top=$((hdr1 - 1))
        for ((i = 0; i <= top; i++)); do
            if [[ "${blk[$i]}" == *": "* ]]; then
                local k2="${blk[$i]%%: *}" v2="${blk[$i]#*: }"
                entry=$((entry + 1))
                result+="entry${entry}.metric ${k2}"$'\n'
                result+="entry${entry}.value ${v2}"$'\n'
            fi
        done

        # Data rows.
        local ndata=0 r
        for ((i = first_data; i < nb; i++)); do
            _sht_is_data "${blk[$i]}" && ndata=$((ndata + 1))
        done
        r=0
        for ((i = first_data; i < nb; i++)); do
            _sht_is_data "${blk[$i]}" || continue
            r=$((r + 1))
            local -a vals=()
            read -ra vals <<< "${blk[$i]}"
            [[ ${#vals[@]} -eq $nnames ]] || continue
            local ci2
            for ((ci2 = 0; ci2 < nnames; ci2++)); do
                entry=$((entry + 1))
                [[ $ndata -gt 1 ]] && result+="entry${entry}.row ${r}"$'\n'
                [[ -n "${groups[$ci2]}" ]] && result+="entry${entry}.group ${groups[$ci2]}"$'\n'
                result+="entry${entry}.metric ${names[$ci2]}"$'\n'
                result+="entry${entry}.value ${vals[$ci2]}"$'\n'
            done
        done
    }

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "${line//[[:space:]]/}" ]]; then
            _sht_flush; blk=()
            continue
        fi
        blk+=("$line")
    done <<< "$text"
    _sht_flush

    [[ $entry -ge 2 ]] || return 0
    result+="total_entries ${entry}"$'\n'
    printf '%s' "$result"
}

strategy_detect () {
    # HINT-ONLY (see header) — never auto-fires.
    _STRATEGY_CONFIDENCE=0
    return 1
}
