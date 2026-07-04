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
    local current_slot=""
    local current_class=""
    local current_vendor=""
    local current_device=""
    local current_driver=""
    local in_device=0

    _flush_device () {
        if [[ $in_device -eq 1 && -n "$current_slot" ]]; then
            local dominated=0
            # Filter to key device types: GPU, NIC, NVMe, InfiniBand, storage
            case "$current_class" in
                *VGA*|*3D*|*Display*|*Ethernet*|*Network*|*InfiniBand*|*NVMe*|*Non-Volatile*|*RAID*|*Mass\ storage*)
                    dominated=0 ;;
                *)
                    dominated=1 ;;
            esac
            if [[ $dominated -eq 0 ]]; then
                dev_num=$((dev_num + 1))
                local prefix="device${dev_num}."
                result+="${prefix}slot ${current_slot}"$'\n'
                [[ -n "$current_class" ]] && result+="${prefix}class ${current_class}"$'\n'
                [[ -n "$current_vendor" ]] && result+="${prefix}vendor ${current_vendor}"$'\n'
                [[ -n "$current_device" ]] && result+="${prefix}device_name ${current_device}"$'\n'
                [[ -n "$current_driver" ]] && result+="${prefix}driver ${current_driver}"$'\n'
            fi
        fi
        current_slot=""
        current_class=""
        current_vendor=""
        current_device=""
        current_driver=""
        in_device=0
    }

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Device header line: "00:1f.6 Ethernet controller: Intel Corporation ..."
        # or verbose: "Slot:  00:1f.6"
        if [[ "$line" =~ ^[0-9a-fA-F]+:[0-9a-fA-F]+\.[0-9a-fA-F] ]]; then
            _flush_device
            in_device=1
            current_slot="${line%% *}"
            local rest="${line#* }"
            # Class is before the colon, vendor+device after
            if [[ "$rest" == *": "* ]]; then
                current_class="${rest%%: *}"
                local vendor_device="${rest#*: }"
                if [[ "$vendor_device" == *" "* ]]; then
                    current_vendor="${vendor_device}"
                    current_device="${vendor_device}"
                fi
            fi
            continue
        fi

        # Verbose mode fields
        if [[ "$line" =~ ^[[:space:]]*Slot:[[:space:]]*(.*) ]]; then
            _flush_device
            in_device=1
            current_slot="${BASH_REMATCH[1]}"
            current_slot="${current_slot# }"
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*Class:[[:space:]]*(.*) ]]; then
            current_class="${BASH_REMATCH[1]}"
            current_class="${current_class# }"
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*Vendor:[[:space:]]*(.*) ]]; then
            current_vendor="${BASH_REMATCH[1]}"
            current_vendor="${current_vendor# }"
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*Device:[[:space:]]*(.*) ]]; then
            current_device="${BASH_REMATCH[1]}"
            current_device="${current_device# }"
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*Driver:[[:space:]]*(.*) ]]; then
            current_driver="${BASH_REMATCH[1]}"
            current_driver="${current_driver# }"
            continue
        fi
        # Alternative: "Kernel driver in use: xxx"
        if [[ "$line" =~ ^[[:space:]]*Kernel\ driver\ in\ use:[[:space:]]*(.*) ]]; then
            current_driver="${BASH_REMATCH[1]}"
            current_driver="${current_driver# }"
            continue
        fi
    done <<< "$text"

    _flush_device

    result+="device_count ${dev_num}"$'\n'
    echo "$result"
}
