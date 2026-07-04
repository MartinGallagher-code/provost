#!/bin/bash
## Name: smartctl
## Description: Extract disk health and SMART attributes from smartctl -a output
## Version: 1.0
## Priority: 10
## Sample: samples/smartctl/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    # Reject JSON
    _is_json "$1" && return 1
    # Must contain "smartctl" somewhere
    [[ "$text" != *smartctl* ]] && return 1
    # Must also contain either the INFORMATION SECTION or SMART health
    if [[ "$text" == *"START OF INFORMATION SECTION"* ]]; then
        return 0
    fi
    if [[ "$text" == *"SMART overall-health"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local in_attributes=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Information section fields: "Key:     Value"
        # Device Model:     WDC WD10EZEX-08WN4A0
        if [[ "$line" == "Device Model:"* ]]; then
            local val="${line#*:}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="Device_Model ${val}"$'\n'
            continue
        fi

        if [[ "$line" == "Model Family:"* ]]; then
            local val="${line#*:}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            # Replace spaces with underscores for field value
            val="${val// /_}"
            [[ -n "$val" ]] && result+="Model_Family ${val}"$'\n'
            continue
        fi

        if [[ "$line" == "Serial Number:"* ]]; then
            local val="${line#*:}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="Serial_Number ${val}"$'\n'
            continue
        fi

        if [[ "$line" == "Firmware Version:"* ]]; then
            local val="${line#*:}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            [[ -n "$val" ]] && result+="Firmware_Version ${val}"$'\n'
            continue
        fi

        if [[ "$line" == "User Capacity:"* ]]; then
            local val="${line#*:}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            # Extract the bracketed human-readable form if present
            if [[ "$val" == *"["*"]"* ]]; then
                local human="${val#*\[}"
                human="${human%%\]*}"
                result+="User_Capacity ${human}"$'\n'
            else
                # Replace spaces/commas for cleaner value
                val="${val//,/}"
                val="${val// /_}"
                result+="User_Capacity ${val}"$'\n'
            fi
            continue
        fi

        if [[ "$line" == "Sector Size:"* ]]; then
            local val="${line#*:}"
            while [[ "$val" == " "* ]]; do val="${val# }"; done
            read -ra _arr <<< "$val"
            [[ -n "${_arr[0]}" ]] && result+="Sector_Size ${_arr[0]}"$'\n'
            continue
        fi

        # SMART health: "SMART overall-health self-assessment test result: PASSED"
        if [[ "$line" == *"SMART overall-health"* ]]; then
            local val="${line##*: }"
            [[ -n "$val" ]] && result+="SMART_health ${val}"$'\n'
            continue
        fi

        # SMART Attributes table header detection
        if [[ "$line" == "ID#"* ]] && [[ "$line" == *"ATTRIBUTE_NAME"* ]]; then
            in_attributes=1
            continue
        fi

        # End of attributes section on blank or section marker
        if [[ $in_attributes -eq 1 ]]; then
            if [[ "$line" == "==="* ]]; then
                in_attributes=0
                continue
            fi

            # Parse attribute rows:
            # ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
            #   9 Power_On_Hours          0x0032   095   095   000    Old_age   Always       -       4234
            read -ra _arr <<< "$line"
            # Need at least 10 fields
            [[ ${#_arr[@]} -lt 10 ]] && continue

            local attr_id="${_arr[0]}"
            local attr_name="${_arr[1]}"
            local raw_value="${_arr[${#_arr[@]}-1]}"

            # Validate attr_id is numeric
            case "$attr_id" in
                [0-9]|[0-9][0-9]|[0-9][0-9][0-9]) ;;
                *) continue ;;
            esac

            # Extract specific well-known attributes
            case "$attr_name" in
                Power_On_Hours)
                    result+="Power_On_Hours ${raw_value}"$'\n'
                    ;;
                Temperature_Celsius)
                    result+="Temperature_Celsius ${raw_value}"$'\n'
                    ;;
                Raw_Read_Error_Rate)
                    result+="Raw_Read_Error_Rate ${raw_value}"$'\n'
                    ;;
                Reallocated_Sector_Ct)
                    result+="Reallocated_Sector_Ct ${raw_value}"$'\n'
                    ;;
                Spin_Up_Time)
                    result+="Spin_Up_Time ${raw_value}"$'\n'
                    ;;
                Start_Stop_Count)
                    result+="Start_Stop_Count ${raw_value}"$'\n'
                    ;;
                Wear_Leveling_Count)
                    result+="Wear_Leveling_Count ${raw_value}"$'\n'
                    ;;
                Total_LBAs_Written)
                    result+="Total_LBAs_Written ${raw_value}"$'\n'
                    ;;
            esac
        fi
    done <<< "$text"

    echo "$result"
}
