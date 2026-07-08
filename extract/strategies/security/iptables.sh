#!/bin/bash
## Name: iptables
## Description: Extract fields from iptables rule listing output
## Version: 1.0
## Priority: 20
## Sample: samples/iptables/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Reject JSON
    _is_json "$text" && return 1

    # Must contain Chain header with policy
    local _has_chain=0
    local _has_columns=0
    local _nl=$'\n'
    local _chain_re="(^|${_nl})Chain (INPUT|OUTPUT|FORWARD|[A-Za-z_-]+) "
    local _col_re="(^|${_nl}) *pkts.*target.*prot.*source.*destination"

    [[ "$text" =~ $_chain_re ]] && _has_chain=1
    [[ "$text" =~ $_col_re ]] && _has_columns=1

    [[ $_has_chain -eq 1 ]] && [[ $_has_columns -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local _chain_num=0
    local _chain_name=""
    local _rule_num=0
    local _in_rules=0

    while IFS= read -r line; do
        # Chain header line
        if [[ "$line" == "Chain "* ]]; then
            _chain_num=$((_chain_num + 1))
            _rule_num=0
            _in_rules=0

            # Extract chain name and policy
            local _rest="${line#Chain }"
            _chain_name="${_rest%% *}"
            _rest="${_rest#"$_chain_name"}"

            # Extract policy from parentheses
            local _paren_re='policy ([A-Z]+)'
            if [[ "$_rest" =~ $_paren_re ]]; then
                local _policy="${BASH_REMATCH[1]}"
                result+="chain${_chain_num}.name ${_chain_name}"$'\n'
                result+="chain${_chain_num}.policy ${_policy}"$'\n'
            else
                result+="chain${_chain_num}.name ${_chain_name}"$'\n'
            fi
            continue
        fi

        # Column header line (skip it, but mark that rules follow)
        if [[ "$line" == *"pkts"*"target"*"prot"* ]]; then
            _in_rules=1
            continue
        fi

        # Empty line resets rule parsing
        if [[ -z "$line" ]]; then
            _in_rules=0
            continue
        fi

        # Rule line (when inside a chain's rules section)
        if [[ $_in_rules -eq 1 ]]; then
            _rule_num=$((_rule_num + 1))

            # Strip leading whitespace
            local _trimmed="$line"
            while [[ "$_trimmed" == " "* ]]; do _trimmed="${_trimmed# }"; done

            # Parse space-separated fields: pkts bytes target prot opt in out source destination [extra...]
            local _fields=""
            local _field_count=0
            local _pkts="" _bytes="" _target="" _prot="" _opt="" _in="" _out="" _source="" _dest="" _extra=""

            local _remaining="$_trimmed"
            while [[ -n "$_remaining" ]]; do
                local _tok="${_remaining%% *}"
                _field_count=$((_field_count + 1))
                case $_field_count in
                    1) _pkts="$_tok" ;;
                    2) _bytes="$_tok" ;;
                    3) _target="$_tok" ;;
                    4) _prot="$_tok" ;;
                    5) _opt="$_tok" ;;
                    6) _in="$_tok" ;;
                    7) _out="$_tok" ;;
                    8) _source="$_tok" ;;
                    9) _dest="$_tok" ;;
                    *)
                        if [[ -n "$_extra" ]]; then
                            _extra="${_extra}_${_tok}"
                        else
                            _extra="$_tok"
                        fi
                        ;;
                esac
                if [[ "$_remaining" == *" "* ]]; then
                    _remaining="${_remaining#"$_tok"}"
                    while [[ "$_remaining" == " "* ]]; do _remaining="${_remaining# }"; done
                else
                    _remaining=""
                fi
            done

            local _prefix="chain${_chain_num}.rule${_rule_num}"
            [[ -n "$_target" ]] && result+="${_prefix}.target ${_target}"$'\n'
            [[ -n "$_prot" ]] && result+="${_prefix}.protocol ${_prot}"$'\n'
            [[ -n "$_source" ]] && result+="${_prefix}.source ${_source}"$'\n'
            [[ -n "$_dest" ]] && result+="${_prefix}.destination ${_dest}"$'\n'
            if [[ -n "$_extra" ]]; then
                result+="${_prefix}.extra ${_extra}"$'\n'
            fi
        fi
    done <<< "$text"

    echo "$result"
}
