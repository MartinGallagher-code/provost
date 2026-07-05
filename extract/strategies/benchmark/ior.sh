#!/bin/bash
## Name: ior
## Description: Extract IOR and mdtest parallel filesystem benchmark results
## Version: 1.0
## Priority: 10
## Sample: samples/ior/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    if [[ "$text" == *"IOR-"* ]]; then
        return 0
    fi
    if [[ "$text" == *"mdtest-"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Max Write:"* ]] || [[ "$text" == *"Max Read:"* ]]; then
        _STRATEGY_CONFIDENCE=85
        return 0
    fi
    if [[ "$text" == *"Operation"* ]] && [[ "$text" == *"Max(MiB)"* ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local is_mdtest=0

    if [[ "$text" == *"mdtest-"* ]] || [[ "$text" == *"mdtest "* ]]; then
        is_mdtest=1
    fi

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # IOR version: "IOR-3.3.0"
        if [[ "$line" == *"IOR-"* ]]; then
            local _ver="${line##*IOR-}"
            read -ra _arr <<< "$_ver"
            result+="ior_version ${_arr[0]}"$'\n'
            continue
        fi

        # mdtest version: "mdtest-3.3.0"
        if [[ "$line" == *"mdtest-"* ]]; then
            local _ver="${line##*mdtest-}"
            read -ra _arr <<< "$_ver"
            result+="mdtest_version ${_arr[0]}"$'\n'
            continue
        fi

        # Number of tasks: "Num Tasks: 4" or "tasks = 4"
        if [[ "$line" == *"tasks"*":"* ]] || [[ "$line" == *"Tasks"*":"* ]]; then
            local _val="${line##*:}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="num_tasks ${_arr[0]}"$'\n'
            continue
        fi

        # File size: "xfersize = 1 MiB" or "blocksize = 1 MiB"
        if [[ "$line" == *"aggregate filesize"* ]]; then
            local _val="${line##*= }"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            _val="${_val// /_}"
            [[ -n "$_val" ]] && result+="aggregate_size ${_val}"$'\n'
            continue
        fi
        if [[ "$line" == *"xfersize"*"="* ]]; then
            local _val="${line##*= }"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            _val="${_val// /_}"
            [[ -n "$_val" ]] && result+="xfer_size ${_val}"$'\n'
            continue
        fi
        if [[ "$line" == *"blocksize"*"="* ]] || [[ "$line" == *"blockSize"*"="* ]]; then
            local _val="${line##*= }"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            _val="${_val// /_}"
            [[ -n "$_val" ]] && result+="block_size ${_val}"$'\n'
            continue
        fi

        # IOR Summary lines: "Max Write: 1234.56 MiB/sec"
        if [[ "$line" == *"Max Write:"* ]]; then
            local _val="${line##*Max Write:}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="max_write_MiB ${_arr[0]}"$'\n'
            continue
        fi
        if [[ "$line" == *"Max Read:"* ]]; then
            local _val="${line##*Max Read:}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="max_read_MiB ${_arr[0]}"$'\n'
            continue
        fi
        if [[ "$line" == *"Mean Write:"* ]]; then
            local _val="${line##*Mean Write:}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="mean_write_MiB ${_arr[0]}"$'\n'
            continue
        fi
        if [[ "$line" == *"Mean Read:"* ]]; then
            local _val="${line##*Mean Read:}"
            while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
            read -ra _arr <<< "$_val"
            [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="mean_read_MiB ${_arr[0]}"$'\n'
            continue
        fi

        # IOR table rows: "write  1234.56  1200.00  1234.56  1234.56  1  ..."
        if [[ "$line" == "write "* ]] || [[ "$line" == "read "* ]]; then
            read -ra _arr <<< "$line"
            local op="${_arr[0]}"
            [[ "${_arr[1]}" =~ ^[0-9] ]] || continue
            result+="${op}.max_MiB ${_arr[1]}"$'\n'
            [[ -n "${_arr[2]}" ]] && result+="${op}.min_MiB ${_arr[2]}"$'\n'
            [[ -n "${_arr[3]}" ]] && result+="${op}.mean_MiB ${_arr[3]}"$'\n'
            [[ -n "${_arr[4]}" ]] && result+="${op}.std_dev ${_arr[4]}"$'\n'
            continue
        fi

        # mdtest results: "File creation  :  12345.678  13000.000  ..."
        if [[ $is_mdtest -eq 1 ]]; then
            if [[ "$line" == *"File creation"*":"* ]]; then
                local _val="${line##*:}"
                while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
                read -ra _arr <<< "$_val"
                [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="file_creation_ops_per_sec ${_arr[0]}"$'\n'
                continue
            fi
            if [[ "$line" == *"File stat"*":"* ]]; then
                local _val="${line##*:}"
                while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
                read -ra _arr <<< "$_val"
                [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="file_stat_ops_per_sec ${_arr[0]}"$'\n'
                continue
            fi
            if [[ "$line" == *"File read"*":"* ]]; then
                local _val="${line##*:}"
                while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
                read -ra _arr <<< "$_val"
                [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="file_read_ops_per_sec ${_arr[0]}"$'\n'
                continue
            fi
            if [[ "$line" == *"File removal"*":"* ]] || [[ "$line" == *"File remove"*":"* ]]; then
                local _val="${line##*:}"
                while [[ "$_val" == " "* ]]; do _val="${_val# }"; done
                read -ra _arr <<< "$_val"
                [[ "${_arr[0]}" =~ ^[0-9] ]] && result+="file_removal_ops_per_sec ${_arr[0]}"$'\n'
                continue
            fi
        fi
    done <<< "$text"

    echo "$result"
}
