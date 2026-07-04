#!/bin/bash
################################################################################
## Strategy Tests: k8s-events
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: k8s-events"
echo "========================================"

test_k8s_events_basic () {
    local output
    output=$(run_mfe -r -s k8s-events "$SAMPLES_DIR/k8s-events/basic.txt")
    assert_contains "$output" "event1.type Normal" "should extract event1 type"
    assert_contains "$output" "event1.reason Scheduled" "should extract event1 reason"
    assert_contains "$output" "event1.object pod/web-app-xyz" "should extract event1 object"
    assert_contains "$output" "event1.message" "should extract event1 message"
    assert_contains "$output" "event7.type Normal" "should extract event7 type"
    assert_contains "$output" "event7.reason Killing" "should extract event7 reason"
    assert_contains "$output" "event7.object pod/api-server-abc" "should extract event7 object"
    assert_contains "$output" "event6.type Warning" "should extract warning event type"
}

test_k8s_events_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s k8s-events "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_k8s_events_not_detected_for_docker_ps () {
    local output
    output=$(run_mfe -d -s k8s-events "$SAMPLES_DIR/docker-ps/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to docker ps output"
}

run_test "k8s-events: basic extraction" test_k8s_events_basic
run_test "k8s-events: not detected for JSON" test_k8s_events_not_detected_for_json
run_test "k8s-events: not detected for docker ps" test_k8s_events_not_detected_for_docker_ps

print_summary
