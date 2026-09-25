#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: nft-list-ruleset
## Description: Extract firewall rules from `nft list ruleset` nested table/chain output
## Version: 1.0
## Priority: 26
## Sample: samples/nft-list-ruleset/basic.txt

# `nft list ruleset` prints nested brace blocks:
#   table inet filter {
#       chain input {
#           type filter hook input priority filter; policy drop;
#           tcp dport 22 accept
#           ...
#       }
#   }
# Emit one record per actual RULE line — the indented statements inside a chain,
# excluding the table/chain headers, the `type ... hook ... policy` declaration,
# and the closing braces. capture's tidy melt renders one row per rule.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    _is_json "$text" && return 1

    # Distinctive signature: a `table <family> <name> {` opener AND a
    # `chain <name> {` opener AND an nft `type ... hook ...` line.
    local has_table=0 has_chain=0 has_hook=0 line t
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        t="${line#"${line%%[![:space:]]*}"}"      # strip leading whitespace
        case "$t" in
            "table "*"{"*) has_table=1 ;;
            "chain "*"{"*) has_chain=1 ;;
            "type "*" hook "*) has_hook=1 ;;
        esac
    done
    [[ $has_table -eq 1 && $has_chain -eq 1 && $has_hook -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line t n=0
    local in_chain=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        t="${line#"${line%%[![:space:]]*}"}"      # strip leading whitespace
        [[ -z "$t" ]] && continue

        case "$t" in
            "table "*) continue ;;
            "chain "*"{"*) in_chain=1; continue ;;
            "type "*" hook "*) continue ;;         # chain type/hook/policy decl
            "}"*)  in_chain=0; continue ;;
            "{"*)  continue ;;
        esac
        [[ $in_chain -eq 1 ]] || continue

        # Whatever remains inside a chain block is a rule statement.
        n=$((n + 1))
        result+="entry${n}.rule ${t}"$'\n'
    done

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
