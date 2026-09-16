#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Strategy Tests: docker-ps
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: docker-ps"
echo "========================================"

test_docker_ps_basic () {
    local output
    output=$(run_mfe -r -s docker-ps "$SAMPLES_DIR/docker-ps/basic.txt")
    assert_contains "$output" "container1.container_id" "should extract container ID field"
    assert_contains "$output" "container1.image" "should extract image field"
    assert_contains "$output" "container1.names" "should extract names field"
    assert_contains "$output" "web-server" "should extract web-server name"
}

test_docker_ps_multiple_containers () {
    local output
    output=$(run_mfe -r -s docker-ps "$SAMPLES_DIR/docker-ps/basic.txt")
    assert_contains "$output" "container2.container_id" "should extract second container ID"
    assert_contains "$output" "container2.image" "should extract second container image"
    assert_contains "$output" "postgres:15" "should extract postgres image"
    assert_contains "$output" "container2.names" "should extract second container names"
    assert_contains "$output" "database" "should extract database name"
}

test_docker_ps_not_applicable_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s docker-ps "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "docker-ps should not apply to JSON"
}

run_test "docker-ps: basic extraction" test_docker_ps_basic
run_test "docker-ps: multiple containers" test_docker_ps_multiple_containers
run_test "docker-ps: not applicable for JSON" test_docker_ps_not_applicable_for_json

print_summary
