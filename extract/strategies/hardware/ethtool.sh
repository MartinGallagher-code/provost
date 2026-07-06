#!/bin/bash
## Name: ethtool
## Description: Extract network interface details from ethtool output
## Version: 1.0
## Priority: 10
## Sample: samples/ethtool/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$1" && return 1
    if [[ "$text" == *"ethtool"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Settings for "* ]] && [[ "$text" == *"Speed:"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Duplex:"* ]] && [[ "$text" == *"Link detected:"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Supported ports:"* ]] && [[ "$text" == *"Speed:"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local section=""

    # Extract interface name from "Settings for ethN:" header
    local iface=""
    iface=$(_strat_ethtool_extract_interface "$text")
    [[ -n "$iface" ]] && result+="interface ${iface}"$'\n'

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Track section context
        if [[ "$line" == "Settings for "* ]]; then
            section="settings"
            continue
        fi
        if [[ "$line" == "Ring parameters for "* ]]; then
            section="ring"
            continue
        fi
        if [[ "$line" == "Current hardware settings:" ]]; then
            section="ring_current"
            continue
        fi
        if [[ "$line" == "Pre-set maximums:" ]]; then
            section="ring_max"
            continue
        fi

        # Parse key: value or key:\tvalue lines
        local key=""
        local val=""
        if [[ "$line" == *":"* ]]; then
            key="${line%%:*}"
            val="${line#*:}"
            # Trim whitespace
            while [[ "$key" == " "* || "$key" == $'\t'* ]]; do key="${key#[	 ]}"; done
            while [[ "$key" == *" " ]]; do key="${key% }"; done
            while [[ "$val" == " "* || "$val" == $'\t'* ]]; do val="${val#[	 ]}"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done
        else
            continue
        fi

        case "$section" in
            settings)
                case "$key" in
                    "Speed") result+="speed ${val}"$'\n' ;;
                    "Duplex") result+="duplex ${val}"$'\n' ;;
                    "Auto-negotiation") result+="auto_negotiation ${val}"$'\n' ;;
                    "Link detected") result+="link_detected ${val}"$'\n' ;;
                    "Port") result+="port ${val}"$'\n' ;;
                    "Supported ports") result+="supported_ports ${val}"$'\n' ;;
                    "Supported link modes")
                        result+="supported_link_modes ${val}"$'\n' ;;
                esac
                ;;
            ring_current)
                case "$key" in
                    "RX") result+="ring_rx ${val}"$'\n' ;;
                    "TX") result+="ring_tx ${val}"$'\n' ;;
                esac
                ;;
        esac

        # Driver info section (no indentation, key: value after settings block)
        if [[ "$section" != "ring" && "$section" != "ring_current" && "$section" != "ring_max" ]]; then
            case "$key" in
                "driver") result+="driver ${val}"$'\n' ;;
                "firmware-version") result+="firmware_version ${val}"$'\n' ;;
                "bus-info") result+="bus_info ${val}"$'\n' ;;
            esac
        fi

    done <<< "$text"

    echo "$result"
}

_strat_ethtool_extract_interface () {
    local text="$1"
    while IFS= read -r line; do
        if [[ "$line" == "Settings for "* ]]; then
            local iface="${line#Settings for }"
            iface="${iface%:}"
            echo "$iface"
            return
        fi
    done <<< "$text"
}
