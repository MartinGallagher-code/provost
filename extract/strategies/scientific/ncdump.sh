#!/bin/bash
## Name: ncdump
## Description: Extract dimensions, variables, and attributes from NetCDF ncdump output
## Version: 1.0
## Priority: 10
## Sample: samples/ncdump/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0

    local hits=0
    [[ "$text" == *"netcdf "* ]] && hits=$((hits + 1))
    [[ "$text" == *"dimensions:"* ]] && hits=$((hits + 1))
    [[ "$text" == *"variables:"* ]] && hits=$((hits + 1))
    [[ "$text" == *"global attributes:"* ]] && hits=$((hits + 1))
    [[ "$text" == *"ncdump"* ]] && hits=$((hits + 1))

    if [[ $hits -ge 3 ]]; then
        _STRATEGY_CONFIDENCE=95
        return 0
    fi
    if [[ $hits -ge 2 ]] && [[ "$text" == *"netcdf "* ]]; then
        _STRATEGY_CONFIDENCE=80
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Extract filename: "netcdf filename {"
    while IFS= read -r line; do
        if [[ "$line" =~ ^netcdf\ +([^ ]+)\ *\{ ]]; then
            result+="filename ${BASH_REMATCH[1]}"$'\n'
            break
        fi
    done <<< "$text"

    # Parse sections
    local section=""
    local num_dimensions=0
    local num_variables=0
    local num_global_attrs=0
    local dimension_names=""
    local variable_names=""

    while IFS= read -r line; do
        local trimmed="$line"
        while [[ "$trimmed" == " "* || "$trimmed" == $'\t'* ]]; do
            trimmed="${trimmed#[[:space:]]}"
        done

        # Detect section headers
        if [[ "$trimmed" == "dimensions:" ]]; then
            section="dimensions"
            continue
        fi
        if [[ "$trimmed" == "variables:" ]]; then
            section="variables"
            continue
        fi
        if [[ "$trimmed" == *"global attributes:"* ]]; then
            section="global_attributes"
            continue
        fi
        if [[ "$trimmed" == "data:" ]]; then
            section="data"
            continue
        fi

        [[ -z "$trimmed" ]] && continue

        # Parse dimensions: "time = 365 ;" or "time = UNLIMITED ; // (365 currently)"
        if [[ "$section" == "dimensions" ]]; then
            if [[ "$trimmed" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)\ *=\ *([^;]+) ]]; then
                num_dimensions=$((num_dimensions + 1))
                local dname="${BASH_REMATCH[1]}"
                local dval="${BASH_REMATCH[2]}"
                # Clean trailing spaces
                while [[ "$dval" == *" " ]]; do dval="${dval% }"; done

                [[ -n "$dimension_names" ]] && dimension_names+=","
                dimension_names+="$dname"

                # Handle UNLIMITED
                if [[ "$dval" == *"UNLIMITED"* ]]; then
                    if [[ "$dval" =~ \(([0-9]+)\ +currently\) ]]; then
                        result+="dimension.${dname} UNLIMITED(${BASH_REMATCH[1]})"$'\n'
                    else
                        result+="dimension.${dname} UNLIMITED"$'\n'
                    fi
                else
                    result+="dimension.${dname} ${dval}"$'\n'
                fi
            fi
            continue
        fi

        # Parse variables: "float temperature(time, lat, lon) ;"
        if [[ "$section" == "variables" ]]; then
            if [[ "$trimmed" == *"("*")"* ]] && [[ "$trimmed" =~ ^([a-z][a-z0-9_]*)\ +([a-zA-Z_][a-zA-Z0-9_]*) ]]; then
                local vtype="${BASH_REMATCH[1]}"
                local vname="${BASH_REMATCH[2]}"
                # Extract dimensions from parentheses
                local _after="${trimmed#*(}"
                local vdims="${_after%%)*}"
                vdims="${vdims// /}"

                num_variables=$((num_variables + 1))
                [[ -n "$variable_names" ]] && variable_names+=","
                variable_names+="$vname"

                result+="variable.${vname}.type ${vtype}"$'\n'
                result+="variable.${vname}.dimensions ${vdims}"$'\n'
            # Scalar variable: "int status ;"
            elif [[ "$trimmed" =~ ^([a-z][a-z0-9_]*)\ +([a-zA-Z_][a-zA-Z0-9_]*)\ *\; ]]; then
                num_variables=$((num_variables + 1))
                local vtype="${BASH_REMATCH[1]}"
                local vname="${BASH_REMATCH[2]}"

                [[ -n "$variable_names" ]] && variable_names+=","
                variable_names+="$vname"

                result+="variable.${vname}.type ${vtype}"$'\n'
            # Variable attribute: "temperature:units = "K" ;"
            elif [[ "$trimmed" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):([a-zA-Z_][a-zA-Z0-9_]*)\ *=\ *(.+)\ *\; ]]; then
                local owner="${BASH_REMATCH[1]}"
                local aname="${BASH_REMATCH[2]}"
                local aval="${BASH_REMATCH[3]}"
                # Remove surrounding quotes and spaces
                while [[ "$aval" == *" " ]]; do aval="${aval% }"; done
                aval="${aval#\"}"
                aval="${aval%\"}"
                result+="variable.${owner}.${aname} ${aval}"$'\n'
            fi
            continue
        fi

        # Parse global attributes: ":history = "created 2024-01-01" ;"
        if [[ "$section" == "global_attributes" ]]; then
            if [[ "$trimmed" =~ ^:([a-zA-Z_][a-zA-Z0-9_]*)\ *=\ *(.+)\ *\; ]]; then
                num_global_attrs=$((num_global_attrs + 1))
                local aname="${BASH_REMATCH[1]}"
                local aval="${BASH_REMATCH[2]}"
                while [[ "$aval" == *" " ]]; do aval="${aval% }"; done
                aval="${aval#\"}"
                aval="${aval%\"}"
                result+="global.${aname} ${aval}"$'\n'
            fi
            continue
        fi
    done <<< "$text"

    [[ $num_dimensions -gt 0 ]] && result+="num_dimensions ${num_dimensions}"$'\n'
    [[ $num_variables -gt 0 ]] && result+="num_variables ${num_variables}"$'\n'
    [[ $num_global_attrs -gt 0 ]] && result+="num_global_attributes ${num_global_attrs}"$'\n'
    [[ -n "$dimension_names" ]] && result+="dimension_names ${dimension_names}"$'\n'
    [[ -n "$variable_names" ]] && result+="variable_names ${variable_names}"$'\n'

    echo "$result"
}
