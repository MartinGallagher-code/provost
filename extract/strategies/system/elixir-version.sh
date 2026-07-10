#!/bin/bash
## Name: elixir-version
## Description: Extract version fields from `elixir --version` banner
## Version: 1.0
## Priority: 20
## Sample: samples/elixir-version/basic.txt

# `elixir --version` prints an Erlang/OTP line ("Erlang/OTP 26 [erts-14.1.1] ...")
# and an Elixir line ("Elixir 1.16.0 (compiled with Erlang/OTP 26)"). One wide
# key/value record: product, version, erlang_otp, erts.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    if [[ "$text" == *"Elixir "* && "$text" == *"Erlang/OTP"* ]]; then
        _STRATEGY_CONFIDENCE=86
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" ver="" otp="" erts=""
    if [[ "$text" =~ Elixir[[:space:]]+([0-9][0-9A-Za-z.+-]*) ]]; then
        ver="${BASH_REMATCH[1]}"
    fi
    if [[ "$text" =~ Erlang/OTP[[:space:]]+([0-9][0-9A-Za-z.+-]*) ]]; then
        otp="${BASH_REMATCH[1]}"
    fi
    if [[ "$text" =~ erts-([0-9][0-9A-Za-z.+-]*) ]]; then
        erts="${BASH_REMATCH[1]}"
    fi
    result+="entry1.product Elixir"$'\n'
    result+="entry1.version ${ver}"$'\n'
    result+="entry1.erlang_otp ${otp}"$'\n'
    result+="entry1.erts ${erts}"$'\n'
    result+="total_entries 1"$'\n'
    echo "$result"
}
