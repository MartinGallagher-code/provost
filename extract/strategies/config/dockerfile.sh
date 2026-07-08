#!/bin/bash
## Name: dockerfile
## Description: Extract instructions from Dockerfile
## Version: 1.0
## Priority: 15
## Sample: samples/dockerfile/basic.Dockerfile

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    # Reject JSON
    _is_json "$1" && return 1

    local has_from=0
    local instruction_count=0
    local _nl=$'\n'
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" ]] && continue
        case "$line" in
            "#"*) continue ;;
        esac
        # Check for FROM as first instruction keyword
        case "$line" in
            "FROM "*) has_from=1 ;;
        esac
        # Count other Dockerfile instructions
        case "$line" in
            "RUN "*|"COPY "*|"ADD "*|"CMD "*|"ENTRYPOINT "*|"ENV "*|"ARG "*|"EXPOSE "*|"WORKDIR "*|"LABEL "*|"VOLUME "*|"USER "*|"HEALTHCHECK "*)
                instruction_count=$((instruction_count + 1))
                ;;
        esac
    done <<< "$text"

    if [[ $has_from -eq 1 && $instruction_count -ge 1 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # First pass: join lines ending with backslash
    local joined=""
    local prev_line=""
    while IFS= read -r line; do
        if [[ -n "$prev_line" ]]; then
            # Check if prev_line ends with backslash
            if [[ "$prev_line" == *"\\" ]]; then
                # Remove trailing backslash and join
                prev_line="${prev_line%\\}"
                # Trim trailing whitespace from prev
                while [[ "$prev_line" == *" " ]]; do prev_line="${prev_line% }"; done
                # Trim leading whitespace from current line
                local trimmed="$line"
                while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done
                prev_line="${prev_line} ${trimmed}"
                continue
            else
                joined+="${prev_line}"$'\n'
            fi
        fi
        prev_line="$line"
    done <<< "$text"
    # Flush last line
    if [[ -n "$prev_line" ]]; then
        joined+="${prev_line}"$'\n'
    fi

    local stage_num=0
    local multi_stage=0

    # Count FROM lines to determine if multi-stage
    local from_count=0
    while IFS= read -r line; do
        case "$line" in
            "FROM "*) from_count=$((from_count + 1)) ;;
        esac
    done <<< "$joined"
    if [[ $from_count -gt 1 ]]; then
        multi_stage=1
    fi

    # Second pass: extract instructions
    stage_num=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        # Skip comments
        case "$line" in
            "#"*) continue ;;
        esac

        # Trim leading whitespace
        local trimmed="$line"
        while [[ "$trimmed" == " "* ]]; do trimmed="${trimmed# }"; done

        local prefix=""

        case "$trimmed" in
            "FROM "*)
                stage_num=$((stage_num + 1))
                if [[ $multi_stage -eq 1 ]]; then
                    prefix="stage${stage_num}."
                fi

                local rest="${trimmed#FROM }"
                # Check for AS clause
                local image=""
                local as_name=""
                case "$rest" in
                    *" AS "*)
                        image="${rest%% AS *}"
                        as_name="${rest##* AS }"
                        ;;
                    *" as "*)
                        image="${rest%% as *}"
                        as_name="${rest##* as }"
                        ;;
                    *)
                        image="$rest"
                        ;;
                esac
                result+="${prefix}from ${image}"$'\n'
                if [[ -n "$as_name" ]]; then
                    result+="${prefix}from.as ${as_name}"$'\n'
                fi
                ;;

            "ENV "*)
                if [[ $multi_stage -eq 1 ]]; then
                    prefix="stage${stage_num}."
                fi
                local rest="${trimmed#ENV }"
                # ENV key=value or ENV key value
                case "$rest" in
                    *"="*)
                        # Could be key=value, possibly multiple
                        local key="${rest%%=*}"
                        local val="${rest#*=}"
                        result+="${prefix}env.${key} ${val}"$'\n'
                        ;;
                    *)
                        # ENV key value
                        local key="${rest%% *}"
                        local val="${rest#* }"
                        result+="${prefix}env.${key} ${val}"$'\n'
                        ;;
                esac
                ;;

            "ARG "*)
                if [[ $multi_stage -eq 1 ]]; then
                    prefix="stage${stage_num}."
                fi
                local rest="${trimmed#ARG }"
                case "$rest" in
                    *"="*)
                        local key="${rest%%=*}"
                        local val="${rest#*=}"
                        result+="${prefix}arg.${key} ${val}"$'\n'
                        ;;
                    *)
                        result+="${prefix}arg.${rest} "
                        ;;
                esac
                ;;

            "EXPOSE "*)
                if [[ $multi_stage -eq 1 ]]; then
                    prefix="stage${stage_num}."
                fi
                local rest="${trimmed#EXPOSE }"
                result+="${prefix}expose ${rest}"$'\n'
                ;;

            "WORKDIR "*)
                if [[ $multi_stage -eq 1 ]]; then
                    prefix="stage${stage_num}."
                fi
                local rest="${trimmed#WORKDIR }"
                result+="${prefix}workdir ${rest}"$'\n'
                ;;

            "LABEL "*)
                if [[ $multi_stage -eq 1 ]]; then
                    prefix="stage${stage_num}."
                fi
                local rest="${trimmed#LABEL }"
                # LABEL key=value or LABEL key="value"
                local key="${rest%%=*}"
                local val="${rest#*=}"
                # Strip surrounding quotes from value
                case "$val" in
                    '"'*'"') val="${val#\"}"; val="${val%\"}" ;;
                    "'"*"'") val="${val#\'}"; val="${val%\'}" ;;
                esac
                result+="${prefix}label.${key} ${val}"$'\n'
                ;;

            "CMD "*)
                if [[ $multi_stage -eq 1 ]]; then
                    prefix="stage${stage_num}."
                fi
                local rest="${trimmed#CMD }"
                # Strip JSON array syntax: ["cmd", "arg1", "arg2"] -> cmd arg1 arg2
                case "$rest" in
                    "["*"]")
                        rest="${rest#\[}"
                        rest="${rest%\]}"
                        # Remove quotes and commas
                        local cleaned=""
                        local i
                        for ((i=0; i<${#rest}; i++)); do
                            local c="${rest:$i:1}"
                            case "$c" in
                                '"') ;; # skip quotes
                                ',') cleaned+=" " ;;
                                *) cleaned+="$c" ;;
                            esac
                        done
                        # Trim leading whitespace
                        while [[ "$cleaned" == " "* ]]; do cleaned="${cleaned# }"; done
                        # Collapse multiple spaces into single space
                        while [[ "$cleaned" == *"  "* ]]; do cleaned="${cleaned//  / }"; done
                        rest="$cleaned"
                        ;;
                esac
                result+="${prefix}cmd ${rest}"$'\n'
                ;;

            "ENTRYPOINT "*)
                if [[ $multi_stage -eq 1 ]]; then
                    prefix="stage${stage_num}."
                fi
                local rest="${trimmed#ENTRYPOINT }"
                # Strip JSON array syntax
                case "$rest" in
                    "["*"]")
                        rest="${rest#\[}"
                        rest="${rest%\]}"
                        local cleaned=""
                        local i
                        for ((i=0; i<${#rest}; i++)); do
                            local c="${rest:$i:1}"
                            case "$c" in
                                '"') ;;
                                ',') cleaned+=" " ;;
                                *) cleaned+="$c" ;;
                            esac
                        done
                        while [[ "$cleaned" == " "* ]]; do cleaned="${cleaned# }"; done
                        # Collapse multiple spaces into single space
                        while [[ "$cleaned" == *"  "* ]]; do cleaned="${cleaned//  / }"; done
                        rest="$cleaned"
                        ;;
                esac
                result+="${prefix}entrypoint ${rest}"$'\n'
                ;;

            # Skip RUN, COPY, ADD
        esac
    done <<< "$joined"

    echo "$result"
}
