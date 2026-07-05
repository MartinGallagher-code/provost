#!/bin/bash
################################################################################
## Strategy Tests: 7zip
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: 7zip"
echo "========================================"

test_7zip_ratings () {
    local output
    output=$(run_mfe -r -s 7zip "$SAMPLES_DIR/7zip/basic.txt")
    assert_contains "$output" "avg_compress_rating_MIPS 25038" "should extract avg compress rating"
    assert_contains "$output" "avg_decompress_rating_MIPS 30279" "should extract avg decompress rating"
    assert_contains "$output" "total_rating_MIPS 27658" "should extract total rating"
}

test_7zip_metadata () {
    local output
    output=$(run_mfe -r -s 7zip "$SAMPLES_DIR/7zip/basic.txt")
    assert_contains "$output" "ram_size_MB 16384" "should extract RAM size"
    assert_contains "$output" "cpu_threads 8" "should extract CPU threads"
    assert_contains "$output" "compress_speed_KiB_per_s 25678" "should extract first dict compress speed"
}

test_7zip_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s 7zip "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "7zip should not apply to JSON"
}

run_test "7zip: rating extraction" test_7zip_ratings
run_test "7zip: metadata and per-dict extraction" test_7zip_metadata
run_test "7zip: not detected for JSON" test_7zip_not_json

print_summary
