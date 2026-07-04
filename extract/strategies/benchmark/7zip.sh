#!/bin/bash
## Name: 7zip
## Description: Extract compression/decompression speed and MIPS from 7-Zip benchmark
## Version: 1.0
## Priority: 10
## Sample: samples/7zip/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Pattern 1: "7-Zip" + "MIPS"
    if [[ "$text" == *"7-Zip"* ]]; then
        if [[ "$text" == *"MIPS"* ]]; then
            return 0
        fi
    fi
    # Pattern 2: "Compressing" + "Decompressing" + "Rating"
    if [[ "$text" == *"Compressing"* ]]; then
        if [[ "$text" == *"Decompressing"* ]]; then
            if [[ "$text" == *"Rating"* ]]; then
                return 0
            fi
        fi
    fi
    return 1
}

_7zip_extract_value () {
    local line="$1"
    local pattern="$2"
    local _tmp="${line##*$pattern}"
    # Strip leading spaces
    while [[ "$_tmp" == " "* ]]; do _tmp="${_tmp# }"; done
    # Get first word
    read -ra _arr <<< "$_tmp"
    local _val="${_arr[0]}"
    # Remove commas
    _val="${_val//,/}"
    echo "$_val"
}

strategy_extract () {
    local text="$1"
    local result=""
    local dict_count=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Version: "7-Zip (a) [64] 16.02 : Copyright ..."
        if [[ "$line" == *"7-Zip"* ]]; then
            if [[ "$line" == *"Copyright"* ]]; then
                local ver
                local _tmp="${line##*] }"
                # Strip leading spaces
                while [[ "$_tmp" == " "* ]]; do _tmp="${_tmp# }"; done
                read -ra _arr <<< "$_tmp"
                ver="${_arr[0]}"
                [[ -n "$ver" ]] && result+="version ${ver}"$'\n'
                continue
            fi
        fi

        # RAM size: "RAM size:    16384 MB,  # CPU hardware threads:   8"
        if [[ "$line" == *"RAM size"* ]]; then
            local ram
            ram=$(_7zip_extract_value "$line" "RAM size:")
            [[ -n "$ram" ]] && result+="ram_size_MB ${ram}"$'\n'
            if [[ "$line" == *"CPU hardware threads"* ]]; then
                local threads
                local _tmp="${line##*# CPU hardware threads:}"
                while [[ "$_tmp" == " "* ]]; do _tmp="${_tmp# }"; done
                read -ra _arr <<< "$_tmp"
                threads="${_arr[0]}"
                [[ -n "$threads" ]] && result+="cpu_threads ${threads}"$'\n'
            fi
            continue
        fi

        # Benchmark threads: "RAM usage:    1765 MB,  # Benchmark threads:      8"
        if [[ "$line" == *"Benchmark threads"* ]]; then
            local bthreads
            local _tmp="${line##*# Benchmark threads:}"
            while [[ "$_tmp" == " "* ]]; do _tmp="${_tmp# }"; done
            read -ra _arr <<< "$_tmp"
            bthreads="${_arr[0]}"
            [[ -n "$bthreads" ]] && result+="benchmark_threads ${bthreads}"$'\n'
            continue
        fi

        # Dict size data rows: "22:      25678   750   3334  25003  |     345678   798   3790  30245"
        if [[ "$line" =~ ^[0-9]+: ]]; then
            # Strip the pipe separator and parse fields
            local cleaned="${line//|/ }"
            local dict_size c_speed c_usage c_ru c_rating d_speed d_usage d_ru d_rating
            read -ra _arr <<< "$cleaned"
            dict_size="${_arr[0]}"
            dict_size="${dict_size%:}"
            c_speed="${_arr[1]}"
            c_usage="${_arr[2]}"
            # $4 is R/U MIPS (compress), $5 is Rating MIPS (compress)
            c_rating="${_arr[4]}"
            d_speed="${_arr[5]}"
            d_usage="${_arr[6]}"
            # $8 is R/U MIPS (decompress), $9 is Rating MIPS (decompress)
            d_rating="${_arr[8]}"

            # Validate: speed should be numeric
            [[ "$c_speed" =~ ^[0-9] ]] || continue

            dict_count=$((dict_count + 1))
            local prefix=""
            if [[ $dict_count -gt 1 ]]; then
                prefix="dict${dict_count}."
            fi

            [[ -n "$c_speed" ]] && result+="${prefix}compress_speed_KiB_per_s ${c_speed}"$'\n'
            [[ -n "$c_usage" ]] && result+="${prefix}compress_usage_pct ${c_usage}"$'\n'
            [[ -n "$c_rating" ]] && result+="${prefix}compress_rating_MIPS ${c_rating}"$'\n'
            [[ -n "$d_speed" ]] && result+="${prefix}decompress_speed_KiB_per_s ${d_speed}"$'\n'
            [[ -n "$d_usage" ]] && result+="${prefix}decompress_usage_pct ${d_usage}"$'\n'
            [[ -n "$d_rating" ]] && result+="${prefix}decompress_rating_MIPS ${d_rating}"$'\n'
            continue
        fi

        # Average line: "Avr:             748   3350  25038  |              797   3801  30279"
        if [[ "$line" == "Avr:"* ]]; then
            local cleaned="${line//|/ }"
            cleaned="${cleaned#Avr:}"
            while [[ "$cleaned" == " "* ]]; do cleaned="${cleaned# }"; done
            local avg_c_rating avg_d_rating
            read -ra _arr <<< "$cleaned"
            avg_c_rating="${_arr[2]}"
            avg_d_rating="${_arr[5]}"
            [[ -n "$avg_c_rating" ]] && result+="avg_compress_rating_MIPS ${avg_c_rating}"$'\n'
            [[ -n "$avg_d_rating" ]] && result+="avg_decompress_rating_MIPS ${avg_d_rating}"$'\n'
            continue
        fi

        # Total line: "Tot:             772   3575  27658"
        if [[ "$line" == "Tot:"* ]]; then
            local tot_rating
            local _tmp="${line#Tot:}"
            while [[ "$_tmp" == " "* ]]; do _tmp="${_tmp# }"; done
            read -ra _arr <<< "$_tmp"
            tot_rating="${_arr[2]}"
            [[ -n "$tot_rating" ]] && result+="total_rating_MIPS ${tot_rating}"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}
