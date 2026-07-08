#!/bin/bash
## Name: ssh-keyscan
## Description: Extract host public-key records from ssh-keyscan output
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/ssh-keyscan/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # ssh-keyscan lines: "<host> <keytype> <base64>", with "#"-comment lines.
    local n=0 line kt
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "#"* ]] && continue
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 3 ]] || continue
        kt="${f[1]}"
        case "$kt" in
            ssh-rsa|ssh-dss|ssh-ed25519|ecdsa-sha2-*|sk-ssh-ed25519@*|sk-ecdsa-*)
                n=$((n + 1)) ;;
        esac
    done <<< "$text"
    if [[ $n -ge 2 ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    local line host keytype
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "#"* ]] && continue
        read -ra f <<< "$line"
        [[ ${#f[@]} -ge 3 ]] || continue
        keytype="${f[1]}"
        case "$keytype" in
            ssh-rsa|ssh-dss|ssh-ed25519|ecdsa-sha2-*|sk-ssh-ed25519@*|sk-ecdsa-*) : ;;
            *) continue ;;
        esac
        host="${f[0]}"

        entry=$((entry + 1))
        result+="entry${entry}.host ${host}"$'\n'
        result+="entry${entry}.keytype ${keytype}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
