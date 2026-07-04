#!/bin/bash
################################################################################
## Strategy Tests: markdown-frontmatter
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

echo ""
echo "========================================"
echo "Strategy Tests: markdown-frontmatter"
echo "========================================"

test_markdown_frontmatter_basic () {
    local output
    output=$(run_mfe -r -s markdown-frontmatter "$SAMPLES_DIR/markdown-frontmatter/basic.md")
    assert_contains "$output" "title My_Blog_Post" "should extract title"
    assert_contains "$output" "date 2024-01-15" "should extract date"
    assert_contains "$output" "author John_Doe" "should extract author"
    assert_contains "$output" "tags javascript,_react" "should extract tags"
    assert_contains "$output" "draft false" "should extract draft"
}

test_markdown_frontmatter_docs_page () {
    local output
    output=$(run_mfe -r -s markdown-frontmatter "$SAMPLES_DIR/markdown-frontmatter/docs-page.md")
    assert_contains "$output" "layout documentation" "should extract layout"
    assert_contains "$output" "sidebar_position 3" "should extract sidebar_position"
    assert_contains "$output" "description Getting_started_with_the_API" "should extract description"
    assert_contains "$output" "version 2.1.0" "should extract version"
    assert_contains "$output" "category guides" "should extract category"
}

test_markdown_frontmatter_not_detected_for_yaml () {
    local output
    output=$(run_mfe -d -s markdown-frontmatter "$SAMPLES_DIR/yaml/basic.yaml" 2>&1)
    assert_contains "$output" "not applicable" "markdown-frontmatter should not apply to plain YAML"
}

test_markdown_frontmatter_not_detected_for_json () {
    local output
    output=$(run_mfe -d -s markdown-frontmatter "$SAMPLES_DIR/json/basic.json" 2>&1)
    assert_contains "$output" "not applicable" "markdown-frontmatter should not apply to JSON"
}

run_test "markdown-frontmatter: basic extraction" test_markdown_frontmatter_basic
run_test "markdown-frontmatter: docs page extraction" test_markdown_frontmatter_docs_page
run_test "markdown-frontmatter: not detected for plain YAML" test_markdown_frontmatter_not_detected_for_yaml
run_test "markdown-frontmatter: not detected for JSON" test_markdown_frontmatter_not_detected_for_json

print_summary
