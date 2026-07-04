#!/bin/bash
## Name: elasticsearch
## Description: Extract search response fields from Elasticsearch JSON output
## Version: 1.0
## Priority: 14
## Sample: samples/elasticsearch/basic.json

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85

    # Must be JSON
    _is_json "$1" || return 1

    # Must contain "hits"
    [[ "$text" == *'"hits"'* ]] || return 1

    # Must contain "_shards" or "took"
    [[ "$text" == *'"_shards"'* || "$text" == *'"took"'* ]] || return 1

    return 0
}

strategy_extract () {
    local text="$1"
    local result=""

    if command -v jq &>/dev/null; then
        _strat_es_extract_jq "$text"
    else
        _strat_es_extract_fallback "$text"
    fi
}

_strat_es_extract_jq () {
    local text="$1"
    local result=""

    # Top-level fields
    local took
    took=$(echo "$text" | jq -r '.took // empty' 2>/dev/null) || true
    if [[ -n "$took" ]]; then
        result+="took ${took}"$'\n'
    fi

    local timed_out
    timed_out=$(echo "$text" | jq -r 'if .timed_out != null then .timed_out | tostring else empty end' 2>/dev/null) || true
    if [[ -n "$timed_out" ]]; then
        result+="timed_out ${timed_out}"$'\n'
    fi

    # _shards fields
    local shards_total
    shards_total=$(echo "$text" | jq -r '._shards.total // empty' 2>/dev/null) || true
    if [[ -n "$shards_total" ]]; then
        result+="_shards.total ${shards_total}"$'\n'
    fi

    local shards_successful
    shards_successful=$(echo "$text" | jq -r '._shards.successful // empty' 2>/dev/null) || true
    if [[ -n "$shards_successful" ]]; then
        result+="_shards.successful ${shards_successful}"$'\n'
    fi

    local shards_skipped
    shards_skipped=$(echo "$text" | jq -r '._shards.skipped // empty' 2>/dev/null) || true
    if [[ -n "$shards_skipped" ]]; then
        result+="_shards.skipped ${shards_skipped}"$'\n'
    fi

    local shards_failed
    shards_failed=$(echo "$text" | jq -r '._shards.failed // empty' 2>/dev/null) || true
    if [[ -n "$shards_failed" ]]; then
        result+="_shards.failed ${shards_failed}"$'\n'
    fi

    # hits metadata
    local hits_total
    hits_total=$(echo "$text" | jq -r '.hits.total.value // empty' 2>/dev/null) || true
    if [[ -n "$hits_total" ]]; then
        result+="hits.total.value ${hits_total}"$'\n'
    fi

    local hits_total_relation
    hits_total_relation=$(echo "$text" | jq -r '.hits.total.relation // empty' 2>/dev/null) || true
    if [[ -n "$hits_total_relation" ]]; then
        result+="hits.total.relation ${hits_total_relation}"$'\n'
    fi

    local max_score
    max_score=$(echo "$text" | jq -r '.hits.max_score // empty' 2>/dev/null) || true
    if [[ -n "$max_score" ]]; then
        result+="hits.max_score ${max_score}"$'\n'
    fi

    # Per-hit fields
    local hit_count
    hit_count=$(echo "$text" | jq -r '.hits.hits | length' 2>/dev/null) || true
    if [[ -n "$hit_count" && "$hit_count" -gt 0 ]] 2>/dev/null; then
        local i=0
        while [[ $i -lt $hit_count ]]; do
            local n=$((i + 1))
            local prefix="hit${n}"

            local h_index
            h_index=$(echo "$text" | jq -r ".hits.hits[$i]._index // empty" 2>/dev/null) || true
            if [[ -n "$h_index" ]]; then
                result+="${prefix}._index ${h_index}"$'\n'
            fi

            local h_id
            h_id=$(echo "$text" | jq -r ".hits.hits[$i]._id // empty" 2>/dev/null) || true
            if [[ -n "$h_id" ]]; then
                result+="${prefix}._id ${h_id}"$'\n'
            fi

            local h_score
            h_score=$(echo "$text" | jq -r ".hits.hits[$i]._score // empty" 2>/dev/null) || true
            if [[ -n "$h_score" ]]; then
                result+="${prefix}._score ${h_score}"$'\n'
            fi

            # Extract _source fields
            local source_keys
            source_keys=$(echo "$text" | jq -r ".hits.hits[$i]._source | keys[]" 2>/dev/null) || true
            if [[ -n "$source_keys" ]]; then
                while IFS= read -r skey; do
                    [[ -z "$skey" ]] && continue
                    local sval
                    sval=$(echo "$text" | jq -r ".hits.hits[$i]._source[\"$skey\"] // empty" 2>/dev/null) || true
                    if [[ -n "$sval" ]]; then
                        local clean_val="${sval// /_}"
                        result+="${prefix}._source.${skey} ${clean_val}"$'\n'
                    fi
                done <<< "$source_keys"
            fi

            i=$((i + 1))
        done
    fi

    echo "$result"
}

_strat_es_extract_fallback () {
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
