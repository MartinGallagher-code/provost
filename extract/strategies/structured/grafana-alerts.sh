#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

## Name: grafana-alerts
## Description: Extract alert information from Grafana alert list output
## Version: 1.0
## Priority: 25
## Sample: samples/grafana-alerts/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80
    _is_json "$text" && return 1
    # Grafana alert list (CLI output) has columns like ID, TITLE, STATE, HEALTH
    local first_line=""
    _fr_lines "$text"
    for _line in "${_FR_LINES[@]}"; do
        [[ -z "$_line" ]] && continue
        first_line="$_line"
        break
    done
    if [[ "$first_line" == *"ID"* && "$first_line" == *"TITLE"* && "$first_line" == *"STATE"* ]]; then
        return 0
    fi
    # Also match Grafana alerting rule format with labels
    local has_alertname=0
    local has_state=0
    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ "$line" == *"alertname"* ]] && has_alertname=1
        [[ "$line" == *"firing"* || "$line" == *"pending"* || "$line" == *"inactive"* ]] && has_state=1
        if [[ $has_alertname -eq 1 && $has_state -eq 1 ]]; then
            return 0
        fi
    done
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local alert_n=0
    local past_header=0

    _fr_lines "$text"
    for line in "${_FR_LINES[@]}"; do
        [[ -z "$line" ]] && continue

        # Table format header
        if [[ "$line" == *"ID"* && "$line" == *"TITLE"* && "$line" == *"STATE"* ]]; then
            past_header=1
            continue
        fi
        # Skip separator lines
        [[ "$line" == "---"* || "$line" == "==="* ]] && continue

        [[ $past_header -eq 0 ]] && continue

        { _fr_tok "$line"; _arr=("${_FR_TOK[@]}"); }
        [[ ${#_arr[@]} -lt 3 ]] && continue

        alert_n=$((alert_n + 1))
        local prefix="alert${alert_n}"

        local id="${_arr[0]}"
        result+="${prefix}.id ${id}"$'\n'

        # State is typically the last or second-to-last token
        local state=""
        local health=""
        local i
        for ((i=1; i<${#_arr[@]}; i++)); do
            case "${_arr[$i]}" in
                firing|pending|inactive|normal|alerting|ok|paused|no_data|error)
                    if [[ -z "$state" ]]; then
                        state="${_arr[$i]}"
                    else
                        health="${_arr[$i]}"
                    fi
                    ;;
            esac
        done

        # Title is tokens between ID and state keywords
        local title=""
        for ((i=1; i<${#_arr[@]}; i++)); do
            case "${_arr[$i]}" in
                firing|pending|inactive|normal|alerting|ok|paused|no_data|error) break ;;
                *)
                    if [[ -z "$title" ]]; then
                        title="${_arr[$i]}"
                    else
                        title="${title}_${_arr[$i]}"
                    fi
                    ;;
            esac
        done

        [[ -n "$title" ]] && result+="${prefix}.title ${title}"$'\n'
        [[ -n "$state" ]] && result+="${prefix}.state ${state}"$'\n'
        [[ -n "$health" ]] && result+="${prefix}.health ${health}"$'\n'
    done

    echo "$result"
}
