#!/bin/bash
################################################################################
## Strategy Tests: hcl
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: hcl"
echo "========================================"

test_hcl_basic () {
    local output
    output=$(run_mfe -r -s hcl "$SAMPLES_DIR/hcl/basic.tf")
    assert_contains "$output" "provider.aws.region us-west-2" "should extract provider region"
    assert_contains "$output" "variable.instance_type.default t3.micro" "should extract variable default"
    assert_contains "$output" "resource.aws_instance.web.ami ami-0c55b159cbfafe1f0" "should extract resource ami"
    assert_contains "$output" "resource.aws_instance.web.tags.Name WebServer" "should extract nested tags"
    assert_contains "$output" "output.instance_id.value aws_instance.web.id" "should extract output value"
    assert_contains "$output" "output.instance_id.description The instance ID" "should extract output description"
}

test_hcl_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s hcl "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "hcl should not apply to JSON"
}

test_hcl_not_detected_for_yaml () {
    local output
    output=$(run_mfe -d -s hcl "$SAMPLES_DIR/yaml/basic.yaml" 2>&1)
    assert_contains "$output" "not applicable" "hcl should not apply to YAML"
}

test_hcl_not_detected_for_ini () {
    local output
    output=$(run_mfe -d -s hcl "$SAMPLES_DIR/ini/basic.ini" 2>&1)
    assert_contains "$output" "not applicable" "hcl should not apply to INI"
}

run_test "hcl: basic extraction" test_hcl_basic
run_test "hcl: not detected for JSON" test_hcl_not_detected_for_json
run_test "hcl: not detected for YAML" test_hcl_not_detected_for_yaml
run_test "hcl: not detected for INI" test_hcl_not_detected_for_ini

print_summary
