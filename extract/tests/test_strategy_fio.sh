#!/bin/bash
################################################################################
## Strategy Tests: fio
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: fio"
echo "========================================"

test_fio_basic () {
    local output
    output=$(run_mfe -r -s fio "$SAMPLES_DIR/fio/basic.txt")
    assert_contains "$output" "name seqread" "should extract job name"
    assert_contains "$output" "read_iops 117k" "should extract read IOPS"
    assert_contains "$output" "read_bw 458MiB/s" "should extract read bandwidth"
    assert_contains "$output" "summary_read_bw 458MiB/s" "should extract summary read BW"
}

test_fio_latency () {
    local output
    output=$(run_mfe -r -s fio "$SAMPLES_DIR/fio/basic.txt")
    assert_contains "$output" "lat_avg 251.89" "should extract lat avg"
    assert_contains "$output" "lat_p99 502" "should extract p99 latency"
    assert_contains "$output" "io_depth 1" "should extract IO depth"
}

test_fio_mixed_rw () {
    local output
    output=$(run_mfe -r -s fio "$SAMPLES_DIR/fio/mixed-rw.txt")
    assert_contains "$output" "read_iops 8567" "should extract read IOPS"
    assert_contains "$output" "write_iops 2856" "should extract write IOPS"
    assert_contains "$output" "summary_read_bw" "should have read summary"
    assert_contains "$output" "summary_write_bw" "should have write summary"
}

test_fio_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s fio "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "fio should not apply to JSON"
}

run_test "fio: basic read extraction" test_fio_basic
run_test "fio: latency extraction" test_fio_latency
run_test "fio: mixed read/write" test_fio_mixed_rw
run_test "fio: not detected for JSON" test_fio_not_json

print_summary
