#!/bin/bash
## Name: perf-report
## Description: Extract symbol overhead data from perf report text output
## Version: 1.0
## Priority: 25
## Sample: samples/perf-report/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Strong: perf report header comments
    if [[ "$text" == *"# Overhead"* ]]; then
        return 0
    fi
    if [[ "$text" == *"# Samples:"* ]] && [[ "$text" == *"Shared Object"* ]]; then
        return 0
    fi
    if [[ "$text" == *"perf report"* ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    # Detect perf report column pattern (distinct from perf stat)
    if [[ "$text" == *"Overhead"* ]] && [[ "$text" == *"Symbol"* ]] && [[ "$text" == *"Shared Object"* ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0
    local in_data=0
    local total_samples=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Extract total samples from header
        if [[ "$line" == *"# Samples:"* ]]; then
            local val="${line##*# Samples:}"
            val="${val#"${val%%[![:space:]]*}"}"
            # Take first token (the number)
            read -ra _arr <<< "$val"
            if [[ ${#_arr[@]} -ge 1 ]]; then
                total_samples="${_arr[0]}"
                total_samples="${total_samples//,/}"
                result+="total_samples ${total_samples}"$'\n'
            fi
            continue
        fi

        # Extract event type from header
        if [[ "$line" == *"# Event:"* ]] || [[ "$line" == *"# event:"* ]]; then
            local val="${line##*:}"
            val="${val#"${val%%[![:space:]]*}"}"
            val="${val%"${val##*[![:space:]]}"}"
            [[ -n "$val" ]] && result+="event_type ${val}"$'\n'
            continue
        fi

        # Skip comment lines (except those we already parsed)
        [[ "$line" == "#"* ]] && continue

        # Detect column header line
        if [[ "$line" == *"Overhead"* ]] && [[ "$line" == *"Symbol"* ]]; then
            in_data=1
            continue
        fi

        # Parse data rows
        # Format: "  42.86%  libc.so.6   [.] __memmove_avx_unaligned"
        # or:     "  42.86%  42.86%  libc.so.6   [.] __memmove_avx_unaligned"
        if [[ $in_data -eq 1 ]]; then
            # Skip separator lines
            [[ "$line" == ------* ]] && continue

            # Must start with a percentage
            local trimmed="${line#"${line%%[![:space:]]*}"}"
            if [[ "$trimmed" =~ ^[0-9]+\.?[0-9]*% ]]; then
                n=$((n + 1))
                read -ra _arr <<< "$trimmed"

                local overhead="${_arr[0]}"
                overhead="${overhead%%%}"
                result+="sym${n}_overhead_percent ${overhead}"$'\n'

                # Find shared object and symbol
                # Symbol is typically after [.] or [k] marker
                local found_so=""
                local found_sym=""
                local i
                for ((i=1; i<${#_arr[@]}; i++)); do
                    if [[ "${_arr[$i]}" == "[.]" ]] || [[ "${_arr[$i]}" == "[k]" ]] || \
                       [[ "${_arr[$i]}" == "[g]" ]] || [[ "${_arr[$i]}" == "[u]" ]]; then
                        # Previous non-bracket field is shared object
                        if [[ -z "$found_so" ]] && [[ $((i-1)) -ge 1 ]]; then
                            # Walk back to find shared object
                            local j
                            for ((j=1; j<i; j++)); do
                                if [[ "${_arr[$j]}" != *"%" ]]; then
                                    found_so="${_arr[$j]}"
                                    break
                                fi
                            done
                        fi
                        # Everything after the bracket is the symbol
                        if [[ $((i+1)) -lt ${#_arr[@]} ]]; then
                            found_sym="${_arr[$((i+1))]}"
                        fi
                        break
                    fi
                done

                # Fallback: if no bracket marker found
                if [[ -z "$found_sym" ]] && [[ ${#_arr[@]} -ge 3 ]]; then
                    found_so="${_arr[1]}"
                    found_sym="${_arr[${#_arr[@]}-1]}"
                fi

                [[ -n "$found_so" ]] && result+="sym${n}_shared_object ${found_so}"$'\n'
                [[ -n "$found_sym" ]] && result+="sym${n}_symbol ${found_sym}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}
