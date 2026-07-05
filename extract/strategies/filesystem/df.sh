#!/bin/bash
## Name: df
## Description: Extract per-filesystem usage rows from `df` / `df -h` output
## Version: 1.0
## Priority: 22
## Sample: samples/df/basic.txt

# `df -h` output looks like:
#   Filesystem      Size  Used Avail Use% Mounted on
#   /dev/sda1       100G   40G   55G  43% /
#   tmpfs           7.9G     0  7.9G   0% /dev/shm
# `df` (no -h) has a "1K-blocks" column instead of "Size"; both share the
# distinctive "Filesystem ... Use% ... Mounted on" header. Each data row becomes
# an entry<N>.<field> group so the capture tidy melt renders one row per mount.
# Limitation: df wraps very long device names onto their own line; this v1 parses
# only single-line rows.

_DF_HEADER_RE='^Filesystem[[:space:]].*Mounted on'

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92

    _is_json "$text" && return 1

    local _has_header=0 _rows=0 _line
    while IFS= read -r _line; do
        if [[ "$_line" =~ $_DF_HEADER_RE ]]; then _has_header=1; continue; fi
        # A data row: name, four columns, a NN% use column, then a mount path.
        [[ "$_line" =~ [[:space:]][0-9]+%[[:space:]] ]] && _rows=$((_rows + 1))
    done <<< "$text"

    [[ $_has_header -eq 1 && $_rows -ge 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    printf '%s\n' "$text" | awk '
        $0 ~ /^Filesystem[[:space:]].*Mounted on/ { next }
        # A row has a Use% column (field 5) of the form NN%.
        $5 ~ /^[0-9]+%$/ && NF >= 6 {
            n++
            usep=$5; sub(/%$/, "", usep)
            mp=$6; for (i = 7; i <= NF; i++) mp = mp "_" $i
            printf "entry%d.filesystem %s\n", n, $1
            printf "entry%d.size %s\n",       n, $2
            printf "entry%d.used %s\n",       n, $3
            printf "entry%d.avail %s\n",      n, $4
            printf "entry%d.use_percent %s\n", n, usep
            printf "entry%d.mounted_on %s\n", n, mp
        }
        END { if (n > 0) printf "total_entries %d\n", n }
    '
}
