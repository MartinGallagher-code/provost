#!/bin/bash
## Name: aligned-columns
## Description: Extract fields from whitespace-aligned columnar output (ps, df, mount, etc.)
## Version: 3.1
## Priority: 55
## Technique: yes
## Sample: samples/aligned-columns/basic.txt

# Echo the block with leading preamble removed: an `ls -l` "total <n>" line, or
# short banner/preamble lines with <2 columns (e.g. `apt list`'s "Listing…"),
# but only when a real (>=2 column) table follows.
_ac_body () {
    local text="$1" _l _tk out="" started=0 has_table=0
    while IFS= read -r _l; do
        [[ -z "${_l//[[:space:]]/}" ]] && continue
        _tk=(); read -ra _tk <<< "$_l"
        [[ ${#_tk[@]} -ge 2 ]] && { has_table=1; break; }
    done <<< "$text"

    while IFS= read -r _l; do
        if [[ $started -eq 0 && -n "${_l//[[:space:]]/}" ]]; then
            _tk=(); read -ra _tk <<< "$_l"
            [[ "$_l" =~ ^[[:space:]]*total[[:space:]]+[0-9]+[[:space:]]*$ ]] && continue
            # A short word-like preamble line (e.g. `apt list`'s "Listing…") before
            # a real table — but NOT a `{`/`[`/`<` structural line (JSON/XML), which
            # must keep aligned-columns from matching those formats.
            [[ $has_table -eq 1 && ${#_tk[@]} -lt 2 && "$_l" =~ ^[[:space:]]*[A-Za-z] ]] && continue
            started=1
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
# Header vs headerless: a header row is labels; data rows carry more pure-numeric
# tokens (counts, sizes, percentages) than the header. So the block has a header
# when row 2 has more pure-numeric tokens than row 1 — this correctly treats
# `df -T` (whose header label `1K-blocks` merely contains a digit) as having a
# header, while `who`/`mount` (no numeric columns) stay headerless. Headerless
# needs >=3 consistent columns so it can't swallow 2-column key/value input.
_ac_shape () {
    local text; text="$(_ac_body "$1")"
    local counts=() dcount=() idx=0 _line first_line=""
    while IFS= read -r _line; do
        [[ -z "${_line//[[:space:]]/}" ]] && continue
        idx=$((idx + 1))
        [[ $idx -eq 1 ]] && first_line="$_line"
        local _tk; _tk=(); read -ra _tk <<< "$_line"
        counts+=("${#_tk[@]}")
        local d=0 t
        for t in "${_tk[@]}"; do [[ "$t" =~ [0-9] ]] && d=$((d + 1)); done
        dcount+=("$d")
        [[ $idx -ge 40 ]] && break
    done <<< "$text"

    local nlines=${#counts[@]}
    [[ $nlines -lt 2 ]] && return 1
    [[ ${counts[0]} -lt 2 ]] && return 1

    # Two-line header: rows 1-2 are label rows (no digit tokens), the field row has
    # more columns, and numeric data starts on row 3 — vmstat, some sar layouts.
    if [[ $nlines -ge 3 && ${dcount[0]} -eq 0 && ${dcount[1]} -eq 0 \
          && ${dcount[2]} -gt 0 && ${counts[1]} -gt ${counts[0]} ]]; then
        printf 'HDR2 %s\n' "${counts[1]}"
        return 0
    fi

    # Header detection. Row 1 is a label header when either:
    #   (a) it is an ALL-CAPS label row (systemctl/kubectl/ps — all-text tables), or
    #   (b) it contains no *value* token (a bare number, time, IP or date) while the
    #       data rows are more numeric than it. This treats df-T (header label
    #       `1K-blocks` is not a value) and free-h (unit values `7.8Gi`) as headed,
    #       but keeps log/record blocks headerless (who, mount, ip route, journalctl,
    #       last — whose first line already carries times/IPs/counts).
    local caps0=0; [[ ! "$first_line" =~ [a-z] ]] && caps0=1
    local v0=0 _t _t1arr; _t1arr=(); read -ra _t1arr <<< "$first_line"
    for _t in "${_t1arr[@]}"; do
        # value token = a number, optionally with a trailing unit (8.421s, 942ms,
        # 7.8Gi, 39%), or a time / IP / date. `1K-blocks` is NOT one (the hyphen),
        # so a df-T-style header label stays a header.
        [[ "$_t" =~ ^[0-9]+([.,][0-9]+)*[a-zA-Z%]*$ || "$_t" =~ ^[0-9]{1,2}:[0-9]{2} \
           || "$_t" =~ ^[0-9]+\.[0-9]+\.[0-9]+\. || "$_t" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]] && v0=$((v0 + 1))
    done
    local maxd=0 i
    for ((i = 1; i < nlines; i++)); do [[ ${dcount[$i]} -gt $maxd ]] && maxd=${dcount[$i]}; done
    if [[ $caps0 -eq 1 || ( $v0 -eq 0 && $maxd -gt ${dcount[0]} ) ]]; then
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
