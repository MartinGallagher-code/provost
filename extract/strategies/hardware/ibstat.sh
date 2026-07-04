#!/bin/bash
## Name: ibstat
## Description: Extract InfiniBand adapter information from ibstat/ibstatus output
## Version: 1.0
## Priority: 15
## Sample: samples/ibstat/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$1" && return 1
    if [[ "$text" == *"ibstat"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Infiniband"* ]] || [[ "$text" == *"InfiniBand"* ]]; then
        if [[ "$text" == *"State:"* ]] || [[ "$text" == *"Rate:"* ]]; then
            return 0
        fi
    fi
    # ibstat format: "CA 'mlx5_0'" followed by port info
    if [[ "$text" == *"CA '"* ]] && [[ "$text" == *"Port "* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local ca_num=0
    local port_num=0
    local current_ca=""
    local ca_prefix=""
    local port_prefix=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # CA header: "CA 'mlx5_0'" or "CA: mlx5_0"
        if [[ "$line" =~ ^CA[[:space:]]+\'([^\']+)\' ]] || \
           [[ "$line" =~ ^CA:[[:space:]]*(.*) ]]; then
            ca_num=$((ca_num + 1))
            current_ca="${BASH_REMATCH[1]}"
            while [[ "$current_ca" == *" " ]]; do current_ca="${current_ca% }"; done
            ca_prefix="ca${ca_num}."
            port_num=0
            result+="${ca_prefix}name ${current_ca}"$'\n'
            continue
        fi

        # CA type: "CA type: MT4123"
        if [[ "$line" =~ ^[[:space:]]*CA[[:space:]]+type:[[:space:]]*(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            result+="${ca_prefix}ca_type ${val}"$'\n'
            continue
        fi

        # Number of ports: "Number of ports: 2"
        if [[ "$line" =~ ^[[:space:]]*Number[[:space:]]+of[[:space:]]+ports:[[:space:]]*([0-9]+) ]]; then
            result+="${ca_prefix}num_ports ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Firmware version
        if [[ "$line" =~ ^[[:space:]]*Firmware[[:space:]]+version:[[:space:]]*(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            result+="${ca_prefix}firmware_version ${val}"$'\n'
            continue
        fi

        # Port header: "Port 1:" or "Port 1"
        if [[ "$line" =~ ^[[:space:]]*Port[[:space:]]+([0-9]+) ]]; then
            port_num="${BASH_REMATCH[1]}"
            port_prefix="${ca_prefix}port${port_num}."
            continue
        fi

        # State: Active / Down / Initializing
        if [[ "$line" =~ ^[[:space:]]*State:[[:space:]]*(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            result+="${port_prefix}state ${val}"$'\n'
            continue
        fi

        # Physical state: LinkUp / Polling / Disabled
        if [[ "$line" =~ ^[[:space:]]*Physical[[:space:]]+state:[[:space:]]*(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            result+="${port_prefix}physical_state ${val}"$'\n'
            continue
        fi

        # Rate: 100 / 200
        if [[ "$line" =~ ^[[:space:]]*Rate:[[:space:]]*(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            result+="${port_prefix}rate ${val}"$'\n'
            continue
        fi

        # Base lid / SM lid
        if [[ "$line" =~ ^[[:space:]]*Base[[:space:]]+lid:[[:space:]]*([0-9]+) ]]; then
            result+="${port_prefix}lid ${BASH_REMATCH[1]}"$'\n'
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]*SM[[:space:]]+lid:[[:space:]]*([0-9]+) ]]; then
            result+="${port_prefix}sm_lid ${BASH_REMATCH[1]}"$'\n'
            continue
        fi

        # Link layer: InfiniBand / Ethernet
        if [[ "$line" =~ ^[[:space:]]*Link[[:space:]]+layer:[[:space:]]*(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            result+="${port_prefix}link_layer ${val}"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}
