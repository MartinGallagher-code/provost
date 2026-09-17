#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Martin J. Gallagher

################################################################################
## Tests for lib/_format.sh — especially _yaml_needs_quote
################################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

# Source just the helpers and format module for unit testing
_FORMAT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/lib"
source "$_FORMAT_DIR/_helpers.sh"
source "$_FORMAT_DIR/_format.sh"

echo ""
echo "========================================"
echo "Format Library Tests"
echo "========================================"

################################################################################
## _yaml_needs_quote unit tests
################################################################################

test_yaml_quote_empty () {
    _yaml_needs_quote ""
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "empty string requires quoting"
}

test_yaml_quote_colon () {
    _yaml_needs_quote "host:port"
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "colon in value requires quoting"
}

test_yaml_quote_hash () {
    _yaml_needs_quote "value#comment"
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "hash in value requires quoting"
}

test_yaml_quote_boolean_true () {
    _yaml_needs_quote "true"
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "boolean 'true' requires quoting"
}

test_yaml_quote_boolean_false () {
    _yaml_needs_quote "false"
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "boolean 'false' requires quoting"
}

test_yaml_quote_null () {
    _yaml_needs_quote "null"
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "'null' requires quoting"
}

test_yaml_quote_yes () {
    _yaml_needs_quote "yes"
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "'yes' requires quoting"
}

test_yaml_quote_numeric_start () {
    _yaml_needs_quote "42"
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "digit-starting value requires quoting"
}

test_yaml_quote_numeric_start_float () {
    _yaml_needs_quote "3.14"
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "float value requires quoting"
}

test_yaml_quote_curly_brace () {
    _yaml_needs_quote "{key: val}"
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "curly brace requires quoting"
}

test_yaml_quote_double_quote () {
    _yaml_needs_quote 'say "hello"'
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "double quote in value requires quoting"
}

test_yaml_quote_special_chars () {
    _yaml_needs_quote "foo@bar"
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "@ character requires quoting"
}

test_yaml_no_quote_plain_word () {
    _yaml_needs_quote "hello"
    assert_eq "0" "$_YAML_NEEDS_QUOTE" "plain word should not require quoting"
}

test_yaml_no_quote_hyphenated () {
    _yaml_needs_quote "server-a"
    assert_eq "0" "$_YAML_NEEDS_QUOTE" "hyphenated identifier should not require quoting"
}

test_yaml_no_quote_dotted () {
    _yaml_needs_quote "10.0.0.1"
    assert_eq "1" "$_YAML_NEEDS_QUOTE" "IP address (digit-start) requires quoting"
}

test_yaml_no_quote_underscore () {
    _yaml_needs_quote "my_value"
    assert_eq "0" "$_YAML_NEEDS_QUOTE" "underscore-containing value should not require quoting"
}

################################################################################
## format_yaml integration tests (via envoy-extract)
################################################################################

test_yaml_output_booleans () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'enabled: true\nname: myservice\n' > "$tmpfile"
    local output
    output=$(run_mfe -s colons -f yaml "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" '"true"' "boolean value should be quoted in YAML"
    assert_not_contains "$output" ': true' "unquoted boolean should not appear"
}

test_yaml_output_plain_string () {
    local tmpfile
    tmpfile=$(mktemp)
    printf 'host: localhost\n' > "$tmpfile"
    local output
    output=$(run_mfe -s colons -f yaml "$tmpfile")
    rm -f "$tmpfile"
    assert_contains "$output" 'host: localhost' "plain string should not be quoted in YAML"
}

################################################################################
## Run all tests
################################################################################

run_test "yaml_needs_quote: empty string" test_yaml_quote_empty
run_test "yaml_needs_quote: colon in value" test_yaml_quote_colon
run_test "yaml_needs_quote: hash in value" test_yaml_quote_hash
run_test "yaml_needs_quote: boolean true" test_yaml_quote_boolean_true
run_test "yaml_needs_quote: boolean false" test_yaml_quote_boolean_false
run_test "yaml_needs_quote: null keyword" test_yaml_quote_null
run_test "yaml_needs_quote: yes keyword" test_yaml_quote_yes
run_test "yaml_needs_quote: digit-start numeric" test_yaml_quote_numeric_start
run_test "yaml_needs_quote: float value" test_yaml_quote_numeric_start_float
run_test "yaml_needs_quote: curly brace" test_yaml_quote_curly_brace
run_test "yaml_needs_quote: double quote" test_yaml_quote_double_quote
run_test "yaml_needs_quote: @ character" test_yaml_quote_special_chars
run_test "yaml_needs_quote: plain word not quoted" test_yaml_no_quote_plain_word
run_test "yaml_needs_quote: hyphenated not quoted" test_yaml_no_quote_hyphenated
run_test "yaml_needs_quote: IP address (digit-start)" test_yaml_no_quote_dotted
run_test "yaml_needs_quote: underscore not quoted" test_yaml_no_quote_underscore
run_test "format_yaml: booleans are quoted" test_yaml_output_booleans
run_test "format_yaml: plain strings unquoted" test_yaml_output_plain_string

print_summary
