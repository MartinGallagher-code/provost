#!/bin/bash
################################################################################
## Strategy Tests: dockerfile
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: dockerfile"
echo "========================================"

test_dockerfile_basic () {
    local output
    output=$(run_mfe -r -s dockerfile "$SAMPLES_DIR/dockerfile/basic.Dockerfile")
    assert_contains "$output" "stage1.from node:18-alpine" "should extract FROM image"
    assert_contains "$output" "stage1.env.PORT 3000" "should extract ENV PORT"
    assert_contains "$output" "stage1.env.APP_NAME myservice" "should extract ENV APP_NAME"
    assert_contains "$output" "stage1.arg.NODE_ENV production" "should extract ARG"
    assert_contains "$output" "stage1.expose 3000" "should extract EXPOSE"
    assert_contains "$output" "stage1.workdir /app" "should extract WORKDIR"
    assert_contains "$output" "stage1.label.maintainer team@example.com" "should extract LABEL maintainer"
    assert_contains "$output" "stage1.label.version 1.2.0" "should extract LABEL version"
    assert_contains "$output" "stage2.cmd node server.js" "should extract CMD"
}

test_dockerfile_multistage () {
    local output
    output=$(run_mfe -r -s dockerfile "$SAMPLES_DIR/dockerfile/basic.Dockerfile")
    assert_contains "$output" "stage1.from node:18-alpine" "should prefix stage1"
    assert_contains "$output" "stage1.from.as builder" "should extract AS alias"
    assert_contains "$output" "stage2.from node:18-alpine" "should prefix stage2"
    assert_contains "$output" "stage2.cmd node server.js" "should prefix stage2 cmd"
    assert_contains "$output" "stage2.env.NODE_ENV production" "should prefix stage2 env"
}

test_dockerfile_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s dockerfile "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_dockerfile_not_plain_text () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'This is just some plain text.\nNothing special here.\nJust regular content.\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s dockerfile "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to plain text"
}

run_test "dockerfile: basic extraction" test_dockerfile_basic
run_test "dockerfile: multi-stage detection" test_dockerfile_multistage
run_test "dockerfile: not detected for JSON" test_dockerfile_not_json
run_test "dockerfile: not detected for plain text" test_dockerfile_not_plain_text

print_summary
