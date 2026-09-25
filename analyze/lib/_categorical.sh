#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Per-column categorical analyses for envoy-analyze
##
## Analyses: top values, category dominance, group summaries, Cramer's V.
##
## Reads:  input_file delim COL_COUNT COL_NAMES COL_TYPE COL_UNIQUE
##         NUM_COL_INDEXES NUM_COL_NAMES CAT_COL_INDEXES CAT_COL_NAMES
##         MAX_GROUP_UNIQUE MAX_GROUPS MAX_GROUP_NUM_COLS
##         AWK_ISMISSING
## Writes: ITEM_TITLES ITEM_BODIES ITEM_TAGS ITEM_KINDS (via add_item)
################################################################################

run_categorical_analyses () {
    for ((i=1; i<=COL_COUNT; i++)); do
        if [[ "${COL_TYPE[$((i-1))]}" != "categorical" ]]; then
            continue
        fi

        local col_name="${COL_NAMES[$((i-1))]}"

        # Single-pass: compute unique count, top 5 values, dominance, and entropy
        local cat_combined
        cat_combined=$(awk -F"$delim" -v col="$i" "$AWK_ISMISSING"'
            function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
            NR>1{
                v=trim($col)
                if(ismissing(v)) next
                total++
                count[v]++
            }
            END{
                if(total==0){print "0|0|0|0.0000|"; exit}
                # Find unique count, top value, and entropy in one loop
                uniq=0; top=0; topval=""; ent=0
                for(k in count){
                    uniq++
                    if(count[k]>top){top=count[k]; topval=k}
                    p=count[k]/total
                    if(p>0) ent -= p*log(p)/log(2)
                }
                printf "%d|%d|%d|%.4f|%s\n", total, uniq, top, ent, topval
                # Sort values by count descending for top-5 (shell sort in awk)
                n=0
                for(k in count){n++; vals[n]=k; cnts[n]=count[k]}
                # Simple selection of top 5
                for(t=1; t<=5 && t<=n; t++){
                    best=t
                    for(j=t+1; j<=n; j++){
                        if(cnts[j]>cnts[best]) best=j
                    }
                    if(best!=t){
                        tmp=vals[t]; vals[t]=vals[best]; vals[best]=tmp
                        tmp=cnts[t]; cnts[t]=cnts[best]; cnts[best]=tmp
                    }
                    printf "%d %s\n", cnts[t], vals[t]
                }
            }
        ' "$input_file")

        # Parse first line: stats
        local cat_stats_line
        cat_stats_line=$(head -n 1 <<< "$cat_combined")
        local cat_total unique_count cat_top cat_entropy cat_topval
        IFS='|' read -r cat_total unique_count cat_top cat_entropy cat_topval <<< "$cat_stats_line"

        COL_UNIQUE[$((i-1))]="$unique_count"

        if [[ -n "$cat_total" && "$cat_total" -gt 0 ]]; then
            local top_share
            local _ts100=$(( cat_top * 10000 / cat_total ))
            top_share="$(( _ts100 / 100 )).$(printf '%02d' $(( _ts100 % 100 )))"
            add_item "Category dominance: $col_name" "Top share: ${top_share}% (value: ${cat_topval})
Entropy (bits): ${cat_entropy}" "ADVANCED" "dominance"
        fi

        # Parse remaining lines: top values
        local top_lines
        top_lines=$(tail -n +2 <<< "$cat_combined")
        local top_body="Unique values: $unique_count"$'\n'"Top values:"$'\n'
        if [[ -n "$top_lines" ]]; then
            local count value
            while read -r count value; do
                top_body+="  $value: $count"$'\n'
            done <<< "$top_lines"
        else
            top_body+="  (none)"$'\n'
        fi
        add_item "Top values: $col_name" "${top_body%$'\n'}" "GOOD" "top_values"
    done
}

run_group_summaries () {
    if [[ ${#NUM_COL_INDEXES[@]} -eq 0 ]]; then
        return
    fi
    # ENV-126: skip per-group awks when group_summary kind is filtered out.
    _will_keep_kind group_summary || return 0

    for ((i=1; i<=COL_COUNT; i++)); do
        if [[ "${COL_TYPE[$((i-1))]}" != "categorical" ]]; then
            continue
        fi
        local unique_count="${COL_UNIQUE[$((i-1))]}"
        if [[ -z "$unique_count" || "$unique_count" -eq 0 || "$unique_count" -gt "$MAX_GROUP_UNIQUE" ]]; then
            if [[ -n "$unique_count" && "$unique_count" -gt "$MAX_GROUP_UNIQUE" ]]; then
                echo "Warning: column '${COL_NAMES[$((i-1))]}' has $unique_count unique values, exceeding MAX_GROUP_UNIQUE=$MAX_GROUP_UNIQUE; skipping group summary" >&2
            fi
            continue
        fi

        local num_cols=()
        local num_names=()
        local n
        if [[ ${#NUM_COL_INDEXES[@]} -gt "$MAX_GROUP_NUM_COLS" ]]; then
            echo "Warning: ${#NUM_COL_INDEXES[@]} numeric columns available but group summary limited to MAX_GROUP_NUM_COLS=$MAX_GROUP_NUM_COLS for column '${COL_NAMES[$((i-1))]}'" >&2
        fi
        for ((n=0; n<${#NUM_COL_INDEXES[@]} && n<MAX_GROUP_NUM_COLS; n++)); do
            num_cols+=("${NUM_COL_INDEXES[$n]}")
            num_names+=("${NUM_COL_NAMES[$n]}")
        done

        if [[ ${#num_cols[@]} -eq 0 ]]; then
            continue
        fi

        local num_cols_list num_names_list
        num_cols_list=$(IFS=,; echo "${num_cols[*]}")
        num_names_list=$(IFS='|'; echo "${num_names[*]}")

        local group_lines
        group_lines=$(awk -F"$delim" -v cat_col="$i" -v num_cols="$num_cols_list" -v num_names="$num_names_list" "$AWK_ISMISSING"'
            function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
            function isnum(x){ return (x ~ /^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$/) }
            BEGIN{ split(num_cols, cols, ","); split(num_names, names, "|") }
            NR>1 {
                cat=trim($cat_col)
                if (ismissing(cat)) next
                count[cat]++
                for (i=1;i<=length(cols);i++) {
                    c=cols[i]
                    v=trim($(c))
                    if (isnum(v)) {
                        sum[cat,i]+=v
                        n[cat,i]++
                    }
                }
            }
            END{
                for (c in count) {
                    printf "%s|%d", c, count[c]
                    for (i=1;i<=length(cols);i++) {
                        if (n[c,i]>0) printf "|%.4f", (sum[c,i]/n[c,i])
                        else printf "|"
                    }
                    print ""
                }
            }
        ' "$input_file" | sort -t'|' -k2,2nr)

        local total_groups
        total_groups=$(printf "%s\n" "$group_lines" | wc -l | tr -d ' ')
        if [[ "$total_groups" -gt "$MAX_GROUPS" ]]; then
            echo "Warning: column '${COL_NAMES[$((i-1))]}' has $total_groups groups but only showing top MAX_GROUPS=$MAX_GROUPS" >&2
            group_lines=$(printf "%s\n" "$group_lines" | awk -v n="$MAX_GROUPS" 'NR <= n')  # awk reads all input: no SIGPIPE under pipefail
        fi

        if [[ -n "$group_lines" ]]; then
            local body="" group count rest
            while IFS='|' read -r group count rest; do
                body+="$group (n=$count): "
                local -a means
                IFS='|' read -r -a means <<< "$rest"
                local m val label
                for ((m=0; m<${#num_names[@]}; m++)); do
                    val="${means[$m]:-}"
                    label="${num_names[$m]}"
                    if [[ -n "$val" ]]; then
                        body+="$label=$val"
                    else
                        body+="$label=n/a"
                    fi
                    if (( m < ${#num_names[@]}-1 )); then
                        body+="; "
                    fi
                done
                body+=$'\n'
            done <<< "$group_lines"

            add_item "Group summary: ${COL_NAMES[$((i-1))]}" "${body%$'\n'}" "GOOD" "group_summary"
        fi
    done
}

run_cramers_v () {
    # ENV-126: skip the N² categorical-pair awk when cramers_v isn't kept.
    _will_keep_kind cramers_v || return 0
    CAT_COL_INDEXES=()
    CAT_COL_NAMES=()
    for ((i=1; i<=COL_COUNT; i++)); do
        if [[ "${COL_TYPE[$((i-1))]}" == "categorical" ]]; then
            local uq="${COL_UNIQUE[$((i-1))]}"
            if [[ -n "$uq" && "$uq" -gt 1 && "$uq" -le "$MAX_GROUP_UNIQUE" ]]; then
                CAT_COL_INDEXES+=("$i")
                CAT_COL_NAMES+=("${COL_NAMES[$((i-1))]}")
            elif [[ -n "$uq" && "$uq" -gt "$MAX_GROUP_UNIQUE" ]]; then
                echo "Warning: column '${COL_NAMES[$((i-1))]}' has $uq unique values, exceeding MAX_GROUP_UNIQUE=$MAX_GROUP_UNIQUE; excluded from Cramer's V" >&2
            fi
        fi
    done

    if [[ ${#CAT_COL_INDEXES[@]} -lt 2 ]]; then
        return
    fi

    local cramer_body=""
    local cramer_found=0
    local ci cj
    for ((ci=0; ci<${#CAT_COL_INDEXES[@]}-1 && ci<4; ci++)); do
        for ((cj=ci+1; cj<${#CAT_COL_INDEXES[@]} && cj<5; cj++)); do
            local cramer_v
            cramer_v=$(awk -F"$delim" -v c1="${CAT_COL_INDEXES[$ci]}" -v c2="${CAT_COL_INDEXES[$cj]}" "$AWK_ISMISSING"'
                function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
                NR>1{
                    v1=trim($c1); v2=trim($c2)
                    if(ismissing(v1)) next
                    if(ismissing(v2)) next
                    n++
                    joint[v1,v2]++
                    row_total[v1]++
                    col_total[v2]++
                    if(!seen_r[v1]){seen_r[v1]=1; nr++}
                    if(!seen_c[v2]){seen_c[v2]=1; nc++}
                }
                END{
                    if(n==0||nr<2||nc<2){print "NA"; exit}
                    chi2=0; low_exp=0; total_cells=0
                    for(key in joint){
                        split(key, parts, SUBSEP)
                        r=parts[1]; c=parts[2]
                        obs=joint[key]
                        exv=row_total[r]*col_total[c]/n
                        total_cells++
                        if(exv<5) low_exp++
                        if(exv>0) chi2+=(obs-exv)*(obs-exv)/exv
                    }
                    k=(nr<nc? nr : nc)
                    v=sqrt(chi2/(n*(k-1)))
                    if(total_cells>0 && low_exp > total_cells*0.2)
                        printf "%.6f|WARNING", v
                    else
                        printf "%.6f", v
                }
            ' "$input_file")
            # Strip warning flag for display
            local cramer_warn=""
            if [[ "$cramer_v" == *"|WARNING" ]]; then
                cramer_warn=" (warning: >20% expected frequencies <5)"
                cramer_v="${cramer_v%%|*}"
            fi
            if [[ "$cramer_v" != "NA" ]]; then
                local strength=""
                if float_cmp "$cramer_v" ">=" "0.3"; then
                    strength="strong"
                elif float_cmp "$cramer_v" ">=" "0.15"; then
                    strength="moderate"
                else
                    strength="weak"
                fi
                if float_cmp "$cramer_v" ">=" "0.15"; then
                    cramer_body+="${CAT_COL_NAMES[$ci]} vs ${CAT_COL_NAMES[$cj]}: V=$cramer_v ($strength association)${cramer_warn}"$'\n'
                    cramer_found=1
                fi
            fi
        done
    done
    if [[ $cramer_found -eq 1 ]]; then
        add_item "Categorical associations (Cramer's V)" "${cramer_body%$'\n'}" "ADVANCED" "cramers_v"
    fi
}
