#!/bin/bash
## Name: dmidecode
## Description: Extract BIOS, system, processor, and memory info from dmidecode output
## Version: 1.0
## Priority: 15
## Sample: samples/dmidecode/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=90
    _is_json "$1" && return 1
    if [[ "$text" == *"dmidecode"* ]]; then
        return 0
    fi
    if [[ "$text" == *"DMI type"* ]]; then
        return 0
    fi
    if [[ "$text" == *"BIOS Information"* ]] && [[ "$text" == *"System Information"* ]]; then
        return 0
    fi
    if [[ "$text" == *"Processor Information"* ]] && [[ "$text" == *"Memory Device"* ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""
    local current_section=""
    local mem_device_num=0
    local proc_num=0
    local total_mem_mb=0

    while IFS= read -r line; do
        # Section headers (non-indented, contain "Information" or "Device")
        if [[ "$line" == "BIOS Information" ]]; then
            current_section="bios"
            continue
        fi
        if [[ "$line" == "System Information" ]]; then
            current_section="system"
            continue
        fi
        if [[ "$line" == "Processor Information" ]]; then
            current_section="processor"
            proc_num=$((proc_num + 1))
            continue
        fi
        if [[ "$line" == "Memory Device" ]]; then
            current_section="memory"
            mem_device_num=$((mem_device_num + 1))
            continue
        fi
        # Other section headers reset context
        if [[ "$line" =~ ^[A-Z][a-zA-Z\ ]+(Information|Device|Table|Entry) ]] && \
           [[ "$line" != *":"* ]]; then
            current_section=""
            continue
        fi
        if [[ "$line" == "Handle "* ]]; then
            continue
        fi

        # Parse indented key: value lines
        if [[ "$line" =~ ^[[:space:]]+([^:]+):[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"
            while [[ "$key" == " "* ]]; do key="${key# }"; done
            while [[ "$key" == *" " ]]; do key="${key% }"; done
            while [[ "$val" == *" " ]]; do val="${val% }"; done

            case "$current_section" in
                bios)
                    case "$key" in
                        "Vendor") result+="bios_vendor ${val}"$'\n' ;;
                        "Version") result+="bios_version ${val}"$'\n' ;;
                        "Release Date") result+="bios_release_date ${val}"$'\n' ;;
                    esac
                    ;;
                system)
                    case "$key" in
                        "Manufacturer") result+="system_manufacturer ${val}"$'\n' ;;
                        "Product Name") result+="system_product ${val}"$'\n' ;;
                        "Serial Number") result+="system_serial ${val}"$'\n' ;;
                    esac
                    ;;
                processor)
                    local pprefix=""
                    if [[ $proc_num -gt 1 ]]; then
                        pprefix="processor${proc_num}."
                    else
                        pprefix="processor."
                    fi
                    case "$key" in
                        "Type") result+="${pprefix}type ${val}"$'\n' ;;
                        "Version") result+="${pprefix}version ${val}"$'\n' ;;
                        "Max Speed"|"Current Speed")
                            if [[ "$key" == "Max Speed" ]]; then
                                result+="${pprefix}max_speed ${val}"$'\n'
                            else
                                result+="${pprefix}current_speed ${val}"$'\n'
                            fi
                            ;;
                        "Core Count") result+="${pprefix}core_count ${val}"$'\n' ;;
                        "Thread Count") result+="${pprefix}thread_count ${val}"$'\n' ;;
                    esac
                    ;;
                memory)
                    local mprefix="memory${mem_device_num}."
                    case "$key" in
                        "Size")
                            result+="${mprefix}size ${val}"$'\n'
                            # Accumulate total memory
                            if [[ "$val" =~ ^([0-9]+)[[:space:]]*MB ]]; then
                                total_mem_mb=$((total_mem_mb + BASH_REMATCH[1]))
                            elif [[ "$val" =~ ^([0-9]+)[[:space:]]*GB ]]; then
                                total_mem_mb=$((total_mem_mb + BASH_REMATCH[1] * 1024))
                            fi
                            ;;
                        "Type") result+="${mprefix}type ${val}"$'\n' ;;
                        "Speed") result+="${mprefix}speed ${val}"$'\n' ;;
                        "Manufacturer") result+="${mprefix}manufacturer ${val}"$'\n' ;;
                        "Locator") result+="${mprefix}locator ${val}"$'\n' ;;
                    esac
                    ;;
            esac
        fi
    done <<< "$text"

    if [[ $total_mem_mb -gt 0 ]]; then
        result+="total_memory_MB ${total_mem_mb}"$'\n'
    fi
    result+="memory_device_count ${mem_device_num}"$'\n'
    result+="processor_count ${proc_num}"$'\n'

    echo "$result"
}
