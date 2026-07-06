#!/bin/bash
## Name: aligned-columns
## Description: Extract fields from whitespace-aligned columnar output (ps, df, mount, etc.)
## Version: 3.0
## Priority: 55
## Technique: yes
## Sample: samples/aligned-columns/basic.txt

# Analyse a block as a whitespace-columnar table. Prints "<mode> <ncols>":
#   HDR n  — first non-blank line is a label header (n columns)
#   HL  n  — headerless table (synthesise c1..cN); n = modal column count
# Prints nothing (returns 1) if the block isn't a consistent columnar table.
#
# Header vs headerless: a header row is all labels, so the first line having a
# digit-bearing token (a path, IP, date, count) means the table is headerless
# (who, mount, ls -l). Headerless needs >=3 consistent columns so it can't
# swallow 2-column key/value input handled by colons/equals/yaml.
_ac_shape () {
    local text="$1"
    local counts=() first_has_digit=0 idx=0 _line
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        local _tk; _tk=(); read -ra _tk <<< "$_line"
        counts+=("${#_tk[@]}")
        if [[ $idx -eq 1 ]]; then
            local t
            for t in "${_tk[@]}"; do [[ "$t" =~ [0-9] ]] && first_has_digit=1; done
        fi
        [[ $idx -ge 40 ]] && break
    done <<< "$text"

    [[ ${#counts[@]} -lt 2 ]] && return 1
    [[ ${counts[0]} -lt 2 ]] && return 1

    if [[ $first_has_digit -eq 0 ]]; then
        printf 'HDR %s\n' "${counts[0]}"
        return 0
    fi

    # Headerless: require a modal column count (>=3) shared by most lines.
    local mode=0 best=0 c d k
    for c in "${counts[@]}"; do
        k=0
        for d in "${counts[@]}"; do [[ "$d" -eq "$c" ]] && k=$((k + 1)); done
        [[ $k -gt $best ]] && { best=$k; mode=$c; }
    done
    [[ $mode -lt 3 ]] && return 1
    [[ $(( best * 100 / ${#counts[@]} )) -lt 60 ]] && return 1
    printf 'HL %s\n' "$mode"
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    # Structural detection: a header row (or a headerless block) of columns with
    # a consistent count. Recognises the whole class of whitespace-columnar tool
    # output (ps, df, ss, iostat, netstat, top, lsblk, systemctl, mount, who …)
    # without a per-tool rule. Confidence scales with column consistency so a
    # clean table outranks the key/value parsers that would collapse it.
    local shape; shape="$(_ac_shape "$text")" || return 1
    local mode="${shape%% *}" n_h="${shape##* }"

    local idx=0 data_rows=0 consistent=0 header_caps=1 _line
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        local _tk; _tk=(); read -ra _tk <<< "$_line"
        local n=${#_tk[@]}
        if [[ "$mode" == HDR && $idx -eq 1 ]]; then
            local t
            for t in "${_tk[@]}"; do [[ "$t" =~ [a-z] ]] && header_caps=0; done
            continue    # header row is not a data row
        fi
        [[ $n -ge 2 ]] && data_rows=$((data_rows + 1))
        [[ $n -ge $((n_h - 1)) ]] && consistent=$((consistent + 1))
        [[ $idx -ge 40 ]] && break
    done <<< "$text"
    [[ "$mode" == HL ]] && header_caps=0

    [[ $data_rows -lt 1 ]] && return 1

    local conf=40
    [[ $data_rows -ge 2 ]] && conf=$((conf + 10))
    conf=$((conf + consistent * 20 / data_rows))   # column-consistency bonus (0..20)
    [[ $header_caps -eq 1 ]] && conf=$((conf + 5))  # ALL-CAPS header (ps/df/ss style)
    [[ "$mode" == HL ]] && conf=$((conf - 10))      # headerless is a weaker signal
    [[ $conf -gt 75 ]] && conf=75
    [[ $conf -lt 1 ]] && conf=1
    _STRATEGY_CONFIDENCE=$conf
    return 0
}

strategy_extract () {
    local text="$1"
    local shape; shape="$(_ac_shape "$text")" || { echo ""; return 0; }
    local mode="${shape%% *}" ncols="${shape##* }"

    # Collect non-blank lines.
    local lines=() _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        lines+=("$_l")
    done <<< "$text"

    # Header names: the first line's tokens (HDR), or synthetic c1..cN (HL).
    local headers=() startidx=0 i
    if [[ "$mode" == HDR ]]; then
        read -ra headers <<< "${lines[0]}"
        startidx=1
    else
        for ((i = 1; i <= ncols; i++)); do headers+=("c$i"); done
        startidx=0
    fi
    # Field names must not contain '.' (the tidy melt splits entry<N>.<field> on
    # the first dot).
    for ((i = 0; i < ${#headers[@]}; i++)); do headers[$i]="${headers[$i]//./_}"; done

    # Emit each data line as an indexed group (entry<N>.<field>) so the tidy melt
    # renders one row per line with shared columns.
    local result="" entry=0 li
    for ((li = startidx; li < ${#lines[@]}; li++)); do
        local values; values=(); read -ra values <<< "${lines[$li]}"
        entry=$((entry + 1))
        for ((i = 0; i < ${#headers[@]}; i++)); do
            local name="${headers[$i]}" value="${values[$i]:-}"
            [[ -z "$value" ]] && continue
            # Last column absorbs any extra trailing tokens.
            if [[ $i -eq $((${#headers[@]} - 1)) && ${#values[@]} -gt ${#headers[@]} ]]; then
                local j
                for ((j = i + 1; j < ${#values[@]}; j++)); do value+="_${values[$j]}"; done
            fi
            result+="entry${entry}.${name} ${value}"$'\n'
        done
    done

    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
