#!/bin/bash
################################################################################
## Strategy Tests: trivy
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: trivy"
echo "========================================"

test_trivy_basic () {
    local output
    output=$(run_mfe -r -s trivy "$SAMPLES_DIR/trivy/basic.txt")
    assert_contains "$output" "total 5" "should extract total count"
    assert_contains "$output" "critical 1" "should extract critical count"
    assert_contains "$output" "high 1" "should extract high count"
    assert_contains "$output" "medium 2" "should extract medium count"
    assert_contains "$output" "low 1" "should extract low count"
    assert_contains "$output" "vuln1.id CVE-2024-0727" "should extract first vuln CVE"
    assert_contains "$output" "vuln1.severity MEDIUM" "should extract first vuln severity"
    assert_contains "$output" "vuln1.package libcrypto3" "should extract first vuln package"
    assert_contains "$output" "vuln1.installed_version 3.1.4-r1" "should extract first vuln installed version"
    assert_contains "$output" "vuln1.fixed_version 3.1.4-r3" "should extract first vuln fixed version"
    assert_contains "$output" "vuln5.severity CRITICAL" "should extract fifth vuln severity"
    assert_contains "$output" "vuln5.package zlib" "should extract fifth vuln package"
}

test_trivy_not_json () {
    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output
    output=$(run_mfe -d -s trivy "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output" "not applicable" "should not apply to JSON"
}

test_trivy_not_aligned_columns () {
    local output
    output=$(run_mfe -d -s trivy "$SAMPLES_DIR/aligned-columns/basic.txt" 2>&1)
    assert_contains "$output" "not applicable" "should not apply to aligned-columns"
}

run_test "trivy: basic extraction" test_trivy_basic
run_test "trivy: not detected for JSON" test_trivy_not_json
run_test "trivy: not detected for aligned-columns" test_trivy_not_aligned_columns

print_summary
