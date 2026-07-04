#!/bin/bash
## Name: jwt
## Description: Extract fields from JWT token payloads (header and payload decoding)
## Version: 1.0
## Priority: 15
## Sample: samples/jwt/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Reject JSON
    _is_json "$text" && return 1

    # Look for JWT pattern: three base64url segments separated by dots
    local _jwt_re='[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'
    [[ "$text" =~ $_jwt_re ]] || return 1

    # Verify we can extract a token and its middle segment decodes to JSON-like content
    local _token="${BASH_REMATCH[0]}"
    local _payload="${_token#*.}"
    _payload="${_payload%%.*}"

    # Base64url to base64: replace - with +, _ with /
    local _b64="$_payload"
    _b64="${_b64//-/+}"
    _b64="${_b64//_//}"
    # Add padding
    local _mod=$(( ${#_b64} % 4 ))
    if [[ $_mod -eq 2 ]]; then
        _b64="${_b64}=="
    elif [[ $_mod -eq 3 ]]; then
        _b64="${_b64}="
    fi

    local _decoded
    _decoded=$(printf '%s' "$_b64" | base64 --decode 2>/dev/null) || return 1
    # Check it looks like JSON (starts with {)
    [[ "$_decoded" == "{"* ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"
    local result=""

    # Find JWT tokens in the text
    local _jwt_re='[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        if [[ "$_line" =~ $_jwt_re ]]; then
            local _token="${BASH_REMATCH[0]}"

            # Split into header.payload.signature
            local _header="${_token%%.*}"
            local _rest="${_token#*.}"
            local _payload="${_rest%%.*}"

            # Decode header
            local _b64="$_header"
            _b64="${_b64//-/+}"
            _b64="${_b64//_//}"
            local _mod=$(( ${#_b64} % 4 ))
            if [[ $_mod -eq 2 ]]; then _b64="${_b64}=="; fi
            if [[ $_mod -eq 3 ]]; then _b64="${_b64}="; fi
            local _hdr_json
            _hdr_json=$(printf '%s' "$_b64" | base64 --decode 2>/dev/null) || continue

            # Parse header JSON key-value pairs
            local _clean="${_hdr_json#\{}"
            _clean="${_clean%\}}"
            # Split on commas — simple flat JSON parsing
            while [[ -n "$_clean" ]]; do
                # Strip leading whitespace and comma
                while [[ "$_clean" == " "* || "$_clean" == ","* ]]; do
                    _clean="${_clean#[, ]}"
                done
                [[ -z "$_clean" ]] && break

                # Extract key (between quotes)
                if [[ "$_clean" == \"* ]]; then
                    _clean="${_clean#\"}"
                    local _key="${_clean%%\"*}"
                    _clean="${_clean#*\"}"
                    # Skip colon
                    while [[ "$_clean" == " "* || "$_clean" == ":"* ]]; do
                        _clean="${_clean#[: ]}"
                    done
                    # Extract value
                    local _val=""
                    if [[ "$_clean" == \"* ]]; then
                        _clean="${_clean#\"}"
                        _val="${_clean%%\"*}"
                        _clean="${_clean#*\"}"
                    elif [[ "$_clean" == "true"* || "$_clean" == "false"* || "$_clean" == "null"* ]]; then
                        _val="${_clean%%[,\}]*}"
                        _clean="${_clean#"$_val"}"
                    elif [[ "$_clean" == "["* ]]; then
                        # Array value — grab until ]
                        _val="${_clean%%]*}]"
                        _clean="${_clean#*]}"
                        _val="${_val// /_}"
                    else
                        _val="${_clean%%[,\}]*}"
                        _clean="${_clean#"$_val"}"
                    fi
                    _val="${_val// /_}"
                    [[ -n "$_key" ]] && [[ -n "$_val" ]] && result+="header.${_key} ${_val}"$'\n'
                else
                    break
                fi
            done

            # Decode payload
            _b64="$_payload"
            _b64="${_b64//-/+}"
            _b64="${_b64//_//}"
            _mod=$(( ${#_b64} % 4 ))
            if [[ $_mod -eq 2 ]]; then _b64="${_b64}=="; fi
            if [[ $_mod -eq 3 ]]; then _b64="${_b64}="; fi
            local _pay_json
            _pay_json=$(printf '%s' "$_b64" | base64 --decode 2>/dev/null) || continue

            # Parse payload JSON key-value pairs
            _clean="${_pay_json#\{}"
            _clean="${_clean%\}}"
            while [[ -n "$_clean" ]]; do
                while [[ "$_clean" == " "* || "$_clean" == ","* ]]; do
                    _clean="${_clean#[, ]}"
                done
                [[ -z "$_clean" ]] && break

                if [[ "$_clean" == \"* ]]; then
                    _clean="${_clean#\"}"
                    local _key="${_clean%%\"*}"
                    _clean="${_clean#*\"}"
                    while [[ "$_clean" == " "* || "$_clean" == ":"* ]]; do
                        _clean="${_clean#[: ]}"
                    done
                    local _val=""
                    if [[ "$_clean" == \"* ]]; then
                        _clean="${_clean#\"}"
                        _val="${_clean%%\"*}"
                        _clean="${_clean#*\"}"
                    elif [[ "$_clean" == "true"* || "$_clean" == "false"* || "$_clean" == "null"* ]]; then
                        _val="${_clean%%[,\}]*}"
                        _clean="${_clean#"$_val"}"
                    elif [[ "$_clean" == "["* ]]; then
                        _val="${_clean%%]*}]"
                        _clean="${_clean#*]}"
                        _val="${_val// /_}"
                    else
                        _val="${_clean%%[,\}]*}"
                        _clean="${_clean#"$_val"}"
                    fi
                    _val="${_val// /_}"
                    [[ -n "$_key" ]] && [[ -n "$_val" ]] && result+="payload.${_key} ${_val}"$'\n'
                else
                    break
                fi
            done
        fi
    done <<< "$text"

    echo "$result"
}
