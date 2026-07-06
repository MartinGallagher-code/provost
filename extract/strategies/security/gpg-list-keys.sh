#!/bin/bash
## Name: gpg-list-keys
## Description: Extract a single key snapshot from `gpg --list-keys`
## Version: 1.0
## Priority: 19
## Sample: samples/gpg-list-keys/basic.txt

# `gpg --list-keys` prints a keyring block:
#   pub   rsa4096/3AA5C34371567BD2 2026-01-15 [SC]
#         <fingerprint>
#   uid   [ultimate] Alice Example <alice@example.com>
#   sub   rsa4096/42B317FD4BA89E7A 2026-01-15 [E]
# Emit one record summarising the primary key.

_gpg_is_pub () {
    [[ "$1" =~ ^pub[[:space:]]+[^[:space:]/]+/[0-9A-Fa-f]{8,40}[[:space:]] ]]
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line
    while IFS= read -r line; do
        if _gpg_is_pub "$line"; then
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local keyid="" created="" uid=""
    local line
    while IFS= read -r line; do
        if [[ $entry -eq 0 ]] && _gpg_is_pub "$line"; then
            read -ra _a <<< "$line"
            local algo_key="${_a[1]}"
            keyid="${algo_key#*/}"
            created="${_a[2]}"
            entry=1
        elif [[ "$line" =~ ^uid[[:space:]] && -z "$uid" ]]; then
            uid="${line#uid}"
            uid="${uid#"${uid%%[![:space:]]*}"}"
            # drop leading [validity] marker if present
            [[ "$uid" == \[*\]* ]] && uid="${uid#*] }"
        fi
    done <<< "$text"
    if [[ $entry -eq 1 ]]; then
        result+="entry1.type pub"$'\n'
        result+="entry1.keyid ${keyid}"$'\n'
        [[ -n "$uid" ]] && result+="entry1.uid ${uid}"$'\n'
        [[ -n "$created" ]] && result+="entry1.created ${created}"$'\n'
        result+="total_entries 1"$'\n'
    fi
    echo "$result"
}
