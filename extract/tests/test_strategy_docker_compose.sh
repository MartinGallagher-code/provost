#!/bin/bash
################################################################################
## Strategy Tests: docker-compose
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: docker-compose"
echo "========================================"

test_docker_compose_basic () {
    local output
    output=$(run_mfe -r -s docker-compose "$SAMPLES_DIR/docker-compose/basic.txt")
    assert_contains "$output" "web.image nginx:latest" "should extract web image"
    assert_contains "$output" "api.build ./api" "should extract api build"
    assert_contains "$output" "db.image postgres:15" "should extract db image"
}

test_docker_compose_service_fields () {
    local output
    output=$(run_mfe -r -s docker-compose "$SAMPLES_DIR/docker-compose/basic.txt")
    assert_contains "$output" "web.restart always" "should extract restart policy"
    assert_contains "$output" "api.restart on-failure" "should extract api restart"
    assert_contains "$output" "web.ports 80:80,443:443" "should extract web ports as comma-separated"
    assert_contains "$output" "web.depends_on api" "should extract web depends_on"
    assert_contains "$output" "api.environment NODE_ENV=production,PORT=3000" "should extract api environment"
    assert_contains "$output" "db.volumes pgdata:/var/lib/postgresql/data" "should extract db volumes"
}

test_docker_compose_not_for_plain_yaml () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'name: myapp\nversion: 1.0\ndependencies:\n  - lodash\n  - express\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s docker-compose "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not detect plain YAML"
}

run_test "docker-compose: basic extraction" test_docker_compose_basic
run_test "docker-compose: service fields" test_docker_compose_service_fields
run_test "docker-compose: not detected for plain YAML" test_docker_compose_not_for_plain_yaml

print_summary
