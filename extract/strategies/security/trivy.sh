#!/bin/bash
## Name: trivy
## Description: Extract vulnerability scan results from Trivy output
## Version: 1.0
## Priority: 18
## Sample: samples/trivy/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=85
    # Reject JSON
    _is_json "$1" && return 1

    local has_total_severity=0
    local has_vuln_table=0
    while IFS= read -r line; do
        # Check for "Total: N (UNKNOWN: N, LOW: N, ..."
        case "$line" in
            *"Total:"*"CRITICAL"*|*"Total:"*"HIGH"*|*"Total:"*"MEDIUM"*|*"Total:"*"LOW"*)
                has_total_severity=1
                ;;
        esac
        # Check for table headers or severity markers in table rows
        case "$line" in
            *"Library"*"Vulnerability"*|*"Vulnerability"*"Severity"*)
                has_vuln_table=1
                ;;
            *"CRITICAL"*"CVE-"*|*"HIGH"*"CVE-"*|*"MEDIUM"*"CVE-"*|*"LOW"*"CVE-"*)
                has_vuln_table=1
                ;;
        esac
        if [[ $has_total_severity -eq 1 && $has_vuln_table -eq 1 ]]; then
            return 0
        fi
    done <<< "$text"
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    # Parse Total line: "Total: 5 (UNKNOWN: 0, LOW: 1, MEDIUM: 2, HIGH: 1, CRITICAL: 1)"
    while IFS= read -r line; do
        case "$line" in
            *"Total:"*)
                local rest="${line#*Total:}"
                while [[ "$rest" == " "* ]]; do rest="${rest# }"; done
                # Extract total count (first number before parenthesis)
                local total="${rest%%(*}"
                while [[ "$total" == *" " ]]; do total="${total% }"; done
                result+="total ${total}"$'\n'

                # Extract severity counts from parenthesized section
                local paren="${rest#*(}"
                paren="${paren%)}"

                local remaining="$paren"
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
                        "CRITICAL: "*)
                            local n="${part#CRITICAL: }"
                            result+="critical ${n}"$'\n'
                            ;;
                        "HIGH: "*)
                            local n="${part#HIGH: }"
                            result+="high ${n}"$'\n'
                            ;;
                        "MEDIUM: "*)
                            local n="${part#MEDIUM: }"
                            result+="medium ${n}"$'\n'
                            ;;
                        "LOW: "*)
                            local n="${part#LOW: }"
                            result+="low ${n}"$'\n'
                            ;;
                        "UNKNOWN: "*)
                            local n="${part#UNKNOWN: }"
                            result+="unknown ${n}"$'\n'
                            ;;
                    esac
                done
                ;;
        esac
    done <<< "$text"

    # Parse vulnerability table rows
    # Look for lines containing CVE IDs and severity levels
    # Table format uses box-drawing or pipe characters as separators
    local vuln_num=0
    local prev_library=""

    while IFS= read -r line; do
        # Skip border/header lines
        case "$line" in
            *"Library"*"Vulnerability"*) continue ;;
        esac
        # Skip lines with box-drawing horizontal bars
        case "$line" in
            *"─"*|*"━"*|*"═"*|*"┌"*|*"┐"*|*"└"*|*"┘"*|*"├"*|*"┤"*) continue ;;
        esac

        # Check if line contains a CVE identifier
        case "$line" in
            *"CVE-"*)
                vuln_num=$((vuln_num + 1))

                # Replace box-drawing vertical bars (│ = E2 94 82) with ASCII pipe
                # Use grep/sed alternative: manually replace the UTF-8 sequence
                local cleaned="$line"
                cleaned="${cleaned//│/|}"

                # Split on | and extract fields, skipping empty leading fields
                local remaining="$cleaned"
                local col=0
                local library="" cve="" severity="" installed="" fixed=""

                while [[ "$remaining" == *"|"* ]]; do
                    local field="${remaining%%|*}"
                    remaining="${remaining#*|}"

                    # Trim whitespace
                    while [[ "$field" == " "* ]]; do field="${field# }"; done
                    while [[ "$field" == *" " ]]; do field="${field% }"; done

                    # Skip empty fields (leading/trailing separators)
                    if [[ -z "$field" ]]; then
                        continue
                    fi

                    col=$((col + 1))
                    case $col in
                        1) library="$field" ;;
                        2) cve="$field" ;;
                        3) severity="$field" ;;
                        4) installed="$field" ;;
                        5) fixed="$field" ;;
                    esac
                done

                # If library is empty, use previous (multi-line vuln for same lib)
                if [[ -z "$library" && -n "$prev_library" ]]; then
                    library="$prev_library"
                fi
                if [[ -n "$library" ]]; then
                    prev_library="$library"
                fi

                # Only emit if we have a CVE
                if [[ -n "$cve" ]]; then
                    result+="vuln${vuln_num}.id ${cve}"$'\n'
                    if [[ -n "$severity" ]]; then
                        result+="vuln${vuln_num}.severity ${severity}"$'\n'
                    fi
                    if [[ -n "$library" ]]; then
                        result+="vuln${vuln_num}.package ${library}"$'\n'
                    fi
                    if [[ -n "$installed" ]]; then
                        result+="vuln${vuln_num}.installed_version ${installed}"$'\n'
                    fi
                    if [[ -n "$fixed" ]]; then
                        result+="vuln${vuln_num}.fixed_version ${fixed}"$'\n'
                    fi
                fi
                ;;
        esac
    done <<< "$text"

    echo "$result"
}
