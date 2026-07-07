#!/bin/bash
## Name: lsusb-t
## Description: Extract per-line rows from `lsusb -t` USB device tree output
## Version: 1.0
## Priority: 27
## Technique: yes
## Sample: samples/lsusb-t/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    _is_json "$text" && return 1
    # `lsusb -t` is distinctive: root hub lines like `/:  Bus 02.Port 1: Dev 1,
    # Class=root_hub, ...` and device lines beginning with `|__ Port`.
    local has_root=0 has_port=0
    while IFS= read -r line; do
        [[ "$line" == "/:"*"Class=root_hub"* ]] && has_root=1
        [[ "$line" == *"|__ Port"* ]] && has_port=1
    done <<< "$text"
    if [[ $has_root -eq 1 && $has_port -eq 1 ]]; then
        _STRATEGY_CONFIDENCE=88
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local entry=0
    while IFS= read -r line; do
        # One record per non-blank line (root hubs + `|__ Port` device lines).
        [[ -z "${line// }" ]] && continue
        # Trim leading whitespace, then fold internal whitespace to underscores
        # so the whole cleaned line survives as a single field value.
        local trimmed="${line#"${line%%[![:space:]]*}"}"
        local cleaned
        cleaned="$(printf '%s' "$trimmed" | tr -s '[:space:]' '_')"

        entry=$((entry + 1))
        result+="entry${entry}.line ${cleaned}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
