#!/bin/bash
## Name: iptables-save
## Description: Extract firewall rules from iptables-save output
## Version: 1.0
## Priority: 22
## Sample: samples/iptables-save/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # Distinctive iptables-save signature: a table marker line "*filter"/"*nat"/etc.,
    # chain definition lines ":CHAIN ...", and rule lines beginning with "-A ".
    local has_table=0 has_chain=0 has_rule=0
    while IFS= read -r line; do
        case "$line" in
            '*filter'|'*nat'|'*mangle'|'*raw'|'*security') has_table=1 ;;
            ':'*) has_chain=1 ;;
            '-A '*) has_rule=1 ;;
        esac
    done <<< "$text"
    if [[ $has_rule -eq 1 && ( $has_table -eq 1 || $has_chain -eq 1 ) ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    while IFS= read -r line; do
        [[ "$line" == '-A '* ]] || continue
        # Strip "-A " prefix, then split chain from remaining rule text.
        local rest="${line#-A }"
        local chain="${rest%% *}"
        local rule="${rest#* }"
        # If there was no space (rule-less), avoid duplicating the chain as the rule.
        [[ "$rule" == "$rest" ]] && rule=""
        entry=$((entry + 1))
        result+="entry${entry}.chain ${chain}"$'\n'
        result+="entry${entry}.rule ${rule}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
