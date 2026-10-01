#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: proc-net-snmp
## Description: Extract per-protocol SNMP counters from /proc/net/snmp
## Version: 1.0
## Priority: 9
## Sample: samples/proc-net-snmp/basic.txt

# /proc/net/snmp is a sequence of header/value line pairs, one pair per protocol:
#   Ip: Forwarding DefaultTTL InReceives ... OutRequests   <- column names
#   Ip: 2 64 1204832 ... 982341                            <- values
# A header line's first data token is a word; a value line's is numeric. We pair
# each value line with the most recent header for the same protocol label and
# emit one record per value line, columns taken from that paired header.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    local reh='(^|
)[A-Za-z][A-Za-z0-9]*:[[:space:]]+[A-Za-z]'
    local rev='(^|
)[A-Za-z][A-Za-z0-9]*:[[:space:]]+-?[0-9]'
    [[ "$text" =~ $reh ]] || return 1
    [[ "$text" =~ $rev ]] || return 1
    # The pairing strategy_extract needs: a value line whose protocol label
    # had a header line BEFORE it (`Ip: Forwarding …` then `Ip: 2 …`). Any
    # colon listing with one word value and one numeric value passed the two
    # regexes above, ranked first at 92 and extracted NOTHING — on a big
    # `Name: x` / `Size: 3` dump that cost two full bash extracts plus an
    # unpruned re-ranking. Declining exactly when the extract would be empty
    # leaves every ranked winner unchanged. (Skipped on the detection sample,
    # where a pair could lie in the unsampled middle: the full text decides.)
    [[ "${_FR_DET_SAMPLE:-0}" -eq 1 ]] && return 0
    _strat_pns_paired "$text"
}

# _strat_pns_paired TEXT — does a value line follow a header line of the
# same label (strategy_extract's condition for emitting anything)? A bare
# `:` label also answers yes: strategy_extract trips over it (an empty
# array subscript), and how that ends is left to strategy_extract as before.
_strat_pns_paired () {
    if (( ${#1} > _FR_BIG_BYTES )); then
        # BIG input: the same scan in awk (fields split as `read -a` splits)
        cat <<< "$1" | awk '
            NF >= 2 && $1 ~ /:$/ {
                l = substr($1, 1, length($1) - 1)
                if (l == "") { f = 1; exit }
                if ($2 ~ /^[-0-9]/) { if (l in H) { f = 1; exit } }
                else H[l] = 1
            }
            END { exit !f }'
        return
    fi
    local line
    local -A _pns_h=()
    _fr_lines "$1"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        local -a f=()
        { _fr_tok "$line"; f=("${_FR_TOK[@]}"); }
        [[ ${#f[@]} -lt 2 ]] && continue
        [[ "${f[0]}" == *: ]] || continue
        local label="${f[0]%:}" first="${f[1]}"
        [[ -n "$label" ]] || return 0
        if [[ "$first" == -* || "$first" == [0-9]* ]]; then
            [[ -n "${_pns_h[$label]:-}" ]] && return 0
        else
            _pns_h[$label]=1
        fi
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line n=0
    declare -A HDR=()

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue
        local -a f=()
        { _fr_tok "$line"; f=("${_FR_TOK[@]}"); }
        [[ ${#f[@]} -lt 2 ]] && continue
        [[ "${f[0]}" == *: ]] || continue

        local label="${f[0]%:}" first="${f[1]}"
        if [[ "$first" == -* || "$first" == [0-9]* ]]; then
            # value line: pair with stored header for this protocol
            local -a hcols=()
            # a value line with no header line before it is not snmp data
            [[ -n "${HDR[$label]:-}" ]] || continue
            { _fr_tok "${HDR[$label]}"; hcols=("${_FR_TOK[@]}"); }
            n=$((n + 1))
            result+="entry${n}.proto ${label}"$'\n'
            local i
            for ((i = 1; i < ${#f[@]}; i++)); do
                local col="${hcols[$((i - 1))]:-col$i}"
                result+="entry${n}.${col} ${f[$i]}"$'\n'
            done
        else
            # header line: remember its column names for this protocol
            HDR[$label]="${f[*]:1}"
        fi
    done

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
