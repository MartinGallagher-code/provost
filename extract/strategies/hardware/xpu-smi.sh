#!/bin/bash
## Name: xpu-smi
## Description: Extract Intel GPU device info and stats from xpu-smi output
## Version: 1.0
## Priority: 10
## Sample: samples/xpu-smi/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    _is_json "$1" && return 1
    if [[ "$text" == *"xpu-smi"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Device Name: Intel"* ]] && [[ "$text" == *"GPU Utilization"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Device ID"* ]] && [[ "$text" == *"PCI BDF Address"* ]]; then
        return 0
    fi
    if [[ "$text" == *"GPU Utilization (%)"* ]] && [[ "$text" == *"GPU Power (W)"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local current_device=""
    local device_count=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip table borders
        [[ "$line" == +* ]] && continue
        [[ "$line" == *"---"* ]] && continue

        # Strip leading/trailing pipe and whitespace
        local stripped=""
        stripped=$(_strat_xpu_smi_strip_row "$line")
        [[ -z "$stripped" ]] && continue

        # Detect device ID rows: "| 0           | Device Name: ..." or "| 0           | GPU Utilization..."
        if [[ "$stripped" =~ ^([0-9]+)[[:space:]]*\|[[:space:]]*(.*) ]]; then
            current_device="${BASH_REMATCH[1]}"
            local rest="${BASH_REMATCH[2]}"

            # Check if this is a new device we haven't counted
            local dev_num=$((current_device + 1))
            if [[ $dev_num -gt $device_count ]]; then
                device_count=$dev_num
            fi

            # Parse any key: value on same line as device ID
            _strat_xpu_smi_parse_field "$rest" "$dev_num" result
            continue
        fi

        # Continuation rows: after stripping, these are plain "Key: value" lines
        # (no leading device ID number)
        if [[ -n "$current_device" ]] && [[ "$stripped" == *":"* ]]; then
            local dev_num=$((current_device + 1))
            _strat_xpu_smi_parse_field "$stripped" "$dev_num" result
            continue
        fi

    done <<< "$text"

    [[ $device_count -gt 0 ]] && result+="device_count ${device_count}"$'\n'

    echo "$result"
}

_strat_xpu_smi_strip_row () {
    local line="$1"
    # Remove leading/trailing pipes and whitespace
    local stripped="$line"
    while [[ "$stripped" == " "* || "$stripped" == "|"* ]]; do stripped="${stripped#[| ]}"; done
    while [[ "$stripped" == *" " || "$stripped" == *"|" ]]; do stripped="${stripped%[| ]}"; done
    echo "$stripped"
}

_strat_xpu_smi_parse_field () {
    local field="$1"
    local dev_num="$2"
    local -n _result=$3
    local prefix="dev${dev_num}"

    # Strip trailing pipe/whitespace
    while [[ "$field" == *"|" || "$field" == *" " ]]; do field="${field%[| ]}"; done

    # Skip header/non-data rows
    [[ "$field" == "Device Information" ]] && return
    [[ "$field" == "Stats" ]] && return
    [[ "$field" == "Device ID"* ]] && return

    if [[ "$field" == *":"* ]]; then
        local key="${field%%:*}"
        local val="${field#*:}"
        while [[ "$val" == " "* ]]; do val="${val# }"; done
        while [[ "$val" == *" " ]]; do val="${val% }"; done
        while [[ "$key" == " "* ]]; do key="${key# }"; done
        while [[ "$key" == *" " ]]; do key="${key% }"; done

        case "$key" in
            "Device Name") _result+="${prefix}_device_name ${val}"$'\n' ;;
            "Vendor") _result+="${prefix}_vendor ${val}"$'\n' ;;
            "Driver Version") _result+="${prefix}_driver_version ${val}"$'\n' ;;
            "PCI BDF Address") _result+="${prefix}_pci_bdf ${val}"$'\n' ;;
            "GPU Utilization (%)") _result+="${prefix}_gpu_util_percent ${val}"$'\n' ;;
            "GPU Power (W)") _result+="${prefix}_power_W ${val}"$'\n' ;;
            "GPU Temperature (C)") _result+="${prefix}_temp_C ${val}"$'\n' ;;
            "Memory Used (MiB)") _result+="${prefix}_memory_used_MiB ${val}"$'\n' ;;
            "Memory Total (MiB)") _result+="${prefix}_memory_total_MiB ${val}"$'\n' ;;
        esac
    fi
}
