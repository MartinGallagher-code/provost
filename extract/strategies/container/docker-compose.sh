#!/bin/bash
## Name: docker-compose
## Description: Extract service definitions from Docker Compose YAML files
## Version: 1.0
## Priority: 15
## Sample: samples/docker-compose/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Reject JSON
    _is_json "$1" && return 1
    # Look for "services:" at start of a line AND indented service names with image:/build:
    local has_services=0 has_image_or_build=0
    while IFS= read -r line; do
        if [[ "$line" == "services:" ]]; then
            has_services=1
        fi
        # Trim leading spaces
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        if [[ "$trimmed" == "image: "* || "$trimmed" == "build: "* ]]; then
            has_image_or_build=1
        fi
        if [[ $has_services -eq 1 && $has_image_or_build -eq 1 ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    local in_services=0
    local current_service=""
    local current_list_key=""
    local list_items=""

    while IFS= read -r line; do
        # Count leading spaces
        local stripped="$line"
        local indent=0
        while [[ "$stripped" == " "* ]]; do
            stripped="${stripped# }"
            indent=$((indent + 1))
        done

        # Skip empty lines and comments
        [[ -z "$stripped" ]] && continue
        [[ "$stripped" == "#"* ]] && continue

        # Top-level key (indent 0)
        if [[ $indent -eq 0 ]]; then
            # Flush any pending list
            if [[ -n "$current_service" && -n "$current_list_key" && -n "$list_items" ]]; then
                result+="${current_service}.${current_list_key} ${list_items}"$'\n'
            fi
            current_list_key=""
            list_items=""

            if [[ "$stripped" == "services:" ]]; then
                in_services=1
            else
                in_services=0
                current_service=""
            fi
            continue
        fi

        # Not inside services section
        [[ $in_services -eq 0 ]] && continue

        # Service name (indent 2)
        if [[ $indent -eq 2 ]]; then
            # Flush any pending list from previous service
            if [[ -n "$current_service" && -n "$current_list_key" && -n "$list_items" ]]; then
                result+="${current_service}.${current_list_key} ${list_items}"$'\n'
            fi
            current_list_key=""
            list_items=""

            # Service name is the key before ':'
            local svc_name="${stripped%%:*}"
            # Validate: must end with ':' (possibly with trailing content)
            if [[ "$stripped" == *":"* ]]; then
                current_service="$svc_name"
            fi
            continue
        fi

        [[ -z "$current_service" ]] && continue

        # Service property (indent 4)
        if [[ $indent -eq 4 ]]; then
            # Flush any pending list from previous key
            if [[ -n "$current_list_key" && -n "$list_items" ]]; then
                result+="${current_service}.${current_list_key} ${list_items}"$'\n'
            fi
            current_list_key=""
            list_items=""

            local key="${stripped%%:*}"
            local value="${stripped#*: }"

            # If the line is just "key:" with no value, it introduces a list or mapping
            if [[ "$stripped" == "${key}:" ]]; then
                # Remember this key for list collection
                case "$key" in
                    ports|volumes|environment|depends_on)
                        current_list_key="$key"
                        list_items=""
                        ;;
                esac
                continue
            fi

            # Scalar value — replace spaces with underscores in value
            local safe_value="${value// /_}"
            result+="${current_service}.${key} ${safe_value}"$'\n'
            continue
        fi

        # List item (indent 6) — "- value"
        if [[ $indent -eq 6 && -n "$current_list_key" ]]; then
            if [[ "$stripped" == "- "* ]]; then
                local item="${stripped#- }"
                # Strip surrounding quotes
                case "$item" in
                    '"'*'"') item="${item#\"}"; item="${item%\"}" ;;
                    "'"*"'") item="${item#\'}"; item="${item%\'}" ;;
                esac
                # Replace spaces with underscores
                item="${item// /_}"
                if [[ -z "$list_items" ]]; then
                    list_items="$item"
                else
                    list_items="${list_items},${item}"
                fi
            fi
            continue
        fi

    done <<< "$text"

    # Flush final pending list
    if [[ -n "$current_service" && -n "$current_list_key" && -n "$list_items" ]]; then
        result+="${current_service}.${current_list_key} ${list_items}"$'\n'
    fi

    echo "$result"
}
