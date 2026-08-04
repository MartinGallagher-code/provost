#!/bin/bash
## Name: dash-labeled-stats
## Description: `NAME - k: v, k: v, …` stat records (go-ycsb READ/UPDATE lines) -> name + one column per key
## Version: 1.0
## Priority: 42
## Sample: samples/dash-labeled-stats/basic.txt

# Benchmark runners print per-operation stat lines — a label, ` - `, then a
# comma-separated list of `key: value` pairs:
#
#   READ   - Takes(s): 48.8, Count: 800482, OPS: 16398.4, Avg(us): 921, P99(us): 2210
#   UPDATE - Takes(s): 48.8, Count: 199518, OPS: 4088.2, Avg(us): 1204, P99(us): 3210
#
# The sibling labeled-inline-kv takes `label: k=v, k=v`; this is the ` - ` +
# `k: v` flavor. One row per label: `name` + a column per key.
#
#   name    Takes(s)  Count   OPS      Avg(us)  P99(us)
#   READ    48.8      800482  16398.4  921      2210
#   UPDATE  48.8      199518  4088.2   1204     3210
#
# Preamble/banner lines (go-ycsb's `"k"="v"` properties block, `Run finished,
# takes 48.8s`) are tolerated: the record lines are distinctive enough that
# they define the dataset — but at least TWO must be present, and every record
# needs >=2 comma-separated `k: v` parts after the dash (so fdbcli's
# `Redundancy mode - triple` single-pair lines never match).

# Parse "$1" -> _DLS_NAME + parallel _DLS_K[] / _DLS_V[]. Returns 1 unless the
# line is `NAME - k: v, k: v[, …]` with >=2 pairs.
_dls_parse () {
    local l="$1"
    _DLS_NAME=""; _DLS_K=(); _DLS_V=()
    [[ "$l" =~ ^([A-Za-z][A-Za-z0-9_]*)[[:space:]]+-[[:space:]]+(.+)$ ]] || return 1
    _DLS_NAME="${BASH_REMATCH[1]}"
    local rest="${BASH_REMATCH[2]}"
    local IFS_SAVE="$IFS" part
    local -a parts=()
    IFS=',' read -ra parts <<< "$rest"
    IFS="$IFS_SAVE"
    [[ ${#parts[@]} -ge 2 ]] || return 1
    for part in "${parts[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        [[ "$part" =~ ^([A-Za-z][A-Za-z0-9_()%/[:space:]]*):[[:space:]]*(.+)$ ]] || return 1
        local k="${BASH_REMATCH[1]}" v="${BASH_REMATCH[2]}"
        k="${k%"${k##*[![:space:]]}"}"
        k="${k// /_}"
        _DLS_K+=("$k"); _DLS_V+=("$v")
    done
    return 0
}

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    local line records=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _dls_parse "$line" && records=$((records + 1))
    done <<< "$text"
    [[ $records -ge 2 ]] || return 1
    _STRATEGY_CONFIDENCE=76
    return 0
}

strategy_extract () {
    local text="$1"
    local line result="" entry=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line//[[:space:]]/}" ]] && continue
        _dls_parse "$line" || continue
        entry=$((entry + 1))
        result+="entry${entry}.name ${_DLS_NAME}"$'\n'
        local i
        for i in "${!_DLS_K[@]}"; do
            result+="entry${entry}.${_DLS_K[$i]} ${_DLS_V[$i]}"$'\n'
        done
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
