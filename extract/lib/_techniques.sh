#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Shared extraction technique functions for provost-extract
##
## Pure-bash utility functions used by generic (technique-tagged) strategies.
## Requires bash 4.0+.
##
## Globals set (no subshell forks):
##   _TECH_STRIPPED   result of _tech_strip_leading
##   _TECH_KEY_VALID  result of _tech_validate_key (0=invalid, 1=valid)
##   _TECH_BLOCKS     result of _tech_split_blocks (null-delimited blocks)
##
## Dependencies: _helpers.sh (_clean_field / _clean_value -> $_CLEANED)
################################################################################

# Strip leading spaces and optional "* " bullet prefix from a string.
# Result stored in $_TECH_STRIPPED (no subshell fork).
_tech_strip_leading () {
    _TECH_STRIPPED="$1"
    while [[ "$_TECH_STRIPPED" == " "* ]]; do
        _TECH_STRIPPED="${_TECH_STRIPPED# }"
    done
    case "$_TECH_STRIPPED" in
        "* "*) _TECH_STRIPPED="${_TECH_STRIPPED#\* }" ;;
    esac
}

# Validate a field key. Sets $_TECH_KEY_VALID=1 if valid, 0 if not.
# Rules: non-empty, length <= 50, does not start with a digit.
_tech_validate_key () {
    _TECH_KEY_VALID=0
    [[ -z "$1" ]] && return
    [[ ${#1} -gt 50 ]] && return
    case "$1" in
        [0-9]*) return ;;
    esac
    _TECH_KEY_VALID=1
}

# Extract key: value pairs from text (colon-delimited).
# Emits "field value" lines to stdout.
# Usage: _tech_kv_colon "$text" "$prefix"
#   $prefix: dot-prefix for output keys (e.g. "record1" -> "record1.key value")
#            pass "" for no prefix.
# Skips: empty lines, keys >50 chars, digit-start keys, and a bare URL LINE
# (`https://host/x` splits at the scheme colon into key `https`, value `//…` —
# a value starting `//`). A labelled URL (`Homepage: https://brew.sh`) is kept.
_tech_kv_colon () {
    local _tkc_text="$1"
    local _tkc_prefix="$2"
    local _tkc_line _tkc_key _tkc_value
    while IFS= read -r _tkc_line; do
        [[ -z "$_tkc_line" ]] && continue
        [[ "$_tkc_line" != *":"* ]] && continue
        # A line whose ` = ` sits BEFORE its first colon is an equals pair
        # whose VALUE happens to contain colons (npm's `noproxy =
        # ["…,::1,…]`) — splitting it here manufactured a garbage key out of
        # half the value. The equals pass owns it.
        if [[ "$_tkc_line" == *" = "* ]]; then
            local _tkc_eq="${_tkc_line%% = *}"
            [[ "$_tkc_eq" != *":"* ]] && continue
        fi
        _tech_strip_leading "$_tkc_line"
        _tkc_line="$_TECH_STRIPPED"
        _tkc_key="${_tkc_line%%:*}"
        _tkc_value="${_tkc_line#*: }"
        # If no space after colon, take everything after the colon
        if [[ "$_tkc_value" == "$_tkc_line" ]]; then
            _tkc_value="${_tkc_line#*:}"
        fi
        _tech_validate_key "$_tkc_key"
        [[ $_TECH_KEY_VALID -eq 0 ]] && continue
        # Skip a bare URL line: split at its scheme colon the value starts
        # with `//`. A value that IS a URL (`Homepage: https://…`) is data.
        [[ "$_tkc_value" == "//"* ]] && continue
        _clean_field "$_tkc_key";   _tkc_key="$_CLEANED"
        _clean_value "$_tkc_value"; _tkc_value="$_CLEANED"
        [[ -z "$_tkc_key" || -z "$_tkc_value" ]] && continue
        if [[ -n "$_tkc_prefix" ]]; then
            echo "${_tkc_prefix}.${_tkc_key} ${_tkc_value}"
        else
            echo "${_tkc_key} ${_tkc_value}"
        fi
    done <<< "$_tkc_text"
}

# Extract key=value pairs from text (equals-delimited).
# Emits "field value" lines to stdout.
# Usage: _tech_kv_equals "$text" "$prefix"
# Skips: ==, +=, != comparisons; empty/invalid keys.
_tech_kv_equals () {
    local _tke_text="$1"
    local _tke_prefix="$2"
    local _tke_line _tke_key _tke_value
    while IFS= read -r _tke_line; do
        [[ -z "$_tke_line" ]] && continue
        [[ "$_tke_line" != *"="* ]] && continue
        # Skip comparison operators
        [[ "$_tke_line" == *"=="* || "$_tke_line" == *"+="* || "$_tke_line" == *"!="* ]] && continue
        _tech_strip_leading "$_tke_line"
        _tke_line="$_TECH_STRIPPED"
        _tke_key="${_tke_line%%=*}"
        _tke_value="${_tke_line#*=}"
        _tech_validate_key "$_tke_key"
        [[ $_TECH_KEY_VALID -eq 0 ]] && continue
        _clean_field "$_tke_key";   _tke_key="$_CLEANED"
        _clean_value "$_tke_value"; _tke_value="$_CLEANED"
        [[ -z "$_tke_key" || -z "$_tke_value" ]] && continue
        if [[ -n "$_tke_prefix" ]]; then
            echo "${_tke_prefix}.${_tke_key} ${_tke_value}"
        else
            echo "${_tke_key} ${_tke_value}"
        fi
    done <<< "$_tke_text"
}

# Split text into blank-line-separated blocks.
# Result stored in $_TECH_BLOCKS as SOH ($'\x01') delimited segments.
# SOH (ASCII 0x01) is used instead of null to be safe in bash string variables.
# Callers iterate blocks:
#   local _remaining="$_TECH_BLOCKS"
#   while [[ -n "$_remaining" ]]; do
#       local _block="${_remaining%%$'\x01'*}"
#       [[ "$_remaining" == *$'\x01'* ]] && _remaining="${_remaining#*$'\x01'}" || _remaining=""
#       # process $_block
#   done
_tech_split_blocks () {
    _TECH_BLOCKS=""
    local _tsb_current="" _tsb_line
    while IFS= read -r _tsb_line; do
        if [[ -z "$_tsb_line" ]]; then
            if [[ -n "$_tsb_current" ]]; then
                if [[ -n "$_TECH_BLOCKS" ]]; then
                    _TECH_BLOCKS+=$'\x01'"$_tsb_current"
                else
                    _TECH_BLOCKS="$_tsb_current"
                fi
                _tsb_current=""
            fi
        else
            if [[ -n "$_tsb_current" ]]; then
                _tsb_current+=$'\n'"$_tsb_line"
            else
                _tsb_current="$_tsb_line"
            fi
        fi
    done <<< "$1"
    # Flush final block (no trailing blank line)
    if [[ -n "$_tsb_current" ]]; then
        if [[ -n "$_TECH_BLOCKS" ]]; then
            _TECH_BLOCKS+=$'\x01'"$_tsb_current"
        else
            _TECH_BLOCKS="$_tsb_current"
        fi
    fi
}
