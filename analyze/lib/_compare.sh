#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Cross-dataset comparison for provost-analyze
##
## Compares summary statistics across multiple CSV/TSV files, producing
## side-by-side tables and rankings.
##
## Reads:  compare_files forced_delim AWK_ISMISSING
## Writes: cleanup_files
##         ITEM_TITLES ITEM_BODIES ITEM_TAGS ITEM_KINDS (via add_item)
################################################################################

# Extract per-column stats from a single file.
# Output: tab-separated lines:  col_name \t mean \t std \t min \t max \t median \t cv
_compare_extract_stats () {
    local file="$1"
    local file_delim="$2"

    awk -F"$file_delim" "$AWK_ISMISSING"'
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function isnum(x){ return (x ~ /^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$/) }
    NR==1{
        for(i=1;i<=NF;i++) col[i]=trim($i)
        ncols=NF
        next
    }
    {
        for(i=1;i<=ncols;i++){
            v=trim($i)
            if(ismissing(v)) continue
            if(!isnum(v)) { text[i]++; total[i]++; continue }
            total[i]++
            num[i]++
            vn=v+0
            # Welford online
            delta=vn-wm[i]
            n1=num[i]
            delta_n=delta/n1
            wm2[i]+=delta*delta_n*(n1-1)
            wm[i]+=delta_n
            if(n1==1||vn<mn[i]) mn[i]=vn
            if(n1==1||vn>mx[i]) mx[i]=vn
            # Store values for median (up to 50K)
            if(num[i]<=50000) { vals[i,num[i]]=vn }
        }
    }
    END{
        for(i=1;i<=ncols;i++){
            n=num[i]+0; t=total[i]+0
            if(t>0 && n/t < 0.80) continue  # skip non-numeric columns
            if(n==0) continue
            mean=wm[i]
            m2=wm2[i]/n; if(m2<0) m2=0
            std=sqrt(m2)
            cv=(mean!=0? (std/(mean<0?-mean:mean))*100 : 0)
            # Compute median via insertion sort on stored values
            # Simple selection for median
            mid=int((n+1)/2)
            # Shell sort the values
            h=1; while(h<n) h=3*h+1
            while(h>1){
                h=int(h/3)
                for(j=h+1;j<=n;j++){
                    tmp=vals[i,j]; k=j
                    while(k>h && vals[i,k-h]>tmp){
                        vals[i,k]=vals[i,k-h]; k-=h
                    }
                    vals[i,k]=tmp
                }
            }
            if(n%2==1) median=vals[i,mid]
            else median=(vals[i,mid]+vals[i,mid+1])/2
            printf "%s\t%.6f\t%.6f\t%g\t%g\t%.6f\t%.2f\n", col[i], mean, std, mn[i], mx[i], median, cv
        }
    }
    ' "$file"
}

# Main entry point for cross-dataset comparison.
# Called from provost-analyze when --compare is active.
run_cross_dataset_comparison () {
    local nfiles=${#compare_files[@]}
    if [[ $nfiles -lt 2 ]]; then
        return
    fi

    # Extract stats from each file
    # _CMP_DATA[fileindex] = multiline output from _compare_extract_stats
    local -a _CMP_DATA=()
    local -a _CMP_LABELS=()
    local fi_idx

    for ((fi_idx=0; fi_idx<nfiles; fi_idx++)); do
        local cfile="${compare_files[$fi_idx]}"
        [[ -f "$cfile" ]] || err "Compare file not found: $cfile"

        # Detect delimiter for this file
        local cdelim
        if [[ -n "$forced_delim" ]]; then
            cdelim="$forced_delim"
        else
            cdelim="$(detect_delim "$cfile")"
        fi

        # BOM strip
        strip_bom "$cfile"
        local cfile_clean="$_STRIP_BOM_RESULT"

        # CSV preprocess if needed
        if needs_csv_preprocess "$cfile_clean"; then
            local ctmp
            ctmp="$(mktemp -t mda-cmp-tsv.XXXXXX)"
            cleanup_files+=("$ctmp")
            csv_to_tsv "$cfile_clean" "$cdelim" > "$ctmp"
            cfile_clean="$ctmp"
            cdelim=$'\t'
        fi

        _CMP_DATA[$fi_idx]="$(_compare_extract_stats "$cfile_clean" "$cdelim")"
        # Label = basename without extension
        local label
        label="$(basename "$cfile")"
        label="${label%.*}"
        _CMP_LABELS[$fi_idx]="$label"
    done

    # Collect all column names that appear in ALL files
    local -A col_in_files
    local -a all_cols=()
    for ((fi_idx=0; fi_idx<nfiles; fi_idx++)); do
        while IFS=$'\t' read -r cname _rest; do
            [[ -z "$cname" ]] && continue
            col_in_files["$cname"]=$(( ${col_in_files["$cname"]:-0} + 1 ))
        done <<< "${_CMP_DATA[$fi_idx]}"
    done
    for cname in "${!col_in_files[@]}"; do
        if [[ "${col_in_files[$cname]}" -eq "$nfiles" ]]; then
            all_cols+=("$cname")
        fi
    done

    if [[ ${#all_cols[@]} -eq 0 ]]; then
        add_item "Cross-dataset comparison" "No shared numeric columns found across datasets." "DIAGNOSTIC" "compare"
        return
    fi

    # Build comparison table for each shared column
    local col
    for col in "${all_cols[@]}"; do
        local table_body=""
        # Header row
        local header="Dataset"
        header+=$'\t'"Mean"$'\t'"Std"$'\t'"Min"$'\t'"Max"$'\t'"Median"$'\t'"CV%"
        table_body+="$header"$'\n'

        local -a means=()
        local -a labels_for_rank=()
        for ((fi_idx=0; fi_idx<nfiles; fi_idx++)); do
            local row
            # NB: no early `exit` in awk. Under `set -euo pipefail`, an awk that
            # exits before consuming all of `echo`'s output can leave `echo` with
            # SIGPIPE (141); pipefail then propagates that and `set -e` aborts the
            # whole comparison — a timing-dependent failure that flaked on Alpine.
            # Column names are unique in the stats payload, so match the first row
            # without closing the pipe early.
            row=$(echo "${_CMP_DATA[$fi_idx]}" | awk -F'\t' -v c="$col" '$1==c && !seen{print; seen=1}')
            if [[ -z "$row" ]]; then continue; fi
            local rmean rstd rmin rmax rmedian rcv
            IFS=$'\t' read -r _ rmean rstd rmin rmax rmedian rcv <<< "$row"
            table_body+="${_CMP_LABELS[$fi_idx]}"$'\t'"$rmean"$'\t'"$rstd"$'\t'"$rmin"$'\t'"$rmax"$'\t'"$rmedian"$'\t'"$rcv"$'\n'
            means+=("$rmean")
            labels_for_rank+=("${_CMP_LABELS[$fi_idx]}")
        done

        add_item "Cross-dataset comparison: $col" "${table_body%$'\n'}" "GOOD" "compare"

        # Ranking by mean (ascending = lowest wins)
        if [[ ${#means[@]} -ge 2 ]]; then
            local rank_body=""
            # Build sortable pairs
            local rank_lines=""
            for ((ri=0; ri<${#means[@]}; ri++)); do
                rank_lines+="${means[$ri]}"$'\t'"${labels_for_rank[$ri]}"$'\n'
            done
            local rank_num=0
            while IFS=$'\t' read -r rmean rlabel; do
                [[ -z "$rlabel" ]] && continue
                rank_num=$((rank_num + 1))
                rank_body+="#${rank_num} ${rlabel} (mean: ${rmean})"$'\n'
            done <<< "$(printf "%s" "$rank_lines" | sort -g)"

            add_item "Dataset ranking: $col" "Ranked by mean (ascending):
${rank_body%$'\n'}" "GOOD" "compare_rank"
        fi
    done

    # Overall comparison summary
    local summary_body
    summary_body="Compared ${nfiles} datasets across ${#all_cols[@]} shared numeric column(s).
Datasets: $(printf "%s, " "${_CMP_LABELS[@]}" | sed 's/, $//')
Columns compared: $(printf "%s, " "${all_cols[@]}" | sed 's/, $//')"

    add_item "Comparison summary" "$summary_body" "GOOD" "compare_summary"
}
