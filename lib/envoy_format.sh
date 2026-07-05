#!/bin/bash
################################################################################
## Envoy Shared Output Formatters — envoy_format.sh
##
## Provides envoy_format_output() which converts "name value" lines on stdin
## to plain, JSON, CSV, or TSV output.
##
## Sourcing this file is OPTIONAL — every tool can still run standalone.
##
## Requires bash 4.0+.
##
## Usage:
##   source "$(dirname "$0")/../lib/envoy_format.sh"
##   printf 'host server-01\nstatus ok\n' | envoy_format_output json
##
################################################################################

# Guard against double-sourcing
[[ -n "${_ENVOY_FORMAT_LOADED:-}" ]] && return 0
_ENVOY_FORMAT_LOADED=1

################################################################################
## _envoy_json_escape
##
## Escapes a string for safe embedding in a JSON value.
## Handles: backslash, double-quote, tab, newline, carriage return.
##
## @param  $1  string  Input value
## @return void (prints escaped string to stdout)
################################################################################

_envoy_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    printf '%s' "$s"
}

################################################################################
## _envoy_csv_escape
##
## Escapes a field for CSV output (RFC 4180).  If the value contains a
## comma, double-quote, or newline, it is wrapped in double-quotes with
## internal double-quotes doubled.
##
## @param  $1  string  Input value
## @return void (prints escaped field to stdout)
################################################################################

_envoy_csv_escape() {
    local s="$1"
    # Check if quoting is needed: contains comma, double-quote, or newline
    case "$s" in
        *,* | *\"* | *$'\n'* | *$'\r'*)
            # Double any embedded quotes
            s="${s//\"/\"\"}"
            printf '"%s"' "$s"
            ;;
        *)
            printf '%s' "$s"
            ;;
    esac
}

################################################################################
## _envoy_tsv_escape
##
## Escapes a field for TSV output.  Replaces embedded tabs with spaces
## to prevent field corruption.
##
## @param  $1  string  Input value
## @return void (prints escaped field to stdout)
################################################################################

_envoy_tsv_escape() {
    local s="$1"
    # Replace tabs with spaces to prevent field corruption
    s="${s//$'\t'/ }"
    printf '%s' "$s"
}

################################################################################
## envoy_format_output
##
## Reads "name value" lines from stdin and writes the requested format to
## stdout.  The first whitespace-delimited token on each line is the field
## name; everything after is the value.
##
## @param  $1  string  Format: plain, json, csv, tsv
## @return void (output to stdout)
################################################################################

envoy_format_output() {
    local format="${1:-plain}"
    local line name value
    local first=1

    case "$format" in
        json)
            printf '{\n'
            while IFS= read -r line || [[ -n "$line" ]]; do
                [[ -z "$line" ]] && continue
                # Split on first whitespace: name is token 1, value is the rest
                name="${line%% *}"
                value="${line#* }"
                # Handle lines with no value (name only)
                [[ "$name" == "$value" ]] && value=""

                if [[ "$first" -eq 1 ]]; then
                    first=0
                else
                    printf ',\n'
                fi
                printf '  "%s": "%s"' "$(_envoy_json_escape "$name")" "$(_envoy_json_escape "$value")"
            done
            printf '\n}\n'
            ;;

        csv)
            # Header row
            printf 'name,value\n'
            while IFS= read -r line || [[ -n "$line" ]]; do
                [[ -z "$line" ]] && continue
                name="${line%% *}"
                value="${line#* }"
                [[ "$name" == "$value" ]] && value=""

                _envoy_csv_escape "$name"
                printf ','
                _envoy_csv_escape "$value"
                printf '\n'
            done
            ;;

        tsv)
            # Header row
            printf 'name\tvalue\n'
            while IFS= read -r line || [[ -n "$line" ]]; do
                [[ -z "$line" ]] && continue
                name="${line%% *}"
                value="${line#* }"
                [[ "$name" == "$value" ]] && value=""

                _envoy_tsv_escape "$name"
                printf '\t'
                _envoy_tsv_escape "$value"
                printf '\n'
            done
            ;;

        *)
            # plain: pass through as-is
            while IFS= read -r line || [[ -n "$line" ]]; do
                printf '%s\n' "$line"
            done
            ;;
    esac
}
