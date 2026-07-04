#!/bin/bash
################################################################################
## Strategy Tests: terraform-plan
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Terraform Plan Strategy Tests"
echo "========================================"

test_detect () {
    local output
    output=$(run_mfe -d -s terraform-plan "$SAMPLES_DIR/terraform-plan/basic.txt" 2>&1)
    assert_contains "$output" "detected as applicable" "terraform-plan should detect basic sample"

    local tmpfile
    tmpfile=$(mktemp)
    printf '{"name": "test", "value": 42}\n' > "$tmpfile"
    local output2
    output2=$(run_mfe -d -s terraform-plan "$tmpfile" 2>&1)
    rm -f "$tmpfile"
    assert_contains "$output2" "not applicable" "terraform-plan should not apply to JSON"
}

test_extract () {
    local output
    output=$(run_mfe -r -s terraform-plan "$SAMPLES_DIR/terraform-plan/basic.txt")
    assert_contains "$output" "plan_add 1" "should extract add count"
    assert_contains "$output" "plan_change 1" "should extract change count"
    assert_contains "$output" "plan_destroy 1" "should extract destroy count"
    assert_contains "$output" "resource1_name aws_instance.web" "should extract first resource name"
    assert_contains "$output" "resource1_action create" "should extract first resource action"
    assert_contains "$output" "resource2_name aws_security_group.allow_http" "should extract second resource name"
    assert_contains "$output" "resource2_action update" "should extract second resource action"
    assert_contains "$output" "resource3_name aws_instance.old" "should extract third resource name"
    assert_contains "$output" "resource3_action destroy" "should extract third resource action"
}

test_field_selection () {
    local output
    output=$(run_mfe -r -s terraform-plan "$SAMPLES_DIR/terraform-plan/create-only.txt")
    assert_contains "$output" "plan_add 2" "should extract add count of 2"
    assert_contains "$output" "plan_change 0" "should extract change count of 0"
    assert_contains "$output" "plan_destroy 0" "should extract destroy count of 0"
    assert_contains "$output" "resource1_name aws_vpc.main" "should extract vpc resource"
    assert_contains "$output" "resource2_name aws_subnet.public" "should extract subnet resource"
    assert_not_contains "$output" "resource3_" "should not have third resource"
}

run_test "terraform-plan: detection" test_detect
run_test "terraform-plan: extraction" test_extract
run_test "terraform-plan: field selection" test_field_selection

print_summary
