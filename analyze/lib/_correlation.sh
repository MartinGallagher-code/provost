#!/bin/bash
################################################################################
## Cross-column correlation analyses for envoy-analyze
##
## Analyses: correlation matrix, strongest pairs, linear regression,
## pairwise completeness, outlier co-occurrence, column correlation strength.
##
## Reads:  input_file delim NUM_COL_INDEXES NUM_COL_NAMES
##         COL_MEAN COL_STD MAX_CORR_COLS
##         AWK_ISMISSING
## Writes: CORR_VALUES corr_cols corr_names _CORR_PAIR_LINES
##         ITEM_TITLES ITEM_BODIES ITEM_TAGS ITEM_KINDS (via add_item)
################################################################################

run_correlation_analyses () {
    local corr_numeric_count=${#NUM_COL_INDEXES[@]}
    # ENV-125: _correlation_dimension_summary's footer needs to know how
    # many columns existed before the MAX_CORR_COLS cap so it can report
    # any drops alongside the summed count.
    local corr_numeric_count_full=$corr_numeric_count
    corr_cols=()
    corr_names=()
    CORR_VALUES=()

    if [[ "$corr_numeric_count" -lt 2 ]]; then
        return
    fi

    # ENV-126: skip the whole correlation pipeline (matrix + pairs +
    # regression + pairwise + outlier-cooccurrence + dimension summary)
    # when none of its kinds are kept. The matrix awk is the costliest
    # single computation in envoy-analyze for wide datasets, so this is
    # the biggest filter-skip win available.
    #
    # Dependency: `run_suggested_drops` (kind=drop_suggest) reads the
    # CORR_VALUES globals to suggest dropping high-correlation columns.
    # If that kind is kept we still need the matrix even if no
    # correlation-kind output is requested.
    if ! _will_keep_kind corr_matrix \
       && ! _will_keep_kind corr_pairs \
       && ! _will_keep_kind regression \
       && ! _will_keep_kind pairwise_complete \
       && ! _will_keep_kind outlier_cooccur \
       && ! _will_keep_kind corr_strength \
       && ! _will_keep_kind drop_suggest; then
        return
    fi

    if [[ "$corr_numeric_count" -gt "$MAX_CORR_COLS" ]]; then
        echo "Warning: $corr_numeric_count numeric columns found but correlation matrix limited to MAX_CORR_COLS=$MAX_CORR_COLS; columns $((MAX_CORR_COLS+1))-${corr_numeric_count} dropped" >&2
    fi

    local i j
    for ((i=0; i<corr_numeric_count && i<MAX_CORR_COLS; i++)); do
        corr_cols+=("${NUM_COL_INDEXES[$i]}")
        corr_names+=("${NUM_COL_NAMES[$i]}")
    done

    _correlation_matrix
    _correlation_strongest_pairs
    _correlation_regression
    _correlation_pairwise_completeness
    _correlation_outlier_cooccurrence
    _correlation_dimension_summary
}

_correlation_matrix () {
    local i j idx nc=${#corr_cols[@]}

    CORR_VALUES=()

    # Build comma-separated column index list for awk
    local cols_csv=""
    for ((i=0; i<nc; i++)); do
        cols_csv+="${corr_cols[$i]},"
    done

    # Single-pass: compute pairwise-correct correlations
    # Uses per-pair sums instead of pre-computed means/stds, so missing
    # values in one pair don't affect other pairs' statistics.
    local corr_raw
    corr_raw=$(awk -F"$delim" -v cols_csv="$cols_csv" -v nc="$nc" '
        function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        function isnum(x){ return (x ~ /^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$/) }
        BEGIN{ split(cols_csv, cols, ",") }
        NR==1{next}
        {
            for(i=1; i<=nc; i++){
                v[i]=trim($cols[i])
                ok[i]=isnum(v[i])
            }
            for(i=1; i<=nc; i++){
                if(!ok[i]) continue
                vi=v[i]+0
                for(j=i+1; j<=nc; j++){
                    if(!ok[j]) continue
                    vj=v[j]+0
                    pn[i,j]++
                    sx[i,j]+=vi; sy[i,j]+=vj
                    sxx[i,j]+=vi*vi; syy[i,j]+=vj*vj
                    sxy[i,j]+=vi*vj
                }
            }
        }
        END{
            for(i=1; i<=nc; i++){
                for(j=i+1; j<=nc; j++){
                    nn=pn[i,j]+0
                    if(nn<2){printf "NA\n"; continue}
                    mx=sx[i,j]/nn; my=sy[i,j]/nn
                    vx=sxx[i,j]/nn - mx*mx
                    vy=syy[i,j]/nn - my*my
                    cov=sxy[i,j]/nn - mx*my
                    if(vx>0 && vy>0){
                        r=cov/sqrt(vx*vy)
                        if(r>1) r=1; if(r<-1) r=-1
                        printf "%.4f\n", r
                    } else {
                        printf "NA\n"
                    }
                }
            }
        }
    ' "$input_file")

    # Fill CORR_VALUES from the single-pass output
    # Read all lines into an array first to avoid per-pair process spawns
    local -a _corr_lines=()
    while IFS= read -r _cl; do
        _corr_lines+=("$_cl")
    done <<< "$corr_raw"

    local pair_idx=0
    local r
    for ((i=0; i<nc; i++)); do
        for ((j=0; j<nc; j++)); do
            idx=$((i*nc+j))
            if (( i == j )); then
                CORR_VALUES[$idx]="1.0000"
            elif (( j < i )); then
                local sym=$((j*nc+i))
                CORR_VALUES[$idx]="${CORR_VALUES[$sym]}"
            else
                CORR_VALUES[$idx]="${_corr_lines[$pair_idx]}"
                pair_idx=$((pair_idx+1))
            fi
        done
    done

    # Build matrix display
    local matrix=" "$'\t'
    local name
    for name in "${corr_names[@]}"; do
        matrix+="$name"$'\t'
    done
    matrix=${matrix%$'\t'}
    matrix+=$'\n'

    for ((i=0; i<${#corr_cols[@]}; i++)); do
        local line="${corr_names[$i]}"
        for ((j=0; j<${#corr_cols[@]}; j++)); do
            idx=$((i*${#corr_cols[@]}+j))
            line+=$'\t'"${CORR_VALUES[$idx]}"
        done
        matrix+="$line"$'\n'
    done

    local matrix_body
    matrix_body=$(printf "%s" "$matrix" | column -t -s$'\t' 2>/dev/null || printf "%s" "$matrix")
    local corr_numeric_count=${#NUM_COL_INDEXES[@]}
    if [[ "$corr_numeric_count" -gt "$MAX_CORR_COLS" ]]; then
        matrix_body+=$'\n'"(Note: showing first $MAX_CORR_COLS numeric columns)"
    fi

    add_item "Correlation matrix" "${matrix_body%$'\n'}" "GOOD" "corr_matrix"
}

_correlation_strongest_pairs () {
    local i j idx r abs
    local pair_lines=""

    for ((i=0; i<${#corr_cols[@]}; i++)); do
        for ((j=i+1; j<${#corr_cols[@]}; j++)); do
            idx=$((i*${#corr_cols[@]}+j))
            r="${CORR_VALUES[$idx]}"
            if [[ "$r" == "NA" ]]; then
                continue
            fi
            abs="${r#-}"
            pair_lines+="$abs"$'\t'"$r"$'\t'"${corr_names[$i]}"$'\t'"${corr_names[$j]}"$'\n'
        done
    done

    # Store for reuse by regression
    _CORR_PAIR_LINES="$pair_lines"

    if [[ -n "$pair_lines" ]]; then
        local top_pairs
        top_pairs=$(printf "%s" "$pair_lines" | sort -nr | awk 'NR<=5')
        local pairs_body=""
        local abs r a b
        while IFS=$'\t' read -r abs r a b; do
            pairs_body+="$a vs $b: r=$r"$'\n'
        done <<< "$top_pairs"
        add_item "Strongest correlations" "${pairs_body%$'\n'}" "GOOD" "corr_pairs"
    fi
}

_correlation_regression () {
    local pair_lines="$_CORR_PAIR_LINES"
    if [[ -z "$pair_lines" ]]; then
        return
    fi

    local reg_body=""
    local reg_count=0
    local abs r col_a col_b
    while IFS=$'\t' read -r abs r col_a col_b; do
        if [[ "$r" == "NA" ]]; then
            continue
        fi
        if ! float_cmp "$abs" ">=" "0.5"; then
            continue
        fi
        local idx_a="" idx_b="" ci
        for ((ci=0; ci<${#corr_names[@]}; ci++)); do
            if [[ "${corr_names[$ci]}" == "$col_a" ]]; then
                idx_a="${corr_cols[$ci]}"
            fi
            if [[ "${corr_names[$ci]}" == "$col_b" ]]; then
                idx_b="${corr_cols[$ci]}"
            fi
        done
        if [[ -z "$idx_a" || -z "$idx_b" ]]; then
            continue
        fi
        local mean_a="${COL_MEAN[$((idx_a-1))]}"
        local mean_b="${COL_MEAN[$((idx_b-1))]}"
        local std_a="${COL_STD[$((idx_a-1))]}"
        local std_b="${COL_STD[$((idx_b-1))]}"
        if [[ -n "$std_a" ]] && float_cmp "$std_a" ">" "0"; then
            local slope intercept r2
            slope=$(awk -v r="$r" -v sy="$std_b" -v sx="$std_a" 'BEGIN{printf "%.6f", r*(sy/sx)}')
            intercept=$(awk -v my="$mean_b" -v sl="$slope" -v mx="$mean_a" 'BEGIN{printf "%.4f", my - sl*mx}')
            r2=$(awk -v r="$r" 'BEGIN{printf "%.4f", r*r}')
            reg_body+="$col_b = ${slope} * $col_a + ${intercept}  (r=$r, R²=$r2)"$'\n'
            reg_count=$((reg_count+1))
            if [[ $reg_count -ge 5 ]]; then
                break
            fi
        fi
    done <<< "$(printf "%s" "$pair_lines" | sort -nr | awk 'NR<=5')"
    if [[ -n "$reg_body" ]]; then
        add_item "Linear regression (top pairs)" "${reg_body%$'\n'}" "ADVANCED" "regression"
    fi
}

_correlation_pairwise_completeness () {
    local nc=${#corr_cols[@]}
    if [[ $nc -lt 2 ]]; then
        return
    fi

    # Limit to first 6 columns
    local limit=$((nc < 6 ? nc : 6))

    # Build comma-separated column index list
    local cols_csv=""
    for ((i=0; i<limit; i++)); do
        cols_csv+="${corr_cols[$i]},"
    done

    # Single-pass: compute pairwise completeness for all pairs
    local pcomp_raw
    pcomp_raw=$(awk -F"$delim" -v cols_csv="$cols_csv" -v nc="$limit" "$AWK_ISMISSING"'
        function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        BEGIN{ split(cols_csv, cols, ",") }
        NR==1{next}
        {
            total++
            for(i=1; i<=nc; i++) miss[i]=ismissing(trim($cols[i]))
            for(i=1; i<nc; i++){
                for(j=i+1; j<=nc; j++){
                    if(miss[i] || miss[j]) inc[i,j]++
                }
            }
        }
        END{
            for(i=1; i<nc; i++){
                for(j=i+1; j<=nc; j++){
                    if(total==0) printf "100.00\n"
                    else printf "%.2f\n", (total-inc[i,j]+0)/total*100
                }
            }
        }
    ' "$input_file")

    local paircomp_body=""
    local paircomp_found=0
    local pair_idx=0
    local ci cj
    for ((ci=0; ci<limit-1; ci++)); do
        for ((cj=ci+1; cj<limit; cj++)); do
            pair_idx=$((pair_idx+1))
            local pcomp
            pcomp=$(sed -n "${pair_idx}p" <<< "$pcomp_raw")
            if float_cmp "$pcomp" "<" "100"; then
                paircomp_body+="${corr_names[$ci]} vs ${corr_names[$cj]}: ${pcomp}% complete"$'\n'
                paircomp_found=1
            fi
        done
    done
    if [[ $paircomp_found -eq 1 ]]; then
        add_item "Pairwise completeness" "${paircomp_body%$'\n'}" "ADVANCED" "pairwise_complete"
    fi
}

_correlation_outlier_cooccurrence () {
    local nc=${#corr_cols[@]}
    if [[ $nc -lt 2 ]]; then
        return
    fi

    # Limit: ci<4, cj<5
    local limit_i=$((nc-1 < 4 ? nc-1 : 4))
    local limit_j=$((nc < 5 ? nc : 5))

    # Collect valid pairs and their Q1/Q3 boundaries
    local pairs_csv="" pair_names_i=() pair_names_j=()
    local pair_count=0
    local ci cj
    for ((ci=0; ci<limit_i; ci++)); do
        for ((cj=ci+1; cj<limit_j; cj++)); do
            local col_ci="${corr_cols[$ci]}"
            local col_cj="${corr_cols[$cj]}"
            local q1_a="${COL_Q1[$((col_ci-1))]:-}"
            local q3_a="${COL_Q3[$((col_ci-1))]:-}"
            local q1_b="${COL_Q1[$((col_cj-1))]:-}"
            local q3_b="${COL_Q3[$((col_cj-1))]:-}"
            if [[ -z "$q1_a" || "$q1_a" == "n/a" || -z "$q1_b" || "$q1_b" == "n/a" ]]; then
                continue
            fi
            pairs_csv+="${col_ci},${col_cj},${q1_a},${q3_a},${q1_b},${q3_b};"
            pair_names_i+=("${corr_names[$ci]}")
            pair_names_j+=("${corr_names[$cj]}")
            pair_count=$((pair_count+1))
        done
    done

    if [[ $pair_count -eq 0 ]]; then
        return
    fi

    # Single-pass: compute outlier co-occurrence for all pairs
    local cooccur_raw
    cooccur_raw=$(awk -F"$delim" -v pairs_csv="$pairs_csv" -v npairs="$pair_count" '
        function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
        function isnum(x){ return (x ~ /^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$/) }
        BEGIN{
            split(pairs_csv, pairs, ";")
            for(p=1; p<=npairs; p++){
                split(pairs[p], pp, ",")
                pc1[p]=pp[1]; pc2[p]=pp[2]
                q1a[p]=pp[3]; q3a[p]=pp[4]; q1b[p]=pp[5]; q3b[p]=pp[6]
                iqr1[p]=q3a[p]-q1a[p]; lo1[p]=q1a[p]-1.5*iqr1[p]; hi1[p]=q3a[p]+1.5*iqr1[p]
                iqr2[p]=q3b[p]-q1b[p]; lo2[p]=q1b[p]-1.5*iqr2[p]; hi2[p]=q3b[p]+1.5*iqr2[p]
            }
        }
        NR>1{
            for(p=1; p<=npairs; p++){
                v1=trim($pc1[p]); v2=trim($pc2[p])
                o1=(isnum(v1) && (v1+0<lo1[p] || v1+0>hi1[p]))
                o2=(isnum(v2) && (v2+0<lo2[p] || v2+0>hi2[p]))
                if(o1) out1[p]++
                if(o2) out2[p]++
                if(o1 && o2) both[p]++
            }
        }
        END{
            for(p=1; p<=npairs; p++){
                printf "%d|%d|%d\n", out1[p]+0, out2[p]+0, both[p]+0
            }
        }
    ' "$input_file")

    local cooccur_body=""
    local cooccur_found=0
    local p=0
    while IFS='|' read -r o1 o2 oboth; do
        if [[ "$oboth" -gt 0 ]]; then
            cooccur_body+="${pair_names_i[$p]} vs ${pair_names_j[$p]}: $oboth rows where both are outliers (${o1} in ${pair_names_i[$p]}, ${o2} in ${pair_names_j[$p]})"$'\n'
            cooccur_found=1
        fi
        p=$((p+1))
    done <<< "$cooccur_raw"
    if [[ $cooccur_found -eq 1 ]]; then
        add_item "Outlier co-occurrence" "${cooccur_body%$'\n'}" "ADVANCED" "outlier_cooccur"
    fi
}

_correlation_dimension_summary () {
    if [[ ${#corr_cols[@]} -lt 3 ]]; then
        return
    fi

    # ENV-125: this is a "how connected is each column to the rest"
    # heuristic, not a dimensional decomposition. Output framing was
    # softened in v0.6 ("Correlation dimension summary" / "Rank N:")
    # but still implied a dimension count it could not deliver. Path A
    # rewrites the body to use neutral `<col>: connectedness=<v>`
    # entries sorted descending, and drops the dimension framing.
    local strength_body
    strength_body=$(awk -v ncols="${#corr_cols[@]}" -v corr_vals="$(printf "%s," "${CORR_VALUES[@]}")" -v col_names="$(IFS='|'; echo "${corr_names[*]}")" '
        BEGIN{
            split(corr_vals, cv, ",")
            split(col_names, names, "|")
            n=ncols
            for(i=0;i<n;i++){
                colsum=0
                for(j=0;j<n;j++){
                    if(i==j) continue
                    idx=i*n+j+1
                    r=cv[idx]+0
                    if(r<0) r=-r
                    colsum+=r
                }
                strength[i]=colsum
            }
            for(i=0;i<n;i++) order[i]=i
            for(i=0;i<n-1;i++) for(j=i+1;j<n;j++){
                if(strength[order[i]]<strength[order[j]]){
                    t=order[i]; order[i]=order[j]; order[j]=t
                }
            }
            print "Sum of |r| with other numeric columns; higher = more linearly related to the rest. Not a PCA / variance-explained metric."
            for(i=0;i<n;i++){
                idx=order[i]
                printf "%s: connectedness=%.3f\n", names[idx+1], strength[idx]
            }
        }
    ')

    # Footer: how many columns were actually summed and how many were
    # dropped by the MAX_CORR_COLS cap (the cap is announced upstream
    # in run_correlation_analyses but the summed count belongs here).
    local n_summed=${#corr_cols[@]}
    local footer="---"$'\n'"Summed across $n_summed numeric column(s)."
    if [[ "${corr_numeric_count_full:-0}" -gt "$n_summed" ]]; then
        local dropped=$(( corr_numeric_count_full - n_summed ))
        footer+=" $dropped further numeric column(s) dropped by MAX_CORR_COLS=$MAX_CORR_COLS."
    fi

    add_item "Column correlation strength" "$strength_body"$'\n'"$footer" "ADVANCED" "corr_strength"
}
