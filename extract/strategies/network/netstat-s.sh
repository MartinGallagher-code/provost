#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: netstat-s
## Description: Extract per-protocol counters from `netstat -s` grouped statistics
## Version: 1.0
## Priority: 26
## Sample: samples/netstat-s/basic.txt

# `netstat -s` groups counters under protocol headers:
#   Ip:
#       Forwarding: 1
#       18274655 total packets received
#   Tcp:
#       9382 active connection openings
# Emit ONE record whose fields are the individual stats: each stat becomes a
# field named `<proto>_<sanitised description>` with the numeric count as value.
# capture's tidy melt renders this as a single wide key/value row.

# Sanitise a free-text description into a field-name fragment: lowercase,
# non-alphanumeric runs collapse to a single underscore, trim leading/trailing.
_netstat_s_slug () {
    printf '%s' "$1" | awk '{
        s=tolower($0); r=""; prev=0
        for(i=1;i<=length(s);i++){
            c=substr(s,i,1)
            if(c ~ /[a-z0-9]/){ r=r c; prev=0 }
            else if(prev==0){ r=r "_"; prev=1 }
        }
        gsub(/^_+/,"",r); gsub(/_+$/,"",r); print r
    }'
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    _is_json "$text" && return 1

    # Signature: a bare protocol group header (`Ip:`, `Tcp:`, ...) at column 0
    # AND an indented `<number> <description>` counter line under it.
    local has_group=0 has_counter=0 line t
    while IFS= read -r line; do
        case "$line" in
            # Only genuine netstat -s protocol groups — not any "word:" line (which
            # would wrongly grab `apt-cache policy`'s "curl:" package header).
            Ip:|Icmp:|IcmpMsg:|Tcp:|Udp:|UdpLite:|TcpExt:|IpExt:) has_group=1 ;;
        esac
        t="${line#"${line%%[![:space:]]*}"}"
        [[ "$line" == "$t" ]] && continue              # counter lines are indented
        case "$t" in
            [0-9]*" "*) has_counter=1 ;;
        esac
    done <<< "$text"
    [[ $has_group -eq 1 && $has_counter -eq 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line t proto="" field val
    local count=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Protocol group header: unindented `<Name>:` with no value.
        case "$line" in
            [A-Za-z]*:)
                # unindented and ends in ':' with nothing after -> group header
                if [[ "${line:0:1}" != " " && "${line:0:1}" != $'\t' ]]; then
                    proto=$(_netstat_s_slug "${line%:}")
                    continue
                fi
                ;;
        esac

        # Only indented lines are counters.
        t="${line#"${line%%[![:space:]]*}"}"
        [[ "$line" == "$t" ]] && continue
        [[ -z "$proto" ]] && continue

        field=""; val=""
        case "$t" in
            [0-9]*" "*)
                # "<number> <description>"
                val="${t%% *}"
                field=$(_netstat_s_slug "${t#* }")
                ;;
            *": "*)
                # "<key>: <value>" — keep only when value is a bare number
                local k="${t%%:*}" v="${t#*: }"
                case "$v" in
                    ""|*[!0-9]*) continue ;;           # non-numeric -> skip sub-headers
                    *) val="$v"; field=$(_netstat_s_slug "$k") ;;
                esac
                ;;
            *) continue ;;
        esac

        [[ -z "$field" || -z "$val" ]] && continue
        count=$((count + 1))
        result+="entry1.${proto:+${proto}_}${field} ${val}"$'\n'
    done <<< "$text"

    [[ $count -gt 0 ]] && result+="total_entries 1"$'\n'
    echo "$result"
}
