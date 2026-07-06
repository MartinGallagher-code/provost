#!/bin/bash
## Name: aligned-columns
## Description: Extract fields from whitespace-aligned columnar output (ps, df, mount, etc.)
## Version: 3.1
## Priority: 55
## Technique: yes
## Sample: samples/aligned-columns/basic.txt

# Echo the block with a leading `ls -l`-style "total <n>" summary line removed
# (it is a block-count preamble, not a data row).
_ac_body () {
    local text="$1" seen=0 _l out=""
    while IFS= read -r _l; do
        if [[ $seen -eq 0 && -n "${_l//[[:space:]]/}" ]]; then
            seen=1
            [[ "$_l" =~ ^[[:space:]]*total[[:space:]]+[0-9]+[[:space:]]*$ ]] && continue
        fi
        out+="$_l"$'\n'
    done <<< "$text"
    printf '%s' "$out"
}

# Analyse a block as a whitespace-columnar table. Prints "<mode> <ncols>":
#   HDR  n — first non-blank line is a label header (n columns)
#   HDR2 n — two-line header (group row + field row); field row has n columns
#   HL   n — headerless table (synthesise c1..cN); n = modal column count
# Prints nothing (returns 1) if the block isn't a consistent columnar table.
#
# Header vs headerless: a header row is all labels, so the first line having a
# digit-bearing token (a path, IP, date, count) means the table is headerless
# (who, mount, ls -l). Headerless needs >=3 consistent columns so it can't
# swallow 2-column key/value input handled by colons/equals/yaml.
_ac_shape () {
    local text; text="$(_ac_body "$1")"
    local counts=() hasdig=() idx=0 _line
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        local _tk; _tk=(); read -ra _tk <<< "$_line"
        counts+=("${#_tk[@]}")
        local d=0 t
        for t in "${_tk[@]}"; do [[ "$t" =~ [0-9] ]] && { d=1; break; }; done
        hasdig+=("$d")
        [[ $idx -ge 40 ]] && break
    done <<< "$text"

    local nlines=${#counts[@]}
    [[ $nlines -lt 2 ]] && return 1
    [[ ${counts[0]} -lt 2 ]] && return 1

    # Two-line header: first two lines are label-only, the field row has more
    # columns than the group row, and data (digits) starts on line 3 — vmstat,
    # some sar/mpstat layouts.
    if [[ $nlines -ge 3 && ${hasdig[0]} -eq 0 && ${hasdig[1]} -eq 0 \
          && ${hasdig[2]} -eq 1 && ${counts[1]} -gt ${counts[0]} ]]; then
        printf 'HDR2 %s\n' "${counts[1]}"
        return 0
    fi

    if [[ ${hasdig[0]} -eq 0 ]]; then
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
    # output (ps, df, ss, iostat, netstat, top, lsblk, systemctl, mount, who,
    # vmstat, ls -l …) without a per-tool rule. Confidence scales with column
    # consistency so a clean table outranks the key/value parsers.
    local shape; shape="$(_ac_shape "$text")" || return 1
    local mode="${shape%% *}" n_h="${shape##* }"
    local hdr_lines=1
    case "$mode" in HL) hdr_lines=0 ;; HDR) hdr_lines=1 ;; HDR2) hdr_lines=2 ;; esac

    local idx=0 data_rows=0 consistent=0 header_caps=1 _line
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        local _tk; _tk=(); read -ra _tk <<< "$_line"
        local n=${#_tk[@]}
        if [[ $idx -le $hdr_lines ]]; then
            if [[ $idx -eq $hdr_lines ]]; then
                local t
                for t in "${_tk[@]}"; do [[ "$t" =~ [a-z] ]] && header_caps=0; done
            fi
            continue    # header row(s) are not data rows
        fi
        [[ $n -ge 2 ]] && data_rows=$((data_rows + 1))
        [[ $n -ge $((n_h - 1)) ]] && consistent=$((consistent + 1))
        [[ $idx -ge 40 ]] && break
    done <<< "$(_ac_body "$text")"
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

    # Collect non-blank lines (after dropping any `total <n>` preamble).
    local lines=() _l
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        lines+=("$_l")
    done <<< "$(_ac_body "$text")"

    # Header names: the header line's tokens (HDR/HDR2), or synthetic c1..cN (HL).
    local headers=() startidx=0 i
    case "$mode" in
        HDR)  read -ra headers <<< "${lines[0]}"; startidx=1 ;;
        HDR2) read -ra headers <<< "${lines[1]}"; startidx=2 ;;
        HL)   for ((i = 1; i <= ncols; i++)); do headers+=("c$i"); done; startidx=0 ;;
    esac
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
