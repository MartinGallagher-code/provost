#!/bin/bash
## Name: systemd-unit
## Description: Extract key-value pairs from systemd unit files ([Unit], [Service], [Install] sections)
## Version: 1.0
## Priority: 20
## Sample: samples/systemd-unit/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Note: cannot use _is_json here — systemd unit files start with '[' which triggers it.
    # The [Unit]/[Service] section header check below is specific enough to avoid false positives.
    # Look for systemd-specific section headers: [Unit] or [Service]
    local found_unit=0
    local found_service=0
    while IFS= read -r line; do
        case "$line" in
            '[Unit]'*) found_unit=1 ;;
            '[Service]'*) found_service=1 ;;
        esac
        if [[ $found_unit -eq 1 || $found_service -eq 1 ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local current_section=""

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Skip comment lines (starting with # or ;)
        case "$line" in
            '#'*) continue ;;
            ';'*) continue ;;
        esac

        # Detect section headers: [SectionName]
        if [[ "$line" == '['*']'* ]]; then
            # Extract section name between [ and ]
            local section="${line#\[}"
            section="${section%%\]*}"
            current_section="$section"
            continue
        fi

        # Skip lines if no section seen yet
        [[ -z "$current_section" ]] && continue

        # Parse Key=Value lines
        [[ "$line" == *"="* ]] || continue

        local key="${line%%=*}"
        local value="${line#*=}"

        # Skip if key is empty
        [[ -z "$key" ]] && continue

        # Strip leading whitespace from key
        while [[ "$key" == " "* ]]; do key="${key# }"; done
        while [[ "$key" == "	"* ]]; do key="${key#	}"; done

        # Strip trailing whitespace from key
        while [[ "$key" == *" " ]]; do key="${key% }"; done

        # Strip leading whitespace from value
        while [[ "$value" == " "* ]]; do value="${value# }"; done
        while [[ "$value" == "	"* ]]; do value="${value#	}"; done

        # Strip trailing whitespace from value
        while [[ "$value" == *" " ]]; do value="${value% }"; done

        # Replace spaces in values with underscores
        local cleaned_value=""
        local i=0
        while [[ $i -lt ${#value} ]]; do
            local ch="${value:$i:1}"
            if [[ "$ch" == " " ]]; then
                cleaned_value+="_"
            else
                cleaned_value+="$ch"
            fi
            i=$((i + 1))
        done

        result+="${current_section}.${key} ${cleaned_value}"$'\n'
    done <<< "$text"

    echo "$result"
}
