#!/bin/bash
## Name: iozone
## Description: Extract filesystem benchmark results from iozone output
## Version: 1.0
## Priority: 10
## Sample: samples/iozone/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Look for "iozone" or "Iozone" marker
    if [[ "$text" != *[Ii][Oo][Zz][Oo][Nn][Ee]* ]]; then
        return 1
    fi
    # Require "reclen"
    [[ "$text" == *"reclen"* ]] || return 1
    # Require "write" or "read" or "KB/sec"
    if [[ "$text" == *"write"* || "$text" == *"read"* || "$text" == *"KB/sec"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local data_rows=0
    local data_lines=""

    # Extract version: "Version $Revision: 3.489 $"
    local ver_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Version"* && "$_line" == *"Revision"* ]]; then
            ver_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$ver_line" ]]; then
        local version="${ver_line#*Revision: }"
        version="${version%%\$*}"
        while [[ "$version" == *" " ]]; do version="${version% }"; done
        while [[ "$version" == " "* ]]; do version="${version# }"; done
        [[ -n "$version" ]] && result+="version ${version}"$'\n'
    fi

    # Extract file size: "File size set to N kB"
    local fsize_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"File size"* ]]; then
            fsize_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$fsize_line" ]]; then
        local fsize
        fsize=$(_strat_iozone_extract_number "$fsize_line")
        [[ -n "$fsize" ]] && result+="file_size_kB ${fsize}"$'\n'
    fi

    # Extract record size: "Record Size N kB"
    local rsize_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *"Record Size"* ]]; then
            rsize_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$rsize_line" ]]; then
        local rsize
        rsize=$(_strat_iozone_extract_number "$rsize_line")
        [[ -n "$rsize" ]] && result+="record_size_kB ${rsize}"$'\n'
    fi

    # Count data rows first (lines starting with numbers after the header)
    local in_table=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect header row: "kB  reclen"
        if [[ "$line" == *"kB"* ]] && [[ "$line" == *"reclen"* ]]; then
            in_table=1
            continue
        fi

        [[ $in_table -eq 0 ]] && continue

        # Skip "random    random" sub-header lines
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        while [[ "$trimmed" == *" " ]]; do trimmed="${trimmed% }"; done
        if [[ "$trimmed" == "random"* ]]; then
            continue
        fi

        # Data rows start with whitespace then a number
        if [[ "$line" =~ ^[[:space:]]+[0-9] ]]; then
            data_rows=$((data_rows + 1))
            data_lines+="${line}"$'\n'
        fi
    done <<< "$text"

    # Parse data rows
    local row_num=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        row_num=$((row_num + 1))

        read -ra _arr <<< "$line"
        local size="${_arr[0]}"
        local reclen="${_arr[1]}"
        local write="${_arr[2]}"
        local rewrite="${_arr[3]}"
        local read_val="${_arr[4]}"
        local reread="${_arr[5]}"
        local rread="${_arr[6]}"
        local rwrite="${_arr[7]}"

        # Validate: size should be numeric
        [[ "$size" =~ ^[0-9] ]] || continue

        local prefix=""
        if [[ $data_rows -gt 1 ]]; then
            prefix="${size}k."
        fi

        [[ -n "$write" ]] && result+="${prefix}write ${write}"$'\n'
        [[ -n "$rewrite" ]] && result+="${prefix}rewrite ${rewrite}"$'\n'
        [[ -n "$read_val" ]] && result+="${prefix}read ${read_val}"$'\n'
        [[ -n "$reread" ]] && result+="${prefix}reread ${reread}"$'\n'
        [[ -n "$rread" ]] && result+="${prefix}random_read ${rread}"$'\n'
        [[ -n "$rwrite" ]] && result+="${prefix}random_write ${rwrite}"$'\n'
    done <<< "$data_lines"

    echo "$result"
}

_strat_iozone_extract_number () {
    local line="$1"
    # Strip non-digits from the front, then get first word
    local stripped="$line"
    while [[ -n "$stripped" && ! "$stripped" =~ ^[0-9] ]]; do
        stripped="${stripped#?}"
    done
    read -ra _arr <<< "$stripped"
    echo "${_arr[0]}"
}
