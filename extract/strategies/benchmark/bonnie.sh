#!/bin/bash
## Name: bonnie
## Description: Extract filesystem benchmark results from bonnie++ output
## Version: 1.0
## Priority: 10
## Sample: samples/bonnie/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *[Bb][Oo][Nn][Nn][Ii][Ee]* ]]; then
        return 0
    fi
    if [[ "$text" == *"Sequential Output"* ]] && \
       [[ "$text" == *"Sequential Input"* ]]; then
        return 0
    fi
    # CSV format: header line with bonnie-specific columns
    if [[ "$text" == *"putc"*"put_block"*"rewrite"*"getc"*"get_block"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Version line: "Version 2.00a" or "Bonnie++ version 2.00a"
    local ver_line=""
    while IFS= read -r _line; do
        if [[ "$_line" == *[Vv]ersion* ]]; then
            ver_line="$_line"
            break
        fi
    done <<< "$text"
    if [[ -n "$ver_line" ]]; then
        local version
        read -ra _arr <<< "$ver_line"
        version="${_arr[${#_arr[@]}-1]}"
        [[ -n "$version" ]] && result+="version ${version}"$'\n'
    fi

    # CSV format: detect if lines have bonnie-specific CSV headers
    if [[ "$text" == *"putc"*"put_block"* ]]; then
        result+=$(_strat_bonnie_extract_csv "$text")
    else
        result+=$(_strat_bonnie_extract_text "$text")
    fi

    echo "$result"
}

_strat_bonnie_extract_text () {
    local text="$1"
    local result=""
    local section=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Track section
        if [[ "$line" == *"Sequential Output"* ]]; then
            section="output"
            continue
        fi
        if [[ "$line" == *"Sequential Input"* ]]; then
            section="input"
            continue
        fi

        # Lines like: "  Per Chr: 456 K/sec"
        # or:         "  Block: 234567 K/sec"
        # or:         "  Rewrite: 123456 K/sec"
        # Extract the number before K/sec or /sec
        if [[ "$line" =~ [0-9]+[[:space:]]+(K/sec|/sec) ]]; then
            # Find the last numeric-only word
            local val=""
            read -ra _arr <<< "$line"
            local _w
            for _w in "${_arr[@]}"; do
                if [[ "$_w" =~ ^[0-9]+$ ]]; then
                    val="$_w"
                fi
            done

            if [[ "$line" == *"Per Chr"* ]]; then
                if [[ "$section" == "output" ]]; then
                    result+="seq_output_per_chr_kps ${val}"$'\n'
                elif [[ "$section" == "input" ]]; then
                    result+="seq_input_per_chr_kps ${val}"$'\n'
                fi
            elif [[ "$line" == *"Rewrite"* ]]; then
                result+="seq_rewrite_block_kps ${val}"$'\n'
            elif [[ "$line" == *"Block"* ]]; then
                if [[ "$section" == "output" ]]; then
                    result+="seq_output_block_kps ${val}"$'\n'
                elif [[ "$section" == "input" ]]; then
                    result+="seq_input_block_kps ${val}"$'\n'
                fi
            elif [[ "$line" == *[Rr]"andom"*[Ss]"eek"* ]]; then
                result+="random_seeks_per_sec ${val}"$'\n'
            elif [[ "$line" == *[Ss]"equential"*[Cc]"reate"* ]]; then
                result+="seq_create_per_sec ${val}"$'\n'
            elif [[ "$line" == *[Rr]"andom"*[Cc]"reate"* ]]; then
                result+="random_create_per_sec ${val}"$'\n'
            fi
            continue
        fi
    done <<< "$text"

    echo "$result"
}

_strat_bonnie_extract_csv () {
    local text="$1"
    local result=""

    # bonnie++ CSV: first line is header, second is data
    # Find lines with 3+ comma-separated fields
    local header_line="" data_line=""
    local _csv_count=0
    while IFS= read -r _line; do
        # Check if line has at least 2 commas (3+ fields)
        local _tmp="${_line//[^,]/}"
        if [[ ${#_tmp} -ge 2 ]]; then
            _csv_count=$((_csv_count + 1))
            if [[ $_csv_count -eq 1 ]]; then
                header_line="$_line"
            elif [[ $_csv_count -eq 2 ]]; then
                data_line="$_line"
                break
            fi
        fi
    done <<< "$text"

    if [[ -n "$data_line" && "$header_line" != "$data_line" ]]; then
        # Split CSV by comma
        IFS=',' read -ra _fields <<< "$data_line"
        local name="${_fields[0]}"
        local size="${_fields[1]}"
        local putc="${_fields[2]}"
        local put_block="${_fields[4]}"
        local rewrite="${_fields[6]}"
        local getc="${_fields[8]}"
        local get_block="${_fields[10]}"
        local seeks="${_fields[12]}"

        [[ -n "$name" ]] && result+="hostname ${name}"$'\n'
        [[ -n "$size" ]] && result+="file_size ${size}"$'\n'
        [[ -n "$putc" && "$putc" != "+++" ]] && result+="seq_output_per_chr_kps ${putc}"$'\n'
        [[ -n "$put_block" && "$put_block" != "+++" ]] && result+="seq_output_block_kps ${put_block}"$'\n'
        [[ -n "$rewrite" && "$rewrite" != "+++" ]] && result+="seq_rewrite_block_kps ${rewrite}"$'\n'
        [[ -n "$getc" && "$getc" != "+++" ]] && result+="seq_input_per_chr_kps ${getc}"$'\n'
        [[ -n "$get_block" && "$get_block" != "+++" ]] && result+="seq_input_block_kps ${get_block}"$'\n'
        [[ -n "$seeks" && "$seeks" != "+++" ]] && result+="random_seeks_per_sec ${seeks}"$'\n'
    fi

    echo "$result"
}
