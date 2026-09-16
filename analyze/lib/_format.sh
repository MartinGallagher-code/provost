#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Output formatting for envoy-analyze
##
## Renders analysis items in plain, JSON, CSV, or TSV format.
##
## Reads:  ITEM_TITLES ITEM_BODIES ITEM_TAGS ITEM_KINDS output_format
##         COLOR_ENABLED VERSION
## Writes: (none — pure output)
################################################################################

# ENV-065: isolated helper — only call when COLOR_ENABLED=1 and format=plain.
_colorize_tag () {
    local tag="$1"
    local c=""
    case "$tag" in
        GOOD)       c='\033[32m' ;;  # green
        ADVANCED)   c='\033[36m' ;;  # cyan
        DIAGNOSTIC) c='\033[33m' ;;  # yellow
        NOISY)      c='\033[90m' ;;  # bright black (grey)
        *)          printf '%s' "$tag"; return ;;
    esac
    printf '%b%s\033[0m' "$c" "$tag"
}

format_output () {
    local -a selected=("$@")
    local item_count=${#ITEM_TITLES[@]}

    case "$output_format" in
        plain)
            for id in "${selected[@]}"; do
                if ! [[ "$id" =~ ^[0-9]+$ ]]; then
                    echo "Skipping invalid selection: $id" >&2
                    continue
                fi
                if (( id < 1 || id > item_count )); then
                    echo "Skipping out-of-range selection: $id" >&2
                    continue
                fi
                local idx=$((id-1))
                local title="${ITEM_TITLES[$idx]}"
                local body="${ITEM_BODIES[$idx]}"
                local tag="${ITEM_TAGS[$idx]}"

                local tag_display="$tag"
                if [[ "${COLOR_ENABLED:-0}" -eq 1 ]]; then
                    tag_display="$(_colorize_tag "$tag")"
                fi
                printf "%d. [%s] %s\n" "$id" "$tag_display" "$title"
                if [[ -n "$body" ]]; then
                    printf "%s\n" "$body" | sed 's/^/   /'
                fi
                printf "\n"
            done
            ;;
        json)
            # ENV-064: stable envelope. schema_version is additive-evolution
            # only — new optional fields can be added without a bump; removing
            # or retyping fields bumps to 2.0. See docs/json-schema.md.
            printf '{"schema_version":"1.0","envoy_analyze_version":"%s","items":[' "${VERSION:-unknown}"
            local first=1
            for id in "${selected[@]}"; do
                if ! [[ "$id" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                if (( id < 1 || id > item_count )); then
                    continue
                fi
                local idx=$((id-1))
                local title body tag kind
                title=$(json_escape "${ITEM_TITLES[$idx]}")
                body=$(json_escape "${ITEM_BODIES[$idx]}")
                tag=$(json_escape "${ITEM_TAGS[$idx]}")
                kind=$(json_escape "${ITEM_KINDS[$idx]:-generic}")
                if [[ $first -eq 0 ]]; then
                    printf ","
                fi
                printf '{"id":%d,"tag":"%s","kind":"%s","title":"%s","body":"%s"}' "$id" "$tag" "$kind" "$title" "$body"
                first=0
            done
            printf ']}\n'
            ;;
        csv)
            printf "id,tag,title,body\n"
            for id in "${selected[@]}"; do
                if ! [[ "$id" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                if (( id < 1 || id > item_count )); then
                    continue
                fi
                local idx=$((id-1))
                printf "%s,%s,%s,%s\n" "$id" "$(escape_csv "${ITEM_TAGS[$idx]}")" "$(escape_csv "${ITEM_TITLES[$idx]}")" "$(escape_csv "${ITEM_BODIES[$idx]}")"
            done
            ;;
        tsv)
            printf "id\ttag\ttitle\tbody\n"
            for id in "${selected[@]}"; do
                if ! [[ "$id" =~ ^[0-9]+$ ]]; then
                    continue
                fi
                if (( id < 1 || id > item_count )); then
                    continue
                fi
                local idx=$((id-1))
                printf "%s\t%s\t%s\t%s\n" "$id" "$(escape_tsv "${ITEM_TAGS[$idx]}")" "$(escape_tsv "${ITEM_TITLES[$idx]}")" "$(escape_tsv "${ITEM_BODIES[$idx]}")"
            done
            ;;
        markdown)
            for id in "${selected[@]}"; do
                if ! [[ "$id" =~ ^[0-9]+$ ]]; then
                    echo "Skipping invalid selection: $id" >&2
                    continue
                fi
                if (( id < 1 || id > item_count )); then
                    echo "Skipping out-of-range selection: $id" >&2
                    continue
                fi
                local idx=$((id-1))
                local title="${ITEM_TITLES[$idx]}"
                local body="${ITEM_BODIES[$idx]}"
                local tag="${ITEM_TAGS[$idx]}"

                printf "## %d. [%s] %s\n\n" "$id" "$tag" "$title"
                if [[ -n "$body" ]]; then
                    # Check if body looks tabular (contains tab-separated lines)
                    if [[ "${body%%$'\n'*}" == *$'\t'* ]]; then
                        # Render as markdown table
                        local first_line=1
                        while IFS= read -r line; do
                            local md_line
                            md_line="| $(echo "$line" | sed 's/\t/ | /g') |"
                            printf "%s\n" "$md_line"
                            if [[ $first_line -eq 1 ]]; then
                                local col_count
                                col_count=$(echo "$line" | awk -F'\t' '{print NF}')
                                local sep="|"
                                local c
                                for ((c=0; c<col_count; c++)); do
                                    sep+=" --- |"
                                done
                                printf "%s\n" "$sep"
                                first_line=0
                            fi
                        done <<< "$body"
                    else
                        printf "%s\n" "$body"
                    fi
                fi
                printf "\n"
            done
            ;;
        html)
            _format_html_output "${selected[@]}"
            ;;
        *)
            err "Unknown output format: $output_format"
            ;;
    esac
}

html_escape () {
    local s="$1"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    printf '%s' "$s"
}

# Generate an inline SVG sparkline bar chart from a body that contains
# numeric distribution data (histogram-style lines like "  [0.0, 5.0)  ████ 12").
# Falls back gracefully if no histogram data found.
_html_sparkline_svg () {
    local body="$1"
    local vals=()
    local max_val=0
    # Extract histogram bucket counts from lines like "Bin N (range): COUNT ####"
    while IFS= read -r line; do
        local count=""
        # Match "): COUNT #" pattern from histogram bins
        count=$(echo "$line" | sed -n 's/.*): *\([0-9][0-9]*\) *#.*/\1/p' || true)
        if [[ -n "$count" && "$count" =~ ^[0-9]+$ ]]; then
            vals+=("$count")
            if (( count > max_val )); then
                max_val=$count
            fi
        fi
    done <<< "$body"

    if [[ ${#vals[@]} -eq 0 || $max_val -eq 0 ]]; then
        return 1
    fi

    local svg_w=$(( ${#vals[@]} * 8 ))
    if (( svg_w < 40 )); then svg_w=40; fi
    if (( svg_w > 200 )); then svg_w=200; fi
    local svg_h=50
    local bar_w=$(( svg_w / ${#vals[@]} ))
    if (( bar_w < 4 )); then bar_w=4; fi

    printf '<svg width="%d" height="%d" xmlns="http://www.w3.org/2000/svg" style="vertical-align:middle">' "$svg_w" "$svg_h"
    local i
    for ((i=0; i<${#vals[@]}; i++)); do
        local v="${vals[$i]}"
        local bar_h=$(( v * (svg_h - 2) / max_val ))
        if (( bar_h < 1 && v > 0 )); then bar_h=1; fi
        local x=$(( i * bar_w ))
        local y=$(( svg_h - bar_h ))
        printf '<rect x="%d" y="%d" width="%d" height="%d" fill="#4a90d9" rx="1"/>' "$x" "$y" "$((bar_w - 1))" "$bar_h"
    done
    printf '</svg>'
    return 0
}

_format_html_output () {
    local -a selected=("$@")
    local item_count=${#ITEM_TITLES[@]}
    local title_text="EnvoyAnalyze Report"

    # HTML document header
    cat <<'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>EnvoyAnalyze Report</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    background: #f8f9fa; color: #212529; line-height: 1.5; padding: 2rem;
    max-width: 960px; margin: 0 auto;
  }
  h1 { font-size: 1.6rem; margin-bottom: 0.5rem; color: #1a1a2e; }
  h2 { font-size: 1.15rem; margin: 1.5rem 0 0.5rem; color: #2c3e50; border-bottom: 1px solid #dee2e6; padding-bottom: 0.25rem; }
  .tag { display: inline-block; font-size: 0.75rem; font-weight: 600; padding: 0.1rem 0.5rem; border-radius: 3px; margin-right: 0.5rem; vertical-align: middle; }
  .tag-GOOD { background: #d4edda; color: #155724; }
  .tag-ADVANCED { background: #d1ecf1; color: #0c5460; }
  .tag-DIAGNOSTIC { background: #fff3cd; color: #856404; }
  .tag-NOISY { background: #e2e3e5; color: #6c757d; }
  .item { background: #fff; border: 1px solid #dee2e6; border-radius: 6px; padding: 1rem 1.2rem; margin-bottom: 1rem; }
  .item-header { font-weight: 600; margin-bottom: 0.5rem; }
  .item-body { white-space: pre-wrap; font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace; font-size: 0.85rem; color: #495057; }
  table.data { border-collapse: collapse; width: 100%; margin: 0.5rem 0; font-size: 0.85rem; }
  table.data th, table.data td { border: 1px solid #dee2e6; padding: 0.3rem 0.6rem; text-align: left; }
  table.data th { background: #e9ecef; font-weight: 600; }
  .anomaly { color: #dc3545; font-weight: 600; }
  .correlation-strong { color: #28a745; font-weight: 600; }
  .sparkline { margin: 0.25rem 0; }
  .summary-stats { background: #e9ecef; border-radius: 4px; padding: 0.75rem 1rem; margin-bottom: 1rem; font-size: 0.9rem; }
  .footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #dee2e6; color: #6c757d; font-size: 0.8rem; }
</style>
</head>
<body>
HTMLHEAD

    printf '<h1>EnvoyAnalyze Report</h1>\n'

    # Summary statistics section
    local total_items=${#selected[@]}
    local good_count=0
    local advanced_count=0
    local noisy_count=0
    local diag_count=0
    for id in "${selected[@]}"; do
        if ! [[ "$id" =~ ^[0-9]+$ ]]; then continue; fi
        if (( id < 1 || id > item_count )); then continue; fi
        local idx=$((id-1))
        case "${ITEM_TAGS[$idx]}" in
            GOOD) good_count=$((good_count+1)) ;;
            ADVANCED) advanced_count=$((advanced_count+1)) ;;
            NOISY) noisy_count=$((noisy_count+1)) ;;
            DIAGNOSTIC) diag_count=$((diag_count+1)) ;;
        esac
    done

    printf '<div class="summary-stats">\n'
    printf '<strong>Summary:</strong> %d items' "$total_items"
    if (( good_count > 0 )); then printf ' &mdash; <span class="tag tag-GOOD">GOOD: %d</span>' "$good_count"; fi
    if (( advanced_count > 0 )); then printf ' <span class="tag tag-ADVANCED">ADVANCED: %d</span>' "$advanced_count"; fi
    if (( noisy_count > 0 )); then printf ' <span class="tag tag-NOISY">NOISY: %d</span>' "$noisy_count"; fi
    if (( diag_count > 0 )); then printf ' <span class="tag tag-DIAGNOSTIC">DIAGNOSTIC: %d</span>' "$diag_count"; fi
    printf '\n</div>\n'

    # Each analysis item
    for id in "${selected[@]}"; do
        if ! [[ "$id" =~ ^[0-9]+$ ]]; then continue; fi
        if (( id < 1 || id > item_count )); then continue; fi
        local idx=$((id-1))
        local title="${ITEM_TITLES[$idx]}"
        local body="${ITEM_BODIES[$idx]}"
        local tag="${ITEM_TAGS[$idx]}"
        local kind="${ITEM_KINDS[$idx]}"

        local escaped_title
        escaped_title=$(html_escape "$title")

        printf '<div class="item">\n'
        printf '<h2><span class="tag tag-%s">%s</span> %d. %s</h2>\n' "$tag" "$tag" "$id" "$escaped_title"

        if [[ -n "$body" ]]; then
            # Check if body is tabular (tab-separated)
            if [[ "${body%%$'\n'*}" == *$'\t'* ]]; then
                printf '<table class="data">\n'
                local first_line=1
                while IFS= read -r line; do
                    if [[ $first_line -eq 1 ]]; then
                        printf '<tr>'
                        while IFS=$'\t' read -r cell; do
                            local ecell
                            ecell=$(html_escape "$cell")
                            printf '<th>%s</th>' "$ecell"
                        done <<< "$(echo "$line" | tr '\t' '\n')"
                        printf '</tr>\n'
                        first_line=0
                    else
                        printf '<tr>'
                        while IFS=$'\t' read -r cell; do
                            local ecell
                            ecell=$(html_escape "$cell")
                            # Color-code anomaly items
                            if [[ "$kind" == "anomaly" ]] && echo "$cell" | grep -qiE 'outlier|anomal'; then
                                printf '<td class="anomaly">%s</td>' "$ecell"
                            else
                                printf '<td>%s</td>' "$ecell"
                            fi
                        done <<< "$(echo "$line" | tr '\t' '\n')"
                        printf '</tr>\n'
                    fi
                done <<< "$body"
                printf '</table>\n'
            else
                # Non-tabular body: render as pre-formatted text
                # Apply color coding for correlations and anomalies
                local escaped_body
                escaped_body=$(html_escape "$body")

                # Color strong correlations (r >= 0.70)
                if [[ "$kind" == "corr_pairs" ]]; then
                    escaped_body=$(echo "$escaped_body" | sed -E 's/(r=0\.[7-9][0-9])/<span class="correlation-strong">\1<\/span>/g; s/(r=1\.00)/<span class="correlation-strong">\1<\/span>/g; s/(r=-0\.[7-9][0-9])/<span class="correlation-strong">\1<\/span>/g; s/(r=-1\.00)/<span class="correlation-strong">\1<\/span>/g')
                fi

                # Color anomaly markers
                if [[ "$kind" == "anomaly" ]]; then
                    escaped_body=$(echo "$escaped_body" | sed -E 's/(outlier[s]?)/<span class="anomaly">\1<\/span>/gi')
                fi

                printf '<div class="item-body">%s</div>\n' "$escaped_body"

                # Add sparkline SVG for histogram/sparkline kinds
                if [[ "$kind" == "histogram" || "$kind" == "sparkline" ]]; then
                    local svg=""
                    svg=$(_html_sparkline_svg "$body" 2>/dev/null) || true
                    if [[ -n "$svg" ]]; then
                        printf '<div class="sparkline">%s</div>\n' "$svg"
                    fi
                fi
            fi
        fi

        printf '</div>\n'
    done

    # Footer
    printf '<div class="footer">Generated by EnvoyAnalyze v%s &mdash; %s</div>\n' "$VERSION" "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '</body>\n</html>\n'
}
