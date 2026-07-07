#!/bin/bash
## Name: bridge-fdb
## Description: Extract MAC forwarding entries from `bridge fdb show` output
## Version: 1.0
## Priority: 26
## Technique: yes
## Sample: samples/bridge-fdb/basic.txt

# `bridge fdb` prints one forwarding-database entry per line:
#   33:33:00:00:00:01 dev eth0 self permanent
#   aa:bb:cc:dd:ee:01 dev eth0 vlan 10 master br0
# Each line is `<mac> dev <iface> [vlan <id>] [master <br>|self] [flags...]`.
# Split into columns (mac, dev, vlan, master, flags) so the tidy melt renders a
# multi-column row per entry.

# A MAC address token: six colon-separated hex pairs.
_bridge_fdb_is_mac () {
    case "$1" in
        [0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]:[0-9a-fA-F][0-9a-fA-F]) return 0 ;;
        *) return 1 ;;
    esac
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=86
    _is_json "$text" && return 1

    # Signature: at least one line whose first token is a MAC address and which
    # contains a " dev " interface clause.
    local hits=0 line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == *" dev "* ]] || continue
        read -ra _f <<< "$line"
        _bridge_fdb_is_mac "${_f[0]}" && hits=$((hits + 1))
    done <<< "$text"
    [[ $hits -ge 1 ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" line n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        read -ra _f <<< "$line"
        _bridge_fdb_is_mac "${_f[0]}" || continue

        local mac="${_f[0]}" dev="" vlan="" master="" flags=""
        local i=1 tok
        while [[ $i -lt ${#_f[@]} ]]; do
            tok="${_f[$i]}"
            case "$tok" in
                dev)    dev="${_f[$((i+1))]}"; i=$((i+2)) ;;
                vlan)   vlan="${_f[$((i+1))]}"; i=$((i+2)) ;;
                master) master="${_f[$((i+1))]}"; i=$((i+2)) ;;
                self)   master="self"; i=$((i+1)) ;;
                *)      flags="${flags:+${flags}_}${tok}"; i=$((i+1)) ;;
            esac
        done

        n=$((n + 1))
        result+="entry${n}.mac ${mac}"$'\n'
        result+="entry${n}.dev ${dev:-NONE}"$'\n'
        result+="entry${n}.vlan ${vlan:-NONE}"$'\n'
        result+="entry${n}.master ${master:-NONE}"$'\n'
        result+="entry${n}.flags ${flags:-NONE}"$'\n'
    done <<< "$text"

    [[ $n -gt 0 ]] && result+="total_entries ${n}"$'\n'
    echo "$result"
}
