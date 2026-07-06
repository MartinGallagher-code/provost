#!/bin/bash
## Name: lshw
## Description: Extract hardware component details from lshw output
## Version: 1.0
## Priority: 15
## Sample: samples/lshw/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$1" && return 1
    if [[ "$text" == *"lshw"* ]]; then
        return 0
    fi
    if [[ "$text" == *"*-cpu"* ]] && [[ "$text" == *"description:"* ]]; then
        return 0
    fi
    if [[ "$text" == *"*-memory"* ]] && [[ "$text" == *"product:"* ]]; then
        return 0
    fi
    if [[ "$text" == *"physical id:"* ]] && [[ "$text" == *"vendor:"* ]] && [[ "$text" == *"*-"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local current_class=""
    local class_counts=""

    # Track counts per component class using simple parallel arrays
    local -a count_keys=()
    local -a count_vals=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect *-class headers
        if [[ "$line" =~ ^[[:space:]]*\*-([a-zA-Z]+) ]]; then
            current_class="${BASH_REMATCH[1]}"
            # Only process key component classes
            case "$current_class" in
                cpu|memory|network|disk|display)
                    _strat_lshw_increment_count count_keys count_vals "$current_class"
                    ;;
                bank)
                    # memory bank sub-component, keep class as memory_bank
                    current_class="memory_bank"
                    _strat_lshw_increment_count count_keys count_vals "memory_bank"
                    ;;
                *)
                    current_class=""
                    ;;
            esac
            continue
        fi

        [[ -z "$current_class" ]] && continue

        # Parse indented "key: value" lines
        if [[ "$line" =~ ^[[:space:]]+([a-zA-Z][a-zA-Z\ _]+):[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            while [[ "$val" == *" " ]]; do val="${val% }"; done

            local num
            num=$(_strat_lshw_get_count count_keys count_vals "$current_class")
            local prefix="${current_class}${num}"

            case "$key" in
                "description") result+="${prefix}_description ${val}"$'\n' ;;
                "product") result+="${prefix}_product ${val}"$'\n' ;;
                "vendor") result+="${prefix}_vendor ${val}"$'\n' ;;
                "physical id") result+="${prefix}_physical_id ${val}"$'\n' ;;
                "size") result+="${prefix}_size ${val}"$'\n' ;;
                "capacity") result+="${prefix}_capacity ${val}"$'\n' ;;
                "clock") result+="${prefix}_clock ${val}"$'\n' ;;
                "width") result+="${prefix}_width ${val}"$'\n' ;;
            esac
        fi
    done <<< "$text"

    echo "$result"
}

_strat_lshw_increment_count () {
    local -n _keys=$1
    local -n _vals=$2
    local class="$3"

    local i
    for i in "${!_keys[@]}"; do
        if [[ "${_keys[$i]}" == "$class" ]]; then
            _vals[$i]=$(( _vals[$i] + 1 ))
            return
        fi
    done
    _keys+=("$class")
    _vals+=(1)
}

# shellcheck disable=SC2178  # false positive: namerefs, not string assignment
_strat_lshw_get_count () {
    local -n _keys=$1
    local -n _vals=$2
    local class="$3"

    local i
    for i in "${!_keys[@]}"; do
        if [[ "${_keys[$i]}" == "$class" ]]; then
            echo "${_vals[$i]}"
            return
        fi
    done
    echo "0"
}
