#!/bin/bash
## Name: dig-output
## Description: Extract DNS query results from dig command output
## Version: 1.0
## Priority: 20
## Technique: mixed
## Sample: samples/dig-output/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$text" && return 1
    # dig output contains ";; ANSWER SECTION:" and ";; Query time:"
    local has_answer=0
    local has_query=0
    while IFS= read -r line; do
        [[ "$line" == *"ANSWER SECTION"* ]] && has_answer=1
        [[ "$line" == *"Query time"* ]] && has_query=1
        if [[ $has_answer -eq 1 && $has_query -eq 1 ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local in_answer=0
    local record_n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && { in_answer=0; continue; }

        # Skip pure comment lines except section headers
        if [[ "$line" == ";;"* ]]; then
            if [[ "$line" == *"ANSWER SECTION"* ]]; then
                in_answer=1
            fi
            # Extract query metadata
            if [[ "$line" == *"Query time:"* ]]; then
                local qt="${line#*Query time: }"
                result+="query_time ${qt}"$'\n'
            fi
            if [[ "$line" == *"SERVER:"* ]]; then
                local srv="${line#*SERVER: }"
                result+="server ${srv}"$'\n'
            fi
            if [[ "$line" == *"MSG SIZE"* ]]; then
                local ms="${line#*rcvd: }"
                result+="msg_size ${ms}"$'\n'
            fi
            continue
        fi

        # Skip comments
        [[ "$line" == ";"* ]] && continue

        # Parse answer records
        if [[ $in_answer -eq 1 ]]; then
            read -ra _arr <<< "$line"
            [[ ${#_arr[@]} -lt 4 ]] && continue

            record_n=$((record_n + 1))
            local prefix="record${record_n}"

            local name="${_arr[0]}"
            local ttl="${_arr[1]}"
            local rclass="${_arr[2]}"
            local rtype="${_arr[3]}"
            local rdata=""
            local i
            for ((i=4; i<${#_arr[@]}; i++)); do
                if [[ -z "$rdata" ]]; then
                    rdata="${_arr[$i]}"
                else
                    rdata="${rdata}_${_arr[$i]}"
                fi
            done

            result+="${prefix}.name ${name}"$'\n'
            result+="${prefix}.ttl ${ttl}"$'\n'
            result+="${prefix}.class ${rclass}"$'\n'
            result+="${prefix}.type ${rtype}"$'\n'
            [[ -n "$rdata" ]] && result+="${prefix}.data ${rdata}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
