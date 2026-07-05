#!/bin/bash
################################################################################
## Strategy Tests: redis-cli
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: redis-cli"
echo "========================================"

test_redis_cli_basic () {
    local output
    output=$(run_mfe -r -s redis-cli "$SAMPLES_DIR/redis-cli/basic.txt")
    assert_contains "$output" "redis_version 7.2.3" "should extract redis_version"
    assert_contains "$output" "tcp_port 6379" "should extract tcp_port"
    assert_contains "$output" "uptime_in_seconds 86400" "should extract uptime_in_seconds"
    assert_contains "$output" "used_memory 1234567" "should extract used_memory"
    assert_contains "$output" "used_memory_human 1.18M" "should extract used_memory_human"
    assert_contains "$output" "maxmemory_policy noeviction" "should extract maxmemory_policy"
}

test_redis_cli_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s redis-cli "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_redis_cli_not_detected_for_colons () {
    local output
    output=$(run_mfe -d -s redis-cli "$SAMPLES_DIR/colons/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to plain colons"
}

run_test "redis-cli: basic INFO extraction" test_redis_cli_basic
run_test "redis-cli: not detected for JSON" test_redis_cli_not_detected_for_json
run_test "redis-cli: not detected for colons" test_redis_cli_not_detected_for_colons

print_summary
