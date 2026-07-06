#!/bin/bash
## Name: host
## Description: Extract answer lines (name/record/value) from `host` lookups
## Version: 1.0
## Priority: 20
## Sample: samples/host/basic.txt

# The `host` resolver prints one answer per line:
#   example.com has address 93.184.216.34
#   example.com has IPv6 address 2606:2800:...
#   example.com mail is handled by 10 mail.example.com.
#   alias.example.com is an alias for example.com.
#   34.216.184.93.in-addr.arpa domain name pointer example.com.

_host_answer_kind () {
    # echoes: record<TAB>value ; returns 1 if not an answer line
    local line="$1" name rest
    case "$line" in
        *" has IPv6 address "*)
            name="${line%% has IPv6 address *}"
            rest="${line#* has IPv6 address }"
            _HOST_NAME="$name"; _HOST_RECORD="ipv6_address"; _HOST_VALUE="$rest"; return 0 ;;
        *" has address "*)
            name="${line%% has address *}"
            rest="${line#* has address }"
            _HOST_NAME="$name"; _HOST_RECORD="address"; _HOST_VALUE="$rest"; return 0 ;;
        *" mail is handled by "*)
            name="${line%% mail is handled by *}"
            rest="${line#* mail is handled by }"
            _HOST_NAME="$name"; _HOST_RECORD="mx"; _HOST_VALUE="$rest"; return 0 ;;
        *" is an alias for "*)
            name="${line%% is an alias for *}"
            rest="${line#* is an alias for }"
            _HOST_NAME="$name"; _HOST_RECORD="alias"; _HOST_VALUE="$rest"; return 0 ;;
        *" domain name pointer "*)
            name="${line%% domain name pointer *}"
            rest="${line#* domain name pointer }"
            _HOST_NAME="$name"; _HOST_RECORD="ptr"; _HOST_VALUE="$rest"; return 0 ;;
    esac
    return 1
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line
    while IFS= read -r line; do
        if _host_answer_kind "$line"; then
            _STRATEGY_CONFIDENCE=88
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0
    local line
    while IFS= read -r line; do
        _host_answer_kind "$line" || continue
        entry=$((entry + 1))
        result+="entry${entry}.name ${_HOST_NAME}"$'\n'
        result+="entry${entry}.record ${_HOST_RECORD}"$'\n'
        result+="entry${entry}.value ${_HOST_VALUE}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
