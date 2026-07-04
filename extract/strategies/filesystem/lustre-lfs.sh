#!/bin/bash
## Name: lustre-lfs
## Description: Extract Lustre filesystem information from lfs commands
## Version: 1.0
## Priority: 15
## Sample: samples/lustre-lfs/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Reject JSON
    _is_json "$1" && return 1
    # Lustre lfs df output contains OST/MDT targets
    if [[ "$text" == *"lustre"* ]] || [[ "$text" == *"Lustre"* ]]; then
        return 0
    fi
    if [[ "$text" == *"OST"* && "$text" == *"MDT"* ]]; then
        return 0
    fi
    if [[ "$text" == *"stripe_count"* ]] || [[ "$text" == *"l_ost_idx"* ]]; then
        return 0
    fi
    if [[ "$text" == *"lfs "* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local target_num=0
    local quota_num=0
    local mode=""

    # Detect which lfs sub-command output we have
    if [[ "$text" == *"stripe_count"* || "$text" == *"lmm_stripe"* ]]; then
        mode="getstripe"
    elif [[ "$text" == *"Filesystem"* && "$text" == *"kbytes"* ]]; then
        mode="df"
    elif [[ "$text" == *"quota"* || "$text" == *"Filesystem"* && "$text" == *"files"* && "$text" == *"limit"* ]]; then
        mode="quota"
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # --- lfs df parsing ---
        if [[ "$mode" == "df" ]]; then
            # Skip header line
            [[ "$line" == *"Filesystem"* && "$line" == *"kbytes"* ]] && continue
            # Lines: filesystem_target  kbytes  used  available  use%  mount
            # e.g.: scratch-OST0000_UUID  1234567  456789  777778  37%  /scratch[OST:0]
            if [[ "$line" == *"OST"* || "$line" == *"MDT"* || "$line" == *"_UUID"* ]]; then
                target_num=$((target_num + 1))
                read -ra _arr <<< "$line"
                local fs_target="${_arr[0]}"
                local used_kb="${_arr[2]}"
                local avail_kb="${_arr[3]}"
                local use_pct="${_arr[4]}"
                use_pct="${use_pct//%/}"
                [[ -n "$fs_target" ]] && result+="target${target_num}.filesystem ${fs_target}"$'\n'
                [[ -n "$used_kb" ]] && result+="target${target_num}.used_KB ${used_kb}"$'\n'
                [[ -n "$avail_kb" ]] && result+="target${target_num}.available_KB ${avail_kb}"$'\n'
                [[ -n "$use_pct" ]] && result+="target${target_num}.use_percent ${use_pct}"$'\n'
            fi
            # Summary line
            if [[ "$line" == *"filesystem_summary"* || "$line" == *"filesystem summary"* ]]; then
                read -ra _arr <<< "$line"
                result+="summary.used_KB ${_arr[2]}"$'\n'
                result+="summary.available_KB ${_arr[3]}"$'\n'
            fi
            continue
        fi

        # --- lfs getstripe parsing ---
        if [[ "$mode" == "getstripe" ]]; then
            if [[ "$line" == *"stripe_count:"* || "$line" == *"lmm_stripe_count:"* ]]; then
                local val="${line##*: }"
                val="${val## }"
                result+="stripe_count ${val}"$'\n'
            fi
            if [[ "$line" == *"stripe_size:"* || "$line" == *"lmm_stripe_size:"* ]]; then
                local val="${line##*: }"
                val="${val## }"
                result+="stripe_size ${val}"$'\n'
            fi
            if [[ "$line" == *"stripe_offset:"* || "$line" == *"lmm_stripe_offset:"* ]]; then
                local val="${line##*: }"
                val="${val## }"
                result+="stripe_offset ${val}"$'\n'
            fi
            if [[ "$line" == *"pool:"* || "$line" == *"lmm_pool:"* ]]; then
                local val="${line##*: }"
                val="${val## }"
                [[ -n "$val" ]] && result+="pool ${val}"$'\n'
            fi
            if [[ "$line" == *"l_ost_idx:"* ]]; then
                target_num=$((target_num + 1))
                local val="${line##*l_ost_idx: }"
                val="${val%%,*}"
                val="${val## }"
                result+="object${target_num}.l_ost_idx ${val}"$'\n'
            fi
            continue
        fi

        # --- lfs quota parsing ---
        # Quota lines: uid/gid  space_used  space_softlimit  space_hardlimit  files_used  files_softlimit  files_hardlimit
        if [[ "$mode" == "quota" ]]; then
            # Skip header/separator lines
            [[ "$line" == *"Filesystem"* ]] && continue
            [[ "$line" == "-"* ]] && continue
            # Detect uid/gid lines (start with a path or quota entry)
            if [[ "$line" == "/"* || "$line" =~ ^[[:space:]]*[0-9] ]]; then
                quota_num=$((quota_num + 1))
                read -ra _arr <<< "$line"
                local qfs="${_arr[0]}"
                local space_used="${_arr[1]}"
                local space_limit="${_arr[2]}"
                local files_used="${_arr[4]}"
                local files_limit="${_arr[5]}"
                [[ -n "$qfs" ]] && result+="quota${quota_num}.filesystem ${qfs}"$'\n'
                [[ -n "$space_used" ]] && result+="quota${quota_num}.space_used ${space_used}"$'\n'
                [[ -n "$space_limit" ]] && result+="quota${quota_num}.space_limit ${space_limit}"$'\n'
                [[ -n "$files_used" ]] && result+="quota${quota_num}.files_used ${files_used}"$'\n'
                [[ -n "$files_limit" ]] && result+="quota${quota_num}.files_limit ${files_limit}"$'\n'
            fi
            continue
        fi

    done <<< "$text"

    echo "$result"
}
