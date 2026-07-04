#!/bin/bash
################################################################################
## Strategy Tests: darshan
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: darshan"
echo "========================================"

SAMPLE_DARSHAN=$(cat <<'EOFSAMPLE'
# darshan log version: 3.21
# exe: /usr/bin/myapp --input data.h5
# nprocs: 64
# run time: 3600
# start_time: 2026-03-15 10:00:00

POSIX  0  12345  POSIX_OPENS  100  /scratch/data/input.h5  /scratch  lustre
POSIX  0  12345  POSIX_READS  5000  /scratch/data/input.h5  /scratch  lustre
POSIX  0  12345  POSIX_WRITES  2000  /scratch/data/input.h5  /scratch  lustre
POSIX  0  12345  POSIX_BYTES_READ  1048576000  /scratch/data/input.h5  /scratch  lustre
POSIX  0  12345  POSIX_BYTES_WRITTEN  524288000  /scratch/data/input.h5  /scratch  lustre
POSIX  0  12345  POSIX_FSYNCS  50  /scratch/data/input.h5  /scratch  lustre
MPI-IO  0  12345  MPIIO_INDEP_OPENS  10  /scratch/data/input.h5  /scratch  lustre
MPI-IO  0  12345  MPIIO_COLL_READS  200  /scratch/data/input.h5  /scratch  lustre
MPI-IO  0  12345  MPIIO_BYTES_READ  2097152  /scratch/data/input.h5  /scratch  lustre
EOFSAMPLE
)

test_darshan_detect () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_DARSHAN" > "$tmpfile"
    local output
    output=$(run_mfe -d -s darshan "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "applicable" "darshan should detect darshan-parser output"
}

test_darshan_extract_metadata () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_DARSHAN" > "$tmpfile"
    local output
    output=$(run_mfe -r -s darshan "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "log_version 3.21" "should extract log version"
    assert_contains "$output" "nprocs 64" "should extract nprocs"
    assert_contains "$output" "run_time 3600" "should extract run_time"
}

test_darshan_extract_posix () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_DARSHAN" > "$tmpfile"
    local output
    output=$(run_mfe -r -s darshan "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "posix_opens 100" "should extract posix opens"
    assert_contains "$output" "posix_reads 5000" "should extract posix reads"
    assert_contains "$output" "posix_writes 2000" "should extract posix writes"
    assert_contains "$output" "posix_bytes_read 1048576000" "should extract posix bytes read"
    assert_contains "$output" "posix_bytes_written 524288000" "should extract posix bytes written"
}

test_darshan_extract_totals () {
    local tmpfile
    tmpfile=$(mktemp)
    echo "$SAMPLE_DARSHAN" > "$tmpfile"
    local output
    output=$(run_mfe -r -s darshan "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "total_bytes_read" "should have total_bytes_read"
    assert_contains "$output" "total_bytes_written" "should have total_bytes_written"
    assert_contains "$output" "mpiio_bytes_read 2097152" "should extract mpiio bytes read"
}

test_darshan_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test"}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s darshan "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "darshan should not apply to JSON"
}

run_test "darshan: detection" test_darshan_detect
run_test "darshan: metadata extraction" test_darshan_extract_metadata
run_test "darshan: POSIX counters" test_darshan_extract_posix
run_test "darshan: totals and MPI-IO" test_darshan_extract_totals
run_test "darshan: not detected for JSON" test_darshan_not_json

print_summary
