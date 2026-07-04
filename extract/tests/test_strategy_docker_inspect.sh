#!/bin/bash
################################################################################
## Strategy Tests: docker-inspect
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: docker-inspect"
echo "========================================"

test_docker_inspect_basic () {
    local output
    output=$(run_mfe -r -s docker-inspect "$SAMPLES_DIR/docker-inspect/basic.json")
    assert_contains "$output" "id abc123def456789" "should extract container id"
    assert_contains "$output" "name mycontainer" "should extract container name"
    assert_contains "$output" "state.status running" "should extract state status"
    assert_contains "$output" "state.running true" "should extract state running"
    assert_contains "$output" "state.pid 12345" "should extract state pid"
    assert_contains "$output" "config.image nginx:latest" "should extract config image"
    assert_contains "$output" "config.hostname abc123" "should extract config hostname"
    assert_contains "$output" "config.env.PATH /usr/local/sbin:/usr/local/bin" "should extract env PATH"
    assert_contains "$output" "config.env.NGINX_VERSION 1.25.3" "should extract env NGINX_VERSION"
    assert_contains "$output" "network.ip_address 172.17.0.2" "should extract IP address"
    assert_contains "$output" "network.gateway 172.17.0.1" "should extract gateway"
    assert_contains "$output" "host_config.memory 536870912" "should extract memory"
    assert_contains "$output" "host_config.cpu_shares 1024" "should extract cpu shares"
}

test_docker_inspect_not_regular_json () {
    local output
    output=$(run_mfe -d -s docker-inspect "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to regular JSON"
}

test_docker_inspect_not_har () {
    local output
    output=$(run_mfe -d -s docker-inspect "$SAMPLES_DIR/har/basic.har" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to HAR JSON"
}

run_test "docker-inspect: basic extraction" test_docker_inspect_basic
run_test "docker-inspect: not detected for regular JSON" test_docker_inspect_not_regular_json
run_test "docker-inspect: not detected for HAR" test_docker_inspect_not_har

print_summary
