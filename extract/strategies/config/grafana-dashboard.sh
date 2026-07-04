#!/bin/bash
## Name: grafana-dashboard
## Description: Extract dashboard metadata and panel info from Grafana dashboard JSON exports
## Version: 1.0
## Priority: 14
## Sample: samples/grafana-dashboard/basic.json

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Must be JSON
    _is_json "$1" || return 1

    # Must contain "panels"
    [[ "$text" == *'"panels"'* ]] || return 1

    # Must contain "schemaVersion" or "templating"
    [[ "$text" == *'"schemaVersion"'* || "$text" == *'"templating"'* ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"
    local result=""

    if command -v jq &>/dev/null; then
        _strat_grafana_extract_jq "$text"
    else
        _strat_grafana_extract_fallback "$text"
    fi
}

_strat_grafana_extract_jq () {
    local text="$1"
    local result=""

    # Extract top-level fields
    local title
    title=$(echo "$text" | jq -r '.title // empty' 2>/dev/null) || true
    if [[ -n "$title" ]]; then
        local clean="${title// /_}"
        result+="title ${clean}"$'\n'
    fi

    local uid
    uid=$(echo "$text" | jq -r '.uid // empty' 2>/dev/null) || true
    if [[ -n "$uid" ]]; then
        result+="uid ${uid}"$'\n'
    fi

    local schema_version
    schema_version=$(echo "$text" | jq -r '.schemaVersion // empty' 2>/dev/null) || true
    if [[ -n "$schema_version" ]]; then
        result+="schemaVersion ${schema_version}"$'\n'
    fi

    local timezone
    timezone=$(echo "$text" | jq -r '.timezone // empty' 2>/dev/null) || true
    if [[ -n "$timezone" ]]; then
        result+="timezone ${timezone}"$'\n'
    fi

    local editable
    editable=$(echo "$text" | jq -r '.editable // empty' 2>/dev/null) || true
    if [[ -n "$editable" ]]; then
        result+="editable ${editable}"$'\n'
    fi

    local refresh
    refresh=$(echo "$text" | jq -r '.refresh // empty' 2>/dev/null) || true
    if [[ -n "$refresh" ]]; then
        result+="refresh ${refresh}"$'\n'
    fi

    # Extract per-panel fields
    local panel_count
    panel_count=$(echo "$text" | jq -r '.panels | length' 2>/dev/null) || true
    if [[ -n "$panel_count" && "$panel_count" -gt 0 ]] 2>/dev/null; then
        local i=0
        while [[ $i -lt $panel_count ]]; do
            local n=$((i + 1))
            local prefix="panel${n}"

            local p_id
            p_id=$(echo "$text" | jq -r ".panels[$i].id // empty" 2>/dev/null) || true
            if [[ -n "$p_id" ]]; then
                result+="${prefix}.id ${p_id}"$'\n'
            fi

            local p_title
            p_title=$(echo "$text" | jq -r ".panels[$i].title // empty" 2>/dev/null) || true
            if [[ -n "$p_title" ]]; then
                local clean_t="${p_title// /_}"
                result+="${prefix}.title ${clean_t}"$'\n'
            fi

            local p_type
            p_type=$(echo "$text" | jq -r ".panels[$i].type // empty" 2>/dev/null) || true
            if [[ -n "$p_type" ]]; then
                result+="${prefix}.type ${p_type}"$'\n'
            fi

            local p_datasource
            p_datasource=$(echo "$text" | jq -r ".panels[$i].datasource // empty" 2>/dev/null) || true
            if [[ -n "$p_datasource" ]]; then
                local clean_ds="${p_datasource// /_}"
                result+="${prefix}.datasource ${clean_ds}"$'\n'
            fi

            i=$((i + 1))
        done
    fi

    echo "$result"
}

_strat_grafana_extract_fallback () {
    local text="$1"
    local result=""

    # Fallback: extract key fields using bash pattern matching
    local remaining="$text"
    while [[ "$remaining" == *'"'*':'* ]]; do
        local after_quote="${remaining#*\"}"
        local key="${after_quote%%\"*}"
        [[ -z "$key" ]] && break
        remaining="${after_quote#*\"}"
        remaining="${remaining#*:}"
        while [[ "$remaining" == " "* ]]; do remaining="${remaining# }"; done
        local value=""
        if [[ "$remaining" == '"'* ]]; then
            remaining="${remaining#\"}"
            value="${remaining%%\"*}"
            remaining="${remaining#*\"}"
        elif [[ "$remaining" =~ ^([0-9.eE+-]+) ]]; then
            value="${BASH_REMATCH[1]}"
            remaining="${remaining#"$value"}"
        elif [[ "$remaining" == "true"* ]]; then
            value="true"; remaining="${remaining#true}"
        elif [[ "$remaining" == "false"* ]]; then
            value="false"; remaining="${remaining#false}"
        elif [[ "$remaining" == "null"* ]]; then
            value="null"; remaining="${remaining#null}"
        else
            break
        fi
        value="${value// /_}"
        if [[ -n "$key" && -n "$value" ]]; then
            result+="${key} ${value}"$'\n'
        fi
    done

    echo "$result"
}
