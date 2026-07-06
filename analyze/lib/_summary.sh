#!/bin/bash
################################################################################
## Summary/verdict output for envoy-analyze
##
## Synthesizes a natural-language summary from analysis results.
##
## Reads:  COL_NAMES COL_TYPE COL_MEAN COL_MISSING COL_COUNT ROW_COUNT
##         NUM_COL_NAMES
##         ITEM_TITLES ITEM_BODIES ITEM_TAGS ITEM_KINDS
##         _CORR_PAIR_LINES threshold_specs
## Writes: ITEM_TITLES ITEM_BODIES ITEM_TAGS ITEM_KINDS (via add_item)
################################################################################

run_summary_verdict () {
    local findings=()

    # 1. Dataset size
    findings+=("Dataset: ${ROW_COUNT} rows, ${COL_COUNT} columns")

    # 2. Column with lowest and highest mean
    if [[ ${#NUM_COL_NAMES[@]} -ge 2 ]]; then
        local lo_name="" lo_mean="" hi_name="" hi_mean=""
        local i
        for ((i=0; i<COL_COUNT; i++)); do
            [[ "${COL_TYPE[$i]}" != "numeric" ]] && continue
            local m="${COL_MEAN[$i]}"
            [[ -z "$m" || "$m" == "NA" ]] && continue
            if [[ -z "$lo_mean" ]] || float_cmp "$m" "<" "$lo_mean"; then
                lo_mean="$m"
                lo_name="${COL_NAMES[$i]}"
            fi
            if [[ -z "$hi_mean" ]] || float_cmp "$m" ">" "$hi_mean"; then
                hi_mean="$m"
                hi_name="${COL_NAMES[$i]}"
            fi
        done
        if [[ -n "$lo_name" && "$lo_name" != "$hi_name" ]]; then
            findings+=("Lowest mean: '$lo_name' ($lo_mean); Highest mean: '$hi_name' ($hi_mean)")
        fi
    fi

    # 3. Strongest correlation
    if [[ -n "${_CORR_PAIR_LINES:-}" ]]; then
        local best_pair
        best_pair=$(printf "%s" "$_CORR_PAIR_LINES" | sort -nr | awk 'NR==1')
        if [[ -n "$best_pair" ]]; then
            local _abs _r _a _b
            IFS=$'\t' read -r _abs _r _a _b <<< "$best_pair"
            findings+=("Strongest correlation: $_a vs $_b (r=$_r)")
        fi
    fi

    # 4. Count outliers from anomaly items
    local total_outliers=0
    local outlier_cols=""
    for ((i=0; i<${#ITEM_KINDS[@]}; i++)); do
        if [[ "${ITEM_KINDS[$i]}" == "anomaly" ]]; then
            local body="${ITEM_BODIES[$i]}"
            # Extract z-score count from "Z-score outliers (|z|>3): N"
            local zcount="0"
            local zline
            zline=$(echo "$body" | grep "Z-score outliers" || true)
            if [[ -n "$zline" ]]; then
                zcount=$(echo "$zline" | sed 's/.*): //' | tr -cd '0-9')
                [[ -z "$zcount" ]] && zcount=0
            fi
            if [[ "$zcount" -gt 0 ]]; then
                total_outliers=$((total_outliers + zcount))
                local cname="${ITEM_TITLES[$i]#Anomaly detection: }"
                outlier_cols+="$cname ($zcount), "
            fi
        fi
    done
    if [[ $total_outliers -gt 0 ]]; then
        findings+=("Outliers: $total_outliers z-score outlier(s) in ${outlier_cols%, }")
    fi

    # 5. Trend detection
    for ((i=0; i<${#ITEM_KINDS[@]}; i++)); do
        if [[ "${ITEM_KINDS[$i]}" == "trend" ]]; then
            local body="${ITEM_BODIES[$i]}"
            if [[ "$body" == *"strong trend"* ]]; then
                local cname="${ITEM_TITLES[$i]#Trend: }"
                local rho
                rho=$(echo "$body" | grep "Spearman rho" | sed 's/.*: //' || true)
                if [[ -n "$rho" ]]; then
                    local dir="increasing"
                    if float_cmp "$rho" "<" "0"; then
                        dir="decreasing"
                    fi
                    findings+=("Strong trend: '$cname' is $dir (rho=$rho)")
                fi
            fi
        fi
    done

    # 6. Quality score
    for ((i=0; i<${#ITEM_KINDS[@]}; i++)); do
        if [[ "${ITEM_KINDS[$i]}" == "quality_score" ]]; then
            local score_line
            score_line="${ITEM_BODIES[$i]%%$'\n'*}"
            findings+=("Quality: $score_line")
            break
        fi
    done

    # 7. Missing data
    local total_missing=0
    for ((i=0; i<COL_COUNT; i++)); do
        total_missing=$((total_missing + ${COL_MISSING[$i]:-0}))
    done
    if [[ $total_missing -gt 0 ]]; then
        findings+=("Missing data: $total_missing missing value(s) across dataset")
    fi

    # 8. Threshold results
    if [[ ${#threshold_specs[@]} -gt 0 ]]; then
        local tpass=0 tfail=0
        for ((i=0; i<${#ITEM_KINDS[@]}; i++)); do
            if [[ "${ITEM_KINDS[$i]}" == "threshold" ]]; then
                if [[ "${ITEM_TAGS[$i]}" == "GOOD" ]]; then
                    tpass=$((tpass + 1))
                else
                    tfail=$((tfail + 1))
                fi
            fi
        done
        if [[ $tfail -gt 0 ]]; then
            findings+=("Thresholds: $tfail of $((tpass+tfail)) check(s) FAILED")
        else
            findings+=("Thresholds: All $tpass check(s) passed")
        fi
    fi

    # Build body
    local body="Key findings:"
    local f
    for f in "${findings[@]}"; do
        body+=$'\n'"- $f"
    done

    add_item "Analysis summary" "$body" "GOOD" "verdict"
}
