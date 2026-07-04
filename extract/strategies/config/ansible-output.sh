#!/bin/bash
## Name: ansible-output
## Description: Extract fields from Ansible playbook recap output
## Version: 1.0
## Priority: 20
## Sample: samples/ansible-output/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Reject JSON
    _is_json "$text" && return 1

    # Must contain PLAY RECAP
    [[ "$text" == *"PLAY RECAP"* ]] || return 1

    # Must contain host recap lines with ok=N changed=N pattern
    local _recap_re='ok=[0-9]+'
    [[ "$text" =~ $_recap_re ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"
    local result=""
    local _host_num=0
    local _play_num=0
    local _in_recap=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Play name: PLAY [name] ***
        if [[ "$line" == "PLAY ["* ]]; then
            _play_num=$((_play_num + 1))
            local _pname="${line#PLAY \[}"
            _pname="${_pname%%\]*}"
            _pname="${_pname// /_}"
            result+="play${_play_num}.name ${_pname}"$'\n'
            _in_recap=0
            continue
        fi

        # PLAY RECAP marker
        if [[ "$line" == "PLAY RECAP"* ]]; then
            _in_recap=1
            continue
        fi

        # Host recap lines (after PLAY RECAP)
        if [[ $_in_recap -eq 1 ]]; then
            # Pattern: hostname : ok=N changed=N unreachable=N failed=N ...
            local _recap_line_re=': +ok='
            if [[ "$line" =~ $_recap_line_re ]]; then
                _host_num=$((_host_num + 1))

                # Extract hostname (before the colon)
                local _hostname="${line%%:*}"
                # Trim trailing spaces
                while [[ "$_hostname" == *" " ]]; do _hostname="${_hostname% }"; done
                _hostname="${_hostname// /_}"

                result+="host${_host_num}.name ${_hostname}"$'\n'

                # Extract ok=N
                local _ok_re='ok=([0-9]+)'
                if [[ "$line" =~ $_ok_re ]]; then
                    result+="host${_host_num}.ok ${BASH_REMATCH[1]}"$'\n'
                fi

                # Extract changed=N
                local _changed_re='changed=([0-9]+)'
                if [[ "$line" =~ $_changed_re ]]; then
                    result+="host${_host_num}.changed ${BASH_REMATCH[1]}"$'\n'
                fi

                # Extract unreachable=N
                local _unreach_re='unreachable=([0-9]+)'
                if [[ "$line" =~ $_unreach_re ]]; then
                    result+="host${_host_num}.unreachable ${BASH_REMATCH[1]}"$'\n'
                fi

                # Extract failed=N
                local _failed_re='failed=([0-9]+)'
                if [[ "$line" =~ $_failed_re ]]; then
                    result+="host${_host_num}.failed ${BASH_REMATCH[1]}"$'\n'
                fi

                # Extract skipped=N
                local _skipped_re='skipped=([0-9]+)'
                if [[ "$line" =~ $_skipped_re ]]; then
                    result+="host${_host_num}.skipped ${BASH_REMATCH[1]}"$'\n'
                fi

                # Extract rescued=N
                local _rescued_re='rescued=([0-9]+)'
                if [[ "$line" =~ $_rescued_re ]]; then
                    result+="host${_host_num}.rescued ${BASH_REMATCH[1]}"$'\n'
                fi
            fi
        fi
    done <<< "$text"

    echo "$result"
}
