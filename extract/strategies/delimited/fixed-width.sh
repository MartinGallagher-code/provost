#!/bin/bash
## Name: fixed-width
## Description: Fixed-width column format with header/separator
## Version: 1.0
## Priority: 30
## Sample: samples/fixed-width/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=65

    # Reject JSON-like input
    _is_json "$1" && return 1

    # Decline `+---+` box tables — psql-table's box parser owns those.
    local _bxl
    while IFS= read -r _bxl; do
        [[ "$_bxl" == *"+"* && "$_bxl" == *"---"* ]] || continue
        [[ "$_bxl" =~ ^[[:space:]]*[-+[:space:]]+$ ]] && return 1
    done <<< "$text"

    # Must have a separator line of dashes with gaps (scan line by line)
    local _det_line
    while IFS= read -r _det_line; do
        if [[ "$_det_line" =~ ^[-]+(\ +[-]+)+ ]]; then
            return 0
        fi
    done <<< "$text"

    return 1
}

_strat_fw_find_columns () {
    # Given a separator line like "-------  --------  --------   -----"
    # return column start:end positions
    local sep_line="$1"
    local positions=""
    local i=0
    local len=${#sep_line}
    local in_dash=0
    local col_start=0

    while [[ $i -lt $len ]]; do
        local ch="${sep_line:$i:1}"
        if [[ "$ch" == "-" ]]; then
            if [[ $in_dash -eq 0 ]]; then
                col_start=$i
                in_dash=1
            fi
        else
            if [[ $in_dash -eq 1 ]]; then
                # End of a dash column
                if [[ -n "$positions" ]]; then
                    positions+="|"
                fi
                positions+="${col_start}:${i}"
                in_dash=0
            fi
        fi
        i=$((i + 1))
    done

    # Handle last column if line ends with dashes
    if [[ $in_dash -eq 1 ]]; then
        if [[ -n "$positions" ]]; then
            positions+="|"
        fi
        positions+="${col_start}:${i}"
    fi

    # A column OWNS the gap up to the next column's start: a dash run only
    # marks where a column begins, and slicing at the run's own END truncates
    # any value wider than its run (heroku's `heroku-postgresql:standard-0`
    # under a 24-dash run lost its tail into the next column). The last
    # column runs to end-of-line.
    local stretched="" seg next_start
    local -a segs=()
    local IFS='|'
    read -ra segs <<< "$positions"
    local si
    for ((si = 0; si < ${#segs[@]}; si++)); do
        seg="${segs[$si]}"
        [[ -z "$seg" ]] && continue
        if [[ $((si + 1)) -lt ${#segs[@]} ]]; then
            next_start="${segs[$((si + 1))]%%:*}"
            seg="${seg%%:*}:$((next_start - 1))"
        else
            seg="${seg%%:*}:100000"
        fi
        [[ -n "$stretched" ]] && stretched+="|"
        stretched+="$seg"
    done

    echo "$stretched"
}

strategy_extract () {
    local text="$1"
    local result=""

    # Find the separator line
    local sep_line=""
    local header_line=""
    local sep_line_num=0
    local line_num=0
    local prev_line=""

    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if [[ "$line" =~ ^[-]+(\ +[-]+)+ ]]; then
            sep_line="$line"
            sep_line_num=$line_num
            header_line="$prev_line"
            break
        fi
        prev_line="$line"
    done <<< "$text"

    [[ -z "$sep_line" ]] && return

    # Get column positions from separator
    local col_positions
    col_positions=$(_strat_fw_find_columns "$sep_line")

    # Parse column positions into arrays
    local col_starts=""
    local col_ends=""
    local num_cols=0
    local old_ifs="$IFS"
    IFS='|'
    local pos_entries
    read -ra pos_entries <<< "$col_positions"
    IFS="$old_ifs"

    local p
    for p in "${pos_entries[@]}"; do
        [[ -z "$p" ]] && continue
        local cs="${p%%:*}"
        local ce="${p##*:}"
        col_starts="${col_starts}${cs} "
        col_ends="${col_ends}${ce} "
        num_cols=$((num_cols + 1))
    done

    # Extract header names using column positions
    local headers=""
    local ci=0
    local starts_arr
    local ends_arr
    read -ra starts_arr <<< "$col_starts"
    read -ra ends_arr <<< "$col_ends"

    for ((ci=0; ci<num_cols; ci++)); do
        local cs=${starts_arr[$ci]}
        local ce=${ends_arr[$ci]}
        local clen=$((ce - cs))
        local hdr="${header_line:$cs:$clen}"
        # Trim whitespace and replace spaces with underscores
        while [[ "$hdr" == " "* ]]; do hdr="${hdr# }"; done
        while [[ "$hdr" == *" " ]]; do hdr="${hdr% }"; done
        hdr="${hdr// /_}"
        if [[ -n "$headers" ]]; then
            headers+=" "
        fi
        headers+="$hdr"
    done

    local headers_arr
    read -ra headers_arr <<< "$headers"

    # Extract data rows (lines after separator)
    local row_num=0
    local past_sep=0
    while IFS= read -r line; do
        if [[ $past_sep -eq 0 ]]; then
            if [[ "$line" =~ ^[-]+(\ +[-]+)+ ]]; then
                past_sep=1
            fi
            continue
        fi

        [[ -z "$line" ]] && continue
        row_num=$((row_num + 1))

        # SOFT boundaries with a per-row cursor. A tool's separator rule can be
        # NARROWER than its own data (heroku-addons' 24-dash Plan run under a
        # 28-char plan name), and slicing hard at the rule's grid cut values
        # mid-word and bled their tails into the next column. Instead: a
        # column ends where the rule says — unless a word is straddling the
        # cut, in which case the column keeps the whole word and the next
        # column starts after it.
        local _fw_cursor=0 _fw_len=${#line}
        for ((ci=0; ci<num_cols; ci++)); do
            local cs=${starts_arr[$ci]}
            local ce=${ends_arr[$ci]}
            local hdr="${headers_arr[$ci]}"
            local val

            [[ $cs -lt $_fw_cursor ]] && cs=$_fw_cursor
            if [[ $ci -eq $((num_cols - 1)) ]]; then
                ce=$_fw_len
            else
                # extend through a straddling word
                while [[ $ce -lt $_fw_len && "${line:$ce:1}" != " " && "${line:$((ce - 1)):1}" != " " ]]; do
                    ce=$((ce + 1))
                done
            fi
            val="${line:$cs:$((ce - cs))}"
            _fw_cursor=$ce

            # Trim edges; spaces inside the value are preserved (the engine keeps
            # everything after the first space as the value).
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            [[ -z "$val" ]] && continue

            result+="row${row_num}.${hdr} ${val}"$'\n'
        done
    done <<< "$text"

    echo "$result"
}
