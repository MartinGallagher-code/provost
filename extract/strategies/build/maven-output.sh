#!/bin/bash
## Name: maven-output
## Description: Extract build results from Maven output
## Version: 1.0
## Priority: 20
## Sample: samples/maven-output/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Note: cannot use _is_json -- maven output starts with [INFO] which triggers false positive
    # Instead check if it looks like actual JSON (starts with [ or { followed by JSON structure)
    local _first_char="${1:0:1}"
    if [[ "$_first_char" == "{" ]]; then
        return 1
    fi
    # [INFO] is not JSON even though it starts with [
    if [[ "$_first_char" == "[" ]]; then
        local _second="${1:1:4}"
        case "$_second" in
            "INFO"*|"WARN"*|"ERRO"*|"DEBU"*) ;;  # log prefix, not JSON
            *) return 1 ;;  # actual JSON array
        esac
    fi

    local has_build_result=0
    local has_maven_marker=0
    while IFS= read -r line; do
        case "$line" in
            *"BUILD SUCCESS"*) has_build_result=1 ;;
            *"BUILD FAILURE"*) has_build_result=1 ;;
        esac
        case "$line" in
            "[INFO] ---"*) has_maven_marker=1 ;;
            *":"*":"*":"*":"*) has_maven_marker=1 ;;  # groupId:artifactId:packaging:version pattern
        esac
        if [[ $has_build_result -eq 1 && $has_maven_marker -eq 1 ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # BUILD SUCCESS / BUILD FAILURE
        case "$line" in
            *"BUILD SUCCESS"*)
                result+="build.result SUCCESS"$'\n'
                ;;
            *"BUILD FAILURE"*)
                result+="build.result FAILURE"$'\n'
                ;;
        esac

        # Total time: 8.234 s
        case "$line" in
            *"Total time:"*)
                local rest="${line#*Total time:}"
                # Trim leading whitespace
                while [[ "$rest" == " "* ]]; do rest="${rest# }"; done
                # Replace spaces with underscores
                rest="${rest// /_}"
                result+="build.time ${rest}"$'\n'
                ;;
        esac

        # Final Memory: 42M/256M
        case "$line" in
            *"Final Memory:"*)
                local rest="${line#*Final Memory:}"
                while [[ "$rest" == " "* ]]; do rest="${rest# }"; done
                rest="${rest// /_}"
                result+="build.memory ${rest}"$'\n'
                ;;
        esac

        # Tests run: 42, Failures: 0, Errors: 0, Skipped: 2
        case "$line" in
            *"Tests run:"*)
                local rest="${line#*Tests run:}"
                while [[ "$rest" == " "* ]]; do rest="${rest# }"; done

                # Parse comma-separated values
                local remaining="$rest"
                while [[ -n "$remaining" ]]; do
                    local part="${remaining%%,*}"
                    if [[ "$part" == "$remaining" ]]; then
                        remaining=""
                    else
                        remaining="${remaining#*,}"
                        while [[ "$remaining" == " "* ]]; do remaining="${remaining# }"; done
                    fi
                    while [[ "$part" == " "* ]]; do part="${part# }"; done
                    while [[ "$part" == *" " ]]; do part="${part% }"; done

                    case "$part" in
                        [0-9]*)
                            # First number is tests run count
                            result+="tests.run ${part}"$'\n'
                            ;;
                        "Failures: "*)
                            local n="${part#Failures: }"
                            result+="tests.failures ${n}"$'\n'
                            ;;
                        "Errors: "*)
                            local n="${part#Errors: }"
                            result+="tests.errors ${n}"$'\n'
                            ;;
                        "Skipped: "*)
                            local n="${part#Skipped: }"
                            result+="tests.skipped ${n}"$'\n'
                            ;;
                    esac
                done
                ;;
        esac

        # Plugin line: --- maven-compiler-plugin:3.11.0:compile (default-compile) @ myproject ---
        case "$line" in
            *"--- "*" @ "*" ---"*)
                local rest="${line#*--- }"
                rest="${rest%% ---*}"
                # Extract artifact name after @
                local artifact="${rest##* @ }"
                while [[ "$artifact" == " "* ]]; do artifact="${artifact# }"; done
                while [[ "$artifact" == *" " ]]; do artifact="${artifact% }"; done
                # Only set once
                case "$result" in
                    *"artifact.name "*)  ;;  # already set
                    *) result+="artifact.name ${artifact}"$'\n' ;;
                esac
                ;;
        esac

        # Building jar: /path/to/project-1.0.0.jar
        case "$line" in
            *"Building jar:"*)
                local jar_path="${line#*Building jar:}"
                while [[ "$jar_path" == " "* ]]; do jar_path="${jar_path# }"; done
                # Extract version from jar filename (name-version.jar)
                local jar_name="${jar_path##*/}"
                jar_name="${jar_name%.jar}"
                # Last segment after - that starts with a digit
                local version=""
                local remaining_name="$jar_name"
                while [[ "$remaining_name" == *"-"* ]]; do
                    local suffix="${remaining_name##*-}"
                    case "$suffix" in
                        [0-9]*)
                            version="$suffix"
                            break
                            ;;
                    esac
                    remaining_name="${remaining_name%-*}"
                done
                if [[ -n "$version" ]]; then
                    result+="artifact.version ${version}"$'\n'
                fi
                ;;
        esac

    done <<< "$text"

    echo "$result"
}
