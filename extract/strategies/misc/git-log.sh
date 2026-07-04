#!/bin/bash
## Name: git-log
## Description: Extract fields from git log output (full and oneline formats)
## Version: 1.0
## Priority: 14
## Sample: samples/git-log/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Detect full git log format: "commit <40-char hex>"
    if [[ "$text" =~ ^commit\ [0-9a-f]{40} ]]; then
        return 0
    fi
    # Detect oneline format: "<7+ char hex> <message>"
    if [[ "$text" =~ ^[0-9a-f]{7,}\  ]]; then
        # Make sure at least 2 lines match to avoid false positives
        local match_count=0
        while IFS= read -r _line; do
            if [[ "$_line" =~ ^[0-9a-f]{7,}\  ]]; then
                match_count=$((match_count + 1))
            fi
            [[ $match_count -ge 2 ]] && return 0
        done <<< "$text"
    fi
    return 1
}

strategy_extract () {
    local text="$1"

    # Check if this is full format or oneline format
    if [[ "$text" =~ ^commit\ [0-9a-f]{40} ]]; then
        _strat_git_log_extract_full "$text"
    else
        _strat_git_log_extract_oneline "$text"
    fi
}

_strat_git_log_extract_full () {
    local text="$1"
    local result=""
    local commit_num=0
    local current_hash=""
    local current_author=""
    local current_date=""
    local current_message=""
    local in_message=0

    while IFS= read -r line; do
        if [[ "$line" =~ ^commit\ ([0-9a-f]{40}) ]]; then
            # Emit previous commit if we have one
            if [[ -n "$current_hash" ]]; then
                _strat_git_log_emit_commit "$commit_num" "$current_hash" "$current_author" "$current_date" "$current_message"
                result+="$_git_log_output"
            fi
            commit_num=$((commit_num + 1))
            current_hash="${BASH_REMATCH[1]}"
            current_author=""
            current_date=""
            current_message=""
            in_message=0
            continue
        fi

        if [[ "$line" == "Author: "* ]]; then
            current_author="${line#Author: }"
            while [[ "$current_author" == " "* ]]; do current_author="${current_author# }"; done
            current_author="${current_author// /_}"
            in_message=0
            continue
        fi

        if [[ "$line" == "Date: "* ]]; then
            current_date="${line#Date: }"
            while [[ "$current_date" == " "* ]]; do current_date="${current_date# }"; done
            current_date="${current_date// /_}"
            in_message=0
            continue
        fi

        # Blank line after Date: signals start of message
        if [[ -z "$line" && -n "$current_date" && -z "$current_message" ]]; then
            in_message=1
            continue
        fi

        # Capture first non-empty indented message line
        if [[ $in_message -eq 1 && -z "$current_message" ]]; then
            local trimmed="$line"
            while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
            if [[ -n "$trimmed" ]]; then
                current_message="${trimmed// /_}"
            fi
        fi
    done <<< "$text"

    # Emit last commit
    if [[ -n "$current_hash" ]]; then
        _strat_git_log_emit_commit "$commit_num" "$current_hash" "$current_author" "$current_date" "$current_message"
        result+="$_git_log_output"
    fi

    echo "$result"
}

# Helper to emit commit fields (uses global _git_log_output to avoid subshell)
_strat_git_log_emit_commit () {
    local num="$1" hash="$2" author="$3" date="$4" message="$5"
    local prefix="commit${num}"
    _git_log_output=""
    _git_log_output+="${prefix}.hash ${hash}"$'\n'
    if [[ -n "$author" ]]; then
        _git_log_output+="${prefix}.author ${author}"$'\n'
    fi
    if [[ -n "$date" ]]; then
        _git_log_output+="${prefix}.date ${date}"$'\n'
    fi
    if [[ -n "$message" ]]; then
        _git_log_output+="${prefix}.message ${message}"$'\n'
    fi
}

_strat_git_log_extract_oneline () {
    local text="$1"
    local result=""
    local commit_num=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if ! [[ "$line" =~ ^[0-9a-f]{7,}\  ]]; then
            continue
        fi
        commit_num=$((commit_num + 1))
        local prefix="commit${commit_num}"
        local hash="${line%% *}"
        local message="${line#* }"
        message="${message// /_}"
        result+="${prefix}.hash ${hash}"$'\n'
        result+="${prefix}.message ${message}"$'\n'
    done <<< "$text"

    echo "$result"
}
