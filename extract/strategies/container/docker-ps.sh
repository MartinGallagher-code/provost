#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: docker-ps
## Description: Extract container information from docker ps output
## Version: 1.0
## Priority: 12
## Commands: podman nerdctl
## Sample: samples/docker-ps/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=92
    # First non-empty line is the `docker ps` header: starts with CONTAINER and
    # carries the ps-specific COMMAND column. Requiring COMMAND avoids hijacking
    # `docker stats` (CONTAINER … CPU %/MEM …) and `buildah containers`
    # (CONTAINER … BUILDER/IMAGE ID …) — those have no COMMAND column and are
    # tidied fine by the generic aligned-columns parser.
    local first_line=""
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"
        break
    done
    [[ "$first_line" == "CONTAINER"* && "$first_line" == *"COMMAND"* ]]
}

strategy_extract () {
    local text="$1"
    local result=""

    # Get the header line to find column positions
    local header_line=""
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ -z "$_line" ]] && continue
        header_line="$_line"
        break
    done

    # Find column start positions from the header
    # Docker ps uses fixed-width columns aligned by header words
    local col_names=()
    local col_starts=()

    _strat_docker_ps_parse_columns "$header_line"

    # Process each data row
    local row_num=0
    local line_num=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        line_num=$((line_num + 1))
        [[ $line_num -eq 1 ]] && continue  # skip header
        [[ -z "$line" ]] && continue

        row_num=$((row_num + 1))
        local prefix="container${row_num}"

        local i
        for ((i=0; i<${#col_names[@]}; i++)); do
            local col_name="${col_names[$i]}"
            local start="${col_starts[$i]}"
            local end=""
            if [[ $((i + 1)) -lt ${#col_names[@]} ]]; then
                end="${col_starts[$((i + 1))]}"
            fi

            local val
            if [[ -n "$end" ]]; then
                local _len=$((end - start))
                val="${line:$((start - 1)):$_len}"
            else
                val="${line:$((start - 1))}"
            fi

            # Trim leading/trailing whitespace
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done
            [[ -z "$val" ]] && continue

            # Normalize column name
            col_name=$(_strat_docker_ps_normalize_col "$col_name")
            result+="${prefix}.${col_name} ${val}"$'\n'
        done
    done

    echo "$result"
}

_strat_docker_ps_parse_columns () {
    local header="$1"
    col_names=()
    col_starts=()

    # Known docker ps column headers (multi-word headers)
    # "CONTAINER ID" is a two-word header
    local remaining="$header"
    local pos=1

    # Find each header's position
    local offset=0
    while [[ -n "$remaining" ]]; do
        # Skip leading spaces
        local stripped="$remaining"
        while [[ "$stripped" == " "* ]]; do stripped="${stripped# }"; done
        local spaces_skipped=$(( ${#remaining} - ${#stripped} ))
        offset=$((offset + spaces_skipped))
        remaining="$stripped"

        [[ -z "$remaining" ]] && break

        # Try to match a known two-word header first
        local matched=0
        if [[ "$remaining" == "CONTAINER ID"* ]]; then
            col_names+=("CONTAINER_ID")
            col_starts+=($((offset + 1)))
            local hdr="CONTAINER ID"
            remaining="${remaining#$hdr}"
            offset=$((offset + ${#hdr}))
            matched=1
        fi

        if [[ $matched -eq 0 ]]; then
            # Single-word header
            { _fr_tok "$remaining"; _arr=("${_FR_TOK[@]}"); }
            local word="${_arr[0]}"
            [[ -z "$word" ]] && break
            col_names+=("$word")
            col_starts+=($((offset + 1)))
            remaining="${remaining#$word}"
            offset=$((offset + ${#word}))
        fi
    done
}

_strat_docker_ps_normalize_col () {
    local col="$1"
    # Replace spaces with underscores
    col="${col// /_}"
    # Lowercase manually
    local _result=""
    local _i
    for ((_i=0; _i<${#col}; _i++)); do
        local _c="${col:$_i:1}"
        case "$_c" in
            A) _c=a ;; B) _c=b ;; C) _c=c ;; D) _c=d ;; E) _c=e ;;
            F) _c=f ;; G) _c=g ;; H) _c=h ;; I) _c=i ;; J) _c=j ;;
            K) _c=k ;; L) _c=l ;; M) _c=m ;; N) _c=n ;; O) _c=o ;;
            P) _c=p ;; Q) _c=q ;; R) _c=r ;; S) _c=s ;; T) _c=t ;;
            U) _c=u ;; V) _c=v ;; W) _c=w ;; X) _c=x ;; Y) _c=y ;;
            Z) _c=z ;;
        esac
        _result+="$_c"
    done
    echo "$_result"
}
