#!/bin/bash
################################################################################
## Strategy Tests: pgbench
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: pgbench"
echo "========================================"

test_pgbench_basic () {
    local output
    output=$(run_mfe -r -s pgbench "$SAMPLES_DIR/pgbench/basic.txt")
    assert_contains "$output" "scaling_factor 10" "should extract scaling factor"
    assert_contains "$output" "number_of_clients 10" "should extract clients"
    assert_contains "$output" "number_of_threads 2" "should extract threads"
    assert_contains "$output" "number_of_transactions 10000" "should extract transactions"
}

test_pgbench_tps () {
    local output
    output=$(run_mfe -r -s pgbench "$SAMPLES_DIR/pgbench/basic.txt")
    assert_contains "$output" "tps_including_connections 2189.456789" "should extract TPS including"
    assert_contains "$output" "tps_excluding_connections 2234.567890" "should extract TPS excluding"
    assert_contains "$output" "latency_average" "should extract latency average"
    assert_contains "$output" "latency_stddev" "should extract latency stddev"
}

test_pgbench_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s pgbench "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "pgbench should not apply to JSON"
}

run_test "pgbench: basic extraction" test_pgbench_basic
run_test "pgbench: TPS and latency extraction" test_pgbench_tps
run_test "pgbench: not detected for JSON" test_pgbench_not_json

print_summary
