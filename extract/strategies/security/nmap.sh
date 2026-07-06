#!/bin/bash
## Name: nmap
## Description: Extract fields from nmap scan output
## Version: 1.0
## Priority: 15
## Sample: samples/nmap/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Contains "Nmap scan report" or "PORT  STATE  SERVICE" header
    [[ "$text" == *"Nmap scan report"* ]] && return 0
    [[ "$text" =~ PORT[[:space:]]+STATE[[:space:]]+SERVICE ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local in_ports=0
    local port_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Extract host info: "Nmap scan report for example.com (93.184.216.34)"
        if [[ "$line" == *"Nmap scan report for"* ]]; then
            local host ip
            local after="${line#*report for }"
            # Try to extract host and IP from "for host (ip)" pattern
            if [[ "$after" == *"("*")"* ]]; then
                host="${after%% (*}"
                ip="${after#*(}"
                ip="${ip%%)*}"
            else
                host="$after"
                ip=""
            fi
            host="${host// /_}"
            result+="host ${host}"$'\n'
            [[ -n "$ip" ]] && result+="ip ${ip}"$'\n'
            continue
        fi

        # Extract latency: "Host is up (0.023s latency)."
        if [[ "$line" == *"Host is up"* ]]; then
            if [[ "$line" == *"("*"latency)"* ]]; then
                local latency="${line#*(}"
                latency="${latency%% latency)*}"
                latency="${latency// /_}"
                result+="latency ${latency}"$'\n'
            fi
            continue
        fi

        # Detect port table header
        if [[ "$line" =~ ^PORT[[:space:]]+STATE[[:space:]]+SERVICE ]]; then
            in_ports=1
            continue
        fi

        # Parse port lines: "22/tcp  open  ssh  OpenSSH 8.9"
        if [[ $in_ports -eq 1 ]]; then
            if [[ "$line" =~ ^[0-9]+/ ]]; then
                port_num=$((port_num + 1))
                read -ra _arr <<< "$line"
                local port="${_arr[0]}"
                local state="${_arr[1]}"
                local service="${_arr[2]}"
                # Version is everything from field 4 onward
                local version_str=""
                local i
                for ((i=3; i<${#_arr[@]}; i++)); do
                    if [[ -n "$version_str" ]]; then
                        version_str+="_"
                    fi
                    version_str+="${_arr[$i]}"
                done

                result+="port${port_num}.port ${port}"$'\n'
                result+="port${port_num}.state ${state}"$'\n'
                result+="port${port_num}.service ${service}"$'\n'
                [[ -n "$version_str" ]] && result+="port${port_num}.version ${version_str}"$'\n'
            else
                in_ports=0
            fi
        fi

        # Extract scan summary: "Nmap done: 1 IP scanned in 12.34 seconds"
        if [[ "$line" == *"Nmap done:"* ]]; then
            if [[ "$line" == *"scanned in "* ]]; then
                local scan_time="${line#*scanned in }"
                scan_time="${scan_time// /_}"
                result+="scan_time ${scan_time}"$'\n'
            fi
        fi

    done <<< "$text"

    echo "$result"
}
