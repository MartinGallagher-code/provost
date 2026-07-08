#!/bin/bash
################################################################################
## Strategy Tests: xml (merges xml-elements + xml-attributes)
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: xml"
echo "========================================"

test_xml_elements_basic () {
    local output
    output=$(run_mfe -r -s xml "$SAMPLES_DIR/xml-elements/basic.xml")
    assert_contains "$output" "title My Page Title" "should extract title element"
    assert_contains "$output" "h1 Welcome" "should extract h1 element"
}

test_xml_elements_with_attributes () {
    local output
    output=$(run_mfe -r -s xml "$SAMPLES_DIR/xml-elements/basic.xml")
    assert_contains "$output" "span Version 2.0" "should extract span text with class attribute"
    assert_contains "$output" "div 42" "should extract div text with id attribute"
    assert_contains "$output" "p This is a paragraph." "should extract paragraph text"
}

test_xml_attributes_basic () {
    local output
    output=$(run_mfe -r -s xml "$SAMPLES_DIR/xml-attributes/basic.xml")
    assert_contains "$output" "config.name my-app" "should extract config name attribute"
    assert_contains "$output" "database.host localhost" "should extract database host attribute"
    assert_contains "$output" "database.port 5432" "should extract database port attribute"
}

test_xml_attributes_self_closing () {
    local output
    output=$(run_mfe -r -s xml "$SAMPLES_DIR/xml-attributes/basic.xml")
    assert_contains "$output" "database.ssl true" "should extract from self-closing database tag"
    assert_contains "$output" "feature.enabled true" "should extract from self-closing feature tag"
    assert_contains "$output" "feature.name dark-mode" "should extract feature name attribute"
}

test_xml_both_passes () {
    local output
    output=$(run_mfe -r -s xml "$SAMPLES_DIR/xml-elements/basic.xml")
    # Both element text and attribute key/value should be extracted
    assert_contains "$output" "h1 Welcome" "should extract element text"
    assert_contains "$output" "span Version 2.0" "should extract element text with attr"
}

test_xml_not_json () {
    local output
    output=$(run_mfe -d -s xml "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "xml should not apply to JSON"
}

run_test "xml: element text extraction" test_xml_elements_basic
run_test "xml: elements with attributes still extract text" test_xml_elements_with_attributes
run_test "xml: attribute key/value extraction" test_xml_attributes_basic
run_test "xml: self-closing tag attributes" test_xml_attributes_self_closing
run_test "xml: both passes run on same file" test_xml_both_passes
run_test "xml: not detected for JSON" test_xml_not_json

print_summary
