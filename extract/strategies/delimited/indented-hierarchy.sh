#!/bin/bash
## Name: indented-hierarchy
## Description: Indentation-based hierarchical data, flattened with dot notation
## Version: 1.0
## Priority: 50
## Technique: yes
## Sample: samples/indented-hierarchy/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=65

    # Reject JSON-like input
    _is_json "$1" && return 1

    # Must have lines with increasing indentation (2+ space-indented lines)
    local indented_count=0
    while IFS= read -r _line; do
        if [[ "$_line" == "  "* ]]; then
            indented_count=$((indented_count + 1))
        fi
    done <<< "$text"
    [[ $indented_count -lt 2 ]] && return 1

    # Must have a non-indented line followed by indented lines
    [[ "${text:0:1}" != " " ]] || return 1

    # Must contain colons
    [[ "$text" == *":"* ]] || return 1

    return 0
}

_strat_ih_get_indent () {
    local line="$1"
    local stripped="$line"
    # Count leading spaces
    local count=0
    while [[ "$stripped" == " "* ]]; do
        stripped="${stripped# }"
        count=$((count + 1))
    done
    echo $count
}

strategy_extract () {
    local text="$1"
    local result=""

    # Build arrays of path components at each indentation level
    # path_keys[0]="System_Information", path_keys[1]="BIOS_Information", etc.
    # We use indexed arrays
    local path_keys=""  # pipe-delimited: "level:key|level:key|..."
    local prev_indent=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local indent
        indent=$(_strat_ih_get_indent "$line")

        # Strip leading whitespace
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        [[ -z "$trimmed" ]] && continue

        # Check if this is a key: value line or a bare heading
        if [[ "$trimmed" == *":"* ]]; then
            local key="${trimmed%%:*}"
            local value="${trimmed#*:}"
            # Trim leading spaces from value
            while [[ "$value" == " "* ]]; do value="${value# }"; done

            # Trim key
            while [[ "$key" == " "* ]]; do key="${key# }"; done
            while [[ "$key" == *" " ]]; do key="${key% }"; done
            key="${key// /_}"
            # Trim value; spaces inside the value are preserved (the engine keeps
            # everything after the first space as the value).
            while [[ "$value" == *" " ]]; do value="${value% }"; done

            if [[ -n "$value" ]]; then
                # This is a key: value line -- emit with full path
                # Build path from path_keys for current indent level
                local path=""
                # Parse pipe-delimited entries
                local old_ifs="$IFS"
                IFS='|'
                local entries
                read -ra entries <<< "$path_keys"
                IFS="$old_ifs"
                local e
                for e in "${entries[@]}"; do
                    [[ -z "$e" ]] && continue
                    local elevel="${e%%:*}"
                    local ekey="${e#*:}"
                    if [[ $elevel -lt $indent ]]; then
                        if [[ -n "$path" ]]; then
                            path+="."
                        fi
                        path+="$ekey"
                    fi
                done
                if [[ -n "$path" ]]; then
                    result+="${path}.${key} ${value}"$'\n'
                else
                    result+="${key} ${value}"$'\n'
                fi
            else
                # Bare heading with colon but no value (e.g., "Section:")
                # Remove entries at this level or deeper
                local new_path_keys=""
                local old_ifs="$IFS"
                IFS='|'
                local entries
                read -ra entries <<< "$path_keys"
                IFS="$old_ifs"
                local e
                for e in "${entries[@]}"; do
                    [[ -z "$e" ]] && continue
                    local elevel="${e%%:*}"
                    if [[ $elevel -lt $indent ]]; then
                        if [[ -n "$new_path_keys" ]]; then
                            new_path_keys+="|"
                        fi
                        new_path_keys+="$e"
                    fi
                done
                if [[ -n "$new_path_keys" ]]; then
                    path_keys="${new_path_keys}|${indent}:${key}"
                else
                    path_keys="${indent}:${key}"
                fi
            fi
        else
            # Bare heading without colon
            local heading="$trimmed"
            while [[ "$heading" == " "* ]]; do heading="${heading# }"; done
            while [[ "$heading" == *" " ]]; do heading="${heading% }"; done
            heading="${heading// /_}"

            # Remove entries at this level or deeper
            local new_path_keys=""
            local old_ifs="$IFS"
            IFS='|'
            local entries
            read -ra entries <<< "$path_keys"
            IFS="$old_ifs"
            local e
            for e in "${entries[@]}"; do
                [[ -z "$e" ]] && continue
                local elevel="${e%%:*}"
                if [[ $elevel -lt $indent ]]; then
                    if [[ -n "$new_path_keys" ]]; then
                        new_path_keys+="|"
                    fi
                    new_path_keys+="$e"
                fi
            done
            if [[ -n "$new_path_keys" ]]; then
                path_keys="${new_path_keys}|${indent}:${heading}"
            else
                path_keys="${indent}:${heading}"
            fi
        fi

        prev_indent=$indent
    done <<< "$text"

    echo "$result"
}
