#!/bin/bash
## Name: gradle-output
## Description: Extract build results from Gradle output
## Version: 1.0
## Priority: 20
## Sample: samples/gradle-output/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Reject JSON
    _is_json "$1" && return 1

    local has_build_result=0
    local has_task_marker=0
    while IFS= read -r line; do
        case "$line" in
            "BUILD SUCCESSFUL"*|"BUILD FAILED"*) has_build_result=1 ;;
            "> Task :"*) has_task_marker=1 ;;
            *"actionable task"*) has_task_marker=1 ;;
            *"Execution optimizations"*) has_task_marker=1 ;;
        esac
        if [[ $has_build_result -eq 1 && $has_task_marker -eq 1 ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    local task_num=0
    local tasks_up_to_date=0
    local tasks_executed=0
    local tasks_from_cache=0
    local tasks_no_source=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Task lines: "> Task :name STATUS"
        case "$line" in
            "> Task :"*)
                task_num=$((task_num + 1))
                local rest="${line#> Task :}"
                local task_name=""
                local task_status="EXECUTED"

                # Check for status suffix (UP-TO-DATE, FROM-CACHE, NO-SOURCE)
                case "$rest" in
                    *" UP-TO-DATE")
                        task_name="${rest% UP-TO-DATE}"
                        task_status="UP-TO-DATE"
                        tasks_up_to_date=$((tasks_up_to_date + 1))
                        ;;
                    *" FROM-CACHE")
                        task_name="${rest% FROM-CACHE}"
                        task_status="FROM-CACHE"
                        tasks_from_cache=$((tasks_from_cache + 1))
                        ;;
                    *" NO-SOURCE")
                        task_name="${rest% NO-SOURCE}"
                        task_status="NO-SOURCE"
                        tasks_no_source=$((tasks_no_source + 1))
                        ;;
                    *)
                        task_name="$rest"
                        task_status="EXECUTED"
                        tasks_executed=$((tasks_executed + 1))
                        ;;
                esac

                result+="task${task_num}.name ${task_name}"$'\n'
                result+="task${task_num}.status ${task_status}"$'\n'
                ;;
        esac

        # BUILD SUCCESSFUL in 12s / BUILD FAILED in 5s
        case "$line" in
            "BUILD SUCCESSFUL"*)
                result+="build.result SUCCESS"$'\n'
                local rest="${line#BUILD SUCCESSFUL in }"
                if [[ "$rest" != "$line" ]]; then
                    result+="build.time ${rest}"$'\n'
                fi
                ;;
            "BUILD FAILED"*)
                result+="build.result FAILED"$'\n'
                local rest="${line#BUILD FAILED in }"
                if [[ "$rest" != "$line" ]]; then
                    result+="build.time ${rest}"$'\n'
                fi
                ;;
        esac

        # Summary: "9 actionable tasks: 3 executed, 6 up-to-date"
        case "$line" in
            *"actionable task"*)
                # Extract total from "N actionable"
                local total="${line%% actionable*}"
                while [[ "$total" == " "* ]]; do total="${total# }"; done
                result+="tasks.total ${total}"$'\n'

                # Parse after colon
                local after_colon="${line#*: }"
                if [[ "$after_colon" != "$line" ]]; then
                    # Split on comma
                    local remaining="$after_colon"
                    while [[ -n "$remaining" ]]; do
                        local part="${remaining%%,*}"
                        if [[ "$part" == "$remaining" ]]; then
                            remaining=""
                        else
                            remaining="${remaining#*,}"
                            while [[ "$remaining" == " "* ]]; do remaining="${remaining# }"; done
                        fi
                        # Trim
                        while [[ "$part" == " "* ]]; do part="${part# }"; done
                        while [[ "$part" == *" " ]]; do part="${part% }"; done

                        case "$part" in
                            *" executed"*)
                                local n="${part%% executed*}"
                                result+="tasks.executed ${n}"$'\n'
                                ;;
                            *" up-to-date"*)
                                local n="${part%% up-to-date*}"
                                result+="tasks.up_to_date ${n}"$'\n'
                                ;;
                            *" from-cache"*)
                                local n="${part%% from-cache*}"
                                result+="tasks.from_cache ${n}"$'\n'
                                ;;
                        esac
                    done
                fi
                ;;
        esac

    done <<< "$text"

    echo "$result"
}
