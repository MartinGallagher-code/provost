#!/bin/bash
## Name: sanitizer
## Description: Extract fields from AddressSanitizer/ThreadSanitizer/UBSan output
## Version: 1.0
## Priority: 15
## Sample: samples/sanitizer/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Contains "ERROR:" followed by "Sanitizer:" or "SUMMARY:.*Sanitizer"
    if [[ "$text" == *"ERROR:"*"Sanitizer:"* ]]; then
        return 0
    fi
    if [[ "$text" == *"SUMMARY:"*"Sanitizer"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Error line: "==12345==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x602000000014"
        if [[ "$line" == *"ERROR:"*"Sanitizer:"* ]]; then
            local sanitizer error_type address

            # Extract sanitizer name (e.g., AddressSanitizer)
            # Get text after "ERROR: " up to next ":"
            local _after_error="${line#*ERROR:}"
            while [[ "$_after_error" == " "* ]]; do _after_error="${_after_error# }"; done
            sanitizer="${_after_error%%:*}"
            result+="sanitizer ${sanitizer}"$'\n'

            # Extract error type (word after sanitizer name and colon)
            local _after_san="${line#*Sanitizer:}"
            while [[ "$_after_san" == " "* ]]; do _after_san="${_after_san# }"; done
            read -ra _arr <<< "$_after_san"
            error_type="${_arr[0]}"
            result+="error_type ${error_type}"$'\n'

            # Extract address if present
            if [[ "$line" == *"on address"* ]]; then
                local _after_addr="${line#*on address}"
                while [[ "$_after_addr" == " "* ]]; do _after_addr="${_after_addr# }"; done
                read -ra _arr <<< "$_after_addr"
                address="${_arr[0]}"
                result+="address ${address}"$'\n'
            fi
            continue
        fi

        # Stack frame: "#0 0x5555555551a0 in main /home/user/src/main.c:42"
        if [[ "$line" =~ ^[\ ]*#0\  ]]; then
            local func file_line

            # Extract function name
            if [[ "$line" == *" in "* ]]; then
                local _after_in="${line#* in }"
                read -ra _arr <<< "$_after_in"
                func="${_arr[0]}"
                result+="function ${func}"$'\n'
            fi

            # Extract file and line number (last word on line)
            read -ra _arr <<< "$line"
            file_line="${_arr[${#_arr[@]}-1]}"
            if [[ "$file_line" == *":"* ]]; then
                local filepath lineno
                filepath="${file_line%:*}"
                lineno="${file_line##*:}"
                result+="file ${filepath}"$'\n'
                result+="line ${lineno}"$'\n'
            fi
            continue
        fi

        # SUMMARY line: "SUMMARY: AddressSanitizer: heap-buffer-overflow /home/user/src/main.c:42 in main"
        if [[ "$line" == "SUMMARY:"* ]]; then
            local _after_sum="${line#SUMMARY:}"
            while [[ "$_after_sum" == " "* ]]; do _after_sum="${_after_sum# }"; done
            local _after_san2="${_after_sum#*Sanitizer:}"
            while [[ "$_after_san2" == " "* ]]; do _after_san2="${_after_san2# }"; done
            read -ra _arr <<< "$_after_san2"
            local summary_type="${_arr[0]}"
            # Only add if we didn't already get it from ERROR line
            if [[ "$result" != *$'\n'"error_type "* && "$result" != "error_type "* ]]; then
                result+="error_type ${summary_type}"$'\n'
            fi
            continue
        fi

    done <<< "$text"

    echo "$result"
}
