#!/bin/bash
## Name: dmesg
## Description: Extract timestamps and messages from dmesg kernel ring buffer output
## Version: 1.0
## Priority: 45
## Sample: samples/dmesg/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Note: cannot use _is_json here — dmesg lines start with '[' which triggers it.
    # The timestamp pattern check below is specific enough to avoid JSON false positives.
    # Look for lines starting with [ followed by a float timestamp and ]
    local count=0
    while IFS= read -r line; do
        case "$line" in
            '['*']'*)
                # Extract the content between brackets
                local inside="${line#\[}"
                inside="${inside%%\]*}"
                # Strip leading spaces
                while [[ "$inside" == " "* ]]; do inside="${inside# }"; done
                # Check if it looks like a float: digits.digits
                if [[ "$inside" =~ ^[0-9]+\.[0-9]+ ]]; then
                    count=$((count + 1))
                fi
                ;;
        esac
        if [[ $count -ge 2 ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Match lines like: [    0.000000] Linux version 5.15.0 ...
        case "$line" in
            '['*']'*)
                # Extract timestamp from brackets
                local inside="${line#\[}"
                inside="${inside%%\]*}"
                # Strip leading spaces
                while [[ "$inside" == " "* ]]; do inside="${inside# }"; done
                # Validate timestamp format
                [[ "$inside" =~ ^[0-9]+\.[0-9]+ ]] || continue

                local timestamp="$inside"

                # Extract message after "] "
                local after="${line#*] }"
                # If after is same as line, skip (no "] " found)
                [[ "$after" == "$line" ]] && continue
                [[ -z "$after" ]] && continue

                n=$((n + 1))

                # First word of message
                read -ra _arr <<< "$after"
                local message="${_arr[0]}"

                # Rest of message (detail)
                local detail=""
                if [[ ${#_arr[@]} -gt 1 ]]; then
                    # Rebuild detail from remaining words
                    local i=1
                    while [[ $i -lt ${#_arr[@]} ]]; do
                        if [[ -z "$detail" ]]; then
                            detail="${_arr[$i]}"
                        else
                            detail="$detail ${_arr[$i]}"
                        fi
                        i=$((i + 1))
                    done
                fi

                result+="dmesg${n}_timestamp ${timestamp}"$'\n'
                result+="dmesg${n}_message ${message}"$'\n'
                [[ -n "$detail" ]] && result+="dmesg${n}_detail ${detail}"$'\n'
                ;;
        esac
    done <<< "$text"

    echo "$result"
}
