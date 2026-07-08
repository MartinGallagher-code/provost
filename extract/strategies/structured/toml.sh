#!/bin/bash
## Name: toml
## Description: Extract key/value pairs from TOML format with section and array table support
## Version: 1.0
## Priority: 15
## Sample: samples/toml/basic.toml

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Must NOT look like JSON
    local first_nonblank=""
    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        local _trimmed="$_line"
        while [[ "$_trimmed" == " "* || "$_trimmed" == "	"* ]]; do _trimmed="${_trimmed#?}"; done
        [[ -z "$_trimmed" ]] && continue
        first_nonblank="$_trimmed"
        break
    done <<< "$text"
    case "$first_nonblank" in
        '{'*|'['*) ;;
    esac

    # Check for actual JSON start
    case "$first_nonblank" in
        '{'*) return 1 ;;
    esac

    # 1. [[array]] table headers
    if [[ "$text" == *$'\n'"[["* || "$text" == "[["* ]]; then
        return 0
    fi

    # 2. [dotted.section] headers
    if [[ "$text" =~ (^|$'\n')\[[a-zA-Z][a-zA-Z0-9_-]*\. ]]; then
        return 0
    fi

    # 3. key = "quoted_value" pattern (TOML uses = with spaces, not :)
    if [[ "$text" =~ (^|$'\n')[a-zA-Z][a-zA-Z0-9_-]*[\ ]*=[\ ]*\" ]]; then
        # Also must have [section] to distinguish from env-vars / equals
        if [[ "$text" == *$'\n'"["* || "$text" == "["* ]]; then
            return 0
        fi
        # Or [[array]] tables
        if [[ "$text" == *"[["* ]]; then
            return 0
        fi
        # Accept if we have key = "value" at top level AND [section] somewhere
        local section_count=0
        while IFS= read -r _line; do
            [[ "$_line" == "["* ]] && section_count=$((section_count + 1))
        done <<< "$text"
        [[ $section_count -ge 1 ]] && return 0
    fi

    return 1
}

strategy_extract () {
    local text="$1"

    local result=""
    local current_section=""
    # Track array table counts using pipe-delimited "name:count" pairs
    local array_table_counts=""

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Skip comment lines
        case "$line" in
            '#'*) continue ;;
        esac

        # Check for array table header [[name]]
        if [[ "$line" == "[["* ]]; then
            local array_name="${line#\[\[}"
            array_name="${array_name%%\]\]*}"
            # Trim whitespace
            while [[ "$array_name" == " "* || "$array_name" == "	"* ]]; do array_name="${array_name#?}"; done
            while [[ "$array_name" == *" " || "$array_name" == *"	" ]]; do array_name="${array_name%?}"; done

            # Get and increment the counter for this array table
            local count
            count=$(_strat_toml_get_array_count "$array_name")
            _strat_toml_set_array_count "$array_name" $((count + 1))

            current_section="${array_name}.${count}"
            continue
        fi

        # Check for section header [name] or [dotted.name]
        if [[ "$line" =~ ^\[[a-zA-Z] ]]; then
            current_section="${line#\[}"
            current_section="${current_section%%\]*}"
            # Trim whitespace
            while [[ "$current_section" == " "* || "$current_section" == "	"* ]]; do current_section="${current_section#?}"; done
            while [[ "$current_section" == *" " || "$current_section" == *"	" ]]; do current_section="${current_section%?}"; done
            continue
        fi

        # Check for key = value lines
        if [[ "$line" == *"="* ]]; then
            local key value

            # Extract key (before first =)
            key="${line%%=*}"
            # Trim whitespace from key
            while [[ "$key" == " "* || "$key" == "	"* ]]; do key="${key#?}"; done
            while [[ "$key" == *" " || "$key" == *"	" ]]; do key="${key%?}"; done

            # Extract value (after first =)
            value="${line#*=}"
            # Trim leading whitespace
            while [[ "$value" == " "* || "$value" == "	"* ]]; do value="${value#?}"; done

            # Skip if key is empty
            [[ -z "$key" ]] && continue

            # Strip quotes from string values
            case "$value" in
                '"'*) value="${value#\"}"; value="${value%\"}" ;;
                "'"*) value="${value#\'}"; value="${value%\'}" ;;
            esac
            # Trim trailing whitespace
            while [[ "$value" == *" " || "$value" == *"	" ]]; do value="${value%?}"; done

            # Skip if value is empty
            [[ -z "$value" ]] && continue

            # Replace spaces in key and value with underscores
            key="${key// /_}"

            # Prefix with section if we have one
            if [[ -n "$current_section" ]]; then
                result+="${current_section}.${key} ${value}"$'\n'
            else
                result+="${key} ${value}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}

# Helper: get array table count for a given name
_strat_toml_get_array_count () {
    local name="$1"
    local IFS_OLD="$IFS"
    IFS="|"
    for entry in $array_table_counts; do
        local entry_name entry_count
        entry_name="${entry%%:*}"
        entry_count="${entry#*:}"
        if [[ "$entry_name" == "$name" ]]; then
            IFS="$IFS_OLD"
            echo "$entry_count"
            return
        fi
    done
    IFS="$IFS_OLD"
    echo "0"
}

# Helper: set array table count for a given name
_strat_toml_set_array_count () {
    local name="$1"
    local new_count="$2"
    local new_counts=""
    local found=0
    local IFS_OLD="$IFS"
    IFS="|"
    for entry in $array_table_counts; do
        local entry_name
        entry_name="${entry%%:*}"
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
    IFS="$IFS_OLD"
    if [[ $found -eq 0 ]]; then
        if [[ -z "$new_counts" ]]; then
            new_counts="${name}:${new_count}"
        else
            new_counts="${new_counts}|${name}:${new_count}"
        fi
    fi
    array_table_counts="$new_counts"
}
