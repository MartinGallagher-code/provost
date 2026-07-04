#!/bin/bash
## Name: terraform-plan
## Description: Extract resource actions and summary from terraform plan output
## Version: 1.0
## Priority: 30
## Sample: samples/terraform-plan/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    local found=0
    while IFS= read -r line; do
        if [[ "$line" == *"Terraform will perform"* ]]; then
            found=1
            break
        fi
        if [[ "$line" == *"Plan:"*"to add"* ]]; then
            found=1
            break
        fi
    done <<< "$text"
    if [[ $found -eq 1 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local resource_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Plan summary line: "Plan: 1 to add, 1 to change, 1 to destroy."
        if [[ "$line" == *"Plan:"*"to add"* ]]; then
            # Extract "N to add"
            local _plan_re='Plan: '
            local remaining="${line#*Plan: }"
            # Parse "N to add, N to change, N to destroy."
            local _add _change _destroy
            # "1 to add, 1 to change, 1 to destroy."
            _add="${remaining%% to add*}"
            # Strip leading spaces
            while [[ "$_add" == " "* ]]; do _add="${_add# }"; done

            local after_add="${remaining#*to add}"
            # ", 1 to change, 1 to destroy."
            after_add="${after_add#, }"
            _change="${after_add%% to change*}"
            while [[ "$_change" == " "* ]]; do _change="${_change# }"; done

            local after_change="${after_add#*to change}"
            after_change="${after_change#, }"
            _destroy="${after_change%% to destroy*}"
            while [[ "$_destroy" == " "* ]]; do _destroy="${_destroy# }"; done
            # Strip trailing period
            _destroy="${_destroy%.}"

            [[ -n "$_add" ]] && result+="plan_add ${_add}"$'\n'
            [[ -n "$_change" ]] && result+="plan_change ${_change}"$'\n'
            [[ -n "$_destroy" ]] && result+="plan_destroy ${_destroy}"$'\n'
            continue
        fi

        # Resource action line: "  # aws_instance.web will be created"
        # or "  # aws_security_group.allow_http will be updated in-place"
        # or "  # aws_instance.old will be destroyed"
        if [[ "$line" == *"# "* ]] && [[ "$line" == *" will be "* ]]; then
            # Strip leading whitespace and "# "
            local stripped="$line"
            while [[ "$stripped" == " "* ]]; do stripped="${stripped# }"; done
            stripped="${stripped#\# }"

            # Extract resource name (everything before " will be ")
            local res_name="${stripped%% will be *}"
            # Extract action (everything after " will be ")
            local res_action="${stripped#*will be }"

            # Normalize action
            case "$res_action" in
                created*) res_action="create" ;;
                "updated in-place"*) res_action="update" ;;
                destroyed*) res_action="destroy" ;;
                "read during apply"*) res_action="read" ;;
                replaced*) res_action="replace" ;;
            esac

            resource_num=$((resource_num + 1))
            result+="resource${resource_num}_name ${res_name}"$'\n'
            result+="resource${resource_num}_action ${res_action}"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}
