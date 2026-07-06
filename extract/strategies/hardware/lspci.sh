#!/bin/bash
## Name: lspci
## Description: Extract PCI device information from lspci verbose output
## Version: 1.0
## Priority: 15
## Sample: samples/lspci/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$1" && return 1
    if [[ "$text" == *"lspci"* ]]; then
        return 0
    fi
    if [[ "$text" == *"PCI bridge"* ]] || \
       [[ "$text" == *"VGA compatible"* ]] || \
       [[ "$text" == *"Ethernet controller"* ]] || \
       [[ "$text" == *"Network controller"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local dev_num=0
    local current_slot="" current_class="" current_desc="" current_driver=""
    local in_device=0

    _flush_device () {
        if [[ $in_device -eq 1 && -n "$current_slot" ]]; then
            # Emit every device (no class filter) as a tidy row.
            dev_num=$((dev_num + 1))
            local prefix="entry${dev_num}."
            result+="${prefix}slot ${current_slot}"$'\n'
            [[ -n "$current_class" ]]  && result+="${prefix}class ${current_class}"$'\n'
            [[ -n "$current_desc" ]]   && result+="${prefix}description ${current_desc}"$'\n'
            [[ -n "$current_driver" ]] && result+="${prefix}driver ${current_driver}"$'\n'
        fi
        current_slot=""; current_class=""; current_desc=""; current_driver=""
        in_device=0
    }

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Device header: "00:1f.6 Ethernet controller: Intel Corporation ..."
        if [[ "$line" =~ ^[0-9a-fA-F]+:[0-9a-fA-F]+\.[0-9a-fA-F] ]]; then
            _flush_device
            in_device=1
            current_slot="${line%% *}"
            local rest="${line#* }"
            if [[ "$rest" == *": "* ]]; then
                current_class="${rest%%: *}"
                current_desc="${rest#*: }"
            else
                current_desc="$rest"
            fi
            continue
        fi

        # Verbose mode fields
        if [[ "$line" =~ ^[[:space:]]*Slot:[[:space:]]*(.*) ]]; then
            _flush_device; in_device=1
            current_slot="${BASH_REMATCH[1]# }"; continue
        fi
        if [[ "$line" =~ ^[[:space:]]*Class:[[:space:]]*(.*) ]]; then
            current_class="${BASH_REMATCH[1]# }"; continue
        fi
        if [[ "$line" =~ ^[[:space:]]*Device:[[:space:]]*(.*) ]]; then
            current_desc="${BASH_REMATCH[1]# }"; continue
        fi
        if [[ "$line" =~ ^[[:space:]]*Driver:[[:space:]]*(.*) ]] \
           || [[ "$line" =~ ^[[:space:]]*Kernel\ driver\ in\ use:[[:space:]]*(.*) ]]; then
            current_driver="${BASH_REMATCH[1]# }"; continue
        fi
    done <<< "$text"

    _flush_device

    result+="total_entries ${dev_num}"$'\n'
    echo "$result"
}
