#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Output formatting functions for envoy-extract
##
## Format extracted fields as JSON, CSV, TSV, plain, YAML, or XML.
## Dependencies: _helpers.sh (_parse_field_line, strip_strat_prefix)
################################################################################

# Display extracted fields as a numbered table.
# Uses a single column -t pass to avoid misalignment.
display () {
    local input="$1"

    # Combine header and data, then columnize in a single pass
    # Columns are TAB-separated: a value may carry spaces (the field stream's
    # name ends at the FIRST space), so whitespace columnising would shred it.
    local _numbered="" _n=0 _did _dfield
    while IFS= read -r _dline; do
        [[ -z "$_dline" ]] && continue
        _n=$((_n + 1))
        _did=""; _dfield="$_dline"
        if [[ "$_dline" == *$'\t'* ]]; then
            _did="${_dline%%$'\t'*}"; _dfield="${_dline#*$'\t'}"
        fi
        if [[ "$_dfield" == *" "* ]]; then
            _dfield="${_dfield%% *}"$'\t'"${_dfield#* }"
        fi
        _numbered+="${_n}"$'\t'"${_did}"$'\t'"${_dfield}"$'\n'
    done <<< "$input"
    local combined
    combined=$(printf "%s\n%s\n%s" \
        "#"$'\t'"ID"$'\t'"Name"$'\t'"Value" \
        "-"$'\t'"--"$'\t'"----"$'\t'"-----" \
        "${_numbered%$'\n'}")
    echo "$combined" | column -t -s $'\t'
}

# Escape a string for JSON output (handles all special characters).
# Result in _ESCAPED (no subshell needed).
_json_escape () {
    _ESCAPED="$1"
    _ESCAPED="${_ESCAPED//\\/\\\\}"      # backslash (must be first)
    _ESCAPED="${_ESCAPED//\"/\\\"}"      # double quote
    _ESCAPED="${_ESCAPED//$'\n'/\\n}"    # newline
    _ESCAPED="${_ESCAPED//$'\t'/\\t}"    # tab
    _ESCAPED="${_ESCAPED//$'\r'/\\r}"    # carriage return
    _ESCAPED="${_ESCAPED//$'\x08'/\\b}"  # backspace
    _ESCAPED="${_ESCAPED//$'\x0c'/\\f}"  # form feed
}

# Format extracted fields as JSON.
format_json () {
    local input="$1"
    local json="{"
    local first=1
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        _parse_field_line "$line"
        _json_escape "$_FIELD_NAME"; local name="$_ESCAPED"
        _json_escape "$_FIELD_VALUE"; local value="$_ESCAPED"
        if [[ $first -eq 1 ]]; then
            first=0
        else
            json+=", "
        fi
        json+="\"$name\": \"$value\""
    done <<< "$input"

    json+="}"
    echo "$json"
}

# Format extracted fields as CSV.
format_csv () {
    local input="$1"
    local names="" values=""
    local first=1
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        _parse_field_line "$line"
        local name="$_FIELD_NAME" value="$_FIELD_VALUE"
        # Escape double quotes in names and values
        name="${name//\"/\"\"}"
        value="${value//\"/\"\"}"
        if [[ $first -eq 1 ]]; then
            first=0
        else
            names+=","
            values+=","
        fi
        names+="\"$name\""
        values+="\"$value\""
    done <<< "$input"

    echo "$names"
    echo "$values"
}

# Format extracted fields as TSV (horizontal: header row + data row).
format_tsv () {
    local input="$1"
    # PERF: names/values collected in arrays and TAB-joined once (per-field
    # `names+=`/`values+=` re-copied both growing strings: quadratic).
    local _ft_all
    local -a _ft_names=() _ft_values=()
    if (( ${#input} > _FR_BIG_BYTES )); then
        # BIG: the same two rows from one awk pass (name = up to the first
        # space, value = after it; a space-less line is both, as in
        # _parse_field_line)
        printf '%s\n' "$input" | awk '
            $0 != "" { n++; L[n] = $0 }
            END {
                for (i = 1; i <= n; i++) {
                    p = index(L[i], " "); nm = p ? substr(L[i], 1, p - 1) : L[i]
                    gsub(/\t/, "_", nm)            # a tab in a NAME: sanitised
                    printf "%s%s", (i > 1 ? "\t" : ""), nm
                }
                printf "\n"
                for (i = 1; i <= n; i++) {
                    p = index(L[i], " "); v = p ? substr(L[i], p + 1) : L[i]
                    gsub(/\t/, " ", v)             # a tab in a VALUE: one space
                    printf "%s%s", (i > 1 ? "\t" : ""), v
                }
                printf "\n"
            }'
        line=""
        return 0
    fi
    mapfile -t _ft_all <<< "$input"
    for line in "${_ft_all[@]}"; do
        [[ -z "$line" ]] && continue
        _parse_field_line "$line"
        # A raw TAB inside a cell would shear the row (more fields than the
        # header) and the tidy melt would misattribute every later cell. In a
        # VALUE it becomes one space (values keep their spaces); a NAME is
        # sanitised like any other whitespace in a name, to `_`.
        _ft_names+=("${_FIELD_NAME//$'	'/_}")
        _ft_values+=("${_FIELD_VALUE//$'	'/ }")
    done
    line=""

    local IFS=$'\t'
    echo "${_ft_names[*]}"
    echo "${_ft_values[*]}"
}

# Format extracted fields as plain key-value pairs.
format_plain () {
    local input="$1"
    echo "$input"
}

# Escape a string for XML output (handles &, <, >, ", ').
# Result in _ESCAPED (no subshell needed).
_xml_escape () {
    _ESCAPED="$1"
    _ESCAPED="${_ESCAPED//&/\&amp;}"       # ampersand (must be first)
    _ESCAPED="${_ESCAPED//</\&lt;}"        # less-than
    _ESCAPED="${_ESCAPED//>/\&gt;}"        # greater-than
    _ESCAPED="${_ESCAPED//\"/\&quot;}"     # double quote
    _ESCAPED="${_ESCAPED//\'/\&apos;}"     # single quote
}

# Determine if a YAML value requires quoting.
# Sets $_YAML_NEEDS_QUOTE=1 if quoting is needed, 0 otherwise.
_yaml_needs_quote () {
    _YAML_NEEDS_QUOTE=0
    local value="$1"
    case "$value" in
        *':'*|*'#'*|*'{'*|*'}'*|*'['*|*']'*|*','*|*'&'*|*'*'*) _YAML_NEEDS_QUOTE=1; return ;;
        *'?'*|*'|'*|*'<'*|*'>'*|*'='*|*'!'*|*'%'*|*'@'*) _YAML_NEEDS_QUOTE=1; return ;;
        *'"'*|*"'"*|*'`'*) _YAML_NEEDS_QUOTE=1; return ;;
        true|false|null|yes|no|on|off) _YAML_NEEDS_QUOTE=1; return ;;
        True|False|Null|Yes|No|On|Off) _YAML_NEEDS_QUOTE=1; return ;;
        TRUE|FALSE|NULL|YES|NO|ON|OFF) _YAML_NEEDS_QUOTE=1; return ;;
        ''|' '*) _YAML_NEEDS_QUOTE=1; return ;;
    esac
    if [[ "$value" =~ ^[0-9] ]]; then _YAML_NEEDS_QUOTE=1; return; fi
    if [[ "$value" == *$'\n'* ]]; then _YAML_NEEDS_QUOTE=1; return; fi
}

# Format extracted fields as YAML key-value pairs.
format_yaml () {
    local input="$1"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        _parse_field_line "$line"
        local name="$_FIELD_NAME" value="$_FIELD_VALUE"
        _yaml_needs_quote "$value"
        if [[ $_YAML_NEEDS_QUOTE -eq 1 ]]; then
            value="${value//\\/\\\\}"
            value="${value//\"/\\\"}"
            value="${value//$'\n'/\\n}"
            value="${value//$'\r'/\\r}"
            value="${value//$'\t'/\\t}"
            printf '%s: "%s"\n' "$name" "$value"
        else
            printf '%s: %s\n' "$name" "$value"
        fi
    done <<< "$input"
}

# Format extracted fields as nested JSON using dot-separated keys.
# Input: "server.host localhost", "server.port 8080", "db.host dbserver"
# Output: {"server": {"host": "localhost", "port": "8080"}, "db": {"host": "dbserver"}}
# Uses awk for the nesting logic since pure bash tree construction would be complex.
format_json_nested () {
    local input="$1"
    local clean=""

    # Strip strat prefixes and build clean key/value lines
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        _parse_field_line "$line"
        clean+="${_FIELD_NAME}	${_FIELD_VALUE}"$'\n'
    done <<< "$input"
    clean="${clean%$'\n'}"

    printf '%s\n' "$clean" | awk -F'\t' '
    BEGIN {
        # Track all paths and their values
        n = 0
    }
    {
        key = $1
        val = $2
        # Escape JSON special chars in value
        gsub(/\\/, "\\\\", val)
        gsub(/"/, "\\\"", val)
        gsub(/\n/, "\\n", val)
        gsub(/\t/, "\\t", val)
        gsub(/\r/, "\\r", val)
        n++
        keys[n] = key
        vals[n] = val
    }
    END {
        # Collect all unique path prefixes and determine nesting
        # Strategy: build a sorted set of all paths, group by top-level key,
        # and output nested JSON

        # First pass: determine which keys are "nested" (contain dots)
        has_nested = 0
        for (i = 1; i <= n; i++) {
            if (index(keys[i], ".") > 0) has_nested = 1
        }

        if (!has_nested) {
            # No dots: output flat JSON (same as format_json)
            printf "{"
            for (i = 1; i <= n; i++) {
                if (i > 1) printf ", "
                printf "\"%s\": \"%s\"", keys[i], vals[i]
            }
            printf "}\n"
        } else {
            # Build nested structure
            # Track top-level keys in order
            top_count = 0
            delete top_keys
            delete top_seen

            for (i = 1; i <= n; i++) {
                dot = index(keys[i], ".")
                if (dot > 0) {
                    top = substr(keys[i], 1, dot - 1)
                } else {
                    top = keys[i]
                }
                if (!(top in top_seen)) {
                    top_count++
                    top_keys[top_count] = top
                    top_seen[top] = 1
                }
            }

            printf "{"
            for (t = 1; t <= top_count; t++) {
                top = top_keys[t]
                if (t > 1) printf ", "

                # Collect all entries for this top-level key
                sub_count = 0
                has_sub = 0
                delete sub_keys
                delete sub_vals

                for (i = 1; i <= n; i++) {
                    dot = index(keys[i], ".")
                    if (dot > 0) {
                        k_top = substr(keys[i], 1, dot - 1)
                        k_rest = substr(keys[i], dot + 1)
                    } else {
                        k_top = keys[i]
                        k_rest = ""
                    }
                    if (k_top == top) {
                        sub_count++
                        if (k_rest == "") {
                            sub_keys[sub_count] = ""
                            sub_vals[sub_count] = vals[i]
                        } else {
                            sub_keys[sub_count] = k_rest
                            sub_vals[sub_count] = vals[i]
                            has_sub = 1
                        }
                    }
                }

                if (has_sub) {
                    printf "\"%s\": {", top
                    first = 1
                    for (s = 1; s <= sub_count; s++) {
                        if (!first) printf ", "
                        first = 0
                        if (sub_keys[s] == "") {
                            printf "\"_value\": \"%s\"", sub_vals[s]
                        } else {
                            printf "\"%s\": \"%s\"", sub_keys[s], sub_vals[s]
                        }
                    }
                    printf "}"
                } else {
                    # Simple value, no nesting
                    printf "\"%s\": \"%s\"", top, sub_vals[1]
                }
            }
            printf "}\n"
        }
    }'
}

# Format extracted fields as XML.
format_xml () {
    local input="$1"
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<fields>'
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        _parse_field_line "$line"
        _xml_escape "$_FIELD_NAME"; local name="$_ESCAPED"
        _xml_escape "$_FIELD_VALUE"; local value="$_ESCAPED"
        echo "  <field name=\"$name\">$value</field>"
    done <<< "$input"
    echo '</fields>'
}
