#!/bin/bash
## Name: nfsstat
## Description: Extract NFS statistics from nfsstat output
## Version: 1.0
## Priority: 15
## Sample: samples/nfsstat/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Reject JSON
    _is_json "$1" && return 1
    # nfsstat markers
    if [[ "$text" == *"nfsstat"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Server rpc stats"* ]] || [[ "$text" == *"Client rpc stats"* ]]; then
        return 0
    fi
    if [[ "$text" == *"nfs v3"* ]] || [[ "$text" == *"nfs v4"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Server nfs"* ]] || [[ "$text" == *"Client nfs"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local section=""
    local role=""
    local nfs_version=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect role: Server or Client
        if [[ "$line" == *"Server"* ]]; then
            role="server"
        fi
        if [[ "$line" == *"Client"* ]]; then
            role="client"
        fi

        # Detect section
        if [[ "$line" == *"rpc stats"* ]]; then
            section="rpc"
            continue
        fi

        # Detect NFS version sections
        if [[ "$line" == *"nfs v3"* || "$line" == *"nfs V3"* || "$line" == *"NFS v3"* ]]; then
            section="nfs_ops"
            nfs_version="v3"
            result+="${role}.nfs_version v3"$'\n'
            continue
        fi
        if [[ "$line" == *"nfs v4"* || "$line" == *"nfs V4"* || "$line" == *"NFS v4"* ]]; then
            section="nfs_ops"
            nfs_version="v4"
            result+="${role}.nfs_version v4"$'\n'
            continue
        fi

        # Parse RPC stats
        # Format: "calls     badcalls   ..."
        #         "12345     67         ..."
        if [[ "$section" == "rpc" ]]; then
            if [[ "$line" == *"calls"* && "$line" == *"badcalls"* ]]; then
                # This is the header line; skip
                continue
            fi
            # Data line with numbers
            read -ra _arr <<< "$line"
            if [[ ${#_arr[@]} -ge 1 && "${_arr[0]}" =~ ^[0-9]+$ ]]; then
                result+="${role}.rpc_calls ${_arr[0]}"$'\n'
                if [[ ${#_arr[@]} -ge 2 ]]; then
                    result+="${role}.rpc_badcalls ${_arr[1]}"$'\n'
                fi
                section=""
            fi
            continue
        fi

        # Parse NFS per-operation stats
        # Format: "read    1234  56%"
        # or grouped: "null  getattr  setattr  lookup ..."
        #             "0  0%  1234  45%  567  12%  890  8% ..."
        if [[ "$section" == "nfs_ops" ]]; then
            # Skip separator lines
            [[ "$line" == "-"* ]] && continue

            # Try operation name with count and percentage on same line
            # e.g., "read         1234567   45%"
            if [[ "$line" =~ ^[[:space:]]*([a-zA-Z_]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)% ]]; then
                local op="${BASH_REMATCH[1]}"
                local count="${BASH_REMATCH[2]}"
                local pct="${BASH_REMATCH[3]}"
                op="${op,,}"
                result+="${role}.${nfs_version}.${op}_count ${count}"$'\n'
                result+="${role}.${nfs_version}.${op}_percent ${pct}"$'\n'
                continue
            fi

            # Paired header + data format:
            # Header line: "null  getattr  setattr  ..."
            # Data line:   "0  0%  1234  45%  ..."
            # Detect header lines (all words, no numbers)
            if [[ "$line" =~ ^[[:space:]]*[a-zA-Z] && ! "$line" =~ [0-9] ]]; then
                # Read op names
                read -ra _op_names <<< "$line"
                # Next line should be data
                IFS= read -r dataline
                if [[ -n "$dataline" ]]; then
                    read -ra _vals <<< "$dataline"
                    local _vi=0
                    local _oi
                    for _oi in "${!_op_names[@]}"; do
                        local op="${_op_names[$_oi]}"
                        op="${op,,}"
                        if [[ $_vi -lt ${#_vals[@]} ]]; then
                            local count="${_vals[$_vi]}"
                            result+="${role}.${nfs_version}.${op}_count ${count}"$'\n'
                            _vi=$((_vi + 1))
                            # Check for percentage
                            if [[ $_vi -lt ${#_vals[@]} && "${_vals[$_vi]}" == *"%" ]]; then
                                local pct="${_vals[$_vi]}"
                                pct="${pct//%/}"
                                result+="${role}.${nfs_version}.${op}_percent ${pct}"$'\n'
                                _vi=$((_vi + 1))
                            fi
                        fi
                    done
                fi
                continue
            fi
        fi

    done <<< "$text"

    echo "$result"
}
