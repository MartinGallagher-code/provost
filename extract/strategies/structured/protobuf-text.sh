#!/bin/bash
## Name: protobuf-text
## Description: Extract field/value pairs from Protocol Buffers text format output
## Version: 1.0
## Priority: 22
## Sample: samples/protobuf-text/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

    # Must NOT be JSON
    _is_json "$text" && return 1

    # Must NOT look like YAML (no --- markers)
    local _nl=$'\n'
    local _re_yaml="(^|${_nl})---"
    [[ "$text" =~ $_re_yaml ]] && return 1

    # Must have { and } block nesting
    [[ "$text" == *"{"* ]] || return 1
    [[ "$text" == *"}"* ]] || return 1

    # Must have field: value pattern (word followed by colon and space)
    local _re_field="(^|${_nl})[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*:[[:space:]]"
    [[ "$text" =~ $_re_field ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"

    local result=""
    # Track prefix stack (pipe-delimited)
    local prefix_stack=""
    local depth=0
    # Track repeated field counts (pipe-delimited "name:count" pairs)
    local repeated_counts=""

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Strip leading whitespace
        local trimmed="$line"
        while [[ "$trimmed" == " "* || "$trimmed" == "	"* ]]; do trimmed="${trimmed#?}"; done

        # Skip comment lines
        case "$trimmed" in
            '#'*) continue ;;
        esac

        # Handle closing brace
        if [[ "$trimmed" == "}" || "$trimmed" == "},"* ]]; then
            if [[ $depth -gt 0 ]]; then
                depth=$((depth - 1))
                if [[ "$prefix_stack" == *"|"* ]]; then
                    prefix_stack="${prefix_stack%|*}"
                else
                    prefix_stack=""
                fi
            fi
            continue
        fi

        # Check for field: { (block opening)
        if [[ "$trimmed" == *"{"* && "$trimmed" == *":"* ]]; then
            local block_name="${trimmed%%:*}"
            # Trim whitespace
            while [[ "$block_name" == " "* || "$block_name" == "	"* ]]; do block_name="${block_name#?}"; done
            while [[ "$block_name" == *" " || "$block_name" == *"	" ]]; do block_name="${block_name%?}"; done

            # Check for repeated field — count occurrences
            local count
            count=$(_strat_pb_get_count "$block_name")
            count=$((count + 1))
            _strat_pb_set_count "$block_name" "$count"

            # Use numbered prefix for repeated fields (count > 1)
            local numbered_name="${block_name}${count}"

            if [[ -z "$prefix_stack" ]]; then
                prefix_stack="$numbered_name"
            else
                prefix_stack="${prefix_stack}|${numbered_name}"
            fi
            depth=$((depth + 1))
            continue
        fi

        # Check for simple block opening (just "name {" without colon)
        if [[ "$trimmed" == *" {"* && "$trimmed" != *":"* ]]; then
            local block_name="${trimmed%% \{*}"
            while [[ "$block_name" == " "* || "$block_name" == "	"* ]]; do block_name="${block_name#?}"; done
            while [[ "$block_name" == *" " || "$block_name" == *"	" ]]; do block_name="${block_name%?}"; done

            local count
            count=$(_strat_pb_get_count "$block_name")
            count=$((count + 1))
            _strat_pb_set_count "$block_name" "$count"

            local numbered_name="${block_name}${count}"

            if [[ -z "$prefix_stack" ]]; then
                prefix_stack="$numbered_name"
            else
                prefix_stack="${prefix_stack}|${numbered_name}"
            fi
            depth=$((depth + 1))
            continue
        fi

        # Check for field: value pair
        if [[ "$trimmed" == *":"* ]]; then
            local key="${trimmed%%:*}"
            local value="${trimmed#*:}"

            # Trim whitespace from key
            while [[ "$key" == " "* || "$key" == "	"* ]]; do key="${key#?}"; done
            while [[ "$key" == *" " || "$key" == *"	" ]]; do key="${key%?}"; done

            # Trim whitespace from value
            while [[ "$value" == " "* || "$value" == "	"* ]]; do value="${value#?}"; done
            while [[ "$value" == *" " || "$value" == *"	" ]]; do value="${value%?}"; done

            # Skip if key or value is empty
            [[ -z "$key" ]] && continue
            [[ -z "$value" ]] && continue

            # Strip quotes from string values
            case "$value" in
                '"'*) value="${value#\"}"; value="${value%\"}" ;;
            esac

            # Replace spaces in key and value with underscores
            key="${key// /_}"

            # Skip if value is empty after stripping
            [[ -z "$value" ]] && continue

            # Build full prefix from stack
            local full_prefix=""
            if [[ -n "$prefix_stack" ]]; then
                local old_ifs="$IFS"
                IFS="|"
                for entry in $prefix_stack; do
                    if [[ -z "$full_prefix" ]]; then
                        full_prefix="$entry"
                    else
                        full_prefix="${full_prefix}.${entry}"
                    fi
                done
                IFS="$old_ifs"
            fi

            if [[ -n "$full_prefix" ]]; then
                result+="${full_prefix}.${key} ${value}"$'\n'
            else
                result+="${key} ${value}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}

# Helper: get repeated field count
_strat_pb_get_count () {
    local name="$1"
    local old_ifs="$IFS"
    IFS="|"
    for entry in $repeated_counts; do
        local entry_name="${entry%%:*}"
        local entry_count="${entry#*:}"
        if [[ "$entry_name" == "$name" ]]; then
            IFS="$old_ifs"
            echo "$entry_count"
            return
        fi
    done
    IFS="$old_ifs"
    echo "0"
}

# Helper: set repeated field count
_strat_pb_set_count () {
    local name="$1"
    local new_count="$2"
    local new_counts=""
    local found=0
    local old_ifs="$IFS"
    IFS="|"
    for entry in $repeated_counts; do
        local entry_name="${entry%%:*}"
        if [[ "$entry_name" == "$name" ]]; then
            entry="${name}:${new_count}"
            found=1
        fi
        if [[ -z "$new_counts" ]]; then
            new_counts="$entry"
        else
            new_counts="${new_counts}|${entry}"
        fi
    done
    IFS="$old_ifs"
    if [[ $found -eq 0 ]]; then
        if [[ -z "$new_counts" ]]; then
            new_counts="${name}:${new_count}"
        else
            new_counts="${new_counts}|${name}:${new_count}"
        fi
    fi
    repeated_counts="$new_counts"
}
