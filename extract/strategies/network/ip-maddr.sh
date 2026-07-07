#!/bin/bash
## Name: ip-maddr
## Description: Extract multicast addresses from `ip maddr show` interface blocks
## Version: 1.0
## Priority: 12
## Technique: yes
## Sample: samples/ip-maddr/basic.txt

# `ip maddr` groups multicast addresses under interface blocks:
#   1:      lo
#           inet  224.0.0.251
#           inet6 ff02::1
#           link  33:33:00:00:00:01
# The header line is `<index>:<TAB><iface>` (iface only, no family token); each
# indented line is `<family> <address>` with family in {inet,inet6,link}. Emit
# one record per address line, carrying its interface, so the tidy melt renders
# one row per multicast address.

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    _is_json "$text" && return 1

    # Signature: an interface header `<num>:<ws><name>` (exactly two tokens, the
    # second NOT a family keyword) AND an indented `<family> <address>` line whose
    # first token is inet/inet6/link with exactly two whitespace-separated tokens.
    local has_header=0 has_addr=0 line t
    while IFS= read -r line; do
        t="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$t" ]] && continue
        read -ra _f <<< "$t"
        case "$t" in
            [0-9]*:*)
                if [[ ${#_f[@]} -eq 2 ]]; then
                    case "${_f[1]}" in
                        inet|inet6|link) ;;
                        *) has_header=1 ;;
                    esac
                fi
                ;;
        esac
        if [[ ${#_f[@]} -eq 2 ]]; then
            case "${_f[0]}" in
                inet|inet6|link) has_addr=1 ;;
            esac
        fi
    done <<< "$text"
    [[ $has_header -eq 1 && $has_addr -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line t n=0 iface=""

    while IFS= read -r line; do
        t="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$t" ]] && continue
        read -ra _f <<< "$t"

        # Interface header: `<num>:<ws><iface>`
        case "$t" in
            [0-9]*:*)
                if [[ ${#_f[@]} -eq 2 ]]; then
                    case "${_f[1]}" in
                        inet|inet6|link) ;;
                        *) iface="${_f[1]}"; continue ;;
                    esac
                fi
                ;;
        esac

        # Address line: `<family> <address>`
        case "${_f[0]}" in
            inet|inet6|link) ;;
            *) continue ;;
        esac
        [[ ${#_f[@]} -ge 2 ]] || continue

        n=$((n + 1))
        result+="entry${n}.iface ${iface:-unknown}"$'\n'
        result+="entry${n}.family ${_f[0]}"$'\n'
        result+="entry${n}.address ${_f[1]}"$'\n'
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
