#!/bin/bash
## Name: docker-inspect
## Description: Extract container details from docker inspect JSON output
## Version: 1.0
## Priority: 12
## Sample: samples/docker-inspect/basic.json

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Must be JSON
    _is_json "$1" || return 1

    local has_config=0
    local has_host_or_net_or_state=0
    while IFS= read -r line; do
        case "$line" in
            *'"Config"'*) has_config=1 ;;
            *'"HostConfig"'*|*'"NetworkSettings"'*|*'"State"'*) has_host_or_net_or_state=1 ;;
        esac
        if [[ $has_config -eq 1 && $has_host_or_net_or_state -eq 1 ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Helper: extract a simple "Key": "Value" or "Key": number/bool from text
    # Uses grep for complex JSON parsing
    _di_extract_field () {
        local key="$1"
        local _text="$2"
        local val=""
        while IFS= read -r line; do
            case "$line" in
                *"\"${key}\""*)
                    # Extract value after the colon
                    local after="${line#*"\"${key}\""}"
                    # Remove leading colon, whitespace
                    after="${after#:}"
                    while [[ "$after" == " "* ]]; do after="${after# }"; done
                    # Remove trailing comma
                    after="${after%,}"
                    while [[ "$after" == *" " ]]; do after="${after% }"; done
                    # Strip quotes
                    case "$after" in
                        '"'*'"') after="${after#\"}"; after="${after%\"}" ;;
                    esac
                    val="$after"
                    break
                    ;;
            esac
        done <<< "$_text"
        echo "$val"
    }

    # Extract Id
    local id_val
    id_val=$(_di_extract_field "Id" "$text")
    if [[ -n "$id_val" ]]; then
        result+="id ${id_val}"$'\n'
    fi

    # Extract Name (strip leading /)
    local name_val
    name_val=$(_di_extract_field "Name" "$text")
    if [[ -n "$name_val" ]]; then
        name_val="${name_val#/}"
        result+="name ${name_val}"$'\n'
    fi

    # Extract State section fields
    local in_state=0
    local state_depth=0
    local state_text=""
    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        if [[ $in_state -eq 0 ]]; then
            case "$trimmed" in
                '"State"'*"{"*) in_state=1; state_depth=1; state_text+="$line"$'\n' ;;
            esac
        else
            state_text+="$line"$'\n'
            local i
            for ((i=0; i<${#trimmed}; i++)); do
                case "${trimmed:$i:1}" in
                    "{") state_depth=$((state_depth + 1)) ;;
                    "}") state_depth=$((state_depth - 1))
                        if [[ $state_depth -eq 0 ]]; then
                            in_state=0
                            break
                        fi
                        ;;
                esac
            done
        fi
    done <<< "$text"

    local status_val
    status_val=$(_di_extract_field "Status" "$state_text")
    if [[ -n "$status_val" ]]; then
        result+="state.status ${status_val}"$'\n'
    fi
    local running_val
    running_val=$(_di_extract_field "Running" "$state_text")
    if [[ -n "$running_val" ]]; then
        result+="state.running ${running_val}"$'\n'
    fi
    local pid_val
    pid_val=$(_di_extract_field "Pid" "$state_text")
    if [[ -n "$pid_val" ]]; then
        result+="state.pid ${pid_val}"$'\n'
    fi

    # Extract Config section
    local in_config=0
    local config_depth=0
    local config_text=""
    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        if [[ $in_config -eq 0 ]]; then
            case "$trimmed" in
                '"Config"'*"{"*) in_config=1; config_depth=1; config_text+="$line"$'\n' ;;
            esac
        else
            config_text+="$line"$'\n'
            local i
            for ((i=0; i<${#trimmed}; i++)); do
                case "${trimmed:$i:1}" in
                    "{") config_depth=$((config_depth + 1)) ;;
                    "}") config_depth=$((config_depth - 1))
                        if [[ $config_depth -eq 0 ]]; then
                            in_config=0
                            break
                        fi
                        ;;
                esac
            done
        fi
    done <<< "$text"

    local image_val
    image_val=$(_di_extract_field "Image" "$config_text")
    if [[ -n "$image_val" ]]; then
        result+="config.image ${image_val}"$'\n'
    fi
    local hostname_val
    hostname_val=$(_di_extract_field "Hostname" "$config_text")
    if [[ -n "$hostname_val" ]]; then
        result+="config.hostname ${hostname_val}"$'\n'
    fi

    # Extract Env entries from Config
    local in_env=0
    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        if [[ $in_env -eq 0 ]]; then
            case "$trimmed" in
                '"Env"'*"["*) in_env=1 ;;
            esac
            continue
        fi
        case "$trimmed" in
            "]"*) in_env=0; continue ;;
        esac
        # Parse "KEY=VALUE" entries
        # Strip quotes and trailing comma
        local entry="$trimmed"
        entry="${entry%,}"
        while [[ "$entry" == " "* ]]; do entry="${entry# }"; done
        while [[ "$entry" == *" " ]]; do entry="${entry% }"; done
        case "$entry" in
            '"'*'"')
                entry="${entry#\"}"
                entry="${entry%\"}"
                local env_key="${entry%%=*}"
                local env_val="${entry#*=}"
                result+="config.env.${env_key} ${env_val}"$'\n'
                ;;
        esac
    done <<< "$config_text"

    # Extract Cmd from Config
    local in_cmd=0
    local cmd_parts=""
    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        if [[ $in_cmd -eq 0 ]]; then
            case "$trimmed" in
                '"Cmd"'*"["*) in_cmd=1 ;;
            esac
            continue
        fi
        case "$trimmed" in
            "]"*) in_cmd=0; continue ;;
        esac
        local entry="$trimmed"
        entry="${entry%,}"
        while [[ "$entry" == " "* ]]; do entry="${entry# }"; done
        while [[ "$entry" == *" " ]]; do entry="${entry% }"; done
        case "$entry" in
            '"'*'"')
                entry="${entry#\"}"
                entry="${entry%\"}"
                if [[ -z "$cmd_parts" ]]; then
                    cmd_parts="$entry"
                else
                    cmd_parts="${cmd_parts} ${entry}"
                fi
                ;;
        esac
    done <<< "$config_text"
    if [[ -n "$cmd_parts" ]]; then
        result+="config.cmd ${cmd_parts}"$'\n'
    fi

    # Extract ExposedPorts from Config
    local in_exposed=0
    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        if [[ $in_exposed -eq 0 ]]; then
            case "$trimmed" in
                '"ExposedPorts"'*"{"*) in_exposed=1 ;;
            esac
            continue
        fi
        case "$trimmed" in
            "}"*) in_exposed=0; continue ;;
        esac
        # Parse "80/tcp": {}
        case "$trimmed" in
            '"'*'"'*)
                local port_entry="$trimmed"
                port_entry="${port_entry%%\":*}"
                port_entry="${port_entry#\"}"
                result+="config.exposed_port ${port_entry}"$'\n'
                ;;
        esac
    done <<< "$config_text"

    # Extract HostConfig section
    local in_hostconfig=0
    local hostconfig_depth=0
    local hostconfig_text=""
    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        if [[ $in_hostconfig -eq 0 ]]; then
            case "$trimmed" in
                '"HostConfig"'*"{"*) in_hostconfig=1; hostconfig_depth=1; hostconfig_text+="$line"$'\n' ;;
            esac
        else
            hostconfig_text+="$line"$'\n'
            local i
            for ((i=0; i<${#trimmed}; i++)); do
                case "${trimmed:$i:1}" in
                    "{") hostconfig_depth=$((hostconfig_depth + 1)) ;;
                    "}") hostconfig_depth=$((hostconfig_depth - 1))
                        if [[ $hostconfig_depth -eq 0 ]]; then
                            in_hostconfig=0
                            break
                        fi
                        ;;
                esac
            done
        fi
    done <<< "$text"

    local memory_val
    memory_val=$(_di_extract_field "Memory" "$hostconfig_text")
    if [[ -n "$memory_val" ]]; then
        result+="host_config.memory ${memory_val}"$'\n'
    fi
    local cpu_val
    cpu_val=$(_di_extract_field "CpuShares" "$hostconfig_text")
    if [[ -n "$cpu_val" ]]; then
        result+="host_config.cpu_shares ${cpu_val}"$'\n'
    fi

    # Extract NetworkSettings section
    local in_network=0
    local network_depth=0
    local network_text=""
    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        if [[ $in_network -eq 0 ]]; then
            case "$trimmed" in
                '"NetworkSettings"'*"{"*) in_network=1; network_depth=1; network_text+="$line"$'\n' ;;
            esac
        else
            network_text+="$line"$'\n'
            local i
            for ((i=0; i<${#trimmed}; i++)); do
                case "${trimmed:$i:1}" in
                    "{") network_depth=$((network_depth + 1)) ;;
                    "}") network_depth=$((network_depth - 1))
                        if [[ $network_depth -eq 0 ]]; then
                            in_network=0
                            break
                        fi
                        ;;
                esac
            done
        fi
    done <<< "$text"

    local ip_val
    ip_val=$(_di_extract_field "IPAddress" "$network_text")
    if [[ -n "$ip_val" ]]; then
        result+="network.ip_address ${ip_val}"$'\n'
    fi
    local gw_val
    gw_val=$(_di_extract_field "Gateway" "$network_text")
    if [[ -n "$gw_val" ]]; then
        result+="network.gateway ${gw_val}"$'\n'
    fi

    echo "$result"
}
