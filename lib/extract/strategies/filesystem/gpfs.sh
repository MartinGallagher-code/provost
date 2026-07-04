#!/bin/bash
## Name: gpfs
## Description: Extract GPFS/Spectrum Scale filesystem info from mmlsfs and mmdf output
## Version: 1.0
## Priority: 15
## Sample: samples/gpfs/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Reject JSON
    _is_json "$1" && return 1
    # GPFS / Spectrum Scale markers
    if [[ "$text" == *"GPFS"* ]] || [[ "$text" == *"gpfs"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Spectrum Scale"* ]]; then
        return 0
    fi
    if [[ "$text" == *"mmlsfs"* ]] || [[ "$text" == *"mmdf"* ]]; then
        return 0
    fi
    if [[ "$text" == *"block size"* && "$text" == *"inode-size"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local mode=""

    # Detect mmlsfs vs mmdf
    if [[ "$text" == *"mmlsfs"* ]] || [[ "$text" == *"-f "* && "$text" == *"block size"* ]]; then
        mode="mmlsfs"
    fi
    if [[ "$text" == *"mmdf"* ]] || [[ "$text" == *"disk size"* && "$text" == *"free space"* ]]; then
        mode="mmdf"
    fi

    local disk_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # --- mmlsfs parsing ---
        # mmlsfs output format: "attribute  value" or "flag  value  description"
        if [[ "$mode" == "mmlsfs" ]]; then
            # Lines like: "-B 4194304 Block size"
            if [[ "$line" == *"lock size"* || "$line" == *"-B "* ]]; then
                read -ra _arr <<< "$line"
                local val="${_arr[1]}"
                [[ -n "$val" ]] && result+="block_size ${val}"$'\n'
                continue
            fi
            if [[ "$line" == *"inode-size"* || "$line" == *"-i "* && "$line" == *"ode"* ]]; then
                read -ra _arr <<< "$line"
                local val="${_arr[1]}"
                [[ -n "$val" ]] && result+="inode_size ${val}"$'\n'
                continue
            fi
            if [[ "$line" == *"mount point"* || "$line" == *"-T "* ]]; then
                read -ra _arr <<< "$line"
                local val="${_arr[1]}"
                [[ -n "$val" ]] && result+="mount_point ${val}"$'\n'
                continue
            fi
            if [[ "$line" == *"inum-limit"* || "$line" == *"-n "* ]]; then
                read -ra _arr <<< "$line"
                local val="${_arr[1]}"
                [[ -n "$val" ]] && result+="inum_limit ${val}"$'\n'
                continue
            fi
            if [[ "$line" == *"max-files"* || "$line" == *"-L "* ]]; then
                read -ra _arr <<< "$line"
                local val="${_arr[1]}"
                [[ -n "$val" ]] && result+="max_files ${val}"$'\n'
                continue
            fi
            if [[ "$line" == *"replication"* || "$line" == *"-r "* && "$line" == *"epl"* ]]; then
                read -ra _arr <<< "$line"
                local val="${_arr[1]}"
                [[ -n "$val" ]] && result+="replication ${val}"$'\n'
                continue
            fi
            # Generic "flag value description" lines starting with -
            if [[ "$line" == " -"* || "$line" == "-"* ]]; then
                read -ra _arr <<< "$line"
                local flag="${_arr[0]}"
                local val="${_arr[1]}"
                flag="${flag//-/}"
                if [[ -n "$flag" && -n "$val" ]]; then
                    result+="attr_${flag} ${val}"$'\n'
                fi
            fi
            continue
        fi

        # --- mmdf parsing ---
        if [[ "$mode" == "mmdf" ]]; then
            # Disk line: "nsd_name  disk size  failure group  ..."
            if [[ "$line" == *"disk size"* ]]; then
                # This is a header; skip
                continue
            fi
            if [[ "$line" == *"free space"* ]]; then
                # "free space:  12345 KB" or similar
                local val="${line##*:}"
                val="${val## }"
                val="${val%% *}"
                [[ -n "$val" ]] && result+="free_space ${val}"$'\n'
                continue
            fi
            if [[ "$line" == *"free fragments"* ]]; then
                local val="${line##*:}"
                val="${val## }"
                val="${val%% *}"
                [[ -n "$val" ]] && result+="free_fragments ${val}"$'\n'
                continue
            fi
            # Disk entries: nsd_name  size  ...
            if [[ "$line" =~ ^[[:space:]]*nsd || "$line" =~ ^[[:space:]]*[a-zA-Z]+[0-9] ]]; then
                read -ra _arr <<< "$line"
                if [[ ${#_arr[@]} -ge 2 ]]; then
                    disk_num=$((disk_num + 1))
                    result+="disk${disk_num}.name ${_arr[0]}"$'\n'
                    result+="disk${disk_num}.size ${_arr[1]}"$'\n'
                fi
                continue
            fi
            if [[ "$line" == *"inode"* ]]; then
                if [[ "$line" == *"used"* ]]; then
                    local val="${line##*:}"
                    val="${val## }"
                    val="${val%% *}"
                    [[ -n "$val" ]] && result+="inode_used ${val}"$'\n'
                fi
                if [[ "$line" == *"free"* ]]; then
                    local val="${line##*:}"
                    val="${val## }"
                    val="${val%% *}"
                    [[ -n "$val" ]] && result+="inode_free ${val}"$'\n'
                fi
                continue
            fi
            # Total disk size line
            if [[ "$line" == *"disk"* && "$line" == *"size"* && "$line" == *":"* ]]; then
                local val="${line##*:}"
                val="${val## }"
                val="${val%% *}"
                [[ -n "$val" ]] && result+="disk_size ${val}"$'\n'
                continue
            fi
        fi

    done <<< "$text"

    echo "$result"
}
