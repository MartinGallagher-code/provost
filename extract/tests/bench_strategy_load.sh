#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Benchmark: strategy-load time for provost-extract (ENV-017)
##
## Measures cold-start time to discover and read metadata for all shipped
## strategies. Runs several iterations and reports min, median, max.
##
## Usage: bash bench_strategy_load.sh [ITERATIONS]
################################################################################
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVOST_EXTRACT_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/provost-extract"
ITERATIONS="${1:-10}"

if [[ ! -x "$PROVOST_EXTRACT_SCRIPT" ]]; then
    echo "ERROR: provost-extract not found at $PROVOST_EXTRACT_SCRIPT" >&2
    exit 2
fi

echo "Strategy-load benchmark (ENV-017)"
echo "================================="
echo "Iterations: $ITERATIONS"
echo ""

TIMEFORMAT='%R'
samples=()

for i in $(seq 1 "$ITERATIONS"); do
    t=$({ time bash "$PROVOST_EXTRACT_SCRIPT" list > /dev/null 2>&1 ; } 2>&1)
    samples+=("$t")
    printf "  run %2d: %s s\n" "$i" "$t"
done

# Compute min / median / max via sort
sorted=$(printf '%s\n' "${samples[@]}" | sort -n)
min=$(echo "$sorted" | head -1)
max=$(echo "$sorted" | tail -1)
mid_idx=$((ITERATIONS / 2 + 1))
median=$(echo "$sorted" | sed -n "${mid_idx}p")

# Strategy count for context
strategy_count=$(bash "$PROVOST_EXTRACT_SCRIPT" list 2>/dev/null | grep -c '^  ')

echo ""
echo "Results"
echo "-------"
echo "  strategies: $strategy_count"
echo "  min:        $min s"
echo "  median:     $median s"
echo "  max:        $max s"

# Optional regression gate: fail if max exceeds 1s cold.
REGRESSION_MAX="${BENCH_MAX:-1.000}"
over=$(awk -v m="$max" -v r="$REGRESSION_MAX" 'BEGIN{exit !(m>r)}' && echo 1 || echo 0)
if [[ "$over" -eq 1 ]]; then
    echo ""
    echo "FAIL: max time $max s exceeded ${REGRESSION_MAX}s threshold"
    exit 1
fi

echo ""
echo "OK: max time $max s under ${REGRESSION_MAX}s threshold"
exit 0
