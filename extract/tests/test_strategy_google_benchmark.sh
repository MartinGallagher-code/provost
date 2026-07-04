#!/bin/bash
################################################################################
## Strategy Tests: google-benchmark
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: google-benchmark"
echo "========================================"

test_google_benchmark_basic () {
    local output
    output=$(run_mfe -r -s google-benchmark "$SAMPLES_DIR/google-benchmark/basic.txt")
    # Check benchmark names
    assert_contains "$output" "bench1.name BM_StringCopy/8" "should extract first benchmark name"
    assert_contains "$output" "bench5.name BM_Sort/1000" "should extract last benchmark name"
    # Check time values
    assert_contains "$output" "bench1.time 3.12_ns" "should extract first benchmark time"
    assert_contains "$output" "bench4.time 1234_ns" "should extract BM_Sort/100 time"
    # Check CPU values
    assert_contains "$output" "bench1.cpu 3.11_ns" "should extract first benchmark CPU"
    # Check iterations
    assert_contains "$output" "bench1.iterations 225000000" "should extract first iterations"
    assert_contains "$output" "bench5.iterations 44700" "should extract last iterations"
}

test_google_benchmark_metadata () {
    local output
    output=$(run_mfe -r -s google-benchmark "$SAMPLES_DIR/google-benchmark/basic.txt")
    # Check CPU info
    assert_contains "$output" "cpu_info" "should extract cpu_info"
    assert_contains "$output" "2400_MHz" "should contain CPU frequency"
    # Check cache info
    assert_contains "$output" "cache1" "should extract cache1"
    assert_contains "$output" "L1_Data" "should contain L1 Data cache"
    assert_contains "$output" "cache4" "should extract cache4"
    assert_contains "$output" "L3_Unified" "should contain L3 Unified cache"
}

test_google_benchmark_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s google-benchmark "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "google-benchmark should not apply to JSON"
}

test_google_benchmark_preamble_detect () {
    # Verify detection works when input has non-matching preamble lines
    local tmpfile
    tmpfile=$(mktemp)
    printf 'Build completed successfully.\nRunning benchmarks...\n\nRun on (8 X 2400 MHz CPU s)\nCPU Caches:\n  L1 Data 32 KiB (x8)\n------------------------------------------------------------\nBenchmark              Time             CPU   Iterations\n------------------------------------------------------------\nBM_StringCopy/8     3.12 ns         3.11 ns    225000000\n' > "$tmpfile"
    local output
    output=$(run_mfe -r -s google-benchmark "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" "bench1.name BM_StringCopy/8" "should detect and extract with preamble"
    assert_contains "$output" "cpu_info" "should extract cpu_info with preamble"
}

run_test "google-benchmark: basic extraction" test_google_benchmark_basic
run_test "google-benchmark: metadata extraction" test_google_benchmark_metadata
run_test "google-benchmark: detection with preamble lines" test_google_benchmark_preamble_detect
run_test "google-benchmark: not detected for JSON" test_google_benchmark_not_json

print_summary
