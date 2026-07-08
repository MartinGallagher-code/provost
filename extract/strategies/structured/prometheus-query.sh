#!/bin/bash
## Name: prometheus-query
## Description: Extract metric values from Prometheus query result output
## Version: 1.0
## Priority: 25
## Technique: mixed
## Sample: samples/prometheus-query/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=88
    _is_json "$text" && return 1
    # Prometheus text output has lines like: metric_name{label="value"} 123.45
    local prom_count=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        [[ "$line" == "#"* ]] && continue
        # Match pattern: name{labels} value or name value
        if [[ "$line" == *"{"*"}"*[0-9]* ]]; then
            prom_count=$((prom_count + 1))
        fi
        [[ $prom_count -ge 3 ]] && return 0
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local metric_n=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Parse HELP and TYPE comments
        if [[ "$line" == "# HELP "* ]]; then
            local help_text="${line#\# HELP }"
            local help_name="${help_text%% *}"
            local help_desc="${help_text#* }"
            result+="meta.${help_name}.help ${help_desc}"$'\n'
            continue
        fi
        if [[ "$line" == "# TYPE "* ]]; then
            local type_text="${line#\# TYPE }"
            local type_name="${type_text%% *}"
            local type_val="${type_text#* }"
            result+="meta.${type_name}.type ${type_val}"$'\n'
            continue
        fi
        [[ "$line" == "#"* ]] && continue

        # Parse metric lines: metric_name{label1="val1",label2="val2"} value
        if [[ "$line" == *"{"*"}"* ]]; then
            metric_n=$((metric_n + 1))
            local prefix="metric${metric_n}"

            local metric_name="${line%%\{*}"
            local rest="${line#*\{}"
            local labels="${rest%%\}*}"
            local value="${rest#*\} }"

            result+="${prefix}.name ${metric_name}"$'\n'
            result+="${prefix}.value ${value}"$'\n'

            # Parse individual labels
            local remaining="$labels"
            while [[ -n "$remaining" ]]; do
                local pair="${remaining%%,*}"
                if [[ "$remaining" == *","* ]]; then
                    remaining="${remaining#*,}"
                else
                    remaining=""
                fi
                local lkey="${pair%%=*}"
                local lval="${pair#*=}"
                # Strip quotes from value
                lval="${lval#\"}"
                lval="${lval%\"}"
                [[ -n "$lkey" && -n "$lval" ]] && result+="${prefix}.label.${lkey} ${lval}"$'\n'
            done
        elif [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*\  ]]; then
            # Simple metric without labels: metric_name value
            metric_n=$((metric_n + 1))
            local prefix="metric${metric_n}"
            read -ra _arr <<< "$line"
            result+="${prefix}.name ${_arr[0]}"$'\n'
            result+="${prefix}.value ${_arr[1]}"$'\n'
        fi
    done <<< "$text"

    echo "$result"
}
