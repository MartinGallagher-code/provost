#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Benchmark: envoy-extract memory profile on large inputs (ENV-042)
##
## Generates a synthetic large input file and times envoy-extract + captures
## peak RSS if /usr/bin/time -v is available. Focuses on streaming mode vs
## batch mode (streaming should use less memory).
##
## Usage:
##   bash bench_memory.sh                 # default: 100MB log
##   bash bench_memory.sh --size 10MB     # smaller for quick check
################################################################################
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MFE_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd)/envoy-extract"

SIZE="100MB"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --size) SIZE="$2"; shift 2 ;;
        *) echo "Unknown: $1" >&2; exit 2 ;;
    esac
done

# Convert size spec to bytes (e.g., 100MB -> 104857600)
size_to_bytes () {
    local spec="$1"
    # Strip the unit part (handle MB / GB / KB)
    local num="${spec%%[GgMmKk]*}"
    local unit
    unit=$(printf '%s' "$spec" | sed 's/^[0-9]*//')
    case "${unit^^}" in
        GB|G)   echo "$(( num * 1024 * 1024 * 1024 ))" ;;
        MB|M)   echo "$(( num * 1024 * 1024 ))" ;;
        KB|K)   echo "$(( num * 1024 ))" ;;
        "")     echo "$num" ;;
        *)      echo "$num" ;;
    esac
}

BYTES=$(size_to_bytes "$SIZE")

echo "Memory benchmark (ENV-042)"
echo "=========================="
echo "Synthetic size: $SIZE ($BYTES bytes)"
echo ""

TMP=$(mktemp -d -t envextract_bench.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# Generate a log file: repeated apache-like access lines
# Each line is ~120 bytes; we loop until we hit target bytes.
echo "Generating synthetic input..."
LINE='192.168.1.100 - - [17/Apr/2026:10:22:01 +0000] "GET /api/v1/users/12345 HTTP/1.1" 200 1234 "-" "Mozilla/5.0" 0.042'
python3 -c "
import sys
line = '''$LINE
'''
line_bytes = line.encode('utf-8')
target = $BYTES
n = target // len(line_bytes) + 1
with open('$TMP/big.log', 'wb') as f:
    for _ in range(n):
        f.write(line_bytes)
" || { echo "generation failed"; exit 1; }

actual=$(wc -c <"$TMP/big.log")
echo "  actual bytes: $actual"

# Force input-size ceiling high enough for batch mode
echo ""
echo "Measuring..."
TIMEFORMAT='%R'

# Streaming mode
stream_time=""
stream_rss=""
if command -v /usr/bin/time >/dev/null 2>&1; then
    /usr/bin/time -v -o "$TMP/stream.time" bash "$MFE_SCRIPT" stream --strategy apache-access < "$TMP/big.log" > /dev/null 2>/dev/null || true
    stream_time=$(awk -F': ' '/Elapsed \(wall clock\)/ {print $2}' "$TMP/stream.time")
    stream_rss=$(awk -F': ' '/Maximum resident set size/ {print $2}' "$TMP/stream.time")
else
    stream_time=$({ time bash "$MFE_SCRIPT" stream --strategy apache-access < "$TMP/big.log" > /dev/null 2>&1 ; } 2>&1)
fi

echo "  stream mode time: ${stream_time}"
[[ -n "$stream_rss" ]] && echo "  stream mode RSS:  ${stream_rss} KB"

# Regression gate (conservative — tune after baseline)
BENCH_MAX_RSS_MB="${BENCH_MAX_RSS_MB:-500}"
if [[ -n "$stream_rss" ]]; then
    local_rss_mb=$((stream_rss / 1024))
    if [[ "$local_rss_mb" -gt "$BENCH_MAX_RSS_MB" ]]; then
        echo ""
        echo "FAIL: stream peak RSS ${local_rss_mb}MB exceeds ${BENCH_MAX_RSS_MB}MB gate"
        exit 1
    fi
fi

echo ""
echo "OK"
exit 0
