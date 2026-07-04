#!/bin/bash
## Name: proc-meminfo
## Description: Extract memory statistics from /proc/meminfo format output
## Version: 1.0
## Priority: 40
## Sample: samples/proc-meminfo/basic.txt

strategy_detect () {
    local text="$1"
    _STRATEGY_CONFIDENCE=95
    local found_memtotal=0
    local found_memfree=0
    local kb_count=0
    while IFS= read -r line; do
        case "$line" in
            "MemTotal:"*) found_memtotal=1 ;;
            "MemFree:"*)  found_memfree=1 ;;
        esac
        # Count lines matching "FieldName:  N kB"
        if [[ "$line" == *" kB" ]]; then
            kb_count=$((kb_count + 1))
        fi
    done <<< "$text"
    if [[ $found_memtotal -eq 1 ]] && [[ $found_memfree -eq 1 ]] && [[ $kb_count -ge 2 ]]; then
        return 0
    fi
    return 1
}

strategy_extract () {
    local text="$1"
    local result=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        # Match pattern: "FieldName:   N kB" or "FieldName:   N"
        # Must have a colon
        [[ "$line" == *":"* ]] || continue

        # Extract key (before colon)
        local key="${line%%:*}"
        # Validate key: must be alphanumeric (with underscores/parens)
        case "$key" in
            *[!A-Za-z0-9_\(\)]*) continue ;;
        esac

        # Extract value part (after colon)
        local val_part="${line#*:}"
        # Strip leading whitespace
        while [[ "$val_part" == " "* ]]; do val_part="${val_part# }"; done
        while [[ "$val_part" == "	"* ]]; do val_part="${val_part#	}"; done

        # Strip " kB" suffix if present
        local value="$val_part"
        if [[ "$value" == *" kB" ]]; then
            value="${value% kB}"
        fi

        # Strip trailing whitespace
        while [[ "$value" == *" " ]]; do value="${value% }"; done

        # Convert CamelCase key to lowercase with underscores
        # MemTotal -> mem_total, MemFree -> mem_free, SwapCached -> swap_cached
        local out_key=""
        local i=0
        local prev_was_upper=0
        while [[ $i -lt ${#key} ]]; do
            local ch="${key:$i:1}"
            case "$ch" in
                [A-Z])
                    if [[ $i -gt 0 ]] && [[ $prev_was_upper -eq 0 ]]; then
                        out_key+="_"
                    fi
                    # Convert uppercase to lowercase
                    case "$ch" in
                        A) out_key+="a" ;; B) out_key+="b" ;; C) out_key+="c" ;;
                        D) out_key+="d" ;; E) out_key+="e" ;; F) out_key+="f" ;;
                        G) out_key+="g" ;; H) out_key+="h" ;; I) out_key+="i" ;;
                        J) out_key+="j" ;; K) out_key+="k" ;; L) out_key+="l" ;;
                        M) out_key+="m" ;; N) out_key+="n" ;; O) out_key+="o" ;;
                        P) out_key+="p" ;; Q) out_key+="q" ;; R) out_key+="r" ;;
                        S) out_key+="s" ;; T) out_key+="t" ;; U) out_key+="u" ;;
                        V) out_key+="v" ;; W) out_key+="w" ;; X) out_key+="x" ;;
                        Y) out_key+="y" ;; Z) out_key+="z" ;;
                    esac
                    prev_was_upper=1
                    ;;
                [a-z0-9_])
                    out_key+="$ch"
                    prev_was_upper=0
                    ;;
                "("|")")
                    # Skip parentheses
                    prev_was_upper=0
                    ;;
                *)
                    out_key+="$ch"
                    prev_was_upper=0
                    ;;
            esac
            i=$((i + 1))
        done

        [[ -n "$value" ]] && result+="${out_key} ${value}"$'\n'
    done <<< "$text"

    echo "$result"
}
