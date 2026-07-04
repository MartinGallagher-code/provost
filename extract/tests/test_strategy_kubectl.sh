#!/bin/bash
################################################################################
## Strategy Tests: kubectl
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: kubectl"
echo "========================================"

test_kubectl_basic () {
    local output
    output=$(run_mfe -r -s kubectl "$SAMPLES_DIR/kubectl/basic.txt")
    assert_contains "$output" "pod1.name" "should extract pod1 name field"
    assert_contains "$output" "nginx-deployment-abc12" "should extract first pod name"
    assert_contains "$output" "pod1.ready" "should extract pod1 ready field"
    assert_contains "$output" "1/1" "should extract ready value"
    assert_contains "$output" "pod1.status" "should extract pod1 status field"
    assert_contains "$output" "Running" "should extract status value"
}

test_kubectl_multiple_pods () {
    local output
    output=$(run_mfe -r -s kubectl "$SAMPLES_DIR/kubectl/basic.txt")
    assert_contains "$output" "pod2.name" "should extract pod2 name field"
    assert_contains "$output" "redis-master-def34" "should extract second pod name"
    assert_contains "$output" "pod3.name" "should extract pod3 name field"
    assert_contains "$output" "api-server-ghi56" "should extract third pod name"
    assert_contains "$output" "pod3.restarts" "should extract pod3 restarts field"
    assert_contains "$output" "pod3.restarts 3" "should extract pod3 restarts value"
}

test_kubectl_not_applicable_for_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"key": "value", "count": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s kubectl "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "kubectl should not apply to JSON"
}

run_test "kubectl: basic extraction" test_kubectl_basic
run_test "kubectl: multiple pods" test_kubectl_multiple_pods
run_test "kubectl: not applicable for JSON" test_kubectl_not_applicable_for_json

print_summary
