#!/bin/bash
## Name: crontab
## Description: Extract fields from crontab entry listings
## Version: 1.0
## Priority: 22
## Sample: samples/crontab/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=80

    # Reject JSON
    _is_json "$text" && return 1

    # Must have comment lines (# prefix) typical of crontabs
    local _has_comments=0
    local _has_schedule=0
    local _has_shortcut=0

    local _nl=$'\n'
    # Cron schedule line: starts with digit or * followed by more schedule fields
    local _sched_re='(^|'"${_nl}"')[0-9*][0-9,/*-]* +[0-9*][0-9,/*-]* +[0-9*][0-9,/*-]* +[0-9*][0-9,/*-]* +[0-9*][0-9,/*-]* +'
    # Shortcut lines: @hourly, @daily, etc.
    local _short_re='(^|'"${_nl}"')@(hourly|daily|weekly|monthly|yearly|annually|reboot) '

    while IFS= read -r _line; do
        if [[ "$_line" == "#"* ]]; then
            _has_comments=1
        fi
    done <<< "$text"

    [[ "$text" =~ $_sched_re ]] && _has_schedule=1
    [[ "$text" =~ $_short_re ]] && _has_shortcut=1

    # Need comments AND (schedule lines or shortcut lines)
    if [[ $_has_comments -eq 1 ]]; then
        if [[ $_has_schedule -eq 1 ]] || [[ $_has_shortcut -eq 1 ]]; then
            return 0
        fi
    fi

    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local _job_num=0

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        # Skip comment lines
        [[ "$line" == "#"* ]] && continue

        # Environment variable assignments (KEY=value)
        if [[ "$line" =~ ^[A-Z_][A-Z0-9_]*= ]]; then
            local _key="${line%%=*}"
            local _val="${line#*=}"
            result+="${_key} ${_val}"$'\n'
            continue
        fi

        # Shortcut entries: @reboot, @daily, etc.
        local _short_re='^@(hourly|daily|weekly|monthly|yearly|annually|reboot)'
        if [[ "$line" =~ $_short_re ]]; then
            _job_num=$((_job_num + 1))
            local _shortcut="${BASH_REMATCH[1]}"
            local _cmd="${line#@"${_shortcut}"}"
            while [[ "$_cmd" == " "* ]]; do _cmd="${_cmd# }"; done

            # Expand shortcuts to schedule fields
            case "$_shortcut" in
                hourly)
                    result+="job${_job_num}.minute 0"$'\n'
                    result+="job${_job_num}.hour *"$'\n'
                    result+="job${_job_num}.day_of_month *"$'\n'
                    result+="job${_job_num}.month *"$'\n'
                    result+="job${_job_num}.day_of_week *"$'\n'
                    ;;
                daily)
                    result+="job${_job_num}.minute 0"$'\n'
                    result+="job${_job_num}.hour 0"$'\n'
                    result+="job${_job_num}.day_of_month *"$'\n'
                    result+="job${_job_num}.month *"$'\n'
                    result+="job${_job_num}.day_of_week *"$'\n'
                    ;;
                weekly)
                    result+="job${_job_num}.minute 0"$'\n'
                    result+="job${_job_num}.hour 0"$'\n'
                    result+="job${_job_num}.day_of_month *"$'\n'
                    result+="job${_job_num}.month *"$'\n'
                    result+="job${_job_num}.day_of_week 0"$'\n'
                    ;;
                monthly)
                    result+="job${_job_num}.minute 0"$'\n'
                    result+="job${_job_num}.hour 0"$'\n'
                    result+="job${_job_num}.day_of_month 1"$'\n'
                    result+="job${_job_num}.month *"$'\n'
                    result+="job${_job_num}.day_of_week *"$'\n'
                    ;;
                yearly|annually)
                    result+="job${_job_num}.minute 0"$'\n'
                    result+="job${_job_num}.hour 0"$'\n'
                    result+="job${_job_num}.day_of_month 1"$'\n'
                    result+="job${_job_num}.month 1"$'\n'
                    result+="job${_job_num}.day_of_week *"$'\n'
                    ;;
                reboot)
                    result+="job${_job_num}.schedule @reboot"$'\n'
                    ;;
            esac
            [[ -n "$_cmd" ]] && result+="job${_job_num}.command ${_cmd}"$'\n'
            continue
        fi

        # Standard cron schedule: min hour dom mon dow command
        local _cron_re='^([0-9*][0-9,/*-]*) +([0-9*][0-9,/*-]*) +([0-9*][0-9,/*-]*) +([0-9*][0-9,/*-]*) +([0-9*][0-9,/*-]*) +(.*)'
        if [[ "$line" =~ $_cron_re ]]; then
            _job_num=$((_job_num + 1))
            result+="job${_job_num}.minute ${BASH_REMATCH[1]}"$'\n'
            result+="job${_job_num}.hour ${BASH_REMATCH[2]}"$'\n'
            result+="job${_job_num}.day_of_month ${BASH_REMATCH[3]}"$'\n'
            result+="job${_job_num}.month ${BASH_REMATCH[4]}"$'\n'
            result+="job${_job_num}.day_of_week ${BASH_REMATCH[5]}"$'\n'
            local _cmd="${BASH_REMATCH[6]}"
            [[ -n "$_cmd" ]] && result+="job${_job_num}.command ${_cmd}"$'\n'
            continue
        fi
    done <<< "$text"

    echo "$result"
}
