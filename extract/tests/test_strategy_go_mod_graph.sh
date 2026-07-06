#!/bin/bash
################################################################################
## Strategy Tests: go-mod-graph
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: go-mod-graph"
echo "========================================"

test_go_mod_graph_basic () {
    local output
    output=$(run_mfe -r -s go-mod-graph "$SAMPLES_DIR/go-mod-graph/basic.txt")
    assert_contains "$output" "edge1.from github.com/user/myapp" "should extract edge1 from"
    assert_contains "$output" "edge1.to github.com/gin-gonic/gin@v1.9.1" "should extract edge1 to"
    assert_contains "$output" "edge3.to go.uber.org/zap@v1.26.0" "should extract edge3 to"
    assert_contains "$output" "edge7.from go.uber.org/zap@v1.26.0" "should extract edge7 from"
    assert_contains "$output" "edge7.to go.uber.org/atomic@v1.11.0" "should extract edge7 to"
    assert_contains "$output" "total_edges 7" "should count total edges"
}

test_go_mod_graph_not_detected_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s go-mod-graph "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_go_mod_graph_not_detected_for_env_vars () {
    local output
    output=$(run_mfe -d -s go-mod-graph "$SAMPLES_DIR/env-vars/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to env vars"
}

run_test "go-mod-graph: basic extraction" test_go_mod_graph_basic
run_test "go-mod-graph: not detected for JSON" test_go_mod_graph_not_detected_for_json
run_test "go-mod-graph: not detected for env vars" test_go_mod_graph_not_detected_for_env_vars

print_summary
