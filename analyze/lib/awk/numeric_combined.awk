# numeric_combined.awk — single-pass per-column numeric analysis.
#
# Computes nine analyses in one pass over the input file: histogram,
# sparkline, mode, precision, Benford's Law, monotonicity, bimodality,
# z-score outliers, and Spearman trend. Emits nine fixed-order lines on
# stdout which `_numeric.sh`'s `run_numeric_analyses` parses into the
# final report items.
#
# Extracted from an inline bash heredoc in ENV-123 (2026-04-24). No
# behaviour change — the awk body is byte-identical; only the quoting
# / interpolation wrapper moved out. Bash dynamic values reach this
# program exclusively through `-v` flags:
#
#   -v col           1-based column index
#   -v mn,mx         min, max from the summary stats phase
#   -v mean,std      mean, stddev from the summary stats phase
#   -v skip          sparkline sampling stride (rows per sample)
#   -v maxn          sparkline max samples ($SPARK_SAMPLES)
#   -v tmpfile       path to write numeric values for percentile sort
#   -v benford_crit  chi-square critical value ($BENFORD_CRIT)
#
# The delimiter (`-F"$delim"`) and input file path are supplied by the
# invoking bash wrapper, as is the output destination (stdout).

function trim(t){ gsub(/^[ \t]+|[ \t]+$/, "", t); return t }
function isnum(x){ return (x ~ /^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$/) }

# Initialise everything the END block touches so `awk -W lint -f … </dev/null`
# is silent. Awk would happily treat these as 0/"" anyway, but explicit init
# documents intent and lets gawk's lint pass on empty input.
BEGIN {
    # Initialise everything the END block touches so gawk's `--lint`
    # is silent on empty input. Awk would happily treat these as 0/""
    # anyway; explicit init documents intent and lets CI run lint as
    # part of the structural test (see tests/test_module_contracts.sh).
    n = 0; row = 0; num_row = 0; spark = ""; spark_n = 0
    prev_vn = 0
    prec_total = 0; prec_integer = 0; prec_decimal = 0
    prec_maxdp = 0; prec_sumdp = 0
    benford_total = 0
    mono_asc = 0; mono_desc = 0; mono_eq = 0
    zcount = 0
    # Histogram and bimodality bins (5 + 10 fixed indices).
    for (_i = 0; _i < 5; _i++) hcount[_i] = 0
    for (_i = 0; _i < 10; _i++) bcount[_i] = 0
    # Benford's first-significant-digit buckets.
    for (_i = 1; _i <= 9; _i++) benford[_i] = 0
    # Declare mode_count as an array so the END-block `for (k in
    # mode_count)` doesn't trip gawk's "for loop on untyped variable"
    # lint when there is no data to populate it.
    mode_count["__init"] = 0; delete mode_count["__init"]
}

NR==1{next}
{
    row++
    v=trim($col)
    is_num=isnum(v)

    # Sparkline sampling (uses numeric-row count for even spacing)
    if(is_num && num_row++ % skip == 0 && spark_n < maxn){
        vn_s=v+0
        if(mx==mn) sidx=4
        else sidx=int((vn_s-mn)/(mx-mn)*7)
        if(sidx<0) sidx=0; if(sidx>7) sidx=7
        spark = spark substr(" .:-=+*#", sidx+1, 1)
        spark_n++
    }

    if(!is_num) next
    vn=v+0
    n++

    # Value extraction for percentile sorting
    print vn > tmpfile

    # Trend: store values and row indices for Spearman
    tval[n]=vn; trow[n]=row

    # Histogram (5 bins)
    if(mn!=mx){
        hidx=int((vn-mn)/(mx-mn)*5)
        if(hidx>=5) hidx=4
        hcount[hidx]++
    }

    # Mode (count occurrences)
    mode_count[v]++

    # Precision
    prec_total++
    if(v ~ /\./){
        prec_decimal++
        split(v, dp_parts, ".")
        dp=length(dp_parts[2])
        if(dp>prec_maxdp) prec_maxdp=dp
        prec_sumdp+=dp
    } else {
        prec_integer++
    }

    # Benford (first significant digit)
    if(vn!=0){
        s=v; gsub(/^-/, "", s); gsub(/^0+\./, "0.", s)
        for(k=1;k<=length(s);k++){
            ch=substr(s,k,1)
            if(ch>="1" && ch<="9"){benford[ch+0]++; benford_total++; break}
        }
    }

    # Monotonicity
    if(n>1){
        if(vn>prev_vn) mono_asc++
        else if(vn<prev_vn) mono_desc++
        else mono_eq++
    }
    prev_vn=vn

    # Bimodality (10 bins)
    if(mn!=mx){
        bidx=int((vn-mn)/(mx-mn)*10)
        if(bidx>=10) bidx=9
        bcount[bidx]++
    }

    # Z-score outliers
    if(std+0>0){
        z=(vn-mean)/std
        if(z<-3 || z>3){
            zcount++
            if(zcount<=5) zvals[zcount]=vn
        }
    }
}
END{
    ## Line 0: HISTOGRAM (semicolon-separated bins, each pipe-delimited)
    if(mn!=mx){
        for(i=0;i<5;i++){
            bstart=mn + (mx-mn)/5*i
            bend=bstart + (mx-mn)/5
            if(i>0) printf ";"
            printf "%d|%.4f|%.4f|%d", i+1, bstart, bend, hcount[i]+0
        }
    }
    printf "\n"

    ## Line 1: SPARKLINE
    printf "%s\n", spark

    ## Line 2: MODE (pipe-separated: val|count|unique)
    maxc=0; uniq=0
    for(k in mode_count){
        uniq++
        if(mode_count[k]>maxc){maxc=mode_count[k]; maxv=k}
    }
    printf "%s|%d|%d\n", (maxc>0? maxv : "n/a"), maxc, uniq

    ## Line 3: PRECISION (pipe-separated: total|int|dec|maxdp|avgdp)
    printf "%d|%d|%d|%d|%.1f\n", prec_total, prec_integer+0, prec_decimal+0, prec_maxdp+0, (prec_decimal>0? prec_sumdp/prec_decimal : 0)

    ## Line 4: BENFORD (original pipe-separated format)
    if(benford_total<20){
        printf "INSUFFICIENT\n"
    } else {
        split("30.1 17.6 12.5 9.7 7.9 6.7 5.8 5.1 4.6", expected, " ")
        chi2=0
        for(d=1;d<=9;d++){
            obs=(benford[d]+0)/benford_total*100
            exv=expected[d]+0
            chi2 += (obs-exv)*(obs-exv)/exv
            printf "%d:%.1f:%.1f|", d, obs, exv
        }
        if(chi2<benford_crit) printf "PASS|%.2f\n", chi2
        else printf "FAIL|%.2f\n", chi2
    }

    ## Line 5: MONOTONICITY (pipe-separated: n|asc|desc|eq|pairs)
    pairs=n-1
    if(n<2) printf "NA|0|0|0|0\n"
    else printf "%d|%d|%d|%d|%d\n", n, mono_asc+0, mono_desc+0, mono_eq+0, pairs

    ## Line 6: BIMODALITY (pipe-separated: flag|peaks|h1|h2)
    if(n>=10 && mn!=mx){
        np=0
        for(i=0;i<10;i++){
            c=bcount[i]+0
            prev_c=(i>0? bcount[i-1]+0 : 0)
            next_c=(i<9? bcount[i+1]+0 : 0)
            min_peak = n * 0.005
            if(min_peak < 1) min_peak = 1
            if(c >= min_peak && c >= prev_c && c >= next_c && (c > prev_c || c > next_c)){
                np++
                peaks[np]=i; peakh[np]=c
            }
        }
        if(np>=2){
            p1=1; p2=2
            if(peakh[2]>peakh[1]){p1=2; p2=1}
            for(k=3;k<=np;k++){
                if(peakh[k]>peakh[p1]){p2=p1; p1=k}
                else if(peakh[k]>peakh[p2]) p2=k
            }
            lo=peaks[p1]; hi=peaks[p2]
            if(lo>hi){tmp=lo; lo=hi; hi=tmp}
            valley=peakh[p1]
            for(i=lo+1;i<hi;i++){
                if(bcount[i]+0 < valley) valley=bcount[i]+0
            }
            thresh=(peakh[p1]<peakh[p2]? peakh[p1] : peakh[p2]) * 0.5
            if(valley < thresh) printf "YES|%d|%d|%d\n", np, peakh[p1], peakh[p2]
            else printf "NO|%d|0|0\n", np
        } else {
            printf "NO|%d|0|0\n", np
        }
    } else {
        printf "NO|0|0|0\n"
    }

    ## Line 7: Z-SCORE OUTLIERS (pipe-separated: count|v1, v2, ...)
    printf "%d", zcount+0
    if(zcount>0){
        printf "|"
        for(i=1;i<=zcount && i<=5;i++) printf "%s%s", zvals[i], (i<zcount && i<5?", ":"")
    }
    printf "\n"

    ## Line 8: TREND (Spearman rank correlation)
    if(n<3){
        printf "NA\n"
    } else {
        # Shell sort to compute ranks (O(n^3/2) vs O(n^2) bubble)
        for(i=1;i<=n;i++) order[i]=i
        h=1; while(h<n) h=3*h+1
        while(h>1){
            h=int(h/3)
            for(i=h+1;i<=n;i++){
                tmp=order[i]; j=i
                while(j>h && tval[order[j-h]]>tval[tmp]){
                    order[j]=order[j-h]; j-=h
                }
                order[j]=tmp
            }
        }
        for(i=1;i<=n;i++) rank[order[i]]=i
        # Handle ties
        i=1
        while(i<=n){
            j=i
            while(j<=n && tval[order[j]]==tval[order[i]]) j++
            avg=(i+j-1)/2.0
            for(k=i;k<j;k++) rank[order[k]]=avg
            i=j
        }
        # Spearman correlation
        for(i=1;i<=n;i++){sr+=rank[i]; srr+=trow[i]}
        mr=sr/n; mrr=srr/n
        for(i=1;i<=n;i++){
            d1=rank[i]-mr; d2=trow[i]-mrr
            cov+=d1*d2; v1+=d1*d1; v2+=d2*d2
        }
        if(v1>0 && v2>0) printf "%.6f\n", cov/sqrt(v1*v2)
        else printf "NA\n"
    }
}
