#!/bin/bash
## Name: terraform-plan-actions
## Description: Extract per-resource action lines from `terraform plan` ("# <resource> will be <action>")
## Version: 1.0
## Priority: 22
## Sample: samples/terraform-plan-actions/basic.txt

# A `terraform plan` summary lists each affected resource on a
# "  # <resource> will be <action>" line, wrapped by a "Terraform will perform
# ..." intro and a "Plan: N to add, ..." footer. Only the "# ... will be ..."
# lines are data — each becomes one record (resource + action) so the plan melts
# to one tidy row per resource. (The distinct name avoids colliding with the
# existing config/terraform-plan strategy, which targets the verbose diff form.)

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=0
    command -v _is_json >/dev/null 2>&1 && _is_json "$text" && return 1
    local line
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*#[[:space:]].*[[:space:]]will[[:space:]]be[[:space:]] ]]; then
            _STRATEGY_CONFIDENCE=86
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result="" entry=0 line
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*#[[:space:]].*[[:space:]]will[[:space:]]be[[:space:]] ]] || continue
        local body="$line"
        while [[ "$body" == " "* ]]; do body="${body# }"; done
        body="${body#\# }"
        local resource="${body%% will be *}"
        local action="${body#* will be }"
        entry=$((entry + 1))
        result+="entry${entry}.resource ${resource}"$'\n'
        result+="entry${entry}.action ${action}"$'\n'
    done <<< "$text"
    [[ $entry -gt 0 ]] && result+="total_entries ${entry}"$'\n'
    echo "$result"
}
