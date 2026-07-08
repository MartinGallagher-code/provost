#!/bin/bash
## Name: hcl
## Description: Extract key/value pairs from HCL (Terraform/Packer) configuration files
## Version: 1.0
## Priority: 18
## Sample: samples/hcl/basic.tf

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Must NOT be JSON
    _is_json "$text" && return 1

    # Must contain { (block structure)
    [[ "$text" == *"{"* ]] || return 1

    # Must contain HCL block keywords followed by space or quote
    local _nl=$'\n'
    local _re="(^|${_nl})(resource|variable|provider|output|data|module|locals|terraform)[ \"]"
    [[ "$text" =~ $_re ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"

    local result=""
    # Stack of block prefixes (pipe-delimited)
    local prefix_stack=""
    local depth=0

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Strip leading whitespace
        local trimmed="$line"
        while [[ "$trimmed" == " "* || "$trimmed" == "	"* ]]; do trimmed="${trimmed#?}"; done

        # Skip comment lines
        case "$trimmed" in
            '#'*|'//'*) continue ;;
        esac

        # Skip closing braces
        if [[ "$trimmed" == "}" || "$trimmed" == "},"* ]]; then
            # Pop from stack
            if [[ $depth -gt 0 ]]; then
                depth=$((depth - 1))
                # Remove last entry from stack
                if [[ "$prefix_stack" == *"|"* ]]; then
                    prefix_stack="${prefix_stack%|*}"
                else
                    prefix_stack=""
                fi
            fi
            continue
        fi

        # Check for block opening: keyword "label1" "label2" ... {
        # Match: word followed by optional quoted labels, ending with {
        if [[ "$trimmed" == *"{"* && "$trimmed" != *"="* ]]; then
            # Extract the block prefix before the {
            local block_def="${trimmed%%\{*}"
            # Trim trailing whitespace
            while [[ "$block_def" == *" " || "$block_def" == *"	" ]]; do block_def="${block_def%?}"; done

            local block_prefix=""
            local remaining="$block_def"

            # Parse the block keyword and labels
            while [[ -n "$remaining" ]]; do
                # Strip leading whitespace
                while [[ "$remaining" == " "* || "$remaining" == "	"* ]]; do remaining="${remaining#?}"; done
                [[ -z "$remaining" ]] && break

                local part=""
                if [[ "$remaining" == \"* ]]; then
                    # Quoted label: extract text between quotes
                    remaining="${remaining#\"}"
                    part="${remaining%%\"*}"
                    remaining="${remaining#*\"}"
                else
                    # Unquoted keyword
                    part="${remaining%% *}"
                    if [[ "$part" == "$remaining" ]]; then
                        remaining=""
                    else
                        remaining="${remaining#* }"
                    fi
                fi

                # Replace spaces in part with underscores
                part="${part// /_}"

                if [[ -z "$block_prefix" ]]; then
                    block_prefix="$part"
                else
                    block_prefix="${block_prefix}.${part}"
                fi
            done

            # Push to stack
            if [[ -z "$prefix_stack" ]]; then
                prefix_stack="$block_prefix"
            else
                prefix_stack="${prefix_stack}|${block_prefix}"
            fi
            depth=$((depth + 1))
            continue
        fi

        # Check for key = value assignment
        if [[ "$trimmed" == *"="* ]]; then
            local key value
            key="${trimmed%%=*}"
            value="${trimmed#*=}"

            # Trim whitespace from key
            while [[ "$key" == " "* || "$key" == "	"* ]]; do key="${key#?}"; done
            while [[ "$key" == *" " || "$key" == *"	" ]]; do key="${key%?}"; done

            # Trim whitespace from value
            while [[ "$value" == " "* || "$value" == "	"* ]]; do value="${value#?}"; done
            while [[ "$value" == *" " || "$value" == *"	" ]]; do value="${value%?}"; done

            # Skip if key or value is empty
            [[ -z "$key" ]] && continue
            [[ -z "$value" ]] && continue

            # Skip block-opening assignments (value contains {)
            if [[ "$value" == "{"* ]]; then
                # This is a nested block like "tags = {"
                local block_prefix="$key"
                block_prefix="${block_prefix// /_}"
                if [[ -z "$prefix_stack" ]]; then
                    prefix_stack="$block_prefix"
                else
                    prefix_stack="${prefix_stack}|${block_prefix}"
                fi
                depth=$((depth + 1))
                continue
            fi

            # Strip quotes from string values
            case "$value" in
                '"'*) value="${value#\"}"; value="${value%\"}" ;;
            esac

            # Replace spaces in key (field name) with underscores
            key="${key// /_}"

            # Skip if value is empty after stripping
            [[ -z "$value" ]] && continue

            # Build full prefix from stack
            local full_prefix=""
            if [[ -n "$prefix_stack" ]]; then
                # Join all stack entries with dots
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
