#!/bin/bash
## Name: dns-record
## Description: Extract fields from dig DNS query output
## Version: 1.0
## Priority: 25
## Sample: samples/dns-record/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    # Contains ";; ANSWER SECTION:" or "DiG" marker
    [[ "$text" == *";; ANSWER SECTION:"* ]] && return 0
    [[ "$text" == *"DiG"* ]] && return 0
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local in_answer=0
    local record_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Detect ANSWER SECTION start
        if [[ "$line" == ";; ANSWER SECTION:"* ]]; then
            in_answer=1
            continue
        fi

        # Detect end of ANSWER SECTION (next section header or blank-ish)
        if [[ $in_answer -eq 1 ]]; then
            if [[ "$line" == ";;"* ]]; then
                in_answer=0
            elif [[ "$line" == ";"* ]]; then
                # Skip comment lines
                continue
            else
                # Parse DNS record: name ttl class type value
                record_num=$((record_num + 1))
                read -ra _arr <<< "$line"
                local name="${_arr[0]}"
                local ttl="${_arr[1]}"
                local rtype="${_arr[3]}"
                # Value is everything from field 5 onward, joined with underscores
                local value=""
                local _i
                for ((_i=4; _i<${#_arr[@]}; _i++)); do
                    if [[ -n "$value" ]]; then
                        value+="_${_arr[$_i]}"
                    else
                        value="${_arr[$_i]}"
                    fi
                done

                name="${name// /_}"
                value="${value// /_}"

                result+="record${record_num}.name ${name}"$'\n'
                result+="record${record_num}.ttl ${ttl}"$'\n'
                result+="record${record_num}.type ${rtype}"$'\n'
                result+="record${record_num}.value ${value}"$'\n'
                continue
            fi
        fi

        # Extract query metadata
        if [[ "$line" == ";; Query time:"* ]]; then
            local qtime="${line#;; Query time: }"
            while [[ "$qtime" == " "* ]]; do qtime="${qtime# }"; done
            qtime="${qtime// /_}"
            result+="query_time ${qtime}"$'\n'
        fi

        if [[ "$line" == ";; SERVER:"* ]]; then
            local server="${line#;; SERVER: }"
            while [[ "$server" == " "* ]]; do server="${server# }"; done
            # Extract just the IP (before #)
            server="${server%%#*}"
            server="${server// /_}"
            result+="server ${server}"$'\n'
        fi

    done <<< "$text"

    echo "$result"
}
