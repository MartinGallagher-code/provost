#!/bin/bash
## Name: exposition-format
## Description: Extract metrics from Prometheus/OpenMetrics exposition format (# TYPE, # HELP, # UNIT, labels)
## Version: 1.0
## Priority: 25
## Sample: samples/prometheus/basic.txt

# Merges prometheus and openmetrics strategies. The OpenMetrics format is a
# strict superset of Prometheus text format. Detects either:
#   - Prometheus: any # TYPE lines (with optional data lines)
#   - OpenMetrics: # EOF marker, # UNIT lines, OM-specific type names, or _created metrics

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90

    # Reject JSON
    _is_json "$1" && return 1

    local found_type=0 found_eof=0 found_unit=0 found_data=0 found_om_type=0 found_created=0
    local _re_type='^# TYPE [a-zA-Z_][a-zA-Z0-9_]* '
    local _re_data='^[a-zA-Z_][a-zA-Z0-9_]*\{.*\} '
    local _re_bare='^[a-zA-Z_][a-zA-Z0-9_]* [0-9]'

    while IFS= read -r _line; do
        [[ -z "$_line" ]] && continue
        [[ "$_line" == "# EOF" ]] && found_eof=1
        [[ "$_line" == "# UNIT "* ]] && found_unit=1
        if [[ "$_line" =~ $_re_type ]]; then
            found_type=1
            [[ "$_line" == *" info" || "$_line" == *" stateset" || "$_line" == *" unknown" ]] && found_om_type=1
        fi
        [[ "$_line" =~ $_re_data ]] && found_data=1
        [[ "$_line" =~ $_re_bare ]] && found_data=1
        [[ "$_line" == *"_created "* || "$_line" == *"_created{"* ]] && found_created=1
        # Early exit once we have enough signal
        [[ $found_type -eq 1 && $found_data -eq 1 ]] && return 0
    done <<< "$text"

    # Accept Prometheus format: # TYPE lines (with or without data)
    [[ $found_type -eq 1 ]] && return 0

    # Accept OpenMetrics-specific signals
    [[ $found_eof -eq 1 && $found_type -eq 1 ]] && return 0
    [[ $found_unit -eq 1 && $found_type -eq 1 ]] && return 0
    [[ $found_om_type -eq 1 ]] && return 0
    [[ $found_created -eq 1 && $found_type -eq 1 ]] && return 0

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local metric_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Skip # EOF marker (OpenMetrics)
        [[ "$line" == "# EOF" ]] && continue

        # Parse # HELP lines: "# HELP metric_name Description text"
        if [[ "$line" == "# HELP "* ]]; then
            local rest="${line#\# HELP }"
            local hname="${rest%% *}"
            local hdesc="${rest#* }"
            [[ "$hdesc" == "$hname" ]] && hdesc=""
            [[ -n "$hname" && -n "$hdesc" ]] && result+="${hname}.help ${hdesc}"$'\n'
            continue
        fi

        # Parse # TYPE lines: "# TYPE metric_name type_string"
        if [[ "$line" == "# TYPE "* ]]; then
            local rest="${line#\# TYPE }"
            local tname="${rest%% *}"
            local ttype="${rest#* }"
            [[ "$ttype" == "$tname" ]] && ttype=""
            [[ -n "$tname" && -n "$ttype" ]] && result+="${tname}.type ${ttype}"$'\n'
            continue
        fi

        # Parse # UNIT lines (OpenMetrics): "# UNIT metric_name unit"
        if [[ "$line" == "# UNIT "* ]]; then
            local rest="${line#\# UNIT }"
            local uname="${rest%% *}"
            local uunit="${rest#* }"
            [[ "$uunit" == "$uname" ]] && uunit=""
            [[ -n "$uname" && -n "$uunit" ]] && result+="${uname}.unit ${uunit}"$'\n'
            continue
        fi

        # Skip other comment lines
        [[ "$line" == "#"* ]] && continue

        # Parse data lines
        # Format: metric_name{label="val",label2="val2"} value [timestamp]
        # or:     metric_name value [timestamp]
        local mname="" labels="" mvalue=""

        if [[ "$line" == *"{"* ]]; then
            mname="${line%%\{*}"
            local after_brace="${line#*\{}"
            labels="${after_brace%%\}*}"
            local after_close="${line#*\} }"
            [[ "$after_close" == "$line" ]] && continue
            read -ra _varr <<< "$after_close"
            mvalue="${_varr[0]}"
        else
            read -ra _varr <<< "$line"
            [[ ${#_varr[@]} -lt 2 ]] && continue
            mname="${_varr[0]}"
            mvalue="${_varr[1]}"
        fi

        # Validate metric name starts with letter or underscore
        local _re_mname='^[a-zA-Z_]'
        [[ ! "$mname" =~ $_re_mname ]] && continue

        # Validate value looks numeric (or special float values)
        local _re_val='^[0-9eE.+\-]'
        case "$mvalue" in
            NaN|Inf|+Inf|-Inf) ;;
            *) [[ ! "$mvalue" =~ $_re_val ]] && continue ;;
        esac

        metric_num=$((metric_num + 1))
        result+="metric${metric_num}.name ${mname}"$'\n'
        result+="metric${metric_num}.value ${mvalue}"$'\n'
        # Split the label set into one label.<key> field per label so the
        # melted table gets a real column per label key (method, code, cpu…)
        # instead of a single opaque labels blob.
        if [[ -n "$labels" ]]; then
            local _lbl_rest="$labels" _lbl_pair _lbl_key _lbl_val
            while [[ -n "$_lbl_rest" ]]; do
                _lbl_pair="${_lbl_rest%%,*}"
                if [[ "$_lbl_rest" == *,* ]]; then _lbl_rest="${_lbl_rest#*,}"; else _lbl_rest=""; fi
                _lbl_key="${_lbl_pair%%=*}"
                _lbl_val="${_lbl_pair#*=}"
                _lbl_val="${_lbl_val#\"}"; _lbl_val="${_lbl_val%\"}"
                [[ -z "$_lbl_key" || "$_lbl_key" == "$_lbl_pair" ]] && continue
                _lbl_key="${_lbl_key//[[:space:]]/}"
                result+="metric${metric_num}.label_${_lbl_key} ${_lbl_val}"$'\n'
            done
        fi

    done <<< "$text"

    echo "$result"
}
