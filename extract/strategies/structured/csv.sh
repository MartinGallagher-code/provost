#!/bin/bash
## Name: csv
## Description: Extract field names and values from CSV files (comma-delimited with header row)
## Version: 2.0
## Priority: 14
## Sample: samples/csv/basic.csv

# Split one CSV line into _CSV_FIELDS, RFC-4180-style. A double quote is
# STRUCTURAL only at field start (start of line, right after a comma, or after
# only spaces since the comma) — `3/4"` keeps its literal inch mark, while
# `"Cash, operating"` protects its comma. Inside a quoted field `""` is an
# escaped quote. Sets _CSV_OPEN=1 when the line ends inside an open quoted
# field (i.e. the logical record continues on the next physical line).
_strat_csv_split () {
    local line="$1" field="" in_quotes=0 at_start=1 i c
    _CSV_FIELDS=()
    _CSV_OPEN=0
    for ((i=0; i<${#line}; i++)); do
        c="${line:$i:1}"
        if [[ $in_quotes -eq 1 ]]; then
            if [[ "$c" == '"' ]]; then
                if [[ "${line:$((i+1)):1}" == '"' ]]; then
                    field+='"'
                    ((i++))
                else
                    in_quotes=0
                fi
            else
                field+="$c"
            fi
        elif [[ "$c" == '"' && $at_start -eq 1 ]]; then
            in_quotes=1
            at_start=0
        elif [[ "$c" == ',' ]]; then
            _CSV_FIELDS+=("$field")
            field=""
            at_start=1
        else
            field+="$c"
            [[ "$c" != " " ]] && at_start=0
        fi
    done
    _CSV_FIELDS+=("$field")
    _CSV_OPEN=$in_quotes
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _STRATEGY_CONFIDENCE_REASON="consistent comma count across lines"

    # Check first 5 non-empty lines for CSV characteristics
    local line_count=0
    local header_commas=0
    local with_commas=0
    local matching=0
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        # Ignore commas inside parenthesised groups — those are not CSV field
        # separators (e.g. `mount` options `(rw,nosuid,nodev)`). Counting only
        # top-level commas keeps csv from claiming such lines.
        local _sep="${_line//(*)/}"
        # Count only commas OUTSIDE quoted fields: a quoted value's embedded
        # commas ("1,234,567.89", "go,api,server") are data, not separators.
        # Without this, quoted CSV fails the consistency check below and falls
        # through to a worse parser.
        _strat_csv_split "$_sep"
        local c=$(( ${#_CSV_FIELDS[@]} - 1 ))
        if [[ $line_count -eq 0 ]]; then
            # First line must have commas
            [[ $c -eq 0 ]] && return 1
            # Decline colon-delimited "key: value" lines whose commas are just
            # prose inside the value (e.g. `file` output: "name: desc, more, ...").
            # A `: ` before the first comma means this belongs to colons, not csv.
            local _before="${_sep%%,*}"
            [[ "$_before" == *": "* ]] && return 1
            header_commas=$c
        fi
        if [[ $c -gt 0 ]]; then
            with_commas=$((with_commas + 1))
            local diff=$(( header_commas - c ))
            if [[ ${diff#-} -le 1 ]]; then
                matching=$((matching + 1))
            fi
        fi
        line_count=$((line_count + 1))
        [[ $line_count -ge 5 ]] && break
    done <<< "$text"
    [[ $line_count -lt 2 ]] && return 1

    # Real CSV: most lines should have commas (allow at most 1 without)
    [[ $with_commas -lt $((line_count - 1)) ]] && return 1

    # Of lines with commas, most should have consistent counts
    local threshold=3
    if [[ $with_commas -lt 3 ]]; then
        threshold=$with_commas
    fi
    [[ $matching -ge $threshold ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"

    # Strip UTF-8 BOM if present (EF BB BF)
    local bom
    bom=$(printf '\xef\xbb\xbf')
    text="${text#"$bom"}"

    # Pre-process: join multi-line quoted fields. A line whose RFC-4180 parse
    # ends inside an OPEN quoted field continues on the next physical line.
    # (Counting raw quote parity here would misfire on literal mid-field quotes
    # — `3/4",100` is a complete row, not a continuation.)
    local processed=""
    local pending=""
    while IFS= read -r line; do
        if [[ -n "$pending" ]]; then
            pending+=" ${line}"
            _strat_csv_split "$pending"
            if [[ $_CSV_OPEN -eq 0 ]]; then
                processed+="${pending}"$'\n'
                pending=""
            fi
        else
            _strat_csv_split "$line"
            if [[ $_CSV_OPEN -eq 1 ]]; then
                pending="$line"
            else
                processed+="${line}"$'\n'
            fi
        fi
    done <<< "$text"
    if [[ -n "$pending" ]]; then
        processed+="${pending}"$'\n'
    fi
    # Remove empty lines
    local _cleaned=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        _cleaned+="$_line"$'\n'
    done <<< "$processed"
    text="$_cleaned"

    # Parse header row for field names
    local header=""
    local _first=1
    while IFS= read -r _line; do
        if [[ $_first -eq 1 ]]; then
            header="$_line"
            _first=0
            break
        fi
    done <<< "$text"

    # Split header quote-aware too — `"Last, First",Dept` is two columns, and a
    # naive IFS=',' split would misalign every data row against it.
    local headers; headers=()
    _strat_csv_split "$header"
    headers=("${_CSV_FIELDS[@]}")

    # Headerless numeric CSV — data loggers (fio --write_bw_log / --write_iops_log,
    # `sar -o` CSV, collectd) emit raw rows with no header. If the FIRST row's
    # fields are all numeric, there is no header (a real header carries
    # non-numeric column names): synthesise A,B,C… and keep row 1 as data.
    local _headerless=1
    [[ ${#headers[@]} -lt 2 ]] && _headerless=0
    local _hf
    for _hf in "${headers[@]}"; do
        _hf="${_hf#"${_hf%%[![:space:]]*}"}"; _hf="${_hf%"${_hf##*[![:space:]]}"}"
        [[ -z "$_hf" || "$_hf" =~ ^-?[0-9]+([.][0-9]+)?%?$ ]] || { _headerless=0; break; }
    done
    if [[ $_headerless -eq 1 ]]; then
        local _hn=${#headers[@]} _hk
        headers=()
        for ((_hk=1; _hk<=_hn; _hk++)); do headers+=("$(_col_letter "$_hk")"); done
    fi

    # Clean BOM and whitespace from header names
    local hi
    for ((hi=0; hi<${#headers[@]}; hi++)); do
        local _h="${headers[$hi]}"
        while [[ "$_h" == " "* || "$_h" == "	"* ]]; do _h="${_h#?}"; done
        while [[ "$_h" == *" " || "$_h" == *"	" ]]; do _h="${_h%?}"; done
        headers[$hi]="$_h"
    done

    # Process each data row. Each row is emitted as an indexed record group
    # (entry<N>.<column>) so the capture tidy melt renders one row per record
    # with shared columns — rather than welding every row's cells into a single
    # wide record with duplicate column names (where the format layer would even
    # drop a later row's field that repeats an earlier row's value).
    local result=""
    local row_num=0
    local rec=0
    while IFS= read -r line; do
        row_num=$((row_num + 1))
        [[ $row_num -eq 1 && $_headerless -eq 0 ]] && continue  # skip header (unless headerless)
        [[ -z "$line" ]] && continue

        # Parse the line field by field (same RFC-4180 splitter as the header:
        # quotes structural only at field start, "" escapes, literal otherwise)
        local values; values=()
        _strat_csv_split "$line"
        values=("${_CSV_FIELDS[@]}")

        rec=$((rec + 1))
        local j
        for ((j=0; j<${#headers[@]}; j++)); do
            local name="${headers[$j]}"
            local value="${values[$j]:-}"
            # Clean up name and value
            name="${name// /_}"
            name="${name//\"/}"
            name="${name#_}"
            name="${name%_}"
            name="${name//./_}"   # '.' would break the tidy melt's group key split
            # NOTE: no blanket quote-strip on the value — the splitter already
            # consumed the structural quotes, so any quote still present is
            # literal data (3/4" inch marks, escaped "" quotes).
            # Trim leading/trailing whitespace (the header fields are trimmed the
            # same way above) so a ", value" delimiter's space isn't turned into a
            # leading underscore by the space->underscore step below.
            while [[ "$value" == " "* || "$value" == "	"* ]]; do value="${value#?}"; done
            while [[ "$value" == *" " || "$value" == *"	" ]]; do value="${value%?}"; done
            [[ -z "$name" ]] && continue
            [[ -z "$value" ]] && continue
            result+="entry${rec}.${name} ${value}"$'\n'
        done
    done <<< "$text"

    [[ $rec -gt 0 ]] && result+="total_entries ${rec}"$'\n'
    echo "$result"
}
