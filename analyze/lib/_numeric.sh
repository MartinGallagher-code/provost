#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Per-column numeric analyses for envoy-analyze (optimized: combined single-pass)
##
## Analyses: summary stats, histogram, sparkline, anomaly detection,
## distribution shape, CV, mode, normality, precision, trend detection,
## bimodality, Benford's Law, monotonicity.
##
## Each numeric column is analyzed in ONE awk pass over the input file (plus
## a sort + small awk for percentiles). Previously required ~10 awk passes
## per column.
##
## Reads:  input_file delim COL_COUNT COL_NAMES COL_TYPE
##         COL_MEAN COL_STD COL_SKEW COL_KURT COL_MIN COL_MAX
##         COL_NUMERIC COL_TEXT
##         ROW_COUNT SPARK_SAMPLES
##         AWK_ISMISSING BENFORD_CRIT BENFORD_ALPHA
## Writes: _NUM_P05 _NUM_Q1 _NUM_P50 _NUM_Q3 _NUM_P95 cleanup_files
##         ITEM_TITLES ITEM_BODIES ITEM_TAGS ITEM_KINDS (via add_item)
################################################################################

# Percentile values set by anomaly detection for use by shape analysis
_NUM_P05="n/a"
_NUM_Q1="n/a"
_NUM_P50="n/a"
_NUM_Q3="n/a"
_NUM_P95="n/a"

########################################
## Combined single-pass awk for one numeric column. Emits 9 fixed-order
## lines parsed by run_numeric_analyses; body in lib/awk/numeric_combined.awk
## (ENV-123). Args: col min max mean std skip tmp_vals.
_numeric_combined_awk () {
    local col="$1" cmin="$2" cmax="$3" cmean="$4" cstd="$5" skip="$6" tmp_vals="$7"

    awk -F"$delim" \
        -v col="$col" -v mn="$cmin" -v mx="$cmax" \
        -v mean="$cmean" -v std="$cstd" -v skip="$skip" \
        -v maxn="$SPARK_SAMPLES" -v tmpfile="$tmp_vals" \
        -v benford_crit="${BENFORD_CRIT:-15.507}" \
        -f "$SCRIPT_DIR/lib/awk/numeric_combined.awk" \
        "$input_file"
}

########################################
## Percentile computation from sorted values.
## Sets _NUM_P05..P95 globals and emits the anomaly item.
## Args: tmp_vals col_name z_count z_vals
##
_numeric_percentiles () {
    local tmp_vals="$1" col_name="$2" z_count="$3" z_vals="$4"

    _NUM_P05="n/a"; _NUM_Q1="n/a"; _NUM_P50="n/a"; _NUM_Q3="n/a"; _NUM_P95="n/a"

    local p05="n/a" q1="n/a" p50="n/a" q3="n/a" p95="n/a"
    local iqr_body="Q1: n/a
Q3: n/a
IQR: n/a
Outliers: 0
Samples: none"

    if [[ -s "$tmp_vals" ]]; then
        local tmp_sorted
        tmp_sorted="$(mktemp -t mda-sorted.XXXXXX)"
        cleanup_files+=("$tmp_sorted")
        sort -n "$tmp_vals" > "$tmp_sorted"
        local iqr_stats
        iqr_stats=$(awk '
            function quantile(p, idx, lo, hi, frac) {
                idx=(n-1)*p+1
                lo=int(idx)
                hi=lo+1
                if (hi>n) hi=n
                frac=idx-lo
                return a[lo] + frac*(a[hi]-a[lo])
            }
            {a[NR]=$1}
            END{
                n=NR
                if (n==0) {print ""; exit}
                p05=quantile(0.05)
                q1=quantile(0.25)
                p50=quantile(0.50)
                q3=quantile(0.75)
                p95=quantile(0.95)
                iqr=q3-q1
                low=q1-1.5*iqr
                high=q3+1.5*iqr
                for(i=1;i<=n;i++){
                    if(a[i]<low || a[i]>high){
                        count++
                        if(count<=5) samples[count]=a[i]
                    }
                }
                printf "%.4f %.4f %.4f %.4f %.4f %.4f %d", p05, q1, p50, q3, p95, iqr, count+0
                for(i=1;i<=count && i<=5;i++) printf "|%s", samples[i]
            }
        ' "$tmp_sorted")

        if [[ -n "$iqr_stats" ]]; then
            local out_count out_vals iqr
            read -r p05 q1 p50 q3 p95 iqr out_count <<< "${iqr_stats%%|*}"
            out_vals=""
            if [[ "$iqr_stats" == *"|"* ]]; then
                out_vals=${iqr_stats#*|}
            fi
            iqr_body="Q1: $q1
Q3: $q3
IQR: $iqr
Outliers: $out_count
Samples: ${out_vals:-none}"
        fi
    fi

    _NUM_P05="$p05"; _NUM_Q1="$q1"; _NUM_P50="$p50"; _NUM_Q3="$q3"; _NUM_P95="$p95"

    add_item "Anomaly detection: $col_name" "Z-score outliers (|z|>3): $z_count
Samples: ${z_vals:-none}

IQR outliers (1.5x):
$iqr_body" "NOISY" "anomaly"
}

########################################
## Main entry point: loop numeric columns, emit all analysis items.
##
run_numeric_analyses () {
    for ((i=1; i<=COL_COUNT; i++)); do
        local col_name="${COL_NAMES[$((i-1))]}"
        local col_type="${COL_TYPE[$((i-1))]}"

        # ENV-135: per-column progress tick on the slowest stage. The
        # global gate `_ENV135_SHOW_PROGRESS` is set in envoy-analyze
        # right before this is called.
        if [[ "${_ENV135_SHOW_PROGRESS:-0}" == "1" ]]; then
            envoy_progress_tick "$i" "$COL_COUNT" "stats: $col_name"
        fi

        if [[ "$col_type" != "numeric" ]]; then
            continue
        fi

        local min="${COL_MIN[$((i-1))]}"
        local max="${COL_MAX[$((i-1))]}"
        local mean="${COL_MEAN[$((i-1))]}"
        local std="${COL_STD[$((i-1))]}"
        local col_skew="${COL_SKEW[$((i-1))]}"
        local col_kurt="${COL_KURT[$((i-1))]}"

        ## 1. Summary stats
        # ENV-132: when the column was classified as numeric but had any
        # non-numeric rows, the mean / std are computed over the numeric
        # subset only. Surface that subset's size inline so the user
        # doesn't read "Mean: 45" without realising 20% of rows were
        # silently dropped. The 0% case (clean numeric column) renders
        # exactly as before — no annotation noise.
        local _excluded="${COL_TEXT[$((i-1))]:-0}"
        local summary_body="Min: $min
Max: $max
Mean: $mean
Std: $std"
        if [[ "${_excluded:-0}" -gt 0 ]]; then
            local _total_rows=$(( ${COL_NUMERIC[$((i-1))]:-0} + _excluded ))
            local _pct
            if [[ "$_total_rows" -gt 0 ]]; then
                local _p100=$(( ${COL_NUMERIC[$((i-1))]:-0} * 10000 / _total_rows ))
                _pct="$(( _p100 / 100 )).$(printf '%02d' $(( _p100 % 100 )))"
            else
                _pct="0.00"
            fi
            summary_body+=$'\n'"Note: $_excluded non-numeric value(s) excluded from mean/std (${_pct}% numeric)"
        fi
        add_item "Summary stats: $col_name" "$summary_body" "GOOD" "summary"

        ## 2. Run combined single-pass awk
        local tmp_vals
        tmp_vals="$(mktemp -t mda-vals.XXXXXX)"
        cleanup_files+=("$tmp_vals")

        local skip=$(( (ROW_COUNT + SPARK_SAMPLES - 1) / SPARK_SAMPLES ))

        local combined
        combined=$(_numeric_combined_awk "$i" "$min" "$max" "$mean" "$std" "$skip" "$tmp_vals")

        # Parse all 9 fixed-order lines into variables
        local _L=()
        while IFS= read -r _cl; do
            _L+=("$_cl")
        done <<< "$combined"

        local hist_data="${_L[0]:-}"
        local spark_data="${_L[1]:-}"
        local mode_data="${_L[2]:-}"
        local prec_data="${_L[3]:-}"
        local benf_data="${_L[4]:-}"
        local mono_data="${_L[5]:-}"
        local bimod_data="${_L[6]:-}"
        local zout_data="${_L[7]:-}"
        local trend_data="${_L[8]:-}"

        ## 3. Histogram
        if [[ -n "$hist_data" ]]; then
            local hist_body=""
            local bin_spec hbin hstart hend hcount bar
            IFS=';' read -r -a hist_bins <<< "$hist_data"
            for bin_spec in "${hist_bins[@]}"; do
                IFS='|' read -r hbin hstart hend hcount <<< "$bin_spec"
                bar=""
                if [[ "$hcount" -gt 0 ]]; then
                    bar=$(printf "%0.s#" $(seq 1 $((hcount>20?20:hcount))))
                fi
                hist_body+="Bin $hbin ($hstart - $hend): $hcount $bar"$'\n'
            done
            add_item "Histogram: $col_name" "${hist_body%$'\n'}" "GOOD" "histogram"
        fi

        ## 4. Sparkline
        if [[ -n "$spark_data" && "$ROW_COUNT" -gt 0 ]]; then
            add_item "Sparkline: $col_name" "Samples: $spark_data" "GOOD" "sparkline"
        fi

        ## 5. Anomaly detection + percentiles (sort tmpfile, compute IQR)
        local z_count="${zout_data%%|*}"
        local z_vals=""
        if [[ "$zout_data" == *"|"* ]]; then
            z_vals="${zout_data#*|}"
        fi

        _numeric_percentiles "$tmp_vals" "$col_name" "$z_count" "$z_vals"
        COL_Q1[$((i-1))]="$_NUM_Q1"
        COL_Q3[$((i-1))]="$_NUM_Q3"

        ## 6. Distribution shape (uses percentiles set by step 5)
        add_item "Distribution shape: $col_name" "Skewness: ${col_skew}
Kurtosis (excess): ${col_kurt}
P05: ${_NUM_P05}
P25: ${_NUM_Q1:-n/a}
P50: ${_NUM_P50}
P75: ${_NUM_Q3:-n/a}
P95: ${_NUM_P95}" "ADVANCED" "shape"

        ## 7. CV (pure math, no file I/O)
        if float_cmp "$mean" "!=" "0"; then
            local cv
            cv=$(awk -v s="$std" -v m="$mean" 'BEGIN{if(m<0) m=-m; printf "%.2f", (s/m)*100}')
            local cv_interp="high variability"
            if float_cmp "$cv" "<" "15"; then
                cv_interp="low variability"
            elif float_cmp "$cv" "<" "30"; then
                cv_interp="moderate variability"
            fi
            add_item "Coefficient of variation: $col_name" "CV: ${cv}%
Mean: $mean
Std: $std
Interpretation: $cv_interp" "ADVANCED" "cv"
        fi

        ## 8. Mode
        local mode_val mode_count mode_uniq
        IFS='|' read -r mode_val mode_count mode_uniq <<< "$mode_data"
        if [[ "$mode_val" != "n/a" && "$mode_count" -gt 1 ]]; then
            add_item "Mode: $col_name" "Mode: $mode_val (appears $mode_count times)
Unique values: $mode_uniq" "ADVANCED" "mode"
        fi

        ## 9. Normality (pure math, no file I/O)
        local norm_desc
        local abs_skew="${col_skew#-}"
        if float_cmp "$abs_skew" "<" "0.5" && float_cmp "$col_kurt" ">" "-1" && float_cmp "$col_kurt" "<" "1"; then
            norm_desc="approximately normal"
        elif float_cmp "$abs_skew" ">=" "0.5" && float_cmp "$abs_skew" "<" "1"; then
            norm_desc="moderately skewed"
        elif float_cmp "$abs_skew" ">=" "1"; then
            norm_desc="highly skewed"
        else
            norm_desc="unknown shape"
        fi
        if float_cmp "$col_kurt" ">" "2"; then
            norm_desc+=", heavy-tailed (leptokurtic)"
        elif float_cmp "$col_kurt" "<" "-1"; then
            norm_desc+=", light-tailed (platykurtic)"
        fi
        local skew_dir=""
        if float_cmp "$col_skew" ">" "0.5"; then
            skew_dir="right-skewed"
        elif float_cmp "$col_skew" "<" "-0.5"; then
            skew_dir="left-skewed"
        else
            skew_dir="symmetric"
        fi
        add_item "Normality: $col_name" "Shape: $norm_desc
Direction: $skew_dir
Skewness: $col_skew
Excess kurtosis: $col_kurt" "ADVANCED" "normality"

        ## 10. Precision
        local prec_total prec_int prec_dec prec_maxdp prec_avgdp
        IFS='|' read -r prec_total prec_int prec_dec prec_maxdp prec_avgdp <<< "$prec_data"
        local prec_type="integer"
        if [[ "$prec_dec" -gt 0 ]]; then
            if [[ "$prec_int" -eq 0 ]]; then
                prec_type="decimal"
            else
                prec_type="mixed (${prec_int} integer, ${prec_dec} decimal)"
            fi
        fi
        add_item "Numeric precision: $col_name" "Type: $prec_type
Max decimal places: $prec_maxdp
Avg decimal places: $prec_avgdp" "ADVANCED" "precision"

        ## 11. Trend
        if [[ "$trend_data" != "NA" ]]; then
            local trend_desc abs_trend="${trend_data#-}"
            if float_cmp "$abs_trend" "<" "0.3"; then
                trend_desc="no trend"
            elif float_cmp "$abs_trend" "<" "0.7"; then
                trend_desc="moderate trend"
            else
                trend_desc="strong trend"
            fi
            if float_cmp "$trend_data" ">" "0.3"; then
                trend_desc+=" (increasing)"
            elif float_cmp "$trend_data" "<" "-0.3"; then
                trend_desc+=" (decreasing)"
            fi
            add_item "Trend: $col_name" "Spearman rho vs row order: $trend_data
$trend_desc" "ADVANCED" "trend"

            ## ENV-057: oscillation detection. Count sign changes in first
            ## differences of sequential numeric values. If the ratio of
            ## sign-changes to transitions exceeds 0.6, report as oscillating.
            local osc_data
            osc_data=$(awk -v col="$i" -F"$delim" "$AWK_ISMISSING"'
                function isnum(x){ return (x ~ /^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$/) }
                NR==1{next}
                {
                    v = $col
                    gsub(/^[ \t]+|[ \t]+$/, "", v)
                    if (ismissing(v) || !isnum(v)) next
                    if (have_prev) {
                        diff = v - prev
                        if (have_prev_diff && prev_diff != 0 && diff != 0) {
                            if ((prev_diff > 0) != (diff > 0)) changes++
                            transitions++
                        }
                        prev_diff = diff
                        have_prev_diff = 1
                    }
                    prev = v
                    have_prev = 1
                }
                END {
                    if (transitions < 5) { print "NA"; exit }
                    ratio = changes / transitions
                    printf "%d|%d|%.3f\n", changes, transitions, ratio
                }' "$input_file")
            if [[ -n "$osc_data" && "$osc_data" != "NA" ]]; then
                local osc_changes osc_trans osc_ratio
                IFS='|' read -r osc_changes osc_trans osc_ratio <<< "$osc_data"
                if float_cmp "$osc_ratio" ">=" "0.6"; then
                    add_item "Oscillation: $col_name" "Sign-change ratio: $osc_ratio ($osc_changes / $osc_trans transitions)
Column alternates direction frequently — consider treating as oscillating rather than trending." "ADVANCED" "oscillation"
                fi
            fi
        fi

        ## 12. Bimodality
        local bimod_flag bimod_peaks bimod_h1 bimod_h2
        IFS='|' read -r bimod_flag bimod_peaks bimod_h1 bimod_h2 <<< "$bimod_data"
        if [[ "$bimod_flag" == "YES" ]]; then
            add_item "Bimodality: $col_name" "Bimodal: YES
Peaks detected: $bimod_peaks
Peak heights: $bimod_h1, $bimod_h2
A valley between peaks drops below 50% of the smaller peak." "ADVANCED" "bimodality"
        fi

        ## 13. Benford's Law
        if [[ "$benf_data" != "INSUFFICIENT" ]]; then
            local benford_body="" benford_chi2=""
            local -a benford_parts
            IFS='|' read -r -a benford_parts <<< "$benf_data"
            local part
            for part in "${benford_parts[@]}"; do
                if [[ "$part" =~ ^[0-9]+: ]]; then
                    local digit obs exp
                    IFS=':' read -r digit obs exp <<< "$part"
                    benford_body+="Digit $digit: observed ${obs}%, expected ${exp}%"$'\n'
                fi
            done
            local n_parts=${#benford_parts[@]}
            local benford_verdict="${benford_parts[$((n_parts-2))]}"
            benford_chi2="${benford_parts[$((n_parts-1))]}"
            add_item "Benford's Law: $col_name" "${benford_body}Chi-squared: $benford_chi2 (df=8, critical=${BENFORD_CRIT:-15.507}, alpha=${BENFORD_ALPHA:-0.05})
Result: $benford_verdict ($(if [[ "$benford_verdict" == "PASS" ]]; then echo "distribution follows Benford's Law"; else echo "deviation from Benford's Law detected"; fi))" "ADVANCED" "benford"
        fi

        ## 14. Monotonicity
        local mono_n mono_asc mono_desc mono_eq mono_pairs
        IFS='|' read -r mono_n mono_asc mono_desc mono_eq mono_pairs <<< "$mono_data"
        if [[ "$mono_n" != "NA" && "$mono_pairs" -gt 0 ]]; then
            local asc_pct desc_pct mono_label
            # Compute percentage with 1 decimal using bash integer math (scaled by 10)
            local _a10=$(( mono_asc * 1000 / mono_pairs ))
            asc_pct="$(( _a10 / 10 )).$(( _a10 % 10 ))"
            local _d10=$(( mono_desc * 1000 / mono_pairs ))
            desc_pct="$(( _d10 / 10 )).$(( _d10 % 10 ))"
            mono_label="not sorted"
            if [[ "$mono_asc" -eq "$mono_pairs" ]]; then
                mono_label="perfectly sorted (ascending)"
            elif [[ "$mono_desc" -eq "$mono_pairs" ]]; then
                mono_label="perfectly sorted (descending)"
            elif float_cmp "$asc_pct" ">=" "90"; then
                mono_label="nearly sorted (ascending, ${asc_pct}%)"
            elif float_cmp "$desc_pct" ">=" "90"; then
                mono_label="nearly sorted (descending, ${desc_pct}%)"
            fi
            if [[ "$mono_label" != "not sorted" ]]; then
                add_item "Monotonicity: $col_name" "$mono_label
Ascending pairs: $mono_asc/$mono_pairs (${asc_pct}%)
Descending pairs: $mono_desc/$mono_pairs (${desc_pct}%)
Equal pairs: $mono_eq" "ADVANCED" "monotonicity"
            fi
        fi
    done
}
