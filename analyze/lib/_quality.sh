#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Data quality and diagnostic analyses for envoy-analyze
##
## Analyses: zero-variance columns, data quality score, suggested drops,
## noisy items (duplicates, sample rows, row lengths, common chars).
##
## Reads:  input_file delim COL_COUNT COL_NAMES COL_TYPE
##         COL_STD COL_MIN COL_MAX COL_MISSING ROW_COUNT
##         CORR_VALUES corr_cols corr_names
## Writes: dup_count
##         ITEM_TITLES ITEM_BODIES ITEM_TAGS ITEM_KINDS (via add_item)
################################################################################

run_zero_variance () {
    local zero_body=""
    local i
    for ((i=1; i<=COL_COUNT; i++)); do
        if [[ "${COL_TYPE[$((i-1))]}" != "numeric" ]]; then
            continue
        fi
        local std="${COL_STD[$((i-1))]}"
        local min="${COL_MIN[$((i-1))]}"
        local max="${COL_MAX[$((i-1))]}"
        if [[ -n "$std" ]] && float_cmp "$std" "==" "0"; then
            zero_body+="${COL_NAMES[$((i-1))]}: std=0, min=$min, max=$max"$'\n'
        fi
    done

    if [[ -n "$zero_body" ]]; then
        add_item "Zero-variance numeric columns" "${zero_body%$'\n'}" "DIAGNOSTIC" "zero_variance"
    fi
}

run_quality_score () {
    # Pre-compute dup_count (also used by noisy items)
    dup_count=$(awk 'NR>1{if(seen[$0]++) dup++} END{print dup+0}' "$input_file")

    local quality_score=100
    local quality_issues=""

    # Missing data penalty
    local total_cells=$((ROW_COUNT * COL_COUNT))
    local total_missing=0
    local i
    for ((i=0; i<COL_COUNT; i++)); do
        total_missing=$((total_missing + ${COL_MISSING[$i]:-0}))
    done
    if [[ $total_cells -gt 0 ]]; then
        local missing_pct missing_penalty
        local _mp100=$(( total_missing * 10000 / total_cells ))
        missing_pct="$(( _mp100 / 100 )).$(printf '%02d' $(( _mp100 % 100 )))"
        # penalty = int(pct * 1.5), capped at 25
        # _mp100 = pct * 100, so pct * 1.5 = _mp100 * 15 / 1000
        missing_penalty=$(( _mp100 * 15 / 1000 ))
        if [[ $missing_penalty -gt 25 ]]; then missing_penalty=25; fi
        quality_score=$((quality_score - missing_penalty))
        if [[ "$total_missing" -gt 0 ]]; then
            quality_issues+="Missing values: ${missing_pct}% of cells (-${missing_penalty} points)"$'\n'
        fi
    fi

    # Duplicate rows penalty
    if [[ "$dup_count" -gt 0 && "$ROW_COUNT" -gt 0 ]]; then
        local dup_pct dup_penalty
        local _dp100=$(( dup_count * 10000 / ROW_COUNT ))
        dup_pct="$(( _dp100 / 100 )).$(printf '%02d' $(( _dp100 % 100 )))"
        dup_penalty=$(( _dp100 / 100 ))
        if [[ $dup_penalty -gt 15 ]]; then dup_penalty=15; fi
        quality_score=$((quality_score - dup_penalty))
        quality_issues+="Duplicate rows: $dup_count (${dup_pct}%, -${dup_penalty} points)"$'\n'
    fi

    # Zero-variance penalty
    local zv_count=0
    for ((i=1; i<=COL_COUNT; i++)); do
        if [[ "${COL_TYPE[$((i-1))]}" == "numeric" ]]; then
            local std_val="${COL_STD[$((i-1))]}"
            if [[ -n "$std_val" ]] && float_cmp "$std_val" "==" "0"; then
                zv_count=$((zv_count+1))
            fi
        fi
    done
    if [[ $zv_count -gt 0 ]]; then
        local zv_penalty=$((zv_count * 5))
        if [[ $zv_penalty -gt 15 ]]; then
            zv_penalty=15
        fi
        quality_score=$((quality_score - zv_penalty))
        quality_issues+="Zero-variance columns: $zv_count (-${zv_penalty} points)"$'\n'
    fi

    # Low row count penalty
    if [[ "$ROW_COUNT" -lt 10 ]]; then
        local low_penalty=10
        quality_score=$((quality_score - low_penalty))
        quality_issues+="Low row count: $ROW_COUNT rows (-${low_penalty} points)"$'\n'
    fi

    # Single-column penalty
    if [[ "$COL_COUNT" -lt 2 ]]; then
        local col_penalty=10
        quality_score=$((quality_score - col_penalty))
        quality_issues+="Single column (-${col_penalty} points)"$'\n'
    fi

    if [[ $quality_score -lt 0 ]]; then
        quality_score=0
    fi

    local quality_grade="Excellent"
    if [[ $quality_score -lt 90 ]]; then quality_grade="Good"; fi
    if [[ $quality_score -lt 70 ]]; then quality_grade="Fair"; fi
    if [[ $quality_score -lt 50 ]]; then quality_grade="Poor"; fi

    local quality_body="Score: ${quality_score}/100 ($quality_grade)
Rows: $ROW_COUNT | Columns: $COL_COUNT | Cells: $total_cells"
    if [[ -n "$quality_issues" ]]; then
        quality_body+=$'\n'"Issues:"$'\n'"${quality_issues%$'\n'}"
    else
        quality_body+=$'\n'"No issues detected."
    fi
    add_item "Data quality score" "$quality_body" "GOOD" "quality_score"
}

run_suggested_drops () {
    local drop_body=""
    local drop_found=0
    local i

    for ((i=1; i<=COL_COUNT; i++)); do
        local col_name="${COL_NAMES[$((i-1))]}"
        local reasons=""

        # Zero variance
        if [[ "${COL_TYPE[$((i-1))]}" == "numeric" ]]; then
            local std_val="${COL_STD[$((i-1))]}"
            local mean_val="${COL_MEAN[$((i-1))]}"
            if [[ -n "$std_val" ]] && float_cmp "$std_val" "==" "0"; then
                reasons+="zero variance; "
            elif [[ -n "$std_val" && -n "$mean_val" ]]; then
                # Near-constant: CV < 1%
                local cv_check
                cv_check=$(awk -v s="$std_val" -v m="$mean_val" 'BEGIN{
                    if(m<0) m=-m; if(m>0) printf "%.4f", s/m*100; else print 0
                }')
                if [[ -z "$reasons" ]] && float_cmp "$cv_check" ">" "0" && float_cmp "$cv_check" "<" "1"; then
                    reasons+="near-constant (CV=${cv_check}%); "
                fi
            fi
        fi

        # High missing (>50%)
        local miss="${COL_MISSING[$((i-1))]}"
        if [[ -n "$miss" && "$miss" -gt 0 && "$ROW_COUNT" -gt 0 ]]; then
            local miss_ratio miss_pct
            local _mr100=$(( miss * 100 / ROW_COUNT ))
            miss_ratio="$(( _mr100 / 100 )).$(printf '%02d' $(( _mr100 % 100 )))"
            if float_cmp "$miss_ratio" ">" "0.50"; then
                miss_pct="$(( _mr100 ))"
                reasons+="${miss_pct}% missing; "
            fi
        fi

        if [[ -n "$reasons" ]]; then
            drop_body+="$col_name: ${reasons%; }"$'\n'
            drop_found=1
        fi
    done

    # Duplicate columns (limit to first 15 columns for performance) — single awk pass
    local max_dup_check=$((COL_COUNT < 15 ? COL_COUNT : 15))
    if [[ $max_dup_check -ge 2 ]]; then
        local dup_raw
        dup_raw=$(awk -F"$delim" -v ncols="$max_dup_check" '
            NR>1{
                for(i=1; i<ncols; i++){
                    for(j=i+1; j<=ncols; j++){
                        if(!diff[i,j] && $i!=$j) diff[i,j]=1
                    }
                }
            }
            END{
                for(i=1; i<ncols; i++){
                    for(j=i+1; j<=ncols; j++){
                        if(!diff[i,j]) printf "%d,%d\n", i, j
                    }
                }
            }
        ' "$input_file")
        if [[ -n "$dup_raw" ]]; then
            local ci cj
            while IFS=',' read -r ci cj; do
                drop_body+="${COL_NAMES[$((cj-1))]}: duplicate of ${COL_NAMES[$((ci-1))]}"$'\n'
                drop_found=1
            done <<< "$dup_raw"
        fi
    fi

    # Perfectly correlated pairs (r > 0.99)
    if [[ "${#CORR_VALUES[@]}" -gt 0 ]]; then
        local ci cj
        for ((ci=0; ci<${#corr_cols[@]}; ci++)); do
            for ((cj=ci+1; cj<${#corr_cols[@]}; cj++)); do
                local idx=$((ci*${#corr_cols[@]}+cj))
                local r="${CORR_VALUES[$idx]}"
                if [[ "$r" == "NA" ]]; then
                    continue
                fi
                local abs_r
                abs_r="${r#-}"
                if float_cmp "$abs_r" ">" "0.99"; then
                    drop_body+="${corr_names[$cj]}: nearly perfectly correlated with ${corr_names[$ci]} (r=$r)"$'\n'
                    drop_found=1
                fi
            done
        done
    fi

    if [[ $drop_found -eq 1 ]]; then
        add_item "Suggested column drops" "${drop_body%$'\n'}" "DIAGNOSTIC" "drop_suggest"
    fi
}

run_noisy_items () {
    add_item "Duplicate rows" "Duplicate rows: $dup_count" "NOISY" "noisy"

    # Single-pass: collect first 3 rows, last 3 rows, line length extremes, and common chars
    local noisy_raw
    noisy_raw=$(awk '
        NR==1{next}
        {
            row++
            l=length($0)
            if(min_len=="" || l<min_len) min_len=l
            if(l>max_len) max_len=l
            if(row<=3) first[row]=$0
            # Keep circular buffer for last 3
            last_buf[row%3]=$0
            last_count=row
            for(i=1;i<=l;i++){
                c=substr($0,i,1)
                if(c==","||c=="\t"||c=="\r"||c==" ") continue
                chars[c]++
            }
        }
        END{
            # Section 1: first rows
            for(i=1;i<=3 && i<=last_count;i++) print first[i]
            print "---SECTION---"
            # Section 2: last rows
            if(last_count>=3){
                for(i=last_count-2;i<=last_count;i++) print last_buf[i%3]
            } else {
                for(i=1;i<=last_count;i++) print first[i]
            }
            print "---SECTION---"
            # Section 3: line lengths
            printf "%d %d\n", min_len+0, max_len+0
            print "---SECTION---"
            # Section 4: common chars (all, to be sorted externally)
            for(c in chars) printf "%d\t%s\n", chars[c], c
        }
    ' "$input_file")

    # Parse sections
    local section=0 first_rows="" last_rows="" line_lengths="" char_lines=""
    while IFS= read -r line; do
        if [[ "$line" == "---SECTION---" ]]; then
            section=$((section+1))
            continue
        fi
        case $section in
            0) first_rows+="$line"$'\n' ;;
            1) last_rows+="$line"$'\n' ;;
            2) line_lengths="$line" ;;
            3) char_lines+="$line"$'\n' ;;
        esac
    done <<< "$noisy_raw"

    add_item "Sample rows (first 3)" "${first_rows%$'\n'}" "NOISY" "noisy"
    add_item "Sample rows (last 3)" "${last_rows%$'\n'}" "NOISY" "noisy"

    local min_len max_len
    read -r min_len max_len <<< "$line_lengths"
    add_item "Row length extremes" "Min row length: $min_len
Max row length: $max_len" "NOISY" "noisy"

    local common_chars chars_body
    common_chars=$(printf "%s" "${char_lines%$'\n'}" | sort -nr | awk 'NR <= 5')  # not head: SIGPIPE on sort under pipefail
    chars_body=""
    if [[ -n "$common_chars" ]]; then
        local count ch
        while IFS=$'\t' read -r count ch; do
            chars_body+="$ch: $count"$'\n'
        done <<< "$common_chars"
    else
        chars_body="(none)"
    fi
    add_item "Most common characters" "${chars_body%$'\n'}" "NOISY" "noisy"
}
