#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Benchmark: provost-analyze on large datasets (ENV-024)
##
## Generates a synthetic CSV with a mix of numeric, categorical, and sparse
## columns, then times a full --all analysis. Produces baselines that can
## back a regression test.
##
## Usage:
##   bash bench_large_dataset.sh                    # default: 10k + 100k
##   bash bench_large_dataset.sh --rows 10000       # single size
################################################################################
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDA_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/provost-analyze"

SIZES=(10000 100000)
SEED=1337

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rows) SIZES=("$2"); shift 2 ;;
        --seed) SEED="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

# Default regression thresholds (seconds)
BENCH_MAX_10K="${BENCH_MAX_10K:-10}"
BENCH_MAX_100K="${BENCH_MAX_100K:-60}"

# Generate a synthetic CSV.
# Columns: id (numeric, unique), region (categorical low card), score (numeric),
#          timestamp (numeric), label (categorical high card), note (sparse text)
gen_csv () {
    local rows="$1" path="$2" seed="$3"
    awk -v rows="$rows" -v seed="$seed" 'BEGIN{
        srand(seed)
        regions[0]="us-east"; regions[1]="us-west"; regions[2]="eu"; regions[3]="apac"
        printf "id,region,score,timestamp,label,note\n"
        for (i=1; i<=rows; i++){
            r=regions[int(rand()*4)]
            s=int(rand()*1000) + 1
            t=1700000000 + int(rand()*86400*365)
            lbl="lbl_" int(rand()*500)
            nt=""
            if (rand() < 0.20) nt="obs_" int(rand()*10000)
            printf "%d,%s,%d,%d,%s,%s\n", i, r, s, t, lbl, nt
        }
    }' > "$path"
}

echo "Large-dataset benchmark for provost-analyze (ENV-024)"
echo "==================================================="
echo "Seed: $SEED"
echo ""

TMP=$(mktemp -d -t envanalyze_bench.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

any_over=0

for rows in "${SIZES[@]}"; do
    csv="$TMP/synth_${rows}.csv"
    echo "--- $rows rows ---"
    gen_t0=$(date +%s.%N)
    gen_csv "$rows" "$csv" "$SEED"
    gen_t1=$(date +%s.%N)
    gen_dur=$(awk -v a="$gen_t0" -v b="$gen_t1" 'BEGIN{printf "%.2f", b-a}')
    bytes=$(wc -c <"$csv")
    echo "  generated ${bytes} bytes in ${gen_dur}s"

    # Measure wall time via bash builtin. Memory sampling is optional and
    # only runs if /usr/bin/time is available (not present in minimal containers).
    sec=""
    peak=""
    TIMEFORMAT='%R'
    if command -v /usr/bin/time >/dev/null 2>&1; then
        out_file="$TMP/time_${rows}.out"
        /usr/bin/time -v -o "$out_file" bash "$MDA_SCRIPT" --all "$csv" >/dev/null 2>&1 || true
        wall=$(awk -F': ' '/Elapsed \(wall clock\)/ {print $2}' "$out_file")
        peak=$(awk -F': ' '/Maximum resident set size/ {print $2}' "$out_file")
        sec=$(awk -v t="$wall" 'BEGIN{
            n = split(t, p, ":")
            if (n==2) { print p[1]*60 + p[2] }
            else if (n==3) { print p[1]*3600 + p[2]*60 + p[3] }
            else { print t }
        }')
    else
        sec=$({ time bash "$MDA_SCRIPT" --all "$csv" > /dev/null 2>&1 ; } 2>&1)
    fi

    if [[ -n "$sec" ]]; then
        echo "  analyze:      ${sec} s"
        [[ -n "$peak" ]] && echo "  peak RSS:     ${peak} KB"

        # Regression check
        local_threshold="$BENCH_MAX_10K"
        [[ "$rows" -ge 100000 ]] && local_threshold="$BENCH_MAX_100K"
        if awk -v v="$sec" -v t="$local_threshold" 'BEGIN{exit !(v>t)}'; then
            echo "  FAIL: analyze time ${sec}s exceeds threshold ${local_threshold}s"
            any_over=1
        else
            echo "  OK: under threshold ${local_threshold}s"
        fi
    else
        echo "  FAIL: could not measure analyze time"
        any_over=1
    fi
    echo ""
done

if [[ $any_over -eq 1 ]]; then
    exit 1
fi
echo "All size points under thresholds."
exit 0
