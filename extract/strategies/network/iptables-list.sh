#!/bin/bash
## Name: iptables-list
## Description: Extract firewall rules from iptables -L -n -v --line-numbers output
## Version: 1.0
## Priority: 48
## Technique: table
## Sample: samples/iptables-list/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=88
    _is_json "$text" && return 1
    # iptables -L -n -v has "Chain" lines with "(policy" and "pkts bytes target"
    local has_chain=0
    local has_table_header=0
    while IFS= read -r line; do
        [[ "$line" == "Chain "* && "$line" == *"policy"* ]] && has_chain=1
        [[ "$line" == *"pkts"* && "$line" == *"bytes"* && "$line" == *"target"* ]] && has_table_header=1
        if [[ $has_chain -eq 1 && $has_table_header -eq 1 ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local chain_name=""
    local chain_policy=""
    local rule_n=0
    local past_header=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && { past_header=0; continue; }

        # Chain header: Chain INPUT (policy ACCEPT 123 packets, 456 bytes)
        if [[ "$line" == "Chain "* ]]; then
            read -ra _ch <<< "$line"
            chain_name="${_ch[1]}"
            # Extract policy
            chain_policy=""
            if [[ "$line" == *"policy "* ]]; then
                local tmp="${line#*policy }"
                chain_policy="${tmp%% *}"
                chain_policy="${chain_policy%)}"
            fi
            [[ -n "$chain_name" ]] && result+="chain.${chain_name}.policy ${chain_policy:-NONE}"$'\n'
            past_header=0
            continue
        fi

        # Skip column header line
        if [[ "$line" == *"pkts"* && "$line" == *"bytes"* && "$line" == *"target"* ]]; then
            past_header=1
            continue
        fi
        [[ $past_header -eq 0 ]] && continue
        [[ -z "$chain_name" ]] && continue

        read -ra _arr <<< "$line"
        [[ ${#_arr[@]} -lt 6 ]] && continue

        rule_n=$((rule_n + 1))
        local prefix="rule${rule_n}"

        local pkts="${_arr[0]}"
        local bytes="${_arr[1]}"
        local target="${_arr[2]}"
        local prot="${_arr[3]}"
        local source="${_arr[7]:-any}"
        local destination="${_arr[8]:-any}"

        result+="${prefix}.chain ${chain_name}"$'\n'
        result+="${prefix}.pkts ${pkts}"$'\n'
        result+="${prefix}.bytes ${bytes}"$'\n'
        result+="${prefix}.target ${target}"$'\n'
        result+="${prefix}.prot ${prot}"$'\n'
        [[ -n "$source" ]] && result+="${prefix}.source ${source}"$'\n'
        [[ -n "$destination" ]] && result+="${prefix}.destination ${destination}"$'\n'
    done <<< "$text"

    echo "$result"
}
