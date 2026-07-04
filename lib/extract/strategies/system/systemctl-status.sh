#!/bin/bash
## Name: systemctl-status
## Description: Extract service information from systemctl status output
## Version: 1.0
## Priority: 22
## Technique: kv_colon
## Sample: samples/systemctl-status/sample1.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$text" && return 1
    # systemctl status output contains "Loaded:" and "Active:" lines
    local has_loaded=0
    local has_active=0
    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        [[ "$trimmed" == "Loaded:"* ]] && has_loaded=1
        [[ "$trimmed" == "Active:"* ]] && has_active=1
        if [[ $has_loaded -eq 1 && $has_active -eq 1 ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract the unit name from the first line (bullet line)
    local unit_name=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
        # First line is typically "● service-name.service - Description"
        if [[ "$trimmed" == *".service"* || "$trimmed" == *".socket"* || "$trimmed" == *".timer"* ]]; then
            # Remove bullet character prefix
            trimmed="${trimmed#*  }"
            while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
            # Get unit name before " - "
            if [[ "$trimmed" == *" - "* ]]; then
                unit_name="${trimmed%% - *}"
                local desc="${trimmed#* - }"
                desc="${desc// /_}"
                result+="unit ${unit_name}"$'\n'
                result+="description ${desc}"$'\n'
            else
                unit_name="$trimmed"
                result+="unit ${unit_name}"$'\n'
            fi
            break
        fi
        break
    done <<< "$text"

    # Extract key: value fields
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        case "$trimmed" in
            "Loaded: "*)
                local val="${trimmed#Loaded: }"
                val="${val// /_}"
                result+="loaded ${val}"$'\n'
                ;;
            "Active: "*)
                local val="${trimmed#Active: }"
                # Extract the state keyword (active, inactive, failed, etc.)
                local state="${val%% *}"
                result+="active ${state}"$'\n'
                # Extract since timestamp if present
                if [[ "$val" == *"since "* ]]; then
                    local since="${val#*since }"
                    since="${since%;*}"
                    since="${since// /_}"
                    result+="since ${since}"$'\n'
                fi
                ;;
            "Main PID: "*)
                local val="${trimmed#Main PID: }"
                local pid="${val%% *}"
                result+="main_pid ${pid}"$'\n'
                ;;
            "Tasks: "*)
                local val="${trimmed#Tasks: }"
                local tasks="${val%% *}"
                result+="tasks ${tasks}"$'\n'
                ;;
            "Memory: "*)
                local val="${trimmed#Memory: }"
                val="${val// /_}"
                result+="memory ${val}"$'\n'
                ;;
            "CPU: "*)
                local val="${trimmed#CPU: }"
                val="${val// /_}"
                result+="cpu ${val}"$'\n'
                ;;
            "CGroup: "*)
                local val="${trimmed#CGroup: }"
                val="${val// /_}"
                result+="cgroup ${val}"$'\n'
                ;;
        esac
    done <<< "$text"

    echo "$result"
}
